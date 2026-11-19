import UIKit
import CoreImage

/// Lê o hodômetro numa foto do painel e escolhe os números mais prováveis.
///
/// Lê a foto em 3 versões (inteira, centro ampliado e preto e branco com contraste),
/// corrige letras confundidas com números (O→0, I→1, S→5, B→8) e pontua cada número:
/// aparecer em várias leituras, estar perto do último km registrado, ter "ODO"/"km" ao lado
/// e ser grande na tela aumentam a chance; números com decimal (parcial/trip), horas,
/// temperatura, autonomia e velocidade diminuem.
enum OdometerReader {
    static func read(_ image: UIImage, lastKnown: Int) async -> [Int] {
        var passes: [[RecognizedLine]] = []
        for variant in variants(of: image) {
            if let lines = try? await TextRecognizer.recognize(variant) {
                passes.append(lines)
            }
        }
        return candidates(from: passes, lastKnown: lastKnown)
    }

    // MARK: Versões da foto

    static func variants(of image: UIImage) -> [UIImage] {
        var result = [image]
        if let crop = centerCrop(image) { result.append(crop) }
        if let contrast = highContrast(image) { result.append(contrast) }
        return result
    }

    /// Centro da foto (onde o hodômetro costuma estar), para a leitura ver os dígitos maiores.
    private static func centerCrop(_ image: UIImage) -> UIImage? {
        let normalized = normalizedImage(image)
        guard let cg = normalized.cgImage else { return nil }
        let w = CGFloat(cg.width), h = CGFloat(cg.height)
        let rect = CGRect(x: w * 0.12, y: h * 0.2, width: w * 0.76, height: h * 0.6).integral
        guard let cropped = cg.cropping(to: rect) else { return nil }
        return UIImage(cgImage: cropped)
    }

    /// Preto e branco com mais contraste (ajuda em visor de LCD e reflexo).
    private static func highContrast(_ image: UIImage) -> UIImage? {
        let normalized = normalizedImage(image)
        guard let input = CIImage(image: normalized),
              let filter = CIFilter(name: "CIColorControls") else { return nil }
        filter.setValue(input, forKey: kCIInputImageKey)
        filter.setValue(0.0, forKey: kCIInputSaturationKey)
        filter.setValue(1.8, forKey: kCIInputContrastKey)
        guard let output = filter.outputImage,
              let cg = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cg)
    }

    /// Foto "em pé" (aplica a rotação da câmera nos pixels), para recortar no lugar certo.
    private static func normalizedImage(_ image: UIImage) -> UIImage {
        guard image.imageOrientation != .up else { return image }
        let maxSide: CGFloat = 2200
        let scale = min(1, maxSide / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        return UIGraphicsImageRenderer(size: size).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    // MARK: Escolha do número

    static func candidates(from passes: [[RecognizedLine]], lastKnown: Int) -> [Int] {
        var scores: [Int: Double] = [:]
        var seenInPass: [Int: Set<Int>] = [:]

        for (passIndex, lines) in passes.enumerated() {
            for line in lines {
                let text = fixDigits(line.text).uppercased()
                // ignora horas, temperaturas e velocidade
                if text.contains(":") || text.contains("°") || text.contains("KM/H") || text.contains("RPM") { continue }
                let isRange = text.contains("AUTONOMIA") || text.contains("RANGE") || text.contains("DTE")
                let isTrip = text.contains("TRIP") || text.contains("PARCIAL")
                let isOdo = text.contains("ODO") || text.contains("TOTAL") || text.contains("HODOM")

                for value in numbers(in: text) {
                    var score = Double(line.height) * 150            // número grande na tela
                    if isOdo { score += 20 }
                    if text.contains("KM") && !isRange && !isTrip { score += 4 }
                    if isRange || isTrip { score -= 25 }
                    if lastKnown > 0 {
                        let diff = value - lastKnown
                        if diff >= 0 && diff <= 3_000 {
                            score += 40 - Double(diff) / 150          // o mais comum: rodou um pouco
                        } else if diff > 3_000 && diff <= 30_000 {
                            score += 15 - Double(diff) / 3_000
                        } else if diff < -50 {
                            score -= 40                               // menor que o último km
                        } else {
                            score -= 10
                        }
                    } else {
                        if value >= 1_000 { score += 6 }
                        if value < 100 { score -= 20 }
                    }
                    scores[value, default: 0] += score
                    seenInPass[value, default: []].insert(passIndex)
                }
            }
        }

        // Aparecer em mais de uma leitura é um bom sinal.
        for (value, passesSeen) in seenInPass {
            scores[value, default: 0] += Double(passesSeen.count - 1) * 12
        }

        return scores
            .sorted { $0.value > $1.value }
            .map(\.key)
            .prefix(4)
            .map { $0 }
    }

    /// Números inteiros de 3 a 7 dígitos, aceitando separador de milhar ("34.567", "34 567").
    /// Números com casa decimal ("123,4", "56.7") são do parcial/consumo e ficam de fora.
    static func numbers(in text: String) -> [Int] {
        let pattern = #"(?<![\d.,])(\d{1,3}(?:[.\s]\d{3})+|\d{3,7})(?![\d]|[.,]\d)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap { match in
            let digits = ns.substring(with: match.range(at: 1)).filter(\.isNumber)
            guard (3...7).contains(digits.count) else { return nil }
            return Int(digits)
        }
    }

    /// Troca letras confundidas com números, só em "palavras" que são quase todas dígitos.
    static func fixDigits(_ text: String) -> String {
        let map: [Character: Character] = ["O": "0", "o": "0", "D": "0", "Q": "0", "I": "1", "l": "1", "|": "1",
                                           "S": "5", "s": "5", "B": "8", "Z": "2", "z": "2", "G": "6"]
        return text.split(separator: " ", omittingEmptySubsequences: false).map { word -> String in
            let digits = word.reduce(0) { $0 + ($1.isNumber ? 1 : 0) }
            guard word.count >= 3, Double(digits) / Double(word.count) >= 0.6 else { return String(word) }
            return String(word.map { map[$0] ?? $0 })
        }.joined(separator: " ")
    }
}

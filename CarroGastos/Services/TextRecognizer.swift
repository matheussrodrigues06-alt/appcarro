import UIKit
import Vision

/// Um trecho de texto encontrado na foto, com o tamanho relativo da letra.
struct RecognizedLine {
    let text: String
    /// Altura da caixa do texto (0...1 em relação à foto) — números grandes no painel têm altura maior.
    let height: CGFloat
    /// Posição vertical do centro (0 = topo, 1 = base).
    let midY: CGFloat
}

/// Leitura de texto 100% no aparelho (framework Vision da Apple). Grátis e sem internet.
enum TextRecognizer {
    static func recognize(_ image: UIImage) async throws -> [RecognizedLine] {
        guard let cgImage = image.cgImage else { return [] }
        let orientation = CGImagePropertyOrientation(image.imageOrientation)
        return try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["pt-BR", "en-US"]
            request.usesLanguageCorrection = false
            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation)
            try handler.perform([request])
            let observations = request.results ?? []
            return observations
                .compactMap { obs -> RecognizedLine? in
                    guard let text = obs.topCandidates(1).first?.string else { return nil }
                    return RecognizedLine(text: text, height: obs.boundingBox.height, midY: 1 - obs.boundingBox.midY)
                }
                .sorted { $0.midY < $1.midY }
        }.value
    }
}

extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}

/// Converte "1.234,56", "100,05" ou "6.79" em número.
func parseBrazilianNumber(_ raw: String) -> Double? {
    var s = raw.trimmingCharacters(in: .whitespaces)
    s = s.replacingOccurrences(of: "R$", with: "").replacingOccurrences(of: " ", with: "")
    guard !s.isEmpty else { return nil }
    if s.contains(",") {
        s = s.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
    }
    return Double(s)
}

/// Todos os números decimais de uma linha ("15,000", "6,67", "100,05").
func decimalNumbers(in line: String) -> [Double] {
    let pattern = #"\d{1,3}(?:\.\d{3})*,\d{2,3}|\d+,\d{2,3}|\d+\.\d{2,3}"#
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
    let range = NSRange(line.startIndex..., in: line)
    return regex.matches(in: line, range: range).compactMap { match in
        Range(match.range, in: line).flatMap { parseBrazilianNumber(String(line[$0])) }
    }
}

import Foundation

/// Escolhe, entre os números lidos na foto do painel, os mais prováveis de serem o hodômetro.
enum OdometerReader {
    static func candidates(from lines: [RecognizedLine], lastKnown: Int) -> [Int] {
        var scored: [(value: Int, score: Double)] = []
        for line in lines {
            let upper = line.text.uppercased()
            // ignora horários, temperaturas e autonomia
            if upper.contains(":") || upper.contains("°") { continue }
            let pattern = #"\d{1,3}(?:[.\s]\d{3})+|\d{3,7}"#
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(upper.startIndex..., in: upper)
            for match in regex.matches(in: upper, range: range) {
                guard let r = Range(match.range, in: upper) else { continue }
                let digits = upper[r].filter(\.isNumber)
                guard digits.count >= 3, digits.count <= 7, let value = Int(digits) else { continue }
                var score = Double(line.height) * 100          // número grande na tela
                if upper.contains("KM") { score += 8 }
                if upper.contains("TRIP") || upper.contains("PARCIAL") || upper.contains("AUTONOMIA") { score -= 15 }
                if lastKnown > 0 {
                    if value >= lastKnown && value <= lastKnown + 20_000 {
                        score += 25 - Double(value - lastKnown) / 2_000   // perto do último km
                    } else if value < lastKnown - 50 {
                        score -= 30
                    }
                } else if value >= 1_000 {
                    score += 5
                }
                scored.append((value, score))
            }
        }
        var seen = Set<Int>()
        return scored
            .sorted { $0.score > $1.score }
            .compactMap { seen.insert($0.value).inserted ? $0.value : nil }
            .prefix(4)
            .map { $0 }
    }
}

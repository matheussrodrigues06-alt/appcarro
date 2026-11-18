import Foundation

/// Dados extraídos de um cupom fiscal (NFC-e) de posto de combustível.
struct ReceiptData {
    var total: Double?
    var liters: Double?
    var pricePerLiter: Double?
    var fuelType: String?
    var station: String?
    var date: Date?

    var isEmpty: Bool { total == nil && liters == nil && pricePerLiter == nil }
}

/// Lê as linhas de um cupom e encontra valor, litros, preço por litro, combustível, posto e data.
/// Funciona por regras (sem internet). O usuário sempre confere antes de salvar.
enum ReceiptParser {
    static func parse(_ lines: [String]) -> ReceiptData {
        var result = ReceiptData()
        let upper = lines.map { $0.uppercased().folding(options: .diacriticInsensitive, locale: Locale(identifier: "pt_BR")) }

        // Combustível
        for line in upper {
            if line.contains("ADITIVAD") || line.contains("PODIUM") || line.contains("V-POWER") {
                result.fuelType = "Gasolina aditivada"; break
            } else if line.contains("GASOLINA") {
                result.fuelType = "Gasolina comum"; break
            } else if line.contains("ETANOL") || line.contains("ALCOOL") {
                result.fuelType = "Etanol"; break
            } else if line.contains("DIESEL") {
                result.fuelType = "Diesel"; break
            } else if line.contains("GNV") {
                result.fuelType = "GNV"; break
            }
        }

        // Valor total
        let totalKeys = ["VALOR TOTAL", "VALOR A PAGAR", "TOTAL R$", "VL. TOTAL", "VL TOTAL", "TOTAL A PAGAR", "VALOR PAGO"]
        for (i, line) in upper.enumerated() where totalKeys.contains(where: { line.contains($0) }) {
            if let value = decimalNumbers(in: line).last {
                result.total = value; break
            }
            if i + 1 < upper.count, let value = decimalNumbers(in: upper[i + 1]).first {
                result.total = value; break
            }
        }

        // Litros: número seguido de L / LT / LTS / LITROS
        let litersPattern = #"(\d+[.,]\d{2,3})\s*(L|LT|LTS|LITROS?)\b"#
        if let regex = try? NSRegularExpression(pattern: litersPattern) {
            for line in upper {
                let range = NSRange(line.startIndex..., in: line)
                if let match = regex.firstMatch(in: line, range: range),
                   let r = Range(match.range(at: 1), in: line),
                   let value = parseBrazilianNumber(String(line[r])), value > 0.5, value < 200 {
                    result.liters = value
                    // Preço unitário costuma vir na mesma linha: "15,000 LT X 6,670"
                    let rest = decimalNumbers(in: line).filter { $0 != value }
                    if let price = rest.first(where: { $0 >= 2 && $0 <= 15 }) {
                        result.pricePerLiter = price
                    }
                    break
                }
            }
        }

        // Preço unitário explícito
        if result.pricePerLiter == nil {
            let unitKeys = ["VL. UNIT", "VL UNIT", "V. UNIT", "VALOR UNIT", "PRECO UNIT", "R$/L", "P. UNIT"]
            for (i, line) in upper.enumerated() where unitKeys.contains(where: { line.contains($0) }) {
                let candidates = decimalNumbers(in: line) + (i + 1 < upper.count ? decimalNumbers(in: upper[i + 1]) : [])
                if let price = candidates.first(where: { $0 >= 2 && $0 <= 15 }) {
                    result.pricePerLiter = price; break
                }
            }
        }

        // Completa o que faltar pela conta
        if let total = result.total, let liters = result.liters, liters > 0, result.pricePerLiter == nil {
            result.pricePerLiter = total / liters
        }
        if let total = result.total, let price = result.pricePerLiter, price > 0, result.liters == nil {
            result.liters = total / price
        }
        if result.total == nil, let liters = result.liters, let price = result.pricePerLiter {
            result.total = (liters * price * 100).rounded() / 100
        }

        // Data dd/mm/aaaa
        if let regex = try? NSRegularExpression(pattern: #"(\d{2})/(\d{2})/(\d{4})"#) {
            for line in upper {
                let range = NSRange(line.startIndex..., in: line)
                if let m = regex.firstMatch(in: line, range: range),
                   let d = Range(m.range(at: 1), in: line), let mo = Range(m.range(at: 2), in: line), let y = Range(m.range(at: 3), in: line),
                   let date = Calendar.current.date(from: DateComponents(year: Int(line[y]), month: Int(line[mo]), day: Int(line[d]))),
                   date <= Date().addingTimeInterval(86_400) {
                    result.date = date; break
                }
            }
        }

        // Nome do posto: primeira linha (nas 6 primeiras) com "POSTO", ou a primeira com letras
        let top = Array(lines.prefix(6))
        let station = top.first { $0.uppercased().contains("POSTO") }
            ?? top.first { line in
                let letters = line.filter(\.isLetter).count
                return letters >= 6 && !line.uppercased().contains("CNPJ") && !line.uppercased().contains("DOCUMENTO")
            }
        if let station {
            result.station = station
                .replacingOccurrences(of: "LTDA", with: "", options: .caseInsensitive)
                .replacingOccurrences(of: " - ME", with: "", options: .caseInsensitive)
                .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
                .capitalized
        }
        return result
    }
}

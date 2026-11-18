import Foundation

extension Double {
    /// Moeda brasileira (R$ 1.234,56).
    var brl: String { formatted(.currency(code: "BRL")) }

    /// Moeda sem centavos (R$ 1.235).
    var brlNoCents: String { formatted(.currency(code: "BRL").precision(.fractionLength(0))) }

    /// Valor para edição em campo de texto (respeita vírgula decimal).
    var decimalInput: String {
        formatted(.number.precision(.fractionLength(0...2)).grouping(.never))
    }

    /// Converte texto digitado ("45,90" ou "45.90") em Double.
    static func parse(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let formatter = NumberFormatter()
        formatter.locale = .current
        formatter.numberStyle = .decimal
        if let number = formatter.number(from: trimmed) { return number.doubleValue }
        return Double(trimmed.replacingOccurrences(of: ",", with: "."))
    }
}

extension Int {
    var km: String { "\(formatted(.number)) km" }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var digitsOnly: Int? { Int(filter(\.isNumber)) }
}

extension Date {
    var startOfMonth: Date {
        Calendar.current.dateInterval(of: .month, for: self)?.start ?? self
    }

    var dayNumber: String { formatted(.dateTime.day()) }

    /// "NOV"
    var monthShortUpper: String {
        formatted(.dateTime.month(.abbreviated)).replacingOccurrences(of: ".", with: "").uppercased()
    }

    /// "QUI"
    var weekdayShortUpper: String {
        formatted(.dateTime.weekday(.abbreviated)).replacingOccurrences(of: ".", with: "").uppercased()
    }

    /// "12/11"
    var dayMonth: String { formatted(.dateTime.day(.twoDigits).month(.twoDigits)) }

    /// "hoje", "ontem", "há 6 dias"
    var relativeDays: String {
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: self), to: calendar.startOfDay(for: .now)).day ?? 0
        switch days {
        case ..<1: return "hoje"
        case 1: return "ontem"
        default: return "há \(days) dias"
        }
    }

    /// "HOJE · 18 NOV" / "QUI · 12 NOV"
    var dayHeader: String {
        let calendar = Calendar.current
        let prefix: String
        if calendar.isDateInToday(self) {
            prefix = "HOJE"
        } else if calendar.isDateInYesterday(self) {
            prefix = "ONTEM"
        } else {
            prefix = weekdayShortUpper
        }
        return "\(prefix) · \(dayNumber) \(monthShortUpper)"
    }
}

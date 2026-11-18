import Foundation
import SwiftData

@Model
final class Expense {
    var categoryRaw: String = ExpenseCategory.fuel.rawValue
    /// Nome do serviço, descrição da multa/seguro ou forma de pagamento do documento.
    var title: String = ""
    /// Posto, oficina ou local.
    var place: String = ""
    var amount: Double = 0
    var date: Date = Date()
    var odometer: Int?
    var liters: Double?
    var fuelType: String = ""
    var isFullTank: Bool = true
    /// Intervalo para o próximo serviço (manutenção).
    var intervalKm: Int?
    var intervalMonths: Int?
    /// Ano de referência para IPVA, licenciamento e demais documentos.
    var referenceYear: Int?
    var notes: String = ""
    @Attribute(.externalStorage) var receiptData: Data?
    var vehicle: Vehicle?

    init(category: ExpenseCategory = .other, amount: Double = 0, date: Date = .now) {
        self.categoryRaw = category.rawValue
        self.amount = amount
        self.date = date
    }

    var category: ExpenseCategory {
        get { ExpenseCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }

    var hasReceipt: Bool { receiptData != nil }

    var effectiveYear: Int {
        referenceYear ?? Calendar.current.component(.year, from: date)
    }

    var pricePerLiter: Double? {
        guard let liters, liters > 0 else { return nil }
        return amount / liters
    }

    var displayTitle: String {
        switch category {
        case .fuel:
            return fuelType.isEmpty ? "Abastecimento" : fuelType
        case .ipva, .licensing:
            return "\(category.displayName) \(effectiveYear)"
        default:
            return title.isEmpty ? category.displayName : title
        }
    }

    /// Título curto usado no diário de bordo.
    var logTitle: String {
        category == .fuel ? "Abastecimento" : displayTitle
    }

    var detailLine: String {
        var parts: [String] = []
        switch category {
        case .fuel:
            if let liters, liters > 0 {
                parts.append("\(liters.formatted(.number.precision(.fractionLength(1)))) L")
            }
            if !place.isEmpty { parts.append(place) }
        case .ipva, .licensing:
            parts.append(title.isEmpty ? "Pago em \(date.dayMonth)" : title)
        default:
            if !place.isEmpty { parts.append(place) }
        }
        if let odometer { parts.append(odometer.km) }
        if parts.isEmpty { parts.append(date.formatted(date: .abbreviated, time: .omitted)) }
        return parts.joined(separator: " · ")
    }
}

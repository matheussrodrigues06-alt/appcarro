import Foundation
import SwiftData

/// Um valor mensal da Tabela FIPE do carro (para o gráfico de desvalorização).
@Model
final class FipeEntry {
    var reference: String = ""
    var value: Double = 0
    var date: Date = Date()
    var vehicle: Vehicle?

    init(reference: String, value: Double, date: Date = .now) {
        self.reference = reference
        self.value = value
        self.date = date
    }
}

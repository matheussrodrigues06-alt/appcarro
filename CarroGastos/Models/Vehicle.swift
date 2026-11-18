import Foundation
import SwiftData

@Model
final class Vehicle {
    var uuid: UUID = UUID()
    var name: String = ""
    var brand: String = ""
    var modelName: String = ""
    /// Versão / motorização (ex.: 2.0 16v Flex Automático).
    var version: String = ""
    var year: Int = 0
    var plate: String = ""
    var initialOdometer: Int = 0
    var odometer: Int = 0
    var odometerUpdatedAt: Date = Date()
    var batteryChangedAt: Date?
    var fipeValue: Double = 0
    /// Alíquota do IPVA em % (varia por estado).
    var ipvaRate: Double = 4.0
    var createdAt: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \Expense.vehicle)
    var expenses: [Expense] = []

    init(name: String) {
        self.uuid = UUID()
        self.name = name
        self.createdAt = .now
        self.odometerUpdatedAt = .now
    }
}

// MARK: - Estatísticas

extension Vehicle {
    static var currentYear: Int { Calendar.current.component(.year, from: .now) }

    var subtitle: String {
        var parts: [String] = []
        let brandModel = [brand, modelName].filter { !$0.isEmpty }.joined(separator: " ")
        if !brandModel.isEmpty { parts.append(brandModel) }
        if year > 0 { parts.append(String(year)) }
        return parts.joined(separator: " · ")
    }

    var eyebrow: String {
        [brand.uppercased(), year > 0 ? String(year) : ""].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    var currentOdometer: Int {
        max(odometer, initialOdometer, expenses.compactMap(\.odometer).max() ?? 0)
    }

    var lastOdometerDate: Date {
        let expenseDates = expenses.filter { $0.odometer != nil }.map(\.date)
        return ([odometerUpdatedAt] + expenseDates).max() ?? odometerUpdatedAt
    }

    var distanceDriven: Int { max(0, currentOdometer - initialOdometer) }

    var totalSpent: Double { expenses.reduce(0) { $0 + $1.amount } }

    var costPerKm: Double? {
        guard distanceDriven > 0 else { return nil }
        return totalSpent / Double(distanceDriven)
    }

    var sortedExpenses: [Expense] { expenses.sorted { $0.date > $1.date } }

    var lastFuel: Expense? {
        expenses.filter { $0.category == .fuel }.max { $0.date < $1.date }
    }

    var lastService: Expense? {
        expenses.filter { $0.category == .maintenance }.max { $0.date < $1.date }
    }

    /// Consumo médio (km/l) pelo método tanque cheio → tanque cheio.
    var fuelEfficiency: Double? {
        let fills = expenses
            .filter { $0.category == .fuel && $0.odometer != nil && ($0.liters ?? 0) > 0 }
            .sorted { ($0.odometer ?? 0) < ($1.odometer ?? 0) }

        var totalKm = 0.0
        var totalLiters = 0.0
        var lastFullOdometer: Int?
        var litersSinceLastFull = 0.0

        for fill in fills {
            guard let km = fill.odometer, let liters = fill.liters else { continue }
            if let last = lastFullOdometer {
                litersSinceLastFull += liters
                if fill.isFullTank {
                    totalKm += Double(km - last)
                    totalLiters += litersSinceLastFull
                    lastFullOdometer = km
                    litersSinceLastFull = 0
                }
            } else if fill.isFullTank {
                lastFullOdometer = km
            }
        }
        guard totalLiters > 0, totalKm > 0 else { return nil }
        return totalKm / totalLiters
    }

    var monthlyAverage: Double {
        guard let first = expenses.map(\.date).min() else { return 0 }
        let months = (Calendar.current.dateComponents([.month], from: first.startOfMonth, to: Date().startOfMonth).month ?? 0) + 1
        return totalSpent / Double(max(months, 1))
    }

    // MARK: Documentação

    var ipvaEstimate: Double? {
        guard fipeValue > 0, ipvaRate > 0 else { return nil }
        return fipeValue * ipvaRate / 100
    }

    func payment(_ category: ExpenseCategory, year: Int) -> Expense? {
        expenses
            .filter { $0.category == category && $0.effectiveYear == year }
            .max { $0.date < $1.date }
    }

    func paidObligations(year: Int) -> Int {
        [ExpenseCategory.ipva, .licensing].filter { payment($0, year: year) != nil }.count
    }

    func documentExpenses(year: Int) -> [Expense] {
        expenses.filter { $0.category.isDocument && $0.effectiveYear == year }
    }

    var docsUpToDate: Bool { paidObligations(year: Vehicle.currentYear) == 2 }

    // MARK: Serviços

    var serviceReminders: [ServiceReminder] {
        let current = currentOdometer
        let withInterval = expenses.filter {
            $0.category == .maintenance && (($0.intervalKm ?? 0) > 0 || ($0.intervalMonths ?? 0) > 0)
        }
        let latest = Dictionary(grouping: withInterval) {
            $0.title.lowercased().trimmingCharacters(in: .whitespaces)
        }
        .compactMap { $0.value.max { $0.date < $1.date } }

        return latest
            .map { ServiceReminder(expense: $0, currentOdometer: current) }
            .sorted { lhs, rhs in
                if lhs.status != rhs.status { return lhs.status > rhs.status }
                return lhs.urgencyScore < rhs.urgencyScore
            }
    }

    var overallStatus: DueStatus {
        let worstService = serviceReminders.map(\.status).max() ?? .ok
        return max(worstService, docsUpToDate ? .ok : .soon)
    }

    // MARK: Bateria

    var batteryAgeMonths: Int? {
        guard let batteryChangedAt else { return nil }
        return Calendar.current.dateComponents([.month], from: batteryChangedAt, to: .now).month
    }

    /// Vida útil restante estimada (bateria dura ~36 meses).
    var batteryRemaining: Double? {
        guard let months = batteryAgeMonths else { return nil }
        return min(1, max(0, 1 - Double(months) / 36))
    }

    // MARK: Exportação

    var csv: String {
        var lines = ["Data;Categoria;Descrição;Local;Valor;Hodômetro (km);Litros;Observações"]
        for e in expenses.sorted(by: { $0.date < $1.date }) {
            let columns = [
                e.date.formatted(date: .numeric, time: .omitted),
                e.category.displayName,
                e.displayTitle,
                e.place,
                e.amount.decimalInput,
                e.odometer.map(String.init) ?? "",
                e.liters?.decimalInput ?? "",
                e.notes
            ].map { $0.replacingOccurrences(of: ";", with: ",").replacingOccurrences(of: "\n", with: " ") }
            lines.append(columns.joined(separator: ";"))
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - Lembrete de serviço

struct ServiceReminder: Identifiable {
    let expense: Expense
    let dueKm: Int?
    let dueDate: Date?
    let kmRemaining: Int?
    let daysRemaining: Int?
    let status: DueStatus

    var id: PersistentIdentifier { expense.persistentModelID }

    init(expense: Expense, currentOdometer: Int) {
        self.expense = expense
        let calendar = Calendar.current

        var dueKm: Int?
        var kmRemaining: Int?
        if let interval = expense.intervalKm, interval > 0, let km = expense.odometer {
            dueKm = km + interval
            kmRemaining = km + interval - currentOdometer
        }

        var dueDate: Date?
        var daysRemaining: Int?
        if let months = expense.intervalMonths, months > 0,
           let date = calendar.date(byAdding: .month, value: months, to: expense.date) {
            dueDate = date
            daysRemaining = calendar.dateComponents(
                [.day],
                from: calendar.startOfDay(for: .now),
                to: calendar.startOfDay(for: date)
            ).day
        }

        let overdue = (kmRemaining.map { $0 <= 0 } ?? false) || (daysRemaining.map { $0 <= 0 } ?? false)
        let soon = (kmRemaining.map { $0 <= 1000 } ?? false) || (daysRemaining.map { $0 <= 30 } ?? false)

        self.dueKm = dueKm
        self.kmRemaining = kmRemaining
        self.dueDate = dueDate
        self.daysRemaining = daysRemaining
        self.status = overdue ? .overdue : (soon ? .soon : .ok)
    }

    /// Quanto menor, mais urgente (usado para ordenar).
    var urgencyScore: Double {
        let kmScore = kmRemaining.map { Double($0) / 1000 } ?? .infinity
        let dayScore = daysRemaining.map { Double($0) / 30 } ?? .infinity
        return min(kmScore, dayScore)
    }

    var title: String {
        expense.title.isEmpty ? "Serviço" : expense.title
    }

    var summary: String {
        var parts: [String] = []
        if let kmRemaining, let dueKm {
            parts.append(kmRemaining > 0 ? "em \(dueKm.km) (faltam \(kmRemaining.km))" : "passou \((-kmRemaining).km)")
        }
        if let daysRemaining, let dueDate {
            if daysRemaining > 0 {
                parts.append("até \(dueDate.formatted(date: .numeric, time: .omitted))")
            } else {
                parts.append(daysRemaining == 0 ? "vence hoje" : "venceu há \(-daysRemaining) dias")
            }
        }
        return parts.joined(separator: " · ")
    }
}

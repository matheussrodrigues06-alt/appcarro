import Foundation
import SwiftData

/// Ações que o assistente pode executar no app. Tudo roda no aparelho.
@MainActor
final class AgentActions {
    let vehicle: Vehicle
    let context: ModelContext

    /// O que foi feito durante a última mensagem (mostrado como cartões no chat, com "Desfazer").
    private(set) var performed: [PerformedAction] = []

    struct PerformedAction: Identifiable {
        let id = UUID()
        let icon: String
        let title: String
        let detail: String
        var expense: Expense?
        var previousOdometer: (value: Int, date: Date)?
    }

    init(vehicle: Vehicle, context: ModelContext) {
        self.vehicle = vehicle
        self.context = context
    }

    func beginTurn() { performed.removeAll() }

    // MARK: Registrar

    func addFuel(amount: Double, liters: Double?, pricePerLiter: Double?, odometer: Int?, station: String?, fuelType: String?, date: String?) -> String {
        guard amount > 0 else { return "Erro: o valor precisa ser maior que zero. Pergunte o valor à pessoa." }
        let expense = Expense(category: .fuel, amount: amount, date: Self.parseDate(date) ?? .now)
        if let liters, liters > 0 {
            expense.liters = liters
        } else if let pricePerLiter, pricePerLiter > 0 {
            expense.liters = amount / pricePerLiter
        }
        expense.odometer = odometer
        expense.place = station?.trimmed ?? ""
        expense.fuelType = Self.normalizedFuel(fuelType) ?? vehicle.lastFuel?.fuelType ?? "Gasolina comum"
        expense.isFullTank = true
        insert(expense)
        var parts = [amount.brl]
        if let l = expense.liters { parts.append("\(l.formatted(.number.precision(.fractionLength(1)))) L") }
        if !expense.place.isEmpty { parts.append(expense.place) }
        if let odometer { parts.append(odometer.km) }
        let detail = parts.joined(separator: " · ")
        performed.append(PerformedAction(icon: "fuelpump.fill", title: "Abastecimento lançado", detail: detail, expense: expense))
        return "Registrado: abastecimento de \(detail) em \(expense.date.formatted(date: .numeric, time: .omitted))."
    }

    func addService(title: String, amount: Double?, place: String?, odometer: Int?, intervalKm: Int?, intervalMonths: Int?, date: String?) -> String {
        let name = title.trimmed.isEmpty ? "Serviço" : title.trimmed.capitalizedFirst
        let expense = Expense(category: .maintenance, amount: max(0, amount ?? 0), date: Self.parseDate(date) ?? .now)
        expense.title = name
        expense.place = place?.trimmed ?? ""
        expense.odometer = odometer ?? vehicle.currentOdometer
        expense.intervalKm = (intervalKm ?? 0) > 0 ? intervalKm : nil
        expense.intervalMonths = (intervalMonths ?? 0) > 0 ? intervalMonths : nil
        insert(expense)
        var parts = [name]
        if expense.amount > 0 { parts.append(expense.amount.brl) }
        if !expense.place.isEmpty { parts.append(expense.place) }
        if let km = expense.intervalKm { parts.append("próxima em \(km.km)") }
        if let m = expense.intervalMonths { parts.append("ou \(m) meses") }
        let detail = parts.joined(separator: " · ")
        performed.append(PerformedAction(icon: "wrench.and.screwdriver.fill", title: "Serviço registrado", detail: detail, expense: expense))
        return "Registrado: \(detail)."
    }

    func addExpense(kind: String, description: String?, amount: Double, date: String?) -> String {
        guard amount > 0 else { return "Erro: o valor precisa ser maior que zero. Pergunte o valor à pessoa." }
        let category = Self.category(for: kind)
        let expense = Expense(category: category, amount: amount, date: Self.parseDate(date) ?? .now)
        expense.title = description?.trimmed ?? ""
        if category == .ipva || category == .licensing || category.isDocument {
            expense.referenceYear = Calendar.current.component(.year, from: expense.date)
        }
        insert(expense)
        let detail = "\(expense.displayTitle) · \(amount.brl)"
        performed.append(PerformedAction(icon: category.icon, title: "\(category.displayName) registrado", detail: detail, expense: expense))
        return "Registrado: \(detail)."
    }

    func updateOdometer(_ km: Int) -> String {
        guard km > 0 else { return "Erro: informe um km válido." }
        let previous = (vehicle.odometer, vehicle.odometerUpdatedAt)
        let warning = km < vehicle.currentOdometer ? " Atenção: é menor que o último registro (\(vehicle.currentOdometer.km))." : ""
        vehicle.odometer = km
        vehicle.odometerUpdatedAt = .now
        try? context.save()
        performed.append(PerformedAction(icon: "speedometer", title: "Km atualizado", detail: km.km, previousOdometer: previous))
        return "Hodômetro atualizado para \(km.km).\(warning)"
    }

    /// Completa o último abastecimento com litros, preço por litro ou km ditos depois.
    func updateFuel(_ expense: Expense, liters: Double?, pricePerLiter: Double?, odometer: Int?) -> String {
        if let liters, liters > 0 {
            expense.liters = liters
        } else if let pricePerLiter, pricePerLiter > 0, expense.amount > 0 {
            expense.liters = expense.amount / pricePerLiter
        }
        if let odometer, odometer > 0 { expense.odometer = odometer }
        try? context.save()
        var parts = [expense.amount.brl]
        if let l = expense.liters { parts.append("\(l.formatted(.number.precision(.fractionLength(2)))) L") }
        if let km = expense.odometer { parts.append(km.km) }
        let detail = parts.joined(separator: " · ")
        performed.append(PerformedAction(icon: "fuelpump.fill", title: "Abastecimento atualizado", detail: detail))
        return "Atualizei o abastecimento: \(detail) ✅"
    }

    // MARK: Consultar

    func summary(period: String) -> String {
        let calendar = Calendar.current
        let now = Date()
        let p = period.lowercased()
        let items: [Expense]
        let label: String
        if p.contains("ano") {
            items = vehicle.expenses.filter { calendar.isDate($0.date, equalTo: now, toGranularity: .year) }
            label = "em \(calendar.component(.year, from: now))"
        } else if p.contains("pass") {
            let last = calendar.date(byAdding: .month, value: -1, to: now) ?? now
            items = vehicle.expenses.filter { calendar.isDate($0.date, equalTo: last, toGranularity: .month) }
            label = "no mês passado"
        } else if p.contains("tudo") || p.contains("total") || p.contains("sempre") {
            items = vehicle.expenses
            label = "desde o início"
        } else {
            items = vehicle.expenses.filter { calendar.isDate($0.date, equalTo: now, toGranularity: .month) }
            label = "neste mês"
        }
        let total = items.reduce(0) { $0 + $1.amount }
        var lines = ["Carro: \(vehicle.name). Total gasto \(label): \(total.brl) em \(items.count) registros."]
        for group in ExpenseGroup.allCases {
            let sum = items.filter { $0.category.group == group }.reduce(0) { $0 + $1.amount }
            if sum > 0 { lines.append("- \(group.rawValue): \(sum.brl)") }
        }
        lines.append("Hodômetro atual: \(vehicle.currentOdometer.km).")
        if let eff = vehicle.fuelEfficiency { lines.append("Consumo médio: \(eff.formatted(.number.precision(.fractionLength(1)))) km/l.") }
        if let cpk = vehicle.costPerKm { lines.append("Custo por km: \(cpk.brl).") }
        if vehicle.monthlyBudget > 0 { lines.append("Orçamento mensal: \(vehicle.monthlyBudget.brl); gasto no mês: \(vehicle.monthTotal.brl).") }
        if vehicle.fipeValue > 0 { lines.append("Valor FIPE: \(vehicle.fipeValue.brl).") }
        if let fuel = vehicle.lastFuel {
            lines.append("Último abastecimento: \(fuel.amount.brl) em \(fuel.date.formatted(date: .numeric, time: .omitted)).")
        }
        let reminders = vehicle.serviceReminders.prefix(3)
        if !reminders.isEmpty {
            lines.append("Próximos serviços: " + reminders.map { "\($0.title) (\($0.summary))" }.joined(separator: "; ") + ".")
        }
        let paid = vehicle.paidObligations(year: Vehicle.currentYear)
        lines.append("Documentação \(Vehicle.currentYear): \(paid) de 2 pagos (IPVA e licenciamento).")
        if let prices = FuelPriceStore.shared.prices {
            var p = ["Preço médio em \(FuelPriceStore.shared.cityLabel):"]
            if let g = prices.gasolina { p.append("gasolina \(g.brl)") }
            if let e = prices.etanol { p.append("etanol \(e.brl)") }
            lines.append(p.joined(separator: " ") + ".")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: Desfazer

    func undo(_ action: PerformedAction) {
        if let expense = action.expense {
            vehicle.expenses.removeAll { $0 == expense }
            context.delete(expense)
        }
        if let previous = action.previousOdometer {
            vehicle.odometer = previous.value
            vehicle.odometerUpdatedAt = previous.date
        }
        try? context.save()
    }

    // MARK: Auxiliares

    private func insert(_ expense: Expense) {
        context.insert(expense)
        vehicle.expenses.append(expense)
        try? context.save()
    }

    static func parseDate(_ text: String?) -> Date? {
        guard let text = text?.trimmed, !text.isEmpty else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: text), date <= Date().addingTimeInterval(86_400) else { return nil }
        return date
    }

    static func normalizedFuel(_ text: String?) -> String? {
        guard let t = text?.lowercased(), !t.isEmpty else { return nil }
        if t.contains("adit") { return "Gasolina aditivada" }
        if t.contains("gasol") { return "Gasolina comum" }
        if t.contains("etanol") || t.contains("álcool") || t.contains("alcool") { return "Etanol" }
        if t.contains("diesel") { return "Diesel" }
        if t.contains("gnv") || t.contains("gás") { return "GNV" }
        return nil
    }

    static func category(for kind: String) -> ExpenseCategory {
        let k = kind.lowercased()
        if k.contains("multa") { return .fine }
        if k.contains("seguro") { return .insurance }
        if k.contains("ipva") { return .ipva }
        if k.contains("licenc") { return .licensing }
        if k.contains("taxa") || k.contains("pedág") || k.contains("pedag") || k.contains("estacion") { return .fee }
        return .other
    }
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

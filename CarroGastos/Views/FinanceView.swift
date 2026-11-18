import SwiftUI
import SwiftData
import Charts

struct FinanceView: View {
    let vehicle: Vehicle
    @Binding var selectedID: String
    @Environment(\.modelContext) private var context
    @State private var mode: Mode = .entries
    @State private var period: Period = .thisMonth
    @State private var search = ""
    @State private var editing: Expense?

    enum Mode: String, CaseIterable, Identifiable {
        case entries = "Lançamentos"
        case analysis = "Análise"
        var id: Self { self }
    }

    enum Period: String, CaseIterable, Identifiable {
        case thisMonth = "Este mês"
        case lastMonth = "Mês passado"
        case last3 = "Últimos 3 meses"
        case thisYear = "Este ano"
        case all = "Tudo"
        var id: Self { self }

        func contains(_ date: Date) -> Bool {
            let calendar = Calendar.current
            let now = Date()
            switch self {
            case .all:
                return true
            case .thisMonth:
                return calendar.isDate(date, equalTo: now, toGranularity: .month)
            case .lastMonth:
                guard let last = calendar.date(byAdding: .month, value: -1, to: now) else { return false }
                return calendar.isDate(date, equalTo: last, toGranularity: .month)
            case .last3:
                guard let start = calendar.date(byAdding: .month, value: -2, to: now.startOfMonth) else { return false }
                return date >= start
            case .thisYear:
                return calendar.isDate(date, equalTo: now, toGranularity: .year)
            }
        }
    }

    struct GroupTotal: Identifiable {
        let group: ExpenseGroup
        let total: Double
        var id: ExpenseGroup { group }
    }

    struct MonthGroup: Identifiable {
        let month: Date
        let items: [Expense]
        var id: Date { month }
        var total: Double { items.reduce(0) { $0 + $1.amount } }
    }

    struct MonthTotal: Identifiable {
        let month: Date
        let total: Double
        var id: Date { month }
    }

    // MARK: Dados

    private var periodExpenses: [Expense] {
        vehicle.expenses.filter { period.contains($0.date) }
    }

    private var periodTotal: Double { periodExpenses.reduce(0) { $0 + $1.amount } }

    private var groupTotals: [GroupTotal] {
        ExpenseGroup.allCases
            .map { group in
                GroupTotal(group: group, total: periodExpenses.filter { $0.category.group == group }.reduce(0) { $0 + $1.amount })
            }
            .filter { $0.total > 0 }
            .sorted { $0.total > $1.total }
    }

    private var monthGroups: [MonthGroup] {
        let query = search.trimmed.lowercased()
        let filtered = periodExpenses.filter { expense in
            guard !query.isEmpty else { return true }
            return [expense.displayTitle, expense.place, expense.notes, expense.category.displayName]
                .contains { $0.lowercased().contains(query) }
        }
        let grouped = Dictionary(grouping: filtered) { $0.date.startOfMonth }
        return grouped.keys.sorted(by: >).map { month in
            MonthGroup(month: month, items: (grouped[month] ?? []).sorted { $0.date > $1.date })
        }
    }

    private var lastSixMonths: [MonthTotal] {
        let calendar = Calendar.current
        let thisMonth = Date().startOfMonth
        return (0..<6).reversed()
            .compactMap { calendar.date(byAdding: .month, value: -$0, to: thisMonth) }
            .map { month in
                MonthTotal(month: month, total: vehicle.expenses.filter { $0.date.startOfMonth == month }.reduce(0) { $0 + $1.amount })
            }
    }

    // MARK: Layout

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Visualização", selection: $mode) {
                        ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }

                Section { summary }

                if mode == .entries {
                    entries
                } else {
                    analysis
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Gastos")
            .searchable(text: $search, prompt: "Buscar lançamentos")
            .appToolbar(vehicle: vehicle, selectedID: $selectedID)
            .sheet(item: $editing) { expense in
                ExpenseFormView(vehicle: vehicle, expense: expense)
            }
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Total gasto").font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                Menu {
                    Picker("Período", selection: $period) {
                        ForEach(Period.allCases) { Text($0.rawValue).tag($0) }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(period.rawValue)
                        Image(systemName: "chevron.up.chevron.down").font(.caption2)
                    }
                    .font(.rounded(14, .semibold))
                }
            }
            Text(periodTotal.brl)
                .font(.rounded(34, .bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            StackedBar(items: groupTotals, total: periodTotal)

            if !groupTotals.isEmpty {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible())], alignment: .leading, spacing: 10) {
                    ForEach(groupTotals) { item in
                        HStack(spacing: 6) {
                            Circle().fill(item.group.color).frame(width: 8, height: 8)
                            Text(item.group.rawValue).font(.caption).lineLimit(1)
                            Spacer(minLength: 2)
                            Text(item.total.brlNoCents)
                                .font(.caption.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var entries: some View {
        if monthGroups.isEmpty {
            Section {
                VStack(spacing: 8) {
                    Image(systemName: "tray").font(.title).foregroundStyle(.secondary)
                    Text(search.isEmpty ? "Nenhum gasto neste período" : "Nada encontrado")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            }
        } else {
            ForEach(monthGroups) { group in
                Section {
                    ForEach(group.items) { expense in
                        Button { editing = expense } label: { ExpenseRow(expense: expense) }
                            .buttonStyle(.plain)
                    }
                    .onDelete { offsets in delete(offsets.map { group.items[$0] }) }
                } header: {
                    HStack {
                        Text(group.month.formatted(.dateTime.month(.wide).year()).capitalized)
                        Spacer()
                        Text(group.total.brl).monospacedDigit()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var analysis: some View {
        Section("Indicadores") {
            metric("Custo por km", vehicle.costPerKm?.brl ?? "—", "road.lanes", Color.brand)
            metric("Consumo médio",
                   vehicle.fuelEfficiency.map { "\($0.formatted(.number.precision(.fractionLength(1)))) km/l" } ?? "—",
                   "fuelpump.fill", Color.fuelBlue)
            metric("Média mensal", vehicle.monthlyAverage.brl, "calendar", Color.serviceViolet)
            metric("Km rodados", vehicle.distanceDriven.km, "speedometer", Color.docsTeal)
            metric("Total desde o início", vehicle.totalSpent.brl, "sum", Color.gray)
        }

        Section("Últimos 6 meses") {
            Chart(lastSixMonths) { item in
                BarMark(
                    x: .value("Mês", item.month, unit: .month),
                    y: .value("Total", item.total)
                )
                .foregroundStyle(Color.brand)
                .cornerRadius(6)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .month)) { _ in
                    AxisValueLabel(format: .dateTime.month(.abbreviated), centered: true)
                }
            }
            .chartYAxis {
                AxisMarks { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let amount = value.as(Double.self) { Text(amount.brlNoCents) }
                    }
                }
            }
            .frame(height: 200)
            .padding(.vertical, 8)
        }

        let prices = Array(
            vehicle.expenses
                .filter { $0.category == .fuel && $0.pricePerLiter != nil }
                .sorted { $0.date < $1.date }
                .suffix(12)
        )
        if prices.count >= 2 {
            Section("Preço do litro") {
                Chart(prices) { item in
                    LineMark(
                        x: .value("Data", item.date),
                        y: .value("R$/L", item.pricePerLiter ?? 0)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(Color.fuelBlue)
                    PointMark(
                        x: .value("Data", item.date),
                        y: .value("R$/L", item.pricePerLiter ?? 0)
                    )
                    .foregroundStyle(Color.fuelBlue)
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .chartYAxis {
                    AxisMarks { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let price = value.as(Double.self) { Text(price.brl) }
                        }
                    }
                }
                .frame(height: 180)
                .padding(.vertical, 8)
            }
        }

        if !groupTotals.isEmpty {
            Section("Por categoria · \(period.rawValue.lowercased())") {
                Chart(groupTotals) { item in
                    BarMark(
                        x: .value("Total", item.total),
                        y: .value("Categoria", item.group.rawValue)
                    )
                    .foregroundStyle(item.group.color)
                    .cornerRadius(6)
                    .annotation(position: .trailing) {
                        Text(item.total.brlNoCents).font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .chartXAxis(.hidden)
                .frame(height: CGFloat(groupTotals.count) * 44 + 10)
                .padding(.vertical, 8)
            }
        }
    }

    private func metric(_ title: String, _ value: String, _ icon: String, _ color: Color) -> some View {
        LabeledContent {
            Text(value).font(.rounded(16, .semibold)).monospacedDigit().foregroundStyle(.primary)
        } label: {
            HStack(spacing: 12) {
                IconTile(systemName: icon, color: color, size: 32)
                Text(title)
            }
        }
    }

    private func delete(_ items: [Expense]) {
        for item in items {
            vehicle.expenses.removeAll { $0 == item }
            context.delete(item)
        }
        try? context.save()
    }
}

/// Barra horizontal dividida pela participação de cada grupo.
struct StackedBar: View {
    let items: [FinanceView.GroupTotal]
    let total: Double

    var body: some View {
        GeometryReader { proxy in
            if total > 0, !items.isEmpty {
                let spacing: CGFloat = 3
                let available = proxy.size.width - spacing * CGFloat(items.count - 1)
                HStack(spacing: spacing) {
                    ForEach(items) { item in
                        Rectangle()
                            .fill(item.group.color)
                            .frame(width: max(4, available * item.total / total))
                    }
                }
            } else {
                Rectangle().fill(Color.secondary.opacity(0.2))
            }
        }
        .frame(height: 12)
        .clipShape(Capsule())
    }
}

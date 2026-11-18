import SwiftUI
import Charts

struct FinanceView: View {
    let vehicle: Vehicle
    @State private var mode: Mode = .statement
    @State private var period: Period = .thisMonth
    @State private var search = ""
    @State private var editing: Expense?

    enum Mode: String, CaseIterable, Identifiable {
        case statement = "Extrato"
        case summary = "Resumo"
        var id: Self { self }
        var icon: String { self == .statement ? "list.bullet" : "chart.pie" }
    }

    enum Period: String, CaseIterable, Identifiable {
        case all = "Tudo"
        case thisMonth = "Este mês"
        case lastMonth = "Mês passado"
        case last3 = "Últimos 3 meses"
        case thisYear = "Este ano"
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

        var centerLabel: String {
            let now = Date()
            switch self {
            case .all: return "Total"
            case .thisMonth: return now.formatted(.dateTime.month(.wide)).capitalized
            case .lastMonth:
                let last = Calendar.current.date(byAdding: .month, value: -1, to: now) ?? now
                return last.formatted(.dateTime.month(.wide)).capitalized
            case .last3: return "3 meses"
            case .thisYear: return String(Vehicle.currentYear)
            }
        }
    }

    struct GroupTotal: Identifiable {
        let group: ExpenseGroup
        let total: Double
        var id: ExpenseGroup { group }
    }

    struct DayGroup: Identifiable {
        let day: Date
        let items: [Expense]
        var id: Date { day }
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
        ExpenseGroup.allCases.map { group in
            GroupTotal(group: group, total: periodExpenses.filter { $0.category.group == group }.reduce(0) { $0 + $1.amount })
        }
    }

    private var legend: [GroupTotal] {
        groupTotals.filter { $0.group != .other || $0.total > 0 }
    }

    private var searchedExpenses: [Expense] {
        let query = search.trimmed.lowercased()
        let base = periodExpenses.sorted { $0.date > $1.date }
        guard !query.isEmpty else { return base }
        return base.filter {
            [$0.displayTitle, $0.place, $0.notes, $0.title, $0.category.displayName, $0.category.group.rawValue]
                .contains { $0.lowercased().contains(query) }
        }
    }

    private var dayGroups: [DayGroup] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: searchedExpenses) { calendar.startOfDay(for: $0.date) }
        return grouped.keys.sorted(by: >).map { DayGroup(day: $0, items: grouped[$0] ?? []) }
    }

    private var lastSixMonths: [MonthTotal] {
        let calendar = Calendar.current
        let thisMonth = Date().startOfMonth
        return (0..<6).reversed().compactMap { calendar.date(byAdding: .month, value: -$0, to: thisMonth) }.map { month in
            MonthTotal(month: month, total: vehicle.expenses.filter { $0.date.startOfMonth == month }.reduce(0) { $0 + $1.amount })
        }
    }

    // MARK: Layout

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                ScreenTitle(text: "Financeiro")
                modePicker
                    .frame(maxWidth: .infinity)

                donut
                periodChips

                if mode == .statement {
                    searchField
                    statement
                } else {
                    summary
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.immediately)
        .sheet(item: $editing) { expense in
            ExpenseFormView(vehicle: vehicle, expense: expense)
        }
    }

    private var modePicker: some View {
        HStack(spacing: 4) {
            ForEach(Mode.allCases) { item in
                Button {
                    withAnimation(.snappy) { mode = item }
                } label: {
                    Label(item.rawValue, systemImage: item.icon)
                        .font(.system(size: 17, weight: mode == item ? .semibold : .regular))
                        .foregroundStyle(mode == item ? Color.white : Color.textSecondary)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 11)
                        .background {
                            if mode == item {
                                RoundedRectangle(cornerRadius: 13, style: .continuous).fill(Color.cardElevated)
                            }
                        }
                }
            }
        }
        .padding(4)
        .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 17, style: .continuous).strokeBorder(Color.cardStroke))
    }

    private var donut: some View {
        HStack(alignment: .center, spacing: 18) {
            ZStack {
                if periodTotal > 0 {
                    Chart(groupTotals.filter { $0.total > 0 }) { item in
                        SectorMark(
                            angle: .value("Valor", item.total),
                            innerRadius: .ratio(0.80),
                            angularInset: 2
                        )
                        .foregroundStyle(item.group.color)
                    }
                } else {
                    Circle().stroke(Color.cardElevated, lineWidth: 18).padding(9)
                }
                VStack(spacing: 4) {
                    Text(period.centerLabel)
                        .font(.system(size: 16))
                        .foregroundStyle(Color.white.opacity(0.75))
                    Text(periodTotal.brlNoCents)
                        .font(.system(size: 26, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
                .padding(.horizontal, 30)
            }
            .frame(width: 168, height: 168)

            VStack(alignment: .leading, spacing: 12) {
                ForEach(legend) { item in
                    HStack(spacing: 10) {
                        Capsule().fill(item.group.color).frame(width: 3.5, height: 42)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(item.group.rawValue)
                                .font(.system(size: 14))
                                .foregroundStyle(Color.white.opacity(0.75))
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text((periodTotal > 0 ? item.total / periodTotal : 0).formatted(.percent.precision(.fractionLength(0))))
                                    .font(.system(size: 22, weight: .bold))
                                Text(item.total.brlNoCents)
                                    .font(.system(size: 13))
                                    .foregroundStyle(Color.textSecondary)
                            }
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var periodChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(Period.allCases) { item in
                    Button {
                        withAnimation(.snappy) { period = item }
                    } label: {
                        Text(item.rawValue)
                            .font(.system(size: 16, weight: period == item ? .semibold : .regular))
                            .foregroundStyle(period == item ? Color.black : Color.white.opacity(0.8))
                            .padding(.horizontal, 18)
                            .padding(.vertical, 11)
                            .background(Capsule().fill(period == item ? Color.white : Color.cardBackground))
                            .overlay(Capsule().strokeBorder(Color.cardStroke))
                    }
                }
            }
        }
        .padding(.horizontal, -20)
        .contentMargins(.horizontal, 20, for: .scrollContent)
    }

    private var searchField: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass").foregroundStyle(Color.textSecondary)
            TextField("", text: $search, prompt: Text("Buscar por serviço, posto, documento…").foregroundColor(Color.textTertiary))
                .foregroundStyle(Color.white)
                .autocorrectionDisabled()
            if !search.isEmpty {
                Button { search = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Color.textSecondary)
                }
            }
        }
        .padding(17)
        .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.cardStroke))
    }

    @ViewBuilder
    private var statement: some View {
        if dayGroups.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "tray").font(.system(size: 30)).foregroundStyle(Color.textSecondary)
                Text(search.isEmpty ? "Nenhum gasto neste período" : "Nada encontrado")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
        } else {
            ForEach(dayGroups) { group in
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(group.day.dayHeader)
                            .font(.system(size: 14, weight: .semibold))
                            .tracking(2.4)
                            .foregroundStyle(Color.textSecondary)
                        Spacer()
                        Text(group.total.brl)
                            .font(.money(14))
                            .foregroundStyle(Color.textSecondary)
                    }
                    .padding(.horizontal, 6)

                    VStack(spacing: 0) {
                        ForEach(Array(group.items.enumerated()), id: \.element.id) { index, expense in
                            if index > 0 {
                                Rectangle().fill(Color.cardStroke).frame(height: 1).padding(.horizontal, 14)
                            }
                            Button { editing = expense } label: {
                                StatementRow(expense: expense)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Color.cardStroke))
                }
            }
        }
    }

    private var summary: some View {
        VStack(spacing: 14) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
                MetricTile(title: "Custo por km", value: vehicle.costPerKm?.brl ?? "—", icon: "road.lanes")
                MetricTile(
                    title: "Consumo médio",
                    value: vehicle.fuelEfficiency.map { "\($0.formatted(.number.precision(.fractionLength(1)))) km/l" } ?? "—",
                    icon: "leaf"
                )
                MetricTile(title: "Média mensal", value: vehicle.monthlyAverage.brl, icon: "calendar")
                MetricTile(title: "Km rodados", value: vehicle.distanceDriven.km, icon: "speedometer")
            }

            VStack(alignment: .leading, spacing: 16) {
                SectionLabel("Últimos 6 meses")
                Chart(lastSixMonths) { item in
                    BarMark(
                        x: .value("Mês", item.month, unit: .month),
                        y: .value("Total", item.total)
                    )
                    .foregroundStyle(Color.lime.gradient)
                    .cornerRadius(8)
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .month)) { _ in
                        AxisValueLabel(format: .dateTime.month(.abbreviated), centered: true)
                            .foregroundStyle(Color.textSecondary)
                    }
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisGridLine().foregroundStyle(Color.cardStroke)
                        AxisValueLabel {
                            if let amount = value.as(Double.self) {
                                Text(amount.brlNoCents).foregroundStyle(Color.textSecondary)
                            }
                        }
                    }
                }
                .frame(height: 190)
            }
            .darkCard()

            VStack(alignment: .leading, spacing: 10) {
                SectionLabel("Desde o início")
                Text(vehicle.totalSpent.brl)
                    .font(.money(30, weight: .bold))
                Text("\(vehicle.expenses.count) registros")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.textSecondary)
            }
            .darkCard()
        }
    }
}

struct StatementRow: View {
    let expense: Expense

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            CategoryBadge(category: expense.category)
            VStack(alignment: .leading, spacing: 4) {
                Text(expense.category.displayName.uppercased())
                    .font(.system(size: 13, weight: .bold))
                    .tracking(1.8)
                    .foregroundStyle(expense.category.color)
                Text(expense.displayTitle)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                Text(expense.detailLine)
                    .font(.system(size: 15))
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 6) {
                Text(expense.amount.brl)
                    .font(.money(17))
                    .foregroundStyle(Color.white)
                if let price = expense.pricePerLiter {
                    Text("\(price.brl)/L")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.textSecondary)
                } else if expense.hasReceipt {
                    Image(systemName: "paperclip")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.textSecondary)
                }
            }
        }
        .padding(18)
        .contentShape(Rectangle())
    }
}

struct MetricTile: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.black)
                .frame(width: 38, height: 38)
                .background(Color.lime, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 14)).foregroundStyle(Color.textSecondary)
                Text(value)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
        .darkCard(padding: 16)
    }
}

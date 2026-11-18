import SwiftUI

struct HomeView: View {
    let vehicle: Vehicle
    @Binding var selectedID: String
    @Binding var tab: AppTab
    @State private var sheet: HomeSheet?
    @AppStorage("gettingStartedDismissed") private var gettingStartedDismissed = false
    @AppStorage(ReminderScheduler.enabledKey) private var notificationsEnabled = false

    enum HomeSheet: Identifiable {
        case odometer, battery, fipe, budget, fuelCompare, trip, city
        case new(ExpenseCategory)
        case edit(Expense)

        var id: String {
            switch self {
            case .odometer: "odometer"
            case .battery: "battery"
            case .fipe: "fipe"
            case .budget: "budget"
            case .fuelCompare: "fuelCompare"
            case .trip: "trip"
            case .city: "city"
            case .new(let category): "new-\(category.rawValue)"
            case .edit(let expense): "edit-\(expense.persistentModelID.hashValue)"
            }
        }
    }

    private struct AlertItem: Identifiable {
        let id: String
        let icon: String
        let color: Color
        let title: String
        let subtitle: String
        let target: AppTab
    }

    private var monthTotal: Double { vehicle.monthTotal }

    private var alerts: [AlertItem] {
        var items = vehicle.serviceReminders.filter { $0.status != .ok }.map {
            AlertItem(id: "s-\($0.id.hashValue)", icon: "wrench.and.screwdriver.fill", color: $0.status.color,
                      title: $0.title, subtitle: $0.summary, target: .services)
        }
        let paid = vehicle.paidObligations(year: Vehicle.currentYear)
        if paid < 2 {
            items.append(AlertItem(id: "docs", icon: "doc.text.fill", color: Color.warning,
                                   title: "Documentação \(Vehicle.currentYear)",
                                   subtitle: "\(paid) de 2 obrigações pagas", target: .documents))
        }
        return items
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    heroCard
                    quickActions
                    gettingStarted
                    alertsSection
                    FuelPriceCard(vehicle: vehicle) { sheet = .city }
                    toolsSection
                    batteryCard
                    recentSection
                }
                .padding(16)
            }
            .background(BrandGlow())
            .navigationTitle("Início")
            .navigationBarTitleDisplayMode(.inline)
            .appToolbar(vehicle: vehicle, selectedID: $selectedID)
            .sheet(item: $sheet) { sheet in
                switch sheet {
                case .odometer: OdometerFormView(vehicle: vehicle)
                case .battery: BatteryFormView(vehicle: vehicle)
                case .fipe: FipeFormView(vehicle: vehicle)
                case .budget: BudgetFormView(vehicle: vehicle)
                case .fuelCompare: FuelCompareView(vehicle: vehicle)
                case .trip: TripCostView(vehicle: vehicle)
                case .city: FuelCityPickerView()
                case .new(let category): ExpenseFormView(vehicle: vehicle, category: category)
                case .edit(let expense): ExpenseFormView(vehicle: vehicle, expense: expense)
                }
            }
        }
    }

    // MARK: Cartão do carro

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(vehicle.subtitle.isEmpty ? "Meu carro" : vehicle.subtitle)
                        .font(.rounded(14, .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text(vehicle.name)
                        .font(.rounded(32, .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                Spacer()
                StatusBadge(status: vehicle.overallStatus)
            }
            if !vehicle.plate.isEmpty {
                MercosulPlate(plate: vehicle.plate)
            }
            Divider()
            HStack(alignment: .top, spacing: 8) {
                    HeroMetric(title: "Hodômetro", value: vehicle.currentOdometer.formatted(.number), unit: "km")
                    HeroMetric(
                        title: "Consumo",
                        value: vehicle.fuelEfficiency.map { $0.formatted(.number.precision(.fractionLength(1))) } ?? "—",
                        unit: vehicle.fuelEfficiency == nil ? "" : "km/l"
                    )
                    HeroMetric(title: "Este mês", value: monthTotal.brlNoCents, unit: "")
            }
            budgetBar
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 24)
    }

    @ViewBuilder
    private var budgetBar: some View {
        if vehicle.monthlyBudget > 0 {
            let ratio = monthTotal / vehicle.monthlyBudget
            let color = ratio > 1 ? Color.danger : (ratio > 0.85 ? Color.warning : Color.brand)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Orçamento do mês").font(.rounded(13, .medium)).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(monthTotal.brlNoCents) de \(vehicle.monthlyBudget.brlNoCents)")
                        .font(.rounded(13, .semibold))
                        .monospacedDigit()
                }
                ProgressView(value: min(ratio, 1)).tint(color)
                if ratio > 1 {
                    Text("Você passou \((monthTotal - vehicle.monthlyBudget).brlNoCents) do orçamento.")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.danger)
                }
            }
        }
    }

    // MARK: Ações rápidas

    private var quickActions: some View {
        HStack(alignment: .top, spacing: 8) {
            Button { sheet = .new(.fuel) } label: { QuickActionLabel(icon: "fuelpump.fill", title: "Abastecer") }
                .buttonStyle(.plain)
            Button { sheet = .odometer } label: { QuickActionLabel(icon: "speedometer", title: "Atualizar km") }
                .buttonStyle(.plain)
            Button { sheet = .new(.maintenance) } label: { QuickActionLabel(icon: "wrench.and.screwdriver.fill", title: "Serviço") }
                .buttonStyle(.plain)
            Menu {
                Button("Multa", systemImage: ExpenseCategory.fine.icon) { sheet = .new(.fine) }
                Button("Seguro", systemImage: ExpenseCategory.insurance.icon) { sheet = .new(.insurance) }
                Button("Taxa", systemImage: ExpenseCategory.fee.icon) { sheet = .new(.fee) }
                Button("Outro gasto", systemImage: ExpenseCategory.other.icon) { sheet = .new(.other) }
            } label: {
                QuickActionLabel(icon: "plus", title: "Outro gasto")
            }
        }
    }

    // MARK: Primeiros passos

    private struct Step: Identifiable {
        let id: String
        let title: String
        let icon: String
        let done: Bool
        let action: () -> Void
    }

    private var steps: [Step] {
        [
            Step(id: "fuel", title: "Registre um abastecimento", icon: "fuelpump.fill", done: vehicle.lastFuel != nil) { sheet = .new(.fuel) },
            Step(id: "fipe", title: "Informe o valor da FIPE", icon: "tag.fill", done: vehicle.fipeValue > 0) { sheet = .fipe },
            Step(id: "budget", title: "Defina um orçamento mensal", icon: "target", done: vehicle.monthlyBudget > 0) { sheet = .budget },
            Step(id: "battery", title: "Informe a troca da bateria", icon: "minus.plus.batteryblock", done: vehicle.batteryChangedAt != nil) { sheet = .battery },
            Step(id: "notify", title: "Ative os lembretes", icon: "bell.badge.fill", done: notificationsEnabled) { enableNotifications() },
        ]
    }

    @ViewBuilder
    private var gettingStarted: some View {
        let done = steps.filter(\.done).count
        if !gettingStartedDismissed && done < steps.count {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Primeiros passos").font(.rounded(18, .bold))
                        Text("\(done) de \(steps.count) concluídos · leva 1 minuto")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        withAnimation { gettingStartedDismissed = true }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.footnote.bold())
                            .foregroundStyle(.secondary)
                            .frame(width: 30, height: 30)
                            .background(Color.secondary.opacity(0.12), in: Circle())
                    }
                    .accessibilityLabel("Dispensar primeiros passos")
                }
                ProgressView(value: Double(done), total: Double(steps.count))
                    .tint(Color.brand)
                VStack(spacing: 2) {
                    ForEach(steps) { step in
                        Button(action: step.action) {
                            HStack(spacing: 12) {
                                Image(systemName: step.done ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundStyle(step.done ? Color.success : Color.secondary)
                                Image(systemName: step.icon)
                                    .font(.subheadline)
                                    .foregroundStyle(Color.brand)
                                    .frame(width: 22)
                                Text(step.title)
                                    .font(.rounded(15, .medium))
                                    .strikethrough(step.done)
                                    .foregroundStyle(step.done ? Color.secondary : Color.primary)
                                Spacer()
                                if !step.done {
                                    Image(systemName: "chevron.right")
                                        .font(.caption.bold())
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .padding(.vertical, 7)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(step.done)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard()
        }
    }

    private func enableNotifications() {
        Task {
            if await ReminderScheduler.requestAuthorization() {
                notificationsEnabled = true
                ReminderScheduler.reschedule(vehicles: [vehicle])
                Haptics.success()
            }
        }
    }

    // MARK: Ferramentas

    private var toolsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Ferramentas")
            HStack(spacing: 12) {
                ToolCard(icon: "drop.halffull", color: Color.docsTeal,
                         title: "Etanol ou gasolina?", subtitle: "Qual compensa hoje") { sheet = .fuelCompare }
                ToolCard(icon: "map.fill", color: Color.serviceViolet,
                         title: "Custo de viagem", subtitle: "Combustível e pedágio") { sheet = .trip }
            }
        }
    }

    // MARK: Atenção

    private var alertsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Atenção")
            VStack(spacing: 0) {
                if alerts.isEmpty {
                    HStack(spacing: 12) {
                        IconTile(systemName: "checkmark.seal.fill", color: Color.success, size: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Nada pendente").font(.rounded(16, .semibold))
                            Text("Serviços e documentos em dia").font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(14)
                } else {
                    ForEach(Array(alerts.enumerated()), id: \.element.id) { index, item in
                        if index > 0 { Divider().padding(.leading, 66) }
                        Button { tab = item.target } label: {
                            HStack(spacing: 12) {
                                IconTile(systemName: item.icon, color: item.color, size: 40)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title).font(.rounded(16, .semibold)).foregroundStyle(.primary)
                                    Text(item.subtitle).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.footnote.bold()).foregroundStyle(.tertiary)
                            }
                            .padding(14)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .glassCard()
        }
    }

    // MARK: Bateria

    private var batteryColor: Color {
        guard let remaining = vehicle.batteryRemaining else { return Color.brand }
        if remaining < 0.15 { return Color.danger }
        if remaining < 0.35 { return Color.warning }
        return Color.success
    }

    private var batteryCard: some View {
        Button { sheet = .battery } label: {
            HStack(spacing: 14) {
                IconTile(systemName: "minus.plus.batteryblock", color: batteryColor, size: 44)
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Bateria 12V").font(.rounded(16, .semibold))
                        Spacer()
                        Text(vehicle.batteryRemaining.map { $0.formatted(.percent.precision(.fractionLength(0))) } ?? "Informar")
                            .font(.rounded(14, .semibold))
                            .foregroundStyle(batteryColor)
                    }
                    if let remaining = vehicle.batteryRemaining, let months = vehicle.batteryAgeMonths {
                        ProgressView(value: remaining).tint(batteryColor)
                        Text(remaining > 0
                             ? "Trocada há \(months) \(months == 1 ? "mês" : "meses") · cerca de \(max(1, 36 - months)) meses restantes"
                             : "Passou da vida útil média. Vale fazer um teste de carga.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Informe a data da última troca para estimar a vida útil.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard()
            .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
    }

    // MARK: Atividade recente

    private var recentSection: some View {
        let recent = Array(vehicle.sortedExpenses.prefix(5))
        return VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Atividade recente", actionTitle: recent.isEmpty ? nil : "Ver todos") {
                tab = .finance
            }
            if recent.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Nenhum registro ainda. Que tal começar pelo próximo abastecimento?")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button("Registrar abastecimento") { sheet = .new(.fuel) }
                        .buttonStyle(PrimaryButtonStyle())
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassCard()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(recent.enumerated()), id: \.element.id) { index, expense in
                        if index > 0 { Divider().padding(.leading, 68) }
                        Button { sheet = .edit(expense) } label: {
                            ExpenseRow(expense: expense).padding(14)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .glassCard()
            }
        }
    }
}

struct ToolCard: View {
    let icon: String
    let color: Color
    let title: String
    let subtitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                IconTile(systemName: icon, color: color, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.rounded(15, .semibold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
            .glassCard()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct HeroMetric: View {
    let title: String
    let value: String
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.rounded(12, .medium))
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).font(.rounded(20, .bold)).monospacedDigit()
                if !unit.isEmpty {
                    Text(unit).font(.rounded(12, .medium)).foregroundStyle(.secondary)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct QuickActionLabel: View {
    let icon: String
    let title: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.brand)
                .frame(width: 58, height: 58)
                .glassCircle()
            Text(title)
                .font(.rounded(12, .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
    }
}

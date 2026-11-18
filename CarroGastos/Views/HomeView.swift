import SwiftUI

struct HomeView: View {
    let vehicle: Vehicle
    @Binding var selectedID: String
    @Binding var tab: AppTab
    @State private var sheet: HomeSheet?

    enum HomeSheet: Identifiable {
        case odometer, battery
        case new(ExpenseCategory)
        case edit(Expense)

        var id: String {
            switch self {
            case .odometer: "odometer"
            case .battery: "battery"
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
                    alertsSection
                    batteryCard
                    recentSection
                }
                .padding(16)
            }
            .background(Color.canvas)
            .navigationTitle("Início")
            .navigationBarTitleDisplayMode(.inline)
            .appToolbar(vehicle: vehicle, selectedID: $selectedID)
            .sheet(item: $sheet) { sheet in
                switch sheet {
                case .odometer: OdometerFormView(vehicle: vehicle)
                case .battery: BatteryFormView(vehicle: vehicle)
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
        .surfaceCard(padding: 20)
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
            .background(Color.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
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
            .surfaceCard()
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
                .surfaceCard()
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
                .background(Color.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
        }
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
                .background(Color.surface, in: Circle())
            Text(title)
                .font(.rounded(12, .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
    }
}

import SwiftUI

struct HomeView: View {
    let vehicle: Vehicle
    @Binding var selectedID: String
    @Binding var tab: AppTab
    @State private var sheet: HomeSheet?
    @State private var scrollToAlerts = false
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
        let year = Vehicle.currentYear
        let missing = [
            vehicle.payment(.ipva, year: year) == nil ? "IPVA" : nil,
            vehicle.payment(.licensing, year: year) == nil ? "licenciamento" : nil,
        ].compactMap { $0 }
        if !missing.isEmpty {
            let what = missing.joined(separator: " e ")
            items.append(AlertItem(id: "docs", icon: "doc.text.fill", color: Color.warning,
                                   title: "Documentação \(year)",
                                   subtitle: "\(what.prefix(1).uppercased() + what.dropFirst()) de \(year) não \(missing.count > 1 ? "foram registrados" : "foi registrado"). Já pagou? Toque para registrar.",
                                   target: .documents))
        }
        return items
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        heroCard
                        quickActions
                        gettingStarted
                        pendingSection.id("alerts")
                        if FuelPriceStore.shared.hasCity {
                            FuelPriceCard(vehicle: vehicle) { sheet = .city }
                        }
                        recentSection
                        moreSection
                    }
                    .padding(16)
                }
                .onChange(of: scrollToAlerts) { _, go in
                    guard go else { return }
                    withAnimation(.snappy) { proxy.scrollTo("alerts", anchor: .top) }
                    scrollToAlerts = false
                }
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
                case .trip: TripPlannerView(vehicle: vehicle)
                case .city: FuelCityPickerView()
                case .new(let category): ExpenseFormView(vehicle: vehicle, category: category)
                case .edit(let expense): ExpenseFormView(vehicle: vehicle, expense: expense)
                }
            }
        }
    }

    // MARK: Cartão do carro

    private var heroCard: some View {
        let items = alerts
        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    if !vehicle.subtitle.isEmpty {
                        Text(vehicle.subtitle)
                            .font(.rounded(14, .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Text(vehicle.name)
                        .font(.rounded(30, .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    if !vehicle.plate.isEmpty {
                        MercosulPlate(plate: vehicle.plate)
                            .padding(.top, 2)
                    }
                }
                Spacer(minLength: 0)
                CarPhotoButton(vehicle: vehicle)
            }

            statusRow(items)

            // Cada número é tocável: leva para onde ele é atualizado ou detalhado.
            HStack(alignment: .top, spacing: 8) {
                Button { sheet = .odometer } label: {
                    HeroMetric(title: "Km atual", value: vehicle.currentOdometer.formatted(.number), unit: "km")
                }
                Button { tab = .finance } label: {
                    HeroMetric(
                        title: "Consumo médio",
                        value: vehicle.fuelEfficiency.map { $0.formatted(.number.precision(.fractionLength(1))) } ?? "—",
                        unit: vehicle.fuelEfficiency == nil ? "" : "km/l"
                    )
                }
                Button { tab = .finance } label: {
                    HeroMetric(title: "Gasto no mês", value: monthTotal.brlNoCents, unit: "")
                }
            }
            .buttonStyle(.plain)
            if vehicle.fuelEfficiency == nil, vehicle.lastFuel != nil {
                Text("O consumo aparece depois de 2 abastecimentos com tanque cheio e km.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            fipeRow
            budgetBar
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .heroGlass(cornerRadius: 24)
    }

    /// Situação do carro em uma frase, sempre explicada e tocável.
    private func statusRow(_ items: [AlertItem]) -> some View {
        let status = vehicle.overallStatus
        let text: String
        if items.isEmpty {
            text = "Tudo em dia: serviços e documentos"
        } else if items.count == 1 {
            text = "Atenção: \(items[0].title)"
        } else {
            text = "\(items.count) itens precisam de atenção"
        }
        return Button {
            if !items.isEmpty { scrollToAlerts = true }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: items.isEmpty ? "checkmark.seal.fill" : status.icon)
                    .foregroundStyle(items.isEmpty ? Color.success : status.color)
                Text(text)
                    .font(.rounded(14, .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 4)
                if !items.isEmpty {
                    Text("Ver").font(.rounded(14, .semibold)).foregroundStyle(Color.brand)
                    Image(systemName: "chevron.down").font(.caption.bold()).foregroundStyle(Color.brand)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background((items.isEmpty ? Color.success : status.color).opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(items.isEmpty ? "" : "Mostra o que precisa de atenção")
    }

    /// Valor FIPE com a data da última atualização (atualiza sozinho).
    private var fipeRow: some View {
        Button { sheet = .fipe } label: {
            HStack(spacing: 10) {
                Image(systemName: "tag.fill")
                    .foregroundStyle(Color.docsTeal)
                    .frame(width: 22)
                if vehicle.isFipeLinked, vehicle.fipeValue > 0 {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("FIPE \(vehicle.fipeValue.brlNoCents)")
                            .font(.rounded(15, .semibold))
                            .foregroundStyle(.primary)
                        Text(fipeUpdateText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else if vehicle.fipeValue > 0 {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("FIPE \(vehicle.fipeValue.brlNoCents) (digitada)")
                            .font(.rounded(15, .semibold))
                            .foregroundStyle(.primary)
                        Text("Toque para escolher o modelo e atualizar sozinho")
                            .font(.caption)
                            .foregroundStyle(Color.brand)
                    }
                } else {
                    Text("Ver valor FIPE do carro")
                        .font(.rounded(15, .semibold))
                        .foregroundStyle(.primary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.docsTeal.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var fipeUpdateText: String {
        var parts: [String] = []
        if let date = vehicle.fipeUpdatedAt {
            parts.append("Atualizada em \(date.formatted(date: .numeric, time: .omitted))")
        }
        if !vehicle.fipeReference.isEmpty {
            parts.append("tabela de \(vehicle.fipeReference)")
        }
        return parts.isEmpty ? "Atualiza sozinha" : parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var budgetBar: some View {
        if vehicle.monthlyBudget > 0 {
            let ratio = monthTotal / vehicle.monthlyBudget
            let color = ratio > 1 ? Color.danger : (ratio > 0.85 ? Color.warning : Color.brand)
            Button { sheet = .budget } label: {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Orçamento do mês").font(.rounded(13, .medium)).foregroundStyle(.secondary)
                        Spacer()
                        Text("\(monthTotal.brlNoCents) de \(vehicle.monthlyBudget.brlNoCents)")
                            .font(.rounded(13, .semibold))
                            .monospacedDigit()
                            .foregroundStyle(.primary)
                    }
                    ProgressView(value: min(ratio, 1)).tint(color)
                    if ratio > 1 {
                        Text("Você passou \((monthTotal - vehicle.monthlyBudget).brlNoCents) do orçamento.")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Color.danger)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Ações rápidas

    private var quickActions: some View {
        HStack(alignment: .top, spacing: 8) {
            Button { sheet = .new(.fuel) } label: { QuickActionLabel(icon: "fuelpump.fill", title: "Abastecer") }
                .buttonStyle(.plain)
            Button { sheet = .odometer } label: { QuickActionLabel(icon: "speedometer", title: "Atualizar km") }
                .buttonStyle(.plain)
            Menu {
                Button("Serviço / manutenção", systemImage: ExpenseCategory.maintenance.icon) { sheet = .new(.maintenance) }
                Button("Multa", systemImage: ExpenseCategory.fine.icon) { sheet = .new(.fine) }
                Button("Seguro", systemImage: ExpenseCategory.insurance.icon) { sheet = .new(.insurance) }
                Button("IPVA", systemImage: ExpenseCategory.ipva.icon) { sheet = .new(.ipva) }
                Button("Licenciamento", systemImage: ExpenseCategory.licensing.icon) { sheet = .new(.licensing) }
                Button("Taxa, pedágio, estacionamento", systemImage: ExpenseCategory.fee.icon) { sheet = .new(.fee) }
                Button("Outro gasto", systemImage: ExpenseCategory.other.icon) { sheet = .new(.other) }
            } label: {
                QuickActionLabel(icon: "plus", title: "Lançar gasto")
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
            Step(id: "fipe", title: "Escolha o modelo na Tabela FIPE", icon: "tag.fill", done: vehicle.isFipeLinked || vehicle.fipeValue > 0) { sheet = .fipe },
            Step(id: "city", title: "Diga onde você mora (preço do combustível e viagens)", icon: "house.and.flag", done: FuelPriceStore.shared.hasHome) { sheet = .city },
            Step(id: "notify", title: "Ative os lembretes", icon: "bell.badge.fill", done: notificationsEnabled) { enableNotifications() },
        ]
    }

    @ViewBuilder
    private var gettingStarted: some View {
        let list = steps
        let done = list.filter(\.done).count
        if !gettingStartedDismissed && done < list.count {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Para começar").font(.rounded(18, .bold))
                        Text("\(done) de \(list.count) feitos · toque em cada item")
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
                    .accessibilityLabel("Esconder")
                }
                VStack(spacing: 2) {
                    ForEach(list) { step in
                        Button(action: step.action) {
                            HStack(spacing: 12) {
                                Image(systemName: step.done ? "checkmark.circle.fill" : step.icon)
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(step.done ? Color.success : Color.brand)
                                    .frame(width: 26)
                                Text(step.title)
                                    .font(.rounded(15, .medium))
                                    .foregroundStyle(step.done ? Color.secondary : Color.primary)
                                    .multilineTextAlignment(.leading)
                                Spacer()
                                if !step.done {
                                    Image(systemName: "chevron.right")
                                        .font(.caption.bold())
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .padding(.vertical, 8)
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

    // MARK: Pendências (só aparece quando há algo)

    @ViewBuilder
    private var pendingSection: some View {
        let items = alerts
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Precisa de atenção")
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        if index > 0 { Divider().padding(.leading, 66) }
                        Button { tab = item.target } label: {
                            HStack(spacing: 12) {
                                IconTile(systemName: item.icon, color: item.color, size: 40)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title).font(.rounded(16, .semibold)).foregroundStyle(.primary)
                                    Text(item.subtitle).font(.subheadline).foregroundStyle(.secondary)
                                        .multilineTextAlignment(.leading)
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
                .glassCard()
            }
        }
    }

    // MARK: Mais (ferramentas e bateria, em lista simples)

    private var batteryColor: Color {
        guard let remaining = vehicle.batteryRemaining else { return Color.secondary }
        if remaining < 0.15 { return Color.danger }
        if remaining < 0.35 { return Color.warning }
        return Color.success
    }

    private var batterySubtitle: String {
        guard let remaining = vehicle.batteryRemaining, let months = vehicle.batteryAgeMonths else {
            return "Informe quando trocou para saber a vida útil"
        }
        if remaining <= 0 { return "Passou da vida útil média. Vale um teste de carga." }
        return "Trocada há \(months) \(months == 1 ? "mês" : "meses") · \(remaining.formatted(.percent.precision(.fractionLength(0)))) de vida"
    }

    private var moreSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Ferramentas")
            VStack(spacing: 0) {
                MoreRow(icon: "drop.halffull", color: Color.docsTeal, title: "Etanol ou gasolina?",
                        subtitle: "Descubra qual compensa hoje") { sheet = .fuelCompare }
                Divider().padding(.leading, 66)
                MoreRow(icon: "map.fill", color: Color.serviceViolet, title: "Planejar viagem",
                        subtitle: "Mapa, pedágios, combustível e tanques") { sheet = .trip }
                Divider().padding(.leading, 66)
                MoreRow(icon: "minus.plus.batteryblock", color: batteryColor, title: "Bateria 12V",
                        subtitle: batterySubtitle) { sheet = .battery }
                Divider().padding(.leading, 66)
                MoreRow(icon: "target", color: Color.brand, title: "Orçamento do mês",
                        subtitle: vehicle.monthlyBudget > 0 ? "Limite de \(vehicle.monthlyBudget.brlNoCents) por mês" : "Defina um limite de gastos") { sheet = .budget }
                Divider().padding(.leading, 66)
                MoreRow(icon: "house.and.flag", color: Color.fuelBlue, title: "Onde você mora",
                        subtitle: FuelPriceStore.shared.home?.label ?? "Para o preço do combustível e as viagens") { sheet = .city }
            }
            .glassCard()
        }
    }

    // MARK: Atividade recente

    private var recentSection: some View {
        let recent = Array(vehicle.sortedExpenses.prefix(4))
        return VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Últimos registros", actionTitle: recent.isEmpty ? nil : "Ver todos") {
                tab = .finance
            }
            if recent.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Nada registrado ainda. Comece pelo próximo abastecimento.")
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

/// Linha tocável de ferramenta: ícone, título, explicação curta e seta.
struct MoreRow: View {
    let icon: String
    let color: Color
    let title: String
    let subtitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                IconTile(systemName: icon, color: color, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.rounded(16, .semibold)).foregroundStyle(.primary)
                    Text(subtitle).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                        .multilineTextAlignment(.leading)
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
                Text(value).font(.rounded(20, .bold)).monospacedDigit().foregroundStyle(.primary)
                if !unit.isEmpty {
                    Text(unit).font(.rounded(12, .medium)).foregroundStyle(.secondary)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
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

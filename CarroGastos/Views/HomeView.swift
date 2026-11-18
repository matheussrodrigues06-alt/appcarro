import SwiftUI

struct HomeView: View {
    let vehicle: Vehicle
    @Binding var tab: AppTab
    @State private var sheet: HomeSheet?

    enum HomeSheet: Identifiable {
        case odometer, fuel, battery
        case edit(Expense)

        var id: String {
            switch self {
            case .odometer: "odometer"
            case .fuel: "fuel"
            case .battery: "battery"
            case .edit(let expense): "edit-\(expense.persistentModelID.hashValue)"
            }
        }
    }

    private var yearExpenses: [Expense] {
        vehicle.expenses.filter { Calendar.current.isDate($0.date, equalTo: .now, toGranularity: .year) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                hero
                odometerSection
                quickActions
                divider
                batterySection
                divider
                logbook
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .odometer: OdometerFormView(vehicle: vehicle)
            case .fuel: ExpenseFormView(vehicle: vehicle, category: .fuel)
            case .battery: BatteryFormView(vehicle: vehicle)
            case .edit(let expense): ExpenseFormView(vehicle: vehicle, expense: expense)
            }
        }
    }

    private var divider: some View {
        Rectangle().fill(Color.cardStroke).frame(height: 1)
    }

    // MARK: Hero

    private var hero: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                RadialGradient(colors: [Color.white.opacity(0.06), .clear], center: .center, startRadius: 10, endRadius: 180)
                CarSilhouette(size: 96)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 240)

            if !vehicle.eyebrow.isEmpty {
                Text(vehicle.eyebrow)
                    .font(.system(size: 15, weight: .bold))
                    .tracking(3)
                    .foregroundStyle(Color.lime)
            }
            Text(vehicle.name)
                .font(.system(size: 60, weight: .heavy))
                .foregroundStyle(Color.white)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            HStack {
                Text(vehicle.version.isEmpty ? vehicle.modelName : vehicle.version)
                    .font(.system(size: 17))
                    .foregroundStyle(Color.white.opacity(0.75))
                    .lineLimit(1)
                Spacer()
                if !vehicle.plate.isEmpty { PlateBadge(plate: vehicle.plate) }
            }
        }
    }

    // MARK: Odômetro

    private var odometerSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionLabel("Odômetro")
            HStack(alignment: .center) {
                Button { sheet = .odometer } label: {
                    OdometerDigits(value: vehicle.currentOdometer)
                }
                .buttonStyle(PressableStyle())
                Spacer(minLength: 8)
                if let efficiency = vehicle.fuelEfficiency {
                    VStack(spacing: 2) {
                        Image(systemName: "leaf").font(.system(size: 18, weight: .medium))
                        Text(efficiency.formatted(.number.precision(.fractionLength(1))))
                            .font(.system(size: 14, weight: .bold))
                        Text("km/l").font(.system(size: 10))
                    }
                    .foregroundStyle(Color.success)
                    .frame(width: 62, height: 70)
                    .background(Color.success.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.success.opacity(0.35)))
                    .accessibilityLabel("Consumo médio de \(efficiency.formatted(.number.precision(.fractionLength(1)))) quilômetros por litro")
                }
            }
        }
    }

    // MARK: Ações rápidas

    private var quickActions: some View {
        HStack(spacing: 14) {
            QuickActionCard(
                icon: "gauge.with.dots.needle.33percent",
                title: "Atualizar KM",
                subtitle: "Último registro \(vehicle.lastOdometerDate.relativeDays)"
            ) { sheet = .odometer }

            QuickActionCard(
                icon: "fuelpump",
                title: "Abastecer",
                subtitle: lastFuelText
            ) { sheet = .fuel }
        }
    }

    private var lastFuelText: String {
        guard let fuel = vehicle.lastFuel else { return "Nenhum registro ainda" }
        var parts: [String] = []
        if let liters = fuel.liters, liters > 0 {
            parts.append("\(liters.formatted(.number.precision(.fractionLength(1)))) L")
        }
        parts.append(fuel.amount.brl)
        return "Último: " + parts.joined(separator: " · ")
    }

    // MARK: Bateria

    private var batterySection: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel("Bateria 12V")
                if let months = vehicle.batteryAgeMonths, let remaining = vehicle.batteryRemaining {
                    Text(months == 0 ? "Trocada este mês" : "Trocada há \(months) \(months == 1 ? "mês" : "meses")")
                        .font(.system(size: 19, weight: .bold))
                    Text(remaining > 0
                         ? "Vida útil estimada: cerca de \(max(1, 36 - months)) meses restantes."
                         : "Já passou da vida útil média. Vale fazer um teste de carga.")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.textSecondary)
                } else {
                    Text("Quando foi a última troca?")
                        .font(.system(size: 19, weight: .bold))
                    Text("Informe a data para estimar a vida útil da bateria.")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.textSecondary)
                }
            }
            Spacer(minLength: 0)
            Button { sheet = .battery } label: {
                BatteryDial(remaining: vehicle.batteryRemaining)
            }
            .buttonStyle(PressableStyle())
        }
    }

    // MARK: Diário de bordo

    private var logbook: some View {
        let recent = Array(vehicle.sortedExpenses.prefix(6))
        let withReceipt = yearExpenses.filter(\.hasReceipt).count
        let yearTotal = yearExpenses.reduce(0) { $0 + $1.amount }

        return VStack(alignment: .leading, spacing: 20) {
            HStack {
                SectionLabel("Diário de bordo")
                Spacer()
                Button("Ver tudo") { withAnimation { tab = .finance } }
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color.lime)
            }

            if recent.isEmpty {
                Text("Nenhum registro ainda. Comece pelo seu próximo abastecimento.")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.textSecondary)
                    .darkCard()
            } else {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: "checkmark.shield")
                        .font(.system(size: 20))
                        .foregroundStyle(Color.success)
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("\(withReceipt) de \(yearExpenses.count) registros comprovados")
                                .font(.system(size: 16, weight: .medium))
                            Spacer()
                            Text("\(yearTotal.brl) em \(String(Vehicle.currentYear))")
                                .font(.system(size: 14))
                                .foregroundStyle(Color.textSecondary)
                        }
                        ProgressSegments(total: max(yearExpenses.count, 1), filled: withReceipt)
                    }
                }

                VStack(spacing: 0) {
                    ForEach(Array(recent.enumerated()), id: \.element.id) { index, expense in
                        TimelineRow(expense: expense, isLast: index == recent.count - 1) {
                            sheet = .edit(expense)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Componentes do painel

struct OdometerDigits: View {
    let value: Int

    var body: some View {
        let text = String(format: "%06ld", max(0, value))
        let digits = Array(text)
        let leadingZeros = value == 0 ? digits.count - 1 : digits.prefix { $0 == "0" }.count
        let width: CGFloat = digits.count > 6 ? 36 : 42

        HStack(alignment: .lastTextBaseline, spacing: 6) {
            HStack(spacing: 6) {
                ForEach(Array(digits.enumerated()), id: \.offset) { index, character in
                    let isLast = index == digits.count - 1
                    Text(String(character))
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                        .foregroundStyle(isLast ? Color.black : (index < leadingZeros ? Color.textTertiary : Color.white))
                        .frame(width: width, height: 62)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(isLast ? Color.lime : Color.cardElevated)
                        )
                }
            }
            Text("km")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.textSecondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Hodômetro: \(value.km)")
    }
}

struct QuickActionCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    Image(systemName: icon)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Color.black)
                        .frame(width: 48, height: 48)
                        .background(Color.lime, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    Spacer()
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.8))
                        .frame(width: 32, height: 32)
                        .background(Color.cardElevated, in: Circle())
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Color.white)
                    Text(subtitle)
                        .font(.system(size: 14))
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .darkCard(padding: 16, radius: 24)
        }
        .buttonStyle(PressableStyle())
    }
}

struct BatteryDial: View {
    /// 0...1, ou nil quando ainda não informado.
    let remaining: Double?
    private let ticks = 44

    var body: some View {
        let filled = Int((remaining ?? 0) * Double(ticks))
        ZStack {
            ForEach(0..<ticks, id: \.self) { index in
                Capsule()
                    .fill(index < filled ? tickColor : Color.white.opacity(0.28))
                    .frame(width: 1.6, height: 8)
                    .offset(y: -60)
                    .rotationEffect(.degrees(Double(index) / Double(ticks) * 360))
            }
            Circle()
                .fill(Color.cardBackground)
                .overlay(Circle().strokeBorder(Color.white.opacity(0.12)))
                .frame(width: 92, height: 92)
            VStack(spacing: 4) {
                Image(systemName: "minus.plus.batteryblock")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(Color.lime)
                Text(remaining.map { $0.formatted(.percent.precision(.fractionLength(0))) } ?? "Informar")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.white)
            }
        }
        .frame(width: 136, height: 136)
    }

    private var tickColor: Color {
        guard let remaining else { return Color.lime }
        if remaining < 0.15 { return Color.danger }
        if remaining < 0.35 { return Color.warning }
        return Color.lime
    }
}

struct ProgressSegments: View {
    let total: Int
    let filled: Int

    var body: some View {
        if total <= 12 {
            HStack(spacing: 4) {
                ForEach(0..<total, id: \.self) { index in
                    Capsule()
                        .fill(index < filled ? Color.success : Color.cardElevated)
                        .frame(height: 5)
                }
            }
        } else {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.cardElevated)
                    Capsule().fill(Color.success)
                        .frame(width: proxy.size.width * Double(filled) / Double(max(total, 1)))
                }
            }
            .frame(height: 5)
        }
    }
}

struct TimelineRow: View {
    let expense: Expense
    let isLast: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 14) {
                VStack(spacing: 2) {
                    Text(expense.date.dayNumber)
                        .font(.system(size: 28, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(Color.white)
                    Text(expense.date.monthShortUpper)
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.textTertiary)
                }
                .frame(width: 44)

                VStack(spacing: 0) {
                    Image(systemName: expense.category.icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(expense.category.color)
                        .frame(width: 30, height: 30)
                        .background(Color.cardElevated, in: Circle())
                    if !isLast {
                        Rectangle()
                            .fill(Color.white.opacity(0.12))
                            .frame(width: 1.5)
                            .frame(maxHeight: .infinity)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(expense.logTitle)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(Color.white)
                            .lineLimit(1)
                        Spacer()
                        Text(expense.amount.brl)
                            .font(.money(16, weight: .regular))
                            .foregroundStyle(Color.white.opacity(0.85))
                    }
                    Text(expense.detailLine)
                        .font(.system(size: 15))
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
                    Label(expense.hasReceipt ? "Comprovante anexado" : "Anexar comprovante",
                          systemImage: expense.hasReceipt ? "checkmark" : "paperclip")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(expense.hasReceipt ? Color.success : Color.white.opacity(0.8))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.18)))
                }
                .padding(.bottom, 26)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

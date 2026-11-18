import SwiftUI

struct DocumentsView: View {
    let vehicle: Vehicle
    @State private var year = Vehicle.currentYear
    @State private var sheet: DocSheet?

    enum DocSheet: Identifiable {
        case add(ExpenseCategory)
        case edit(Expense)
        case fipe

        var id: String {
            switch self {
            case .add(let category): "add-\(category.rawValue)"
            case .edit(let expense): "edit-\(expense.persistentModelID.hashValue)"
            case .fipe: "fipe"
            }
        }
    }

    private var years: [Int] {
        let dataYears = vehicle.expenses.filter { $0.category.isDocument }.map(\.effectiveYear)
        let base = Array((Vehicle.currentYear - 3)...(Vehicle.currentYear + 1))
        return Array(Set(base + dataYears)).sorted(by: >)
    }

    private var paid: Int { vehicle.paidObligations(year: year) }
    private var paidTotal: Double { vehicle.documentExpenses(year: year).reduce(0) { $0 + $1.amount } }

    private var optionalItems: [Expense] {
        vehicle.documentExpenses(year: year)
            .filter { $0.category != .ipva && $0.category != .licensing }
            .sorted { $0.date > $1.date }
    }

    private var nextObligation: String {
        if vehicle.payment(.ipva, year: year) == nil { return "IPVA \(year)" }
        if vehicle.payment(.licensing, year: year) == nil { return "Licenc. \(year)" }
        return "IPVA \(year + 1)"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ScreenTitle(text: "Documentação")
                yearPicker
                summaryCard

                HStack {
                    SectionLabel("Todo carro paga")
                    Spacer()
                    Text("Toque para marcar").font(.system(size: 15)).foregroundStyle(Color.textSecondary)
                }
                .padding(.top, 10)

                ObligationCard(vehicle: vehicle, category: .ipva, year: year, payment: vehicle.payment(.ipva, year: year)) {
                    open(.ipva)
                } onEditFipe: {
                    sheet = .fipe
                }
                ObligationCard(vehicle: vehicle, category: .licensing, year: year, payment: vehicle.payment(.licensing, year: year)) {
                    open(.licensing)
                } onEditFipe: {}

                HStack {
                    SectionLabel("Só se acontecer")
                    Spacer()
                    Text("Opcional").font(.system(size: 15)).foregroundStyle(Color.textSecondary)
                }
                .padding(.top, 10)

                optionalCard
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .add(let category): ExpenseFormView(vehicle: vehicle, category: category, referenceYear: year)
            case .edit(let expense): ExpenseFormView(vehicle: vehicle, expense: expense)
            case .fipe: FipeFormView(vehicle: vehicle)
            }
        }
    }

    private func open(_ category: ExpenseCategory) {
        if let payment = vehicle.payment(category, year: year) {
            sheet = .edit(payment)
        } else {
            sheet = .add(category)
        }
    }

    private var yearPicker: some View {
        Menu {
            ForEach(years, id: \.self) { item in
                Button {
                    year = item
                } label: {
                    if item == year {
                        Label(String(item), systemImage: "checkmark")
                    } else {
                        Text(String(item))
                    }
                }
            }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(String(year)).font(.system(size: 24, weight: .bold))
                Text("\(paid)/2").font(.system(size: 15, weight: .medium)).foregroundStyle(Color.black.opacity(0.5))
            }
            .foregroundStyle(Color.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.white.opacity(0.95), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    SectionLabel("Seu \(String(year))")
                    HStack(alignment: .center, spacing: 14) {
                        HStack(spacing: 0) {
                            Text("\(paid)").foregroundStyle(Color.lime)
                            Text("/2").foregroundStyle(Color.white.opacity(0.4))
                        }
                        .font(.system(size: 84, weight: .heavy))
                        Text("obrigações\nquitadas")
                            .font(.system(size: 17))
                            .foregroundStyle(Color.white.opacity(0.75))
                    }
                }
                Spacer(minLength: 0)
                if paid == 2 {
                    PaidStamp(year: year)
                        .padding(.top, 4)
                }
            }

            HStack(spacing: 10) {
                ForEach(0..<2, id: \.self) { index in
                    Capsule()
                        .fill(index < paid ? Color.lime : Color.cardElevated)
                        .frame(height: 9)
                }
            }

            Rectangle().fill(Color.cardStroke).frame(height: 1)

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Já pago").font(.system(size: 15)).foregroundStyle(Color.textSecondary)
                    Text(paidTotal.brl).font(.money(24, weight: .bold)).lineLimit(1).minimumScaleFactor(0.6)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Próxima").font(.system(size: 15)).foregroundStyle(Color.textSecondary)
                    Text(nextObligation).font(.money(24, weight: .bold)).lineLimit(1).minimumScaleFactor(0.6)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .darkCard(padding: 22, radius: 28)
    }

    private var optionalCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            if optionalItems.isEmpty {
                HStack(spacing: 14) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(Color.textSecondary)
                        .frame(width: 44, height: 44)
                        .background(Color.cardElevated, in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Nenhum extra em \(String(year))").font(.system(size: 17, weight: .bold))
                        Text("Teve multa, seguro ou outra taxa? Registre aqui.")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.textSecondary)
                    }
                }
            } else {
                ForEach(optionalItems) { item in
                    Button { sheet = .edit(item) } label: {
                        HStack(spacing: 12) {
                            CategoryBadge(category: item.category, size: 40)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.displayTitle).font(.system(size: 16, weight: .bold)).foregroundStyle(Color.white)
                                Text("\(item.category.displayName) · \(item.date.formatted(date: .numeric, time: .omitted))")
                                    .font(.system(size: 13))
                                    .foregroundStyle(Color.textSecondary)
                            }
                            Spacer()
                            Text(item.amount.brl).font(.money(15)).foregroundStyle(Color.white)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack {
                addButton("Multa", .fine)
                Spacer()
                addButton("Seguro", .insurance)
                Spacer()
                addButton("Outra taxa", .fee)
            }
            .padding(.top, 4)
        }
        .darkCard()
    }

    private func addButton(_ title: String, _ category: ExpenseCategory) -> some View {
        Button { sheet = .add(category) } label: {
            Label(title, systemImage: "plus")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.lime)
        }
    }
}

struct ObligationCard: View {
    let vehicle: Vehicle
    let category: ExpenseCategory
    let year: Int
    let payment: Expense?
    let onTap: () -> Void
    let onEditFipe: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Button(action: onTap) {
                ZStack {
                    if payment != nil {
                        Circle().fill(Color.lime)
                        Image(systemName: "checkmark")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(Color.black)
                    } else {
                        Circle().strokeBorder(Color.white.opacity(0.3), lineWidth: 2)
                    }
                }
                .frame(width: 40, height: 40)
            }
            .buttonStyle(PressableStyle())

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(category.displayName) \(String(year))")
                        .font(.system(size: 19, weight: .bold))
                    if let payment, !payment.hasReceipt {
                        Image(systemName: "paperclip")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.textTertiary)
                    }
                    Spacer()
                    Text(amountText)
                        .font(.money(18, weight: .semibold))
                        .foregroundStyle(payment == nil ? Color.textSecondary : Color.white)
                }

                HStack(alignment: .firstTextBaseline) {
                    Text(statusText)
                        .font(.system(size: 15))
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button(action: onTap) {
                        Label(payment == nil ? "Marcar" : "Editar", systemImage: payment == nil ? "checkmark" : "pencil")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.85))
                    }
                }

                if category == .ipva {
                    HStack(spacing: 4) {
                        Text(vehicle.fipeValue > 0 ? "FIPE \(vehicle.fipeValue.brl) ·" : "Informe a FIPE para estimar ·")
                            .font(.system(size: 15))
                            .foregroundStyle(Color.textSecondary)
                        Button("Alterar", action: onEditFipe)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.violet)
                    }
                    .padding(.top, 4)
                }

                if category == .licensing, payment != nil {
                    HStack(spacing: 14) {
                        Image(systemName: "doc.text")
                            .foregroundStyle(Color.textSecondary)
                            .frame(width: 42, height: 42)
                            .background(Color.black, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("CRLV-e \(String(year))").font(.system(size: 16, weight: .medium))
                            Text(payment?.hasReceipt == true ? "Anexado" : "Ainda não anexado")
                                .font(.system(size: 13))
                                .foregroundStyle(Color.textSecondary)
                        }
                        Spacer()
                        Button(payment?.hasReceipt == true ? "Ver" : "Anexar", action: onTap)
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(Color.lime)
                    }
                    .padding(12)
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.cardStroke, lineWidth: 1.5))
                }
            }
            .foregroundStyle(Color.white)
        }
        .darkCard(padding: 20, radius: 26)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }

    private var amountText: String {
        if let payment { return payment.amount.brl }
        if category == .ipva, let estimate = vehicle.ipvaEstimate { return "~\(estimate.brl)" }
        return "—"
    }

    private var statusText: String {
        guard let payment else {
            if category == .ipva, vehicle.ipvaEstimate != nil { return "Pendente · valor estimado" }
            return "Pendente"
        }
        var parts: [String] = []
        if !payment.title.isEmpty { parts.append(payment.title) }
        parts.append("Pago em \(payment.date.dayMonth)")
        if category == .ipva, let estimate = vehicle.ipvaEstimate {
            parts.append("estimativa era \(estimate.brl)")
        }
        return parts.joined(separator: " · ")
    }
}

struct PaidStamp: View {
    let year: Int

    var body: some View {
        ZStack {
            Circle().strokeBorder(Color.lime, lineWidth: 2.5)
            Circle().strokeBorder(Color.lime.opacity(0.6), lineWidth: 1).padding(7)
            VStack(spacing: 0) {
                Text("EM DIA").font(.system(size: 13, weight: .heavy)).tracking(3)
                Text(String(year)).font(.system(size: 30, weight: .heavy))
                Text("TUDO PAGO").font(.system(size: 9, weight: .heavy)).tracking(2)
            }
        }
        .foregroundStyle(Color.lime)
        .frame(width: 120, height: 120)
        .rotationEffect(.degrees(12))
        .accessibilityLabel("Em dia: tudo pago em \(String(year))")
    }
}

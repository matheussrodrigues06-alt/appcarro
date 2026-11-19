import SwiftUI
import SwiftData

struct DocumentsView: View {
    let vehicle: Vehicle
    @Binding var selectedID: String
    @Environment(\.modelContext) private var context
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

    private var extras: [Expense] {
        vehicle.documentExpenses(year: year)
            .filter { $0.category != .ipva && $0.category != .licensing }
            .sorted { $0.date > $1.date }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Ano", selection: $year) {
                        ForEach(years, id: \.self) { Text(String($0)).tag($0) }
                    }
                    HStack(spacing: 18) {
                        Gauge(value: Double(paid), in: 0...2) {
                            EmptyView()
                        } currentValueLabel: {
                            Text("\(paid)/2").font(.rounded(14, .bold))
                        }
                        .gaugeStyle(.accessoryCircularCapacity)
                        .tint(paid == 2 ? Color.success : Color.brand)
                        .scaleEffect(1.15)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(paid == 2 ? "Tudo pago em \(String(year))" : "\(2 - paid) pendente\(paid == 1 ? "" : "s") em \(String(year))")
                                .font(.rounded(17, .bold))
                            Text("Total pago no ano: \(paidTotal.brl)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 8)
                }

                Section {
                    ObligationRow(vehicle: vehicle, category: .ipva, year: year) { open(.ipva) }
                    Button { sheet = .fipe } label: {
                        LabeledContent {
                            Text(vehicle.fipeValue > 0 ? vehicle.fipeValue.brl : "Buscar")
                        } label: {
                            Label("Tabela FIPE", systemImage: "tag")
                        }
                    }
                    .foregroundStyle(.primary)
                    ObligationRow(vehicle: vehicle, category: .licensing, year: year) { open(.licensing) }
                } header: {
                    Text("Obrigatórios")
                } footer: {
                    Text("Toque para registrar o pagamento e anexar o comprovante (ex.: CRLV-e). Com a FIPE informada, o app estima o IPVA.")
                }

                Section("Extras do ano") {
                    ForEach(extras) { item in
                        Button { sheet = .edit(item) } label: { ExpenseRow(expense: item) }
                            .buttonStyle(.plain)
                    }
                    .onDelete(perform: deleteExtras)
                    Button { sheet = .add(.fine) } label: { Label("Adicionar multa", systemImage: "plus.circle.fill") }
                    Button { sheet = .add(.insurance) } label: { Label("Adicionar seguro", systemImage: "plus.circle.fill") }
                    Button { sheet = .add(.fee) } label: { Label("Adicionar outra taxa", systemImage: "plus.circle.fill") }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Documentos")
            .appToolbar(vehicle: vehicle, selectedID: $selectedID)
            .sheet(item: $sheet) { sheet in
                switch sheet {
                case .add(let category): ExpenseFormView(vehicle: vehicle, category: category, referenceYear: year)
                case .edit(let expense): ExpenseFormView(vehicle: vehicle, expense: expense)
                case .fipe: FipeFormView(vehicle: vehicle)
                }
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

    private func deleteExtras(at offsets: IndexSet) {
        let items = offsets.map { extras[$0] }
        for item in items {
            vehicle.expenses.removeAll { $0 == item }
            context.delete(item)
        }
        try? context.save()
    }
}

struct ObligationRow: View {
    let vehicle: Vehicle
    let category: ExpenseCategory
    let year: Int
    let action: () -> Void

    private var payment: Expense? { vehicle.payment(category, year: year) }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: payment != nil ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 26))
                    .foregroundStyle(payment != nil ? Color.success : Color.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(category.displayName) \(String(year))").font(.rounded(16, .semibold))
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(amountText)
                        .font(.rounded(15, .semibold))
                        .monospacedDigit()
                        .foregroundStyle(payment == nil ? Color.secondary : Color.primary)
                    if payment?.hasReceipt == true {
                        Image(systemName: "paperclip").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var amountText: String {
        if let payment { return payment.amount.brl }
        if category == .ipva, let estimate = vehicle.ipvaEstimate { return "≈ \(estimate.brl)" }
        return "—"
    }

    private var subtitle: String {
        guard let payment else {
            return category == .ipva && vehicle.ipvaEstimate != nil ? "Pendente · valor estimado" : "Pendente · toque para registrar"
        }
        var parts = ["Pago em \(payment.date.formatted(date: .numeric, time: .omitted))"]
        if !payment.title.isEmpty { parts.append(payment.title) }
        return parts.joined(separator: " · ")
    }
}

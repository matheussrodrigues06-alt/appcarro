import SwiftUI
import SwiftData
import PhotosUI

struct ExpenseFormView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let vehicle: Vehicle
    let expense: Expense?
    let category: ExpenseCategory
    let presetYear: Int?

    init(vehicle: Vehicle, expense: Expense? = nil, category: ExpenseCategory? = nil, referenceYear: Int? = nil) {
        self.vehicle = vehicle
        self.expense = expense
        self.category = expense?.category ?? category ?? .other
        self.presetYear = expense?.referenceYear ?? referenceYear
    }

    @State private var title = ""
    @State private var place = ""
    @State private var amountText = ""
    @State private var date = Date()
    @State private var odometerText = ""
    @State private var litersText = ""
    @State private var priceText = ""
    @State private var fuelType = ExpenseFormView.fuelTypes[0]
    @State private var isFullTank = true
    @State private var intervalKmText = ""
    @State private var intervalMonthsText = ""
    @State private var notes = ""
    @State private var receiptData: Data?
    @State private var photoItem: PhotosPickerItem?
    @State private var showingDelete = false
    @State private var loaded = false

    static let fuelTypes = ["Gasolina comum", "Gasolina aditivada", "Etanol", "Diesel", "GNV"]
    static let serviceSuggestions = [
        "Troca de óleo", "Filtro de óleo", "Filtro de ar", "Filtro de cabine", "Aditivo",
        "Alinhamento e balanceamento", "Pneus", "Pastilhas de freio", "Revisão",
        "Correia dentada", "Velas", "Bateria", "Lavagem"
    ]

    private var amountValue: Double? { Double.parse(amountText) }
    private var litersValue: Double? { Double.parse(litersText) }
    private var priceValue: Double? { Double.parse(priceText) }

    /// Litros informados ou calculados a partir do preço por litro.
    private var effectiveLiters: Double? {
        if let liters = litersValue, liters > 0 { return liters }
        if let amount = amountValue, let price = priceValue, price > 0 { return amount / price }
        return nil
    }
    private var year: Int { presetYear ?? Calendar.current.component(.year, from: date) }

    private var isValid: Bool {
        switch category {
        case .maintenance: return !title.trimmed.isEmpty
        default: return (amountValue ?? 0) > 0
        }
    }

    private var navTitle: String {
        switch category {
        case .fuel: return expense == nil ? "Abastecer" : "Abastecimento"
        case .maintenance: return expense == nil ? "Registrar serviço" : "Serviço"
        case .ipva, .licensing: return "\(category.displayName) \(String(year))"
        default: return expense == nil ? "Nova \(category.displayName.lowercased())" : category.displayName
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                switch category {
                case .fuel: fuelSections
                case .maintenance: serviceSections
                case .ipva, .licensing: obligationSections
                default: genericSections
                }

                Section("Observações") {
                    TextField("Opcional", text: $notes, axis: .vertical)
                        .lineLimit(2...5)
                }

                receiptSection

                if expense != nil {
                    Section {
                        Button("Excluir registro", role: .destructive) { showingDelete = true }
                    }
                }
            }
            .darkForm()
            .navigationTitle(navTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                        .foregroundStyle(Color.white)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salvar") { save() }
                        .fontWeight(.bold)
                        .disabled(!isValid)
                }
            }
            .confirmationDialog("Excluir este registro?", isPresented: $showingDelete, titleVisibility: .visible) {
                Button("Excluir", role: .destructive) { deleteExpense() }
            }
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        receiptData = Self.compress(data)
                    }
                }
            }
            .onAppear(perform: load)
        }
        .appSheetStyle()
    }

    // MARK: Seções

    @ViewBuilder
    private var fuelSections: some View {
        Section {
            numberRow("Valor (R$)", text: $amountText, placeholder: "0,00")
            numberRow("Preço por litro (R$)", text: $priceText, placeholder: "Opcional")
            numberRow("Litros", text: $litersText, placeholder: "Opcional")
            if (litersValue ?? 0) <= 0, let liters = effectiveLiters {
                LabeledContent("Litros (calculado)", value: "\(liters.formatted(.number.precision(.fractionLength(2)))) L")
            } else if (priceValue ?? 0) <= 0, let amount = amountValue, let liters = litersValue, liters > 0 {
                LabeledContent("Preço por litro", value: (amount / liters).brl)
            }
            Picker("Combustível", selection: $fuelType) {
                ForEach(Self.fuelTypes, id: \.self) { Text($0).tag($0) }
            }
            Toggle("Tanque cheio", isOn: $isFullTank)
        } footer: {
            Text("Informe o preço por litro ou os litros (um calcula o outro). Com tanque cheio e hodômetro, o app calcula seu consumo médio (km/l).")
        }

        Section {
            numberRow("Hodômetro (km)", text: $odometerText, placeholder: String(vehicle.currentOdometer), keyboard: .numberPad)
            TextField("Posto (opcional)", text: $place)
            DatePicker("Data", selection: $date, displayedComponents: .date)
        }
    }

    @ViewBuilder
    private var serviceSections: some View {
        Section {
            HStack {
                TextField("Serviço (ex.: Troca de óleo)", text: $title)
                Menu {
                    ForEach(Self.serviceSuggestions, id: \.self) { suggestion in
                        Button(suggestion) { title = suggestion }
                    }
                } label: {
                    Image(systemName: "list.bullet.circle.fill")
                        .font(.title3)
                        .foregroundStyle(Color.lime)
                }
            }
            TextField("Local / oficina", text: $place)
            numberRow("Valor (R$)", text: $amountText, placeholder: "0,00")
            numberRow("Hodômetro (km)", text: $odometerText, placeholder: String(vehicle.currentOdometer), keyboard: .numberPad)
            DatePicker("Data", selection: $date, displayedComponents: .date)
        }

        Section {
            numberRow("A cada (km)", text: $intervalKmText, placeholder: "Ex.: 10000", keyboard: .numberPad)
            numberRow("A cada (meses)", text: $intervalMonthsText, placeholder: "Ex.: 12", keyboard: .numberPad)
        } header: {
            Text("Lembrete da próxima vez")
        } footer: {
            Text("Preencha para acompanhar o próximo vencimento na Central de serviços. O que vencer primeiro (km ou tempo) gera o alerta.")
        }
    }

    @ViewBuilder
    private var obligationSections: some View {
        Section {
            numberRow("Valor pago (R$)", text: $amountText, placeholder: "0,00")
            DatePicker("Data do pagamento", selection: $date, displayedComponents: .date)
            TextField(category == .ipva ? "Forma (ex.: à vista, cota única)" : "Detalhe (opcional)", text: $title)
        } footer: {
            if category == .ipva, let estimate = vehicle.ipvaEstimate {
                Text("Estimativa pela tabela FIPE: \(estimate.brl)")
            } else if category == .licensing {
                Text("Anexe o CRLV-e como comprovante para tê-lo sempre à mão.")
            }
        }
    }

    @ViewBuilder
    private var genericSections: some View {
        Section {
            TextField(genericPlaceholder, text: $title)
            numberRow("Valor (R$)", text: $amountText, placeholder: "0,00")
            DatePicker("Data", selection: $date, displayedComponents: .date)
            if category == .fine {
                TextField("Local (opcional)", text: $place)
            }
        }
    }

    private var genericPlaceholder: String {
        switch category {
        case .fine: "Descrição (ex.: excesso de velocidade)"
        case .insurance: "Seguradora / apólice"
        case .fee: "Descrição da taxa"
        default: "Descrição"
        }
    }

    private var receiptSection: some View {
        Section {
            if let receiptData, let image = UIImage(data: receiptData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 240)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                Button("Remover comprovante", role: .destructive) {
                    self.receiptData = nil
                    photoItem = nil
                }
            }
            PhotosPicker(selection: $photoItem, matching: .images) {
                Label(receiptData == nil ? "Anexar comprovante" : "Trocar foto", systemImage: "paperclip")
                    .foregroundStyle(Color.lime)
            }
        } header: {
            Text("Comprovante")
        }
    }

    private func numberRow(_ label: String, text: Binding<String>, placeholder: String, keyboard: UIKeyboardType = .decimalPad) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField(placeholder, text: text)
                .keyboardType(keyboard)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
        }
    }

    // MARK: Ações

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let expense else {
            if category == .fuel || category == .maintenance {
                odometerText = String(vehicle.currentOdometer)
            }
            if category == .fuel, let lastType = vehicle.lastFuel?.fuelType, !lastType.isEmpty {
                fuelType = lastType
            }
            return
        }
        title = expense.title
        place = expense.place
        amountText = expense.amount > 0 ? expense.amount.decimalInput : ""
        date = expense.date
        odometerText = expense.odometer.map(String.init) ?? ""
        litersText = expense.liters?.decimalInput ?? ""
        if !expense.fuelType.isEmpty { fuelType = expense.fuelType }
        isFullTank = expense.isFullTank
        intervalKmText = expense.intervalKm.map(String.init) ?? ""
        intervalMonthsText = expense.intervalMonths.map(String.init) ?? ""
        notes = expense.notes
        receiptData = expense.receiptData
    }

    private func save() {
        guard isValid else { return }
        let target = expense ?? Expense(category: category)
        target.title = title.trimmed
        target.place = place.trimmed
        target.amount = amountValue ?? 0
        target.date = date
        target.odometer = odometerText.digitsOnly
        target.notes = notes.trimmed
        target.receiptData = receiptData

        if category == .fuel {
            target.liters = effectiveLiters
            target.fuelType = fuelType
            target.isFullTank = isFullTank
        } else {
            target.liters = nil
        }

        if category == .maintenance {
            target.intervalKm = intervalKmText.digitsOnly
            target.intervalMonths = intervalMonthsText.digitsOnly
        }

        if category.isDocument {
            target.referenceYear = presetYear ?? Calendar.current.component(.year, from: date)
        }

        if expense == nil {
            context.insert(target)
            vehicle.expenses.append(target)
        }
        try? context.save()
        Haptics.success()
        dismiss()
    }

    private func deleteExpense() {
        guard let expense else { return }
        vehicle.expenses.removeAll { $0 == expense }
        context.delete(expense)
        try? context.save()
        dismiss()
    }

    /// Reduz a foto para economizar espaço.
    static func compress(_ data: Data) -> Data {
        guard let image = UIImage(data: data) else { return data }
        let maxSide: CGFloat = 1600
        let scale = min(1, maxSide / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let resized = UIGraphicsImageRenderer(size: size).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return resized.jpegData(compressionQuality: 0.7) ?? data
    }
}

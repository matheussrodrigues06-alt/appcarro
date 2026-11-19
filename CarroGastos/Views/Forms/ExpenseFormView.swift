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
    @State private var scanning = false
    @State private var scanMessage: String?
    @State private var fuelType = ExpenseFormView.fuelTypes[0]
    @State private var isFullTank = true
    @State private var intervalKmText = ""
    @State private var intervalMonthsText = ""
    @State private var notes = ""
    @State private var receiptData: Data?
    @State private var receiptPreview: UIImage?
    @State private var recentPlaces: [String] = []
    @State private var photoItem: PhotosPickerItem?
    @State private var showingDelete = false
    @State private var loaded = false
    @FocusState private var focus: Field?

    enum Field { case amount, title }

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
            .navigationTitle(navTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                        
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
                        setReceipt(await Self.compressInBackground(data))
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
            PhotoSourceButtons(cameraTitle: "Fotografar cupom", libraryTitle: "Da galeria") { image in
                readReceipt(image)
            }
            if scanning {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Lendo o cupom…").foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Ler cupom fiscal")
        } footer: {
            Text(scanMessage ?? "Fotografe a nota do posto: o app preenche valor, litros, preço, combustível, posto e data. A leitura acontece no próprio iPhone.")
        }

        Section {
            amountRow("Valor (R$)")
            numberRow("Preço por litro (R$)", text: $priceText, placeholder: lastPricePlaceholder)
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
            VStack(alignment: .leading, spacing: 4) {
                if let average = FuelPriceStore.shared.average(for: fuelType) {
                    Text(cityComparison(average: average))
                        .fontWeight(.medium)
                }
                Text("Informe o preço por litro ou os litros (um calcula o outro). Com tanque cheio e hodômetro, o app calcula seu consumo médio (km/l).")
            }
        }

        Section {
            numberRow("Hodômetro (km)", text: $odometerText, placeholder: String(vehicle.currentOdometer), keyboard: .numberPad)
            placeField("Posto (opcional)")
            DatePicker("Data", selection: $date, displayedComponents: .date)
        }
    }

    @ViewBuilder
    private var serviceSections: some View {
        Section {
            HStack {
                TextField("Serviço (ex.: Troca de óleo)", text: $title)
                    .focused($focus, equals: .title)
                Menu {
                    ForEach(Self.serviceSuggestions, id: \.self) { suggestion in
                        Button(suggestion) { title = suggestion }
                    }
                } label: {
                    Image(systemName: "list.bullet.circle.fill")
                        .font(.title3)
                        .foregroundStyle(Color.brand)
                }
            }
            placeField("Local / oficina")
            amountRow("Valor (R$)")
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
            amountRow("Valor pago (R$)")
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
            amountRow("Valor (R$)")
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
            if let image = receiptPreview {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 240)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                Button("Remover comprovante", role: .destructive) {
                    setReceipt(nil)
                    photoItem = nil
                }
            }
            PhotosPicker(selection: $photoItem, matching: .images) {
                Label(receiptData == nil ? "Anexar comprovante" : "Trocar foto", systemImage: "paperclip")
                    .foregroundStyle(Color.brand)
            }
        } header: {
            Text("Comprovante")
        }
    }

    private func amountRow(_ label: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("0,00", text: $amountText)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .focused($focus, equals: .amount)
        }
    }

    /// Postos/oficinas usados recentemente nesta categoria.
    private func loadRecentPlaces() -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for item in vehicle.sortedExpenses where item.category == category && !item.place.isEmpty {
            if seen.insert(item.place.lowercased()).inserted { result.append(item.place) }
            if result.count == 6 { break }
        }
        return result
    }

    private func placeField(_ prompt: String) -> some View {
        HStack {
            TextField(prompt, text: $place)
            if !recentPlaces.isEmpty {
                Menu {
                    ForEach(recentPlaces, id: \.self) { item in
                        Button(item) { place = item }
                    }
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                        .foregroundStyle(Color.brand)
                }
                .accessibilityLabel("Locais recentes")
            }
        }
    }

    private var lastPricePlaceholder: String {
        if let price = vehicle.lastFuel?.pricePerLiter { return "Último: \(price.brl)" }
        return "Opcional"
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

    // MARK: Leitura do cupom

    private func cityComparison(average: Double) -> String {
        let city = FuelPriceStore.shared.cityLabel
        let price = priceValue ?? {
            guard let amount = amountValue, let liters = litersValue, liters > 0 else { return nil }
            return amount / liters
        }()
        guard let price, price > 0 else {
            return "Média em \(city): \(average.brl)/L"
        }
        let diff = (price - average) / average
        if abs(diff) < 0.01 { return "Você pagou a média de \(city) (\(average.brl)/L)." }
        let pct = abs(diff).formatted(.percent.precision(.fractionLength(0)))
        return diff > 0
            ? "\(pct) acima da média de \(city) (\(average.brl)/L)."
            : "\(pct) abaixo da média de \(city) (\(average.brl)/L). Boa!"
    }

    private func readReceipt(_ image: UIImage) {
        scanning = true
        scanMessage = nil
        Task {
            let lines = (try? await TextRecognizer.recognize(image)) ?? []
            let data = ReceiptParser.parse(lines.map(\.text))
            await MainActor.run {
                scanning = false
                guard !data.isEmpty else {
                    scanMessage = "Não consegui ler o cupom. Tente uma foto mais reta, nítida e bem iluminada, ou preencha à mão."
                    Haptics.warning()
                    return
                }
                if let total = data.total { amountText = total.decimalInput }
                if let price = data.pricePerLiter {
                    priceText = price.formatted(.number.precision(.fractionLength(2...3)).grouping(.never))
                }
                if let liters = data.liters {
                    litersText = liters.formatted(.number.precision(.fractionLength(0...3)).grouping(.never))
                }
                if let type = data.fuelType, Self.fuelTypes.contains(type) { fuelType = type }
                if let station = data.station, place.isEmpty { place = station }
                if let readDate = data.date { date = readDate }
                if receiptData == nil {
                    Task {
                        if let jpeg = image.jpegData(compressionQuality: 0.9) {
                            setReceipt(await Self.compressInBackground(jpeg))
                        }
                    }
                }
                scanMessage = "Cupom lido e anexado como comprovante. Confira os valores antes de salvar."
                Haptics.success()
            }
        }
    }

    // MARK: Ações

    private func load() {
        guard !loaded else { return }
        loaded = true
        recentPlaces = loadRecentPlaces()
        guard let expense else {
            // No serviço o km atual é um bom padrão; no abastecimento fica vazio
            // (um km repetido estragaria o cálculo do consumo médio).
            if category == .maintenance {
                odometerText = String(vehicle.currentOdometer)
            }
            if category == .fuel, let lastType = vehicle.lastFuel?.fuelType, !lastType.isEmpty {
                fuelType = lastType
            }
            // Abre já com o teclado no campo principal
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                focus = category == .maintenance ? .title : .amount
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
        receiptPreview = expense.receiptData.flatMap { UIImage(data: $0) }
        if let liters = expense.liters, liters > 0, expense.amount > 0, category == .fuel {
            priceText = (expense.amount / liters).formatted(.number.precision(.fractionLength(2...3)).grouping(.never))
        }
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
        target.setReceipt(receiptData)

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

    /// Guarda a foto e decodifica a prévia uma vez só (não a cada tecla digitada).
    private func setReceipt(_ data: Data?) {
        receiptData = data
        receiptPreview = data.flatMap { UIImage(data: $0) }
    }

    /// Reduz a foto fora da tela principal (evita travadas).
    static func compressInBackground(_ data: Data) async -> Data {
        await Task.detached(priority: .userInitiated) { compress(data) }.value
    }

    /// Reduz a foto para economizar espaço.
    nonisolated static func compress(_ data: Data) -> Data {
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

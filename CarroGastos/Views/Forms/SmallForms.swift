import SwiftUI
import SwiftData
import Charts

// MARK: - Atualizar KM

struct OdometerFormView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let vehicle: Vehicle
    @State private var text = ""
    @State private var scanning = false
    @State private var candidates: [Int] = []
    @State private var scanMessage: String?
    @FocusState private var focused: Bool

    private var value: Int? { text.digitsOnly }

    var body: some View {
        NavigationStack {
            VStack(spacing: 22) {
                Text("Hodômetro atual").font(.rounded(15, .semibold)).foregroundStyle(.secondary)
                    .padding(.top, 20)
                TextField(String(vehicle.currentOdometer), text: $text)
                    .keyboardType(.numberPad)
                    .font(.rounded(52, .bold))
                    .monospacedDigit()
                    .multilineTextAlignment(.center)
                    .focused($focused)
                Text("Último: \(vehicle.currentOdometer.km) · \(vehicle.lastOdometerDate.relativeDays)")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.secondary)
                if let value, value < vehicle.currentOdometer {
                    Label("Valor menor que o último registro", systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.warning)
                }

                VStack(spacing: 10) {
                    PhotoSourceButtons(cameraTitle: "Foto do painel", libraryTitle: "Da galeria") { image in
                        readDashboard(image)
                    }
                    if !scanning && candidates.isEmpty && scanMessage == nil {
                        Text("Dica: fotografe de perto, com o hodômetro (km total) no meio da foto e sem reflexo. Confira o número antes de salvar.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    if scanning {
                        HStack(spacing: 8) { ProgressView(); Text("Lendo o painel…").foregroundStyle(.secondary) }
                    }
                    if !candidates.isEmpty {
                        Text("Toque no km certo:").font(.footnote).foregroundStyle(.secondary)
                        HStack(spacing: 8) {
                            ForEach(candidates, id: \.self) { km in
                                Button(km.formatted(.number)) {
                                    text = String(km)
                                    Haptics.success()
                                }
                                .buttonStyle(.bordered)
                                .tint(text == String(km) ? Color.brand : Color.secondary)
                                .font(.rounded(15, .semibold))
                            }
                        }
                    } else if let scanMessage {
                        Text(scanMessage).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                }
                Spacer()
                Button("Salvar") { save() }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(value == nil)
                    .opacity(value == nil ? 0.5 : 1)
            }
            .padding(24)
            .background(Color.canvas)
            .navigationTitle("Atualizar KM")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
            }
            .onAppear { focused = true }
        }
        .presentationDetents([.large])
        .appSheetStyle()
    }

    private func readDashboard(_ image: UIImage) {
        focused = false
        scanning = true
        candidates = []
        scanMessage = nil
        Task {
            let found = await OdometerReader.read(image, lastKnown: vehicle.currentOdometer)
            await MainActor.run {
                scanning = false
                candidates = found
                if let best = found.first {
                    text = String(best)
                    Haptics.success()
                } else {
                    scanMessage = "Não encontrei o km na foto. Tente aproximar a câmera do hodômetro, ou digite."
                    Haptics.warning()
                }
            }
        }
    }

    private func save() {
        guard let value else { return }
        vehicle.odometer = value
        vehicle.odometerUpdatedAt = .now
        try? context.save()
        Haptics.success()
        dismiss()
    }
}

// MARK: - Bateria

struct BatteryFormView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let vehicle: Vehicle
    @State private var date = Date()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Data da troca", selection: $date, in: ...Date(), displayedComponents: .date)
                        .datePickerStyle(.graphical)
                } footer: {
                    Text("Baterias automotivas costumam durar de 2 a 4 anos. Usamos 3 anos como referência.")
                }
                if vehicle.batteryChangedAt != nil {
                    Section {
                        Button("Remover data", role: .destructive) {
                            vehicle.batteryChangedAt = nil
                            try? context.save()
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("Bateria 12V")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salvar") {
                        vehicle.batteryChangedAt = date
                        try? context.save()
                        dismiss()
                    }
                    .fontWeight(.bold)
                }
            }
            .onAppear { date = vehicle.batteryChangedAt ?? .now }
        }
        .appSheetStyle()
    }
}

// MARK: - FIPE / IPVA

struct FipeFormView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let vehicle: Vehicle
    @State private var fipeText = ""
    @State private var rateText = ""
    @State private var showingSearch = false
    @State private var updating = false
    @State private var message: String?

    private var currentFipe: Double? {
        vehicle.isFipeLinked ? vehicle.fipeValue : Double.parse(fipeText)
    }

    private var estimate: Double? {
        guard let fipe = currentFipe, let rate = Double.parse(rateText), fipe > 0, rate > 0 else { return nil }
        return fipe * rate / 100
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if vehicle.isFipeLinked {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(vehicle.fipeModelName).font(.rounded(15, .semibold))
                            Text(vehicle.fipeValue.brl).font(.rounded(28, .bold)).monospacedDigit()
                            Text("Referência: \(vehicle.fipeReference)\(vehicle.fipeCode.isEmpty ? "" : " · código \(vehicle.fipeCode)")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                        Button {
                            refresh()
                        } label: {
                            HStack {
                                Label("Atualizar agora", systemImage: "arrow.clockwise")
                                if updating { Spacer(); ProgressView() }
                            }
                        }
                        .disabled(updating)
                        Button("Trocar veículo na tabela") { showingSearch = true }
                        Button("Desvincular da Tabela FIPE", role: .destructive) { unlink() }
                    } else {
                        Button {
                            showingSearch = true
                        } label: {
                            Label("Buscar meu carro na Tabela FIPE", systemImage: "magnifyingglass")
                                .font(.rounded(16, .semibold))
                        }
                    }
                } header: {
                    Text("FIPE automática")
                } footer: {
                    Text(message ?? (vehicle.isFipeLinked
                        ? "O valor se atualiza sozinho todo mês quando você abre o app."
                        : "Escolha marca, modelo e ano uma vez e o valor se atualiza sozinho todo mês. Grátis."))
                }

                let history = vehicle.sortedFipeHistory
                if history.count >= 2, let first = history.first, let last = history.last {
                    Section("Desvalorização") {
                        DepreciationChart(entries: history)
                        let change = last.value - first.value
                        let pct = first.value > 0 ? change / first.value : 0
                        Text("Desde \(first.reference): \(change >= 0 ? "+" : "−")\(abs(change).brl) (\(pct.formatted(.percent.precision(.fractionLength(1)))))")
                            .font(.subheadline)
                            .foregroundStyle(change < 0 ? Color.danger : Color.success)
                    }
                }

                Section {
                    if !vehicle.isFipeLinked {
                        HStack {
                            Text("Valor FIPE (R$)")
                            Spacer()
                            TextField("0", text: $fipeText)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                    HStack {
                        Text("Alíquota IPVA (%)")
                        Spacer()
                        TextField("4", text: $rateText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    if let estimate {
                        LabeledContent("IPVA estimado", value: estimate.brl)
                    }
                } header: {
                    Text("IPVA")
                } footer: {
                    Text("A alíquota varia por estado (ex.: SP 4%). Consulte o site da Secretaria da Fazenda do seu estado.")
                }
            }
            .navigationTitle("FIPE e IPVA")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salvar") {
                        if !vehicle.isFipeLinked {
                            vehicle.fipeValue = Double.parse(fipeText) ?? 0
                        }
                        vehicle.ipvaRate = Double.parse(rateText) ?? 4
                        try? context.save()
                        Haptics.success()
                        dismiss()
                    }
                    .fontWeight(.bold)
                }
            }
            .sheet(isPresented: $showingSearch) {
                FipeSearchView(vehicle: vehicle)
            }
            .onAppear {
                fipeText = vehicle.fipeValue > 0 ? vehicle.fipeValue.decimalInput : ""
                rateText = vehicle.ipvaRate.decimalInput
            }
        }
        .appSheetStyle()
    }

    private func refresh() {
        updating = true
        message = nil
        Task {
            let ok = await FipeUpdater.update(vehicle, context: context)
            updating = false
            message = ok ? "Atualizado agora." : "Não consegui atualizar. Verifique a internet."
            if ok { Haptics.success() } else { Haptics.warning() }
        }
    }

    private func unlink() {
        vehicle.fipeBrandCode = ""
        vehicle.fipeModelCode = ""
        vehicle.fipeYearCode = ""
        vehicle.fipeModelName = ""
        vehicle.fipeCode = ""
        vehicle.fipeReference = ""
        vehicle.fipeUpdatedAt = nil
        try? context.save()
    }
}

/// Gráfico do valor FIPE mês a mês.
struct DepreciationChart: View {
    let entries: [FipeEntry]

    var body: some View {
        Chart(entries) { entry in
            LineMark(x: .value("Mês", entry.date), y: .value("Valor", entry.value))
                .interpolationMethod(.catmullRom)
                .foregroundStyle(Color.brand)
            PointMark(x: .value("Mês", entry.date), y: .value("Valor", entry.value))
                .foregroundStyle(Color.brand)
        }
        .chartYScale(domain: .automatic(includesZero: false))
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisValueLabel {
                    if let amount = value.as(Double.self) { Text(amount.brlNoCents) }
                }
            }
        }
        .frame(height: 170)
        .padding(.vertical, 6)
    }
}

// MARK: - Orçamento mensal

struct BudgetFormView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let vehicle: Vehicle
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("Limite por mês (R$)")
                        Spacer()
                        TextField("0", text: $text)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .monospacedDigit()
                            .focused($focused)
                    }
                    if vehicle.monthTotal > 0 {
                        LabeledContent("Gasto este mês", value: vehicle.monthTotal.brl)
                    }
                    if vehicle.monthlyAverage > 0 {
                        Button("Usar minha média mensal (\(vehicle.monthlyAverage.brlNoCents))") {
                            text = vehicle.monthlyAverage.rounded().decimalInput
                        }
                    }
                } footer: {
                    Text("O cartão do carro mostra quanto do orçamento já foi usado no mês.")
                }
                if vehicle.monthlyBudget > 0 {
                    Section {
                        Button("Remover orçamento", role: .destructive) {
                            vehicle.monthlyBudget = 0
                            try? context.save()
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("Orçamento mensal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salvar") {
                        vehicle.monthlyBudget = Double.parse(text) ?? 0
                        try? context.save()
                        Haptics.success()
                        dismiss()
                    }
                    .fontWeight(.bold)
                }
            }
            .onAppear {
                text = vehicle.monthlyBudget > 0 ? vehicle.monthlyBudget.decimalInput : ""
                focused = true
            }
        }
        .presentationDetents([.medium, .large])
        .appSheetStyle()
    }
}

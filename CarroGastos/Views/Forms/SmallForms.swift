import SwiftUI
import SwiftData

// MARK: - Atualizar KM

struct OdometerFormView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let vehicle: Vehicle
    @State private var text = ""
    @FocusState private var focused: Bool

    private var value: Int? { text.digitsOnly }

    var body: some View {
        NavigationStack {
            VStack(spacing: 22) {
                SectionLabel("Hodômetro atual")
                    .padding(.top, 20)
                TextField(String(vehicle.currentOdometer), text: $text)
                    .keyboardType(.numberPad)
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .multilineTextAlignment(.center)
                    .focused($focused)
                Text("Último: \(vehicle.currentOdometer.km) · \(vehicle.lastOdometerDate.relativeDays)")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.textSecondary)
                if let value, value < vehicle.currentOdometer {
                    Label("Valor menor que o último registro", systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.warning)
                }
                Spacer()
                Button("Salvar") { save() }
                    .buttonStyle(LimeButtonStyle())
                    .disabled(value == nil)
                    .opacity(value == nil ? 0.5 : 1)
            }
            .padding(24)
            .background(AppBackground())
            .navigationTitle("Atualizar KM")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }.foregroundStyle(Color.white)
                }
            }
            .onAppear { focused = true }
        }
        .presentationDetents([.medium])
        .appSheetStyle()
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
            .darkForm()
            .navigationTitle("Bateria 12V")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }.foregroundStyle(Color.white)
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

    private var estimate: Double? {
        guard let fipe = Double.parse(fipeText), let rate = Double.parse(rateText), fipe > 0, rate > 0 else { return nil }
        return fipe * rate / 100
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("Valor FIPE (R$)")
                        Spacer()
                        TextField("0", text: $fipeText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
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
                } footer: {
                    Text("A alíquota varia por estado (ex.: SP 4%). Consulte o site da Secretaria da Fazenda do seu estado e a tabela FIPE do seu modelo.")
                }
            }
            .darkForm()
            .navigationTitle("FIPE e IPVA")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }.foregroundStyle(Color.white)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salvar") {
                        vehicle.fipeValue = Double.parse(fipeText) ?? 0
                        vehicle.ipvaRate = Double.parse(rateText) ?? 4
                        try? context.save()
                        dismiss()
                    }
                    .fontWeight(.bold)
                }
            }
            .onAppear {
                fipeText = vehicle.fipeValue > 0 ? vehicle.fipeValue.decimalInput : ""
                rateText = vehicle.ipvaRate.decimalInput
            }
        }
        .presentationDetents([.medium, .large])
        .appSheetStyle()
    }
}

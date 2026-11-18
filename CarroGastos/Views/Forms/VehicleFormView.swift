import SwiftUI
import SwiftData

struct VehicleFormView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let vehicle: Vehicle?

    @State private var name = ""
    @State private var brand = ""
    @State private var modelName = ""
    @State private var version = ""
    @State private var yearText = ""
    @State private var plate = ""
    @State private var odometerText = ""
    @State private var fipeText = ""
    @State private var loaded = false

    private var isValid: Bool { !name.trimmed.isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section("Identificação") {
                    TextField("Apelido (ex.: IX35)", text: $name)
                    TextField("Marca (ex.: Hyundai)", text: $brand)
                    TextField("Modelo (ex.: ix35)", text: $modelName)
                    TextField("Versão (ex.: 2.0 16v Flex Automático)", text: $version)
                    TextField("Ano", text: $yearText)
                        .keyboardType(.numberPad)
                    TextField("Placa", text: $plate)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .font(.system(.body, design: .monospaced))
                }
                Section {
                    TextField("Km atual", text: $odometerText)
                        .keyboardType(.numberPad)
                    TextField("Valor FIPE (opcional)", text: $fipeText)
                        .keyboardType(.decimalPad)
                } header: {
                    Text("Situação atual")
                } footer: {
                    Text("A quilometragem inicial é usada para calcular o custo por km. A FIPE serve para estimar o IPVA.")
                }
            }
            .darkForm()
            .navigationTitle(vehicle == nil ? "Novo carro" : "Editar carro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }.foregroundStyle(Color.white)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salvar") { save() }
                        .fontWeight(.bold)
                        .disabled(!isValid)
                }
            }
            .onAppear(perform: load)
        }
        .appSheetStyle()
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let vehicle else { return }
        name = vehicle.name
        brand = vehicle.brand
        modelName = vehicle.modelName
        version = vehicle.version
        yearText = vehicle.year > 0 ? String(vehicle.year) : ""
        plate = vehicle.plate
        odometerText = vehicle.currentOdometer > 0 ? String(vehicle.currentOdometer) : ""
        fipeText = vehicle.fipeValue > 0 ? vehicle.fipeValue.decimalInput : ""
    }

    private func save() {
        let target = vehicle ?? Vehicle(name: "")
        target.name = name.trimmed
        target.brand = brand.trimmed
        target.modelName = modelName.trimmed
        target.version = version.trimmed
        target.year = yearText.digitsOnly ?? 0
        target.plate = plate.trimmed.uppercased()
        target.fipeValue = Double.parse(fipeText) ?? 0

        let km = odometerText.digitsOnly ?? 0
        if vehicle == nil {
            target.initialOdometer = km
            target.odometer = km
            target.odometerUpdatedAt = .now
            context.insert(target)
        } else if km != target.currentOdometer {
            target.odometer = km
            target.odometerUpdatedAt = .now
            if km < target.initialOdometer { target.initialOdometer = km }
        }
        try? context.save()
        dismiss()
    }
}

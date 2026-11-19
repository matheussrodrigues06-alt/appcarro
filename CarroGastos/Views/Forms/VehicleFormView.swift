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
    @State private var selection: FipeSelection?
    @State private var linkedName = ""
    @State private var showingCatalog = false
    @State private var showingManual = false
    @State private var loaded = false

    private var isValid: Bool { !name.trimmed.isEmpty || !modelName.trimmed.isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button {
                        showingCatalog = true
                    } label: {
                        HStack(spacing: 12) {
                            IconTile(systemName: "car.fill", color: .brand, size: 40)
                            VStack(alignment: .leading, spacing: 2) {
                                if let chosen = chosenName {
                                    Text(chosen).font(.rounded(16, .semibold)).foregroundStyle(.primary)
                                    Text("Toque para trocar").font(.caption).foregroundStyle(.secondary)
                                } else {
                                    Text("Escolher marca, modelo e ano").font(.rounded(16, .semibold)).foregroundStyle(.primary)
                                    Text("Pela Tabela FIPE, sem digitar").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                        }
                    }
                } header: {
                    Text("Seu carro")
                } footer: {
                    Text("O valor FIPE é buscado sozinho e atualizado todo mês.")
                }

                Section("Identificação") {
                    TextField("Apelido (ex.: Meu carro)", text: $name)
                    TextField("Placa", text: $plate)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .font(.system(.body, design: .monospaced))
                }

                Section {
                    TextField("Km atual", text: $odometerText)
                        .keyboardType(.numberPad)
                } header: {
                    Text("Situação atual")
                } footer: {
                    Text("Usado para calcular o custo por km e os lembretes de manutenção.")
                }

                Section {
                    DisclosureGroup("Preencher manualmente", isExpanded: $showingManual) {
                        TextField("Marca (ex.: Hyundai)", text: $brand)
                        TextField("Modelo (ex.: ix35)", text: $modelName)
                        TextField("Versão (ex.: 2.0 Flex Automático)", text: $version)
                        TextField("Ano", text: $yearText)
                            .keyboardType(.numberPad)
                    }
                } footer: {
                    Text("Só se o seu carro não estiver na lista.")
                }
            }
            .navigationTitle(vehicle == nil ? "Novo carro" : "Editar carro")
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
            .sheet(isPresented: $showingCatalog) {
                FipeCatalogPicker { apply($0) }
            }
            .onAppear(perform: load)
        }
        .appSheetStyle()
    }

    private var chosenName: String? {
        if let selection { return selection.displayName }
        if !linkedName.isEmpty { return linkedName }
        let manual = [brand, modelName, yearText].map(\.trimmed).filter { !$0.isEmpty }.joined(separator: " ")
        return manual.isEmpty ? nil : manual
    }

    private func apply(_ chosen: FipeSelection) {
        let previousAutoName = selection.map { $0.modelName.uppercased() } ?? modelName.uppercased()
        selection = chosen
        brand = chosen.brand.nome
        modelName = chosen.modelName
        version = chosen.version
        yearText = String(chosen.yearNumber)
        // Apelido automático (a pessoa pode trocar).
        if name.trimmed.isEmpty || name.uppercased() == previousAutoName {
            name = chosen.modelName.uppercased()
        }
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
        linkedName = vehicle.isFipeLinked ? vehicle.fipeModelName : ""
    }

    private func save() {
        let target = vehicle ?? Vehicle(name: "")
        target.name = name.trimmed.isEmpty ? modelName.trimmed.uppercased() : name.trimmed
        target.brand = brand.trimmed
        target.modelName = modelName.trimmed
        target.version = version.trimmed
        target.year = yearText.digitsOnly ?? 0
        target.plate = plate.trimmed.uppercased()

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

        if let selection {
            if target.fipeYearCode != selection.year.codigo || target.fipeModelCode != selection.model.codigo {
                for entry in target.fipeHistory { context.delete(entry) }
                target.fipeHistory.removeAll()
            }
            target.fipeBrandCode = selection.brand.codigo
            target.fipeModelCode = selection.model.codigo
            target.fipeYearCode = selection.year.codigo
            target.fipeModelName = selection.displayName
        }
        try? context.save()

        // Busca o valor FIPE em segundo plano; o app atualiza sozinho todo mês.
        if selection != nil {
            Task { await FipeUpdater.update(target, context: context) }
        }
        Haptics.success()
        dismiss()
    }
}

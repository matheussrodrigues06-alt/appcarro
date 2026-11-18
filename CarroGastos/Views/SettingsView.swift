import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    let vehicle: Vehicle
    @State private var editingVehicle = false
    @State private var editingFipe = false
    @State private var editingBattery = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Carro ativo · \(vehicle.name)") {
                    Button { editingVehicle = true } label: {
                        Label("Editar dados do carro", systemImage: "car.side")
                    }
                    Button { editingFipe = true } label: {
                        Label("Valor FIPE e alíquota do IPVA", systemImage: "dollarsign.circle")
                    }
                    Button { editingBattery = true } label: {
                        Label("Data da troca da bateria", systemImage: "minus.plus.batteryblock")
                    }
                }
                .foregroundStyle(Color.white)

                Section("Dados") {
                    ShareLink(
                        item: CSVExport(fileName: "gastos-\(vehicle.plate.isEmpty ? "carro" : vehicle.plate.lowercased()).csv", content: vehicle.csv),
                        preview: SharePreview("Gastos – \(vehicle.name)")
                    ) {
                        Label("Exportar registros (CSV)", systemImage: "square.and.arrow.up")
                    }
                    .foregroundStyle(Color.white)
                    LabeledContent("Registros", value: "\(vehicle.expenses.count)")
                    LabeledContent("Total gasto", value: vehicle.totalSpent.brl)
                }

                Section {
                    LabeledContent("Versão", value: "2.0")
                } footer: {
                    Text("Seus dados ficam salvos somente neste iPhone.")
                }
            }
            .darkForm()
            .navigationTitle("Ajustes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { dismiss() }.fontWeight(.bold)
                }
            }
            .sheet(isPresented: $editingVehicle) { VehicleFormView(vehicle: vehicle) }
            .sheet(isPresented: $editingFipe) { FipeFormView(vehicle: vehicle) }
            .sheet(isPresented: $editingBattery) { BatteryFormView(vehicle: vehicle) }
        }
        .appSheetStyle()
    }
}

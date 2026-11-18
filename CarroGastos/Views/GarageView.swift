import SwiftUI
import SwiftData

struct GarageView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Vehicle.createdAt) private var vehicles: [Vehicle]
    @Binding var selectedID: String
    @State private var showingNew = false
    @State private var editing: Vehicle?
    @State private var pendingDelete: Vehicle?

    private func isSelected(_ vehicle: Vehicle) -> Bool {
        if vehicles.contains(where: { $0.uuid.uuidString == selectedID }) {
            return vehicle.uuid.uuidString == selectedID
        }
        return vehicle == vehicles.first
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(vehicles) { vehicle in
                        Button {
                            selectedID = vehicle.uuid.uuidString
                            dismiss()
                        } label: {
                            GarageRow(vehicle: vehicle, isSelected: isSelected(vehicle))
                        }
                        .buttonStyle(.plain)
                        .swipeActions {
                            Button { pendingDelete = vehicle } label: { Label("Excluir", systemImage: "trash") }
                                .tint(Color.danger)
                            Button { editing = vehicle } label: { Label("Editar", systemImage: "pencil") }
                                .tint(Color.fuelBlue)
                        }
                    }
                } footer: {
                    Text("Toque para selecionar. Deslize para editar ou excluir.")
                }

                Section {
                    Button { showingNew = true } label: {
                        Label("Adicionar carro", systemImage: "plus.circle.fill")
                            .font(.rounded(16, .semibold))
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Meus carros")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fechar") { dismiss() }
                }
            }
            .sheet(isPresented: $showingNew) { VehicleFormView(vehicle: nil) }
            .sheet(item: $editing) { VehicleFormView(vehicle: $0) }
            .confirmationDialog(
                "Excluir carro?",
                isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                titleVisibility: .visible,
                presenting: pendingDelete
            ) { vehicle in
                Button("Excluir \(vehicle.name) e seus registros", role: .destructive) { delete(vehicle) }
            } message: { _ in
                Text("Todos os registros deste carro serão apagados. Esta ação não pode ser desfeita.")
            }
        }
        .appSheetStyle()
    }

    private func delete(_ vehicle: Vehicle) {
        if isSelected(vehicle) {
            selectedID = vehicles.first(where: { $0 != vehicle })?.uuid.uuidString ?? ""
        }
        context.delete(vehicle)
        try? context.save()
    }
}

struct GarageRow: View {
    let vehicle: Vehicle
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "car.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.white)
                .frame(width: 48, height: 48)
                .background(Color.brand, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 5) {
                Text(vehicle.name).font(.rounded(17, .bold))
                if !vehicle.subtitle.isEmpty {
                    Text(vehicle.subtitle).font(.caption).foregroundStyle(.secondary)
                }
                HStack(spacing: 8) {
                    if !vehicle.plate.isEmpty { MercosulPlate(plate: vehicle.plate, scale: 0.7) }
                    StatusBadge(status: vehicle.overallStatus)
                }
            }
            Spacer()
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(Color.brand)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

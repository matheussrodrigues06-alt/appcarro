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
        ZStack {
            AppBackground()
            ScrollView {
                VStack(spacing: 18) {
                    ScreenTitle(text: "Sua garagem", centered: false)
                        .padding(.bottom, 8)

                    ForEach(vehicles) { vehicle in
                        Button {
                            selectedID = vehicle.uuid.uuidString
                            dismiss()
                        } label: {
                            GarageCard(vehicle: vehicle, isSelected: isSelected(vehicle))
                        }
                        .buttonStyle(PressableStyle())
                        .contextMenu {
                            Button("Editar", systemImage: "pencil") { editing = vehicle }
                            Button("Excluir", systemImage: "trash", role: .destructive) { pendingDelete = vehicle }
                        }
                    }

                    Button {
                        showingNew = true
                    } label: {
                        HStack(spacing: 22) {
                            Image(systemName: "plus")
                                .font(.system(size: 22, weight: .medium))
                                .foregroundStyle(Color.white.opacity(0.8))
                                .frame(width: 56, height: 56)
                                .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            Text("Adicionar carro")
                                .font(.system(size: 19, weight: .medium))
                                .foregroundStyle(Color.white.opacity(0.85))
                            Spacer()
                        }
                        .padding(14)
                        .overlay(
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .strokeBorder(style: StrokeStyle(lineWidth: 1.2, dash: [6, 5]))
                                .foregroundStyle(Color.white.opacity(0.25))
                        )
                    }
                    .buttonStyle(PressableStyle())

                    Text("Status baseado nos débitos cadastrados e estimados. Toque e segure um carro para editar.")
                        .font(.footnote)
                        .foregroundStyle(Color.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 20)
                }
                .padding(20)
            }
        }
        .appSheetStyle()
        .sheet(isPresented: $showingNew) { VehicleFormView(vehicle: nil) }
        .sheet(item: $editing) { VehicleFormView(vehicle: $0) }
        .confirmationDialog(
            "Excluir veículo?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { vehicle in
            Button("Excluir \(vehicle.name) e seus registros", role: .destructive) { delete(vehicle) }
        } message: { _ in
            Text("Todos os registros deste carro serão apagados. Esta ação não pode ser desfeita.")
        }
    }

    private func delete(_ vehicle: Vehicle) {
        if isSelected(vehicle) {
            selectedID = vehicles.first(where: { $0 != vehicle })?.uuid.uuidString ?? ""
        }
        context.delete(vehicle)
        try? context.save()
    }
}

struct GarageCard: View {
    let vehicle: Vehicle
    let isSelected: Bool

    private var reminder: ServiceReminder? {
        vehicle.serviceReminders.first { $0.status != .ok }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Topo
            VStack(alignment: .leading, spacing: 0) {
                StatusPill(status: vehicle.overallStatus)
                CarSilhouette()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                Text(vehicle.name)
                    .font(.system(size: 40, weight: .bold))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                HStack {
                    Text(vehicle.subtitle)
                        .font(.system(size: 17))
                        .foregroundStyle(Color.white.opacity(0.75))
                    Spacer()
                    if !vehicle.plate.isEmpty { PlateBadge(plate: vehicle.plate) }
                }
            }
            .padding(20)
            .background(
                LinearGradient(colors: [Color.cardBackground, Color.black.opacity(0.6)], startPoint: .top, endPoint: .bottom)
            )

            // Base
            VStack(spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionLabel("Odômetro")
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(vehicle.currentOdometer.formatted(.number))
                                .font(.system(size: 28, weight: .bold))
                            Text("km").font(.system(size: 15)).foregroundStyle(Color.textSecondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    VStack(alignment: .leading, spacing: 8) {
                        SectionLabel("Docs")
                        let paid = vehicle.paidObligations(year: Vehicle.currentYear)
                        Text(paid == 2 ? "Em dia" : "\(paid)/2 pagos")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(paid == 2 ? Color.success : Color.warning)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .foregroundStyle(Color.white)

                reminderRow
            }
            .padding(20)
            .background(Color.cardBackground)
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(isSelected ? Color.lime.opacity(0.7) : Color.cardStroke, lineWidth: isSelected ? 1.5 : 1)
        )
    }

    private var reminderRow: some View {
        let status = reminder?.status ?? .ok
        let title = reminder?.title ?? "Nada vencendo agora"
        let subtitle: String = {
            if let reminder { return reminder.summary }
            if let last = vehicle.lastService {
                let where_ = last.place.isEmpty ? last.displayTitle : last.place
                return "Último serviço · \(where_) em \(last.date.dayMonth)"
            }
            return "Nenhum serviço registrado"
        }()

        return HStack(spacing: 16) {
            Image(systemName: status == .ok ? "checkmark.circle" : "exclamationmark.circle")
                .font(.system(size: 26))
                .foregroundStyle(status.color)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 18, weight: .medium)).foregroundStyle(Color.white)
                Text(subtitle).font(.system(size: 15)).foregroundStyle(Color.white.opacity(0.7)).lineLimit(1)
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(Color.textSecondary)
        }
        .padding(16)
        .background(status.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

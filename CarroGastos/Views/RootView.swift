import SwiftUI
import SwiftData

enum AppTab: Hashable {
    case home, services, documents, finance
}

struct RootView: View {
    @Query(sort: \Vehicle.createdAt) private var vehicles: [Vehicle]
    @AppStorage("selectedVehicleID") private var selectedID: String = ""
    @State private var tab: AppTab = .home
    @Environment(\.scenePhase) private var scenePhase

    private var selectedVehicle: Vehicle? {
        vehicles.first { $0.uuid.uuidString == selectedID } ?? vehicles.first
    }

    var body: some View {
        Group {
            if let vehicle = selectedVehicle {
                TabView(selection: $tab) {
                    HomeView(vehicle: vehicle, selectedID: $selectedID, tab: $tab)
                        .tabItem { Label("Início", systemImage: "house.fill") }
                        .tag(AppTab.home)
                    ServicesView(vehicle: vehicle, selectedID: $selectedID)
                        .tabItem { Label("Serviços", systemImage: "wrench.and.screwdriver.fill") }
                        .tag(AppTab.services)
                    DocumentsView(vehicle: vehicle, selectedID: $selectedID)
                        .tabItem { Label("Documentos", systemImage: "doc.text.fill") }
                        .tag(AppTab.documents)
                    FinanceView(vehicle: vehicle, selectedID: $selectedID)
                        .tabItem { Label("Gastos", systemImage: "chart.bar.fill") }
                        .tag(AppTab.finance)
                }
            } else {
                WelcomeView()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            // Reagenda os lembretes sempre que o app vai para segundo plano
            if phase == .background {
                ReminderScheduler.reschedule(vehicles: vehicles)
            }
        }
    }
}

/// Menu da barra superior para trocar de carro.
struct VehicleMenu: View {
    @Query(sort: \Vehicle.createdAt) private var vehicles: [Vehicle]
    let current: Vehicle
    @Binding var selectedID: String
    let onManage: () -> Void

    var body: some View {
        Menu {
            ForEach(vehicles) { vehicle in
                Button {
                    selectedID = vehicle.uuid.uuidString
                } label: {
                    if vehicle == current {
                        Label(vehicle.name, systemImage: "checkmark")
                    } else {
                        Text(vehicle.name)
                    }
                }
            }
            Divider()
            Button(action: onManage) {
                Label("Gerenciar carros", systemImage: "car.2")
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "car.fill")
                Text(current.name)
                    .font(.rounded(16, .semibold))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.caption2.bold())
            }
        }
    }
}

struct WelcomeView: View {
    @State private var showingNewVehicle = false

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            Spacer()
            Image(systemName: "car.side.fill")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(Color.white)
                .frame(width: 76, height: 76)
                .background(Color.brand, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            VStack(alignment: .leading, spacing: 10) {
                Text("Gastos do Carro")
                    .font(.rounded(36, .bold))
                Text("Tudo o que seu carro custa, em um só lugar.")
                    .font(.rounded(18))
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 16) {
                feature("fuelpump", "Abastecimentos e consumo médio")
                feature("wrench.and.screwdriver", "Lembretes de manutenção")
                feature("doc.text", "IPVA, licenciamento e multas")
                feature("chart.bar", "Custo por mês e por km")
            }
            Spacer()
            Button("Cadastrar meu carro") { showingNewVehicle = true }
                .buttonStyle(PrimaryButtonStyle())
        }
        .padding(28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.canvas)
        .sheet(isPresented: $showingNewVehicle) {
            VehicleFormView(vehicle: nil)
        }
    }

    private func feature(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color.brand)
                .frame(width: 26)
            Text(text).font(.rounded(16))
        }
    }
}

#Preview {
    RootView()
        .modelContainer(for: [Vehicle.self, Expense.self], inMemory: true)
}

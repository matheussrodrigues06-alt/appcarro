import SwiftUI
import SwiftData

enum AppTab: Int, CaseIterable, Identifiable {
    case home, services, documents, finance

    var id: Int { rawValue }

    var icon: String {
        switch self {
        case .home: "speedometer"
        case .services: "wrench.and.screwdriver.fill"
        case .documents: "doc.text.fill"
        case .finance: "banknote.fill"
        }
    }

    var label: String {
        switch self {
        case .home: "Painel"
        case .services: "Serviços"
        case .documents: "Documentação"
        case .finance: "Financeiro"
        }
    }
}

struct RootView: View {
    @Query(sort: \Vehicle.createdAt) private var vehicles: [Vehicle]
    @AppStorage("selectedVehicleID") private var selectedID: String = ""
    @State private var tab: AppTab = .home
    @State private var showingGarage = false
    @State private var showingSettings = false
    @Environment(\.scenePhase) private var scenePhase

    private var selectedVehicle: Vehicle? {
        vehicles.first { $0.uuid.uuidString == selectedID } ?? vehicles.first
    }

    var body: some View {
        ZStack {
            AppBackground()

            if let vehicle = selectedVehicle {
                Group {
                    switch tab {
                    case .home: HomeView(vehicle: vehicle, tab: $tab)
                    case .services: ServicesView(vehicle: vehicle)
                    case .documents: DocumentsView(vehicle: vehicle)
                    case .finance: FinanceView(vehicle: vehicle)
                    }
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    BottomBar(
                        tab: $tab,
                        onGarage: { showingGarage = true },
                        onSettings: { showingSettings = true }
                    )
                }
                .sheet(isPresented: $showingSettings) {
                    SettingsView(vehicle: vehicle)
                }
            } else {
                WelcomeView()
            }
        }
        .sheet(isPresented: $showingGarage) {
            GarageView(selectedID: $selectedID)
        }
        .onChange(of: scenePhase) { _, phase in
            // Reagenda os lembretes sempre que o app vai para segundo plano
            if phase == .background {
                ReminderScheduler.reschedule(vehicles: vehicles)
            }
        }
    }
}

// MARK: - Barra inferior flutuante

struct BottomBar: View {
    @Binding var tab: AppTab
    let onGarage: () -> Void
    let onSettings: () -> Void
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onGarage) {
                ZStack(alignment: .bottomTrailing) {
                    Circle()
                        .fill(Color.appBackground.opacity(0.92))
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.28), lineWidth: 1.5))
                        .overlay(
                            Image(systemName: "car.side")
                                .font(.system(size: 22, weight: .light))
                                .foregroundStyle(Color.white.opacity(0.7))
                        )
                        .frame(width: 60, height: 60)
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.lime)
                        .frame(width: 24, height: 24)
                        .background(Color.black, in: Circle())
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.15)))
                        .offset(x: 4, y: 4)
                }
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("Trocar de carro")

            Spacer(minLength: 8)

            HStack(spacing: 2) {
                ForEach(AppTab.allCases) { item in
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { tab = item }
                    } label: {
                        Image(systemName: item.icon)
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundStyle(tab == item ? Color.lime : Color.black)
                            .frame(width: 52, height: 52)
                            .background {
                                if tab == item {
                                    Circle()
                                        .fill(Color.black)
                                        .matchedGeometryEffect(id: "selectedTab", in: namespace)
                                }
                            }
                    }
                    .accessibilityLabel(item.label)
                }
            }
            .padding(5)
            .background(Color.lime, in: Capsule())
            .shadow(color: Color.lime.opacity(0.35), radius: 18, y: 6)

            Spacer(minLength: 8)

            Button(action: onSettings) {
                Image(systemName: "slider.vertical.3")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.black)
                    .frame(width: 60, height: 60)
                    .background(Color.lime, in: Circle())
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("Ajustes")
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 2)
    }
}

// MARK: - Boas-vindas

struct WelcomeView: View {
    @State private var showingNewVehicle = false

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            CarSilhouette(size: 110)
            VStack(spacing: 10) {
                Text("Sua garagem")
                    .font(.system(size: 38, weight: .bold))
                Text("Abastecimentos, serviços, IPVA, licenciamento e todos os gastos do seu carro em um só lugar.")
                    .font(.system(size: 17))
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
            }
            Spacer()
            Button("Cadastrar meu carro") { showingNewVehicle = true }
                .buttonStyle(LimeButtonStyle())
        }
        .padding(28)
        .sheet(isPresented: $showingNewVehicle) {
            VehicleFormView(vehicle: nil)
        }
    }
}

#Preview {
    RootView()
        .modelContainer(for: [Vehicle.self, Expense.self], inMemory: true)
        .preferredColorScheme(.dark)
}

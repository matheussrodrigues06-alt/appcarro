import SwiftUI

// MARK: - Cores

extension Color {
    /// Laranja da marca — a única cor de destaque do app.
    static let brand = Color(red: 1.0, green: 0.42, blue: 0.17)
    static let canvas = Color(uiColor: .systemGroupedBackground)
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)
    static let success = Color(red: 0.20, green: 0.72, blue: 0.42)
    static let warning = Color(red: 0.98, green: 0.62, blue: 0.10)
    static let danger = Color(red: 0.92, green: 0.26, blue: 0.30)
    static let fuelBlue = Color(red: 0.23, green: 0.56, blue: 0.98)
    static let docsTeal = Color(red: 0.10, green: 0.66, blue: 0.64)
    static let serviceViolet = Color(red: 0.53, green: 0.39, blue: 0.95)
}

// MARK: - Fontes

extension Font {
    static func rounded(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

// MARK: - Modificadores

extension View {
    func surfaceCard(padding: CGFloat = 16) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    func appSheetStyle() -> some View {
        self.tint(Color.brand)
    }
}

// MARK: - Componentes

struct IconTile: View {
    let systemName: String
    let color: Color
    var size: CGFloat = 36

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.44, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
    }
}

/// Placa no padrão Mercosul.
struct MercosulPlate: View {
    let plate: String
    var scale: CGFloat = 1

    var body: some View {
        VStack(spacing: 0) {
            Text("BRASIL")
                .font(.system(size: 7 * scale, weight: .heavy))
                .tracking(1)
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity)
                .frame(height: 11 * scale)
                .background(Color(red: 0.0, green: 0.22, blue: 0.62))
            Text(plate.uppercased())
                .font(.system(size: 17 * scale, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.black)
                .padding(.horizontal, 10 * scale)
                .padding(.vertical, 3 * scale)
        }
        .fixedSize()
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 5 * scale, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 5 * scale, style: .continuous)
                .strokeBorder(Color.black.opacity(0.6), lineWidth: 1)
        )
        .accessibilityLabel("Placa \(plate)")
    }
}

struct StatusBadge: View {
    let status: DueStatus
    var onGradient = false

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: status.icon).font(.caption.bold())
            Text(status.title).font(.rounded(13, .semibold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .foregroundStyle(onGradient ? Color.white : status.color)
        .background(onGradient ? Color.white.opacity(0.22) : status.color.opacity(0.15), in: Capsule())
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.rounded(17, .semibold))
            .foregroundStyle(Color.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(Color.brand, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct SectionHeader: View {
    let title: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.rounded(20, .bold))
            Spacer()
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.rounded(15, .semibold))
                    .foregroundStyle(Color.brand)
            }
        }
    }
}

/// Linha padrão de um registro (gasto, serviço, documento).
struct ExpenseRow: View {
    let expense: Expense

    var body: some View {
        HStack(spacing: 12) {
            IconTile(systemName: expense.category.icon, color: expense.category.color, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(expense.displayTitle)
                    .font(.rounded(16, .semibold))
                    .lineLimit(1)
                Text(expense.detailLine)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) {
                Text(expense.amount.brl)
                    .font(.rounded(16, .semibold))
                    .monospacedDigit()
                HStack(spacing: 4) {
                    if expense.hasReceipt { Image(systemName: "paperclip") }
                    Text(expense.date.formatted(.dateTime.day().month(.abbreviated)))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
    }
}

/// Seletor de carro e botão de ajustes, comuns a todas as abas.
struct AppToolbar: ViewModifier {
    let vehicle: Vehicle
    @Binding var selectedID: String
    @State private var showingGarage = false
    @State private var showingSettings = false

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    VehicleMenu(current: vehicle, selectedID: $selectedID) { showingGarage = true }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingSettings = true } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Ajustes")
                }
            }
            .sheet(isPresented: $showingGarage) { GarageView(selectedID: $selectedID) }
            .sheet(isPresented: $showingSettings) { SettingsView(vehicle: vehicle) }
    }
}

extension View {
    func appToolbar(vehicle: Vehicle, selectedID: Binding<String>) -> some View {
        modifier(AppToolbar(vehicle: vehicle, selectedID: selectedID))
    }
}

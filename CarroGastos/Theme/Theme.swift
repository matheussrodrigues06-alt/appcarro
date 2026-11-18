import SwiftUI

// MARK: - Cores

extension Color {
    static let appBackground = Color(red: 0.035, green: 0.035, blue: 0.05)
    static let auroraPurple = Color(red: 0.19, green: 0.08, blue: 0.32)
    static let cardBackground = Color(red: 0.11, green: 0.11, blue: 0.13)
    static let cardElevated = Color(red: 0.16, green: 0.16, blue: 0.19)
    static let cardStroke = Color.white.opacity(0.07)
    static let lime = Color(red: 0.78, green: 1.0, blue: 0.0)
    static let textSecondary = Color.white.opacity(0.55)
    static let textTertiary = Color.white.opacity(0.32)
    static let success = Color(red: 0.16, green: 0.78, blue: 0.40)
    static let warning = Color(red: 1.0, green: 0.74, blue: 0.20)
    static let danger = Color(red: 0.96, green: 0.27, blue: 0.38)
    static let violet = Color(red: 0.70, green: 0.58, blue: 1.0)
    static let fuelBlue = Color(red: 0.36, green: 0.66, blue: 1.0)
    static let docsTeal = Color(red: 0.18, green: 0.83, blue: 0.76)
}

// MARK: - Fontes

extension Font {
    /// Fonte monoespaçada usada em valores em dinheiro.
    static func money(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

// MARK: - Fundo

struct AppBackground: View {
    var body: some View {
        ZStack(alignment: .top) {
            Color.appBackground
            LinearGradient(
                colors: [Color.auroraPurple, Color.auroraPurple.opacity(0.35), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 360)
        }
        .ignoresSafeArea()
    }
}

// MARK: - Componentes

extension View {
    func darkCard(padding: CGFloat = 20, radius: CGFloat = 24) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Color.cardStroke))
    }

    /// Estilo padrão das telas apresentadas em sheet.
    func appSheetStyle() -> some View {
        self
            .preferredColorScheme(.dark)
            .tint(Color.lime)
    }

    /// Form escuro com o fundo do app.
    func darkForm() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(AppBackground())
    }
}

struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 13, weight: .semibold))
            .tracking(2.6)
            .foregroundStyle(Color.textSecondary)
    }
}

struct ScreenTitle: View {
    let text: String
    var centered = true

    var body: some View {
        Text(text)
            .font(.system(size: 34, weight: .bold))
            .foregroundStyle(Color.white)
            .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
            .padding(.top, 12)
    }
}

struct PlateBadge: View {
    let plate: String

    var body: some View {
        Text(plate.uppercased())
            .font(.system(size: 15, weight: .medium, design: .monospaced))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.cardElevated, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct LimeButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .bold))
            .foregroundStyle(Color.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 17)
            .background(Color.lime, in: Capsule())
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct StatusPill: View {
    let status: DueStatus

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(status.color).frame(width: 9, height: 9)
            Text(status.title).font(.system(size: 15, weight: .medium))
        }
        .foregroundStyle(Color.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(Color.black.opacity(0.75), in: Capsule())
    }
}

struct CategoryBadge: View {
    let category: ExpenseCategory
    var size: CGFloat = 44

    var body: some View {
        Image(systemName: category.icon)
            .font(.system(size: size * 0.36, weight: .semibold))
            .foregroundStyle(category.color)
            .frame(width: size, height: size)
            .background(Color.cardElevated, in: Circle())
    }
}

/// Silhueta de carro usada nos cartões.
struct CarSilhouette: View {
    var size: CGFloat = 76

    var body: some View {
        Image(systemName: "car.side")
            .font(.system(size: size, weight: .ultraLight))
            .foregroundStyle(Color.white.opacity(0.55))
    }
}

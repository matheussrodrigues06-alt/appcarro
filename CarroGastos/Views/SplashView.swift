import SwiftUI

/// Abertura animada: as barras do ícone sobem, as rodas entram girando e o nome aparece.
struct SplashView: View {
    let onFinish: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var barsUp = false
    @State private var wheelsIn = false
    @State private var titleIn = false

    // Mesmas proporções do ícone (em "unidades" do desenho)
    private let heights: [CGFloat] = [14, 16, 27, 31, 31, 27, 17, 15]
    private let unit: CGFloat = 3.0
    private let barWidth: CGFloat = 6.2
    private let gap: CGFloat = 1.6
    private let wheelCenters: [CGFloat] = [13.9, 46.9]   // a partir do início das barras

    private var glyphWidth: CGFloat { (CGFloat(heights.count) * barWidth + CGFloat(heights.count - 1) * gap) * unit }
    private var baseY: CGFloat { 31 * unit }
    private var glyphHeight: CGFloat { (31 + 1 + 7.2) * unit }

    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground).ignoresSafeArea()

            VStack(spacing: 28) {
                glyph
                VStack(spacing: 6) {
                    Text("Auto Check")
                        .font(.rounded(30, .bold))
                    Text("Seu carro em dia")
                        .font(.rounded(15, .medium))
                        .foregroundStyle(.secondary)
                }
                .opacity(titleIn ? 1 : 0)
                .offset(y: titleIn ? 0 : 10)
            }
        }
        .onAppear(perform: start)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Auto Check")
    }

    private var glyph: some View {
        ZStack(alignment: .topLeading) {
            // Barras do gráfico
            HStack(alignment: .bottom, spacing: gap * unit) {
                ForEach(Array(heights.enumerated()), id: \.offset) { index, height in
                    RoundedRectangle(cornerRadius: 1.6 * unit, style: .continuous)
                        .fill(Color.primary)
                        .frame(width: barWidth * unit, height: height * unit)
                        .scaleEffect(x: 1, y: barsUp ? 1 : 0.001, anchor: .bottom)
                        .opacity(barsUp ? 1 : 0)
                        .animation(
                            reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.62).delay(Double(index) * 0.055),
                            value: barsUp
                        )
                }
            }
            .frame(width: glyphWidth, height: baseY, alignment: .bottomLeading)

            // Rodas (com o "recorte" na cor do fundo, como no ícone)
            ForEach(wheelCenters, id: \.self) { center in
                ZStack {
                    Circle().fill(Color(uiColor: .systemBackground))
                        .frame(width: 14.4 * unit, height: 14.4 * unit)
                    Circle().fill(Color.primary)
                        .frame(width: 10 * unit, height: 10 * unit)
                    Circle().fill(Color(uiColor: .systemBackground))
                        .frame(width: 2.4 * unit, height: 2.4 * unit)
                        .offset(x: 2.2 * unit)          // marca que mostra a roda girando
                }
                .rotationEffect(.degrees(wheelsIn ? 0 : -300))
                .scaleEffect(wheelsIn ? 1 : 0.01)
                .position(x: center * unit, y: baseY + 1 * unit)
            }
        }
        .frame(width: glyphWidth, height: glyphHeight)
    }

    private func start() {
        if reduceMotion {
            barsUp = true
            wheelsIn = true
            withAnimation(.easeOut(duration: 0.25)) { titleIn = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { onFinish() }
            return
        }
        barsUp = true
        withAnimation(.spring(response: 0.55, dampingFraction: 0.7).delay(0.42)) { wheelsIn = true }
        withAnimation(.easeOut(duration: 0.35).delay(0.65)) { titleIn = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.55) { onFinish() }
    }
}

/// Mostra a abertura por cima do app e depois a esconde com um fade.
struct AppShell: View {
    @State private var showSplash = true

    var body: some View {
        ZStack {
            RootView()
            if showSplash {
                SplashView {
                    withAnimation(.easeInOut(duration: 0.4)) { showSplash = false }
                }
                .transition(.opacity.combined(with: .scale(scale: 1.06)))
                .zIndex(1)
            }
        }
    }
}

#Preview("Abertura") {
    SplashView {}
}

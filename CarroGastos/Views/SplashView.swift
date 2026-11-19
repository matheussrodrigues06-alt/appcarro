import SwiftUI

/// Abertura animada (cerca de 1,6 s):
/// o brilho laranja acende, o ícone surge, as barras sobem, as rodas giram,
/// riscos de velocidade passam, o nome aparece e uma barrinha completa o carregamento.
/// Só formas simples (sem desfoque), para rodar liso também em iPhones mais antigos.
struct SplashView: View {
    let onFinish: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var glowIn = false
    @State private var tileIn = false
    @State private var barsUp = false
    @State private var wheelsIn = false
    @State private var linesIn = false
    @State private var linesOut = false
    @State private var titleIn = false
    @State private var taglineIn = false
    @State private var progress: CGFloat = 0

    private let background = Color(red: 0.055, green: 0.055, blue: 0.065)
    private let tileSize: CGFloat = 128

    // Mesmas proporções do ícone (em "unidades" do desenho)
    private let heights: [CGFloat] = [14, 16, 27, 31, 31, 27, 17, 15]
    private let unit: CGFloat = 1.55
    private let barWidth: CGFloat = 6.2
    private let gap: CGFloat = 1.6
    private let wheelCenters: [CGFloat] = [13.9, 46.9]

    private var glyphWidth: CGFloat { (CGFloat(heights.count) * barWidth + CGFloat(heights.count - 1) * gap) * unit }
    private var baseY: CGFloat { 31 * unit }
    private var glyphHeight: CGFloat { (31 + 1 + 7.2) * unit }

    var body: some View {
        ZStack {
            background.ignoresSafeArea()

            RadialGradient(
                colors: [Color.brand.opacity(0.55), Color.brand.opacity(0.12), .clear],
                center: .center, startRadius: 0, endRadius: 320
            )
            .scaleEffect(glowIn ? 1 : 0.3)
            .opacity(glowIn ? 1 : 0)
            .offset(y: -40)
            .ignoresSafeArea()

            VStack(spacing: 34) {
                ZStack {
                    speedLines
                    tile
                }
                VStack(spacing: 8) {
                    Text("Auto Check")
                        .font(.rounded(34, .heavy))
                        .tracking(titleIn ? 0.5 : 10)
                        .foregroundStyle(Color.white)
                        .opacity(titleIn ? 1 : 0)
                    Text("Seu carro em dia, sem complicação")
                        .font(.rounded(15, .medium))
                        .foregroundStyle(Color.white.opacity(0.6))
                        .opacity(taglineIn ? 1 : 0)
                        .offset(y: taglineIn ? 0 : 8)
                }
            }
            .offset(y: -30)

            VStack {
                Spacer()
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.12))
                    Capsule().fill(Color.brand).frame(width: 140 * progress)
                }
                .frame(width: 140, height: 4)
                .padding(.bottom, 70)
            }
        }
        .onAppear(perform: start)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Auto Check")
    }

    /// Ícone do app: cartão branco com o "gráfico-carro" em preto.
    private var tile: some View {
        RoundedRectangle(cornerRadius: tileSize * 0.235, style: .continuous)
            .fill(Color.white)
            .frame(width: tileSize, height: tileSize)
            .overlay(glyph.offset(y: 4))
            .shadow(color: Color.brand.opacity(tileIn ? 0.55 : 0), radius: 28, y: 8)
            .scaleEffect(tileIn ? 1 : 0.4)
            .rotationEffect(.degrees(tileIn ? 0 : -12))
            .opacity(tileIn ? 1 : 0)
    }

    private var glyph: some View {
        ZStack(alignment: .topLeading) {
            HStack(alignment: .bottom, spacing: gap * unit) {
                ForEach(Array(heights.enumerated()), id: \.offset) { index, height in
                    RoundedRectangle(cornerRadius: 1.6 * unit, style: .continuous)
                        .fill(Color.black)
                        .frame(width: barWidth * unit, height: height * unit)
                        .scaleEffect(x: 1, y: barsUp ? 1 : 0.001, anchor: .bottom)
                        .opacity(barsUp ? 1 : 0)
                        .animation(
                            reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.6).delay(0.18 + Double(index) * 0.035),
                            value: barsUp
                        )
                }
            }
            .frame(width: glyphWidth, height: baseY, alignment: .bottomLeading)

            ForEach(wheelCenters, id: \.self) { center in
                ZStack {
                    Circle().fill(Color.white)
                        .frame(width: 14.4 * unit, height: 14.4 * unit)
                    Circle().fill(Color.black)
                        .frame(width: 10 * unit, height: 10 * unit)
                    Circle().fill(Color.white)
                        .frame(width: 2.4 * unit, height: 2.4 * unit)
                        .offset(x: 2.2 * unit)
                }
                .rotationEffect(.degrees(wheelsIn ? 0 : -540))
                .scaleEffect(wheelsIn ? 1 : 0.01)
                .position(x: center * unit, y: baseY + 1 * unit)
            }
        }
        .frame(width: glyphWidth, height: glyphHeight)
    }

    /// Riscos de velocidade que passam atrás do ícone.
    private var speedLines: some View {
        VStack(alignment: .trailing, spacing: 14) {
            Capsule().frame(width: 54, height: 5)
            Capsule().frame(width: 86, height: 5)
            Capsule().frame(width: 40, height: 5)
        }
        .foregroundStyle(Color.brand)
        .scaleEffect(x: linesIn ? 1 : 0.01, y: 1, anchor: .trailing)
        .opacity(linesOut ? 0 : (linesIn ? 1 : 0))
        .offset(x: -(tileSize / 2 + 50) - (linesOut ? 30 : 0))
    }

    private func start() {
        if reduceMotion {
            glowIn = true; tileIn = true; barsUp = true; wheelsIn = true
            titleIn = true; taglineIn = true; progress = 1
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { onFinish() }
            return
        }
        withAnimation(.easeOut(duration: 0.7)) { glowIn = true }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.68)) { tileIn = true }
        barsUp = true
        withAnimation(.spring(response: 0.6, dampingFraction: 0.75).delay(0.45)) { wheelsIn = true }
        withAnimation(.easeOut(duration: 0.25).delay(0.55)) { linesIn = true }
        withAnimation(.easeIn(duration: 0.3).delay(0.9)) { linesOut = true }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.6)) { titleIn = true }
        withAnimation(.easeOut(duration: 0.4).delay(0.8)) { taglineIn = true }
        withAnimation(.easeInOut(duration: 1.35)) { progress = 1 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { onFinish() }
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
        .statusBarHidden(showSplash)
    }
}

#Preview("Abertura") {
    SplashView {}
}

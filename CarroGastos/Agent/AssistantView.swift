import SwiftUI
import SwiftData
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Aba "Assistente": chat com a IA da Apple que registra gastos e responde perguntas.
/// Em aparelhos sem Apple Intelligence, a aba aparece desativada com a explicação.
struct AssistantView: View {
    let vehicle: Vehicle
    @Binding var selectedID: String

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Assistente")
                .navigationBarTitleDisplayMode(.inline)
                .appToolbar(vehicle: vehicle, selectedID: $selectedID)
        }
    }

    @ViewBuilder
    private var content: some View {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            AssistantAvailabilityGate(vehicle: vehicle)
        } else {
            AssistantUnavailableView(
                title: "Precisa do iOS 26",
                message: "O assistente usa a Apple Intelligence, que chegou no iOS 26. Atualize o iPhone em Ajustes → Geral → Atualização de Software."
            )
        }
        #else
        AssistantUnavailableView(
            title: "Assistente indisponível",
            message: "Esta versão do app foi gerada sem suporte à Apple Intelligence."
        )
        #endif
    }
}

struct AssistantUnavailableView: View {
    let title: String
    let message: String

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: "sparkles")
        } description: {
            Text(message)
        }
        .background(Color.canvas)
    }
}

#if canImport(FoundationModels)
@available(iOS 26.0, *)
struct AssistantAvailabilityGate: View {
    let vehicle: Vehicle

    var body: some View {
        switch SystemLanguageModel.default.availability {
        case .available:
            AssistantChatView(vehicle: vehicle)
        case .unavailable(.deviceNotEligible):
            AssistantUnavailableView(
                title: "iPhone não compatível",
                message: "O assistente usa a Apple Intelligence, disponível a partir do iPhone 15 Pro. O restante do app funciona normalmente."
            )
        case .unavailable(.appleIntelligenceNotEnabled):
            AssistantUnavailableView(
                title: "Ative a Apple Intelligence",
                message: "Vá em Ajustes → Apple Intelligence e Siri e ative a Apple Intelligence para usar o assistente."
            )
        case .unavailable(.modelNotReady):
            AssistantUnavailableView(
                title: "Preparando a IA",
                message: "O iPhone ainda está baixando os modelos da Apple Intelligence. Deixe-o no Wi-Fi e carregando, e tente de novo mais tarde."
            )
        case .unavailable:
            AssistantUnavailableView(
                title: "Assistente indisponível",
                message: "A Apple Intelligence não está disponível neste momento."
            )
        }
    }
}

@available(iOS 26.0, *)
struct AssistantChatView: View {
    @Environment(\.modelContext) private var context
    let vehicle: Vehicle

    struct Message: Identifiable {
        enum Role { case user, assistant }
        let id = UUID()
        let role: Role
        let text: String
        var actions: [AgentActions.PerformedAction] = []
    }

    @State private var engine: AssistantEngine?
    @State private var messages: [Message] = []
    @State private var input = ""
    @State private var thinking = false
    @State private var undone: Set<UUID> = []
    @FocusState private var inputFocused: Bool

    private let suggestions = [
        "Abasteci 100 reais de gasolina",
        "Troquei o óleo por 250, próxima em 10 mil km",
        "Quanto gastei este mês?",
        "Meu km agora é 34.800",
        "Paguei uma multa de 195",
    ]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if messages.isEmpty {
                        welcome
                    }
                    ForEach(messages) { message in
                        bubble(message)
                            .id(message.id)
                    }
                    if thinking {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Pensando…").font(.subheadline).foregroundStyle(.secondary)
                        }
                        .id("thinking")
                    }
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .contentShape(Rectangle())
            .onTapGesture { inputFocused = false }
            .background(BrandGlow())
            .onChange(of: messages.count) { _, _ in
                withAnimation { proxy.scrollTo(messages.last?.id, anchor: .bottom) }
            }
            .onChange(of: thinking) { _, isThinking in
                if isThinking { withAnimation { proxy.scrollTo("thinking", anchor: .bottom) } }
            }
        }
        .safeAreaInset(edge: .bottom) { inputBar }
        .toolbar {
            ToolbarItem(placement: .principal) {
                if !messages.isEmpty {
                    Button("Nova conversa") {
                        messages.removeAll()
                        engine?.reset()
                    }
                    .font(.rounded(14, .semibold))
                }
            }
        }
        .onAppear {
            if engine == nil {
                engine = AssistantEngine(actions: AgentActions(vehicle: vehicle, context: context))
            }
        }
    }

    // MARK: Partes da tela

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "sparkles")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(Color.white)
                .frame(width: 60, height: 60)
                .background(Color.brand, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            Text("Fala que eu anoto").font(.rounded(26, .bold))
            Text("Conte o que aconteceu com o \(vehicle.name) e eu registro para você, ou pergunte sobre seus gastos. Tudo roda no seu iPhone, sem internet.")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(suggestions, id: \.self) { suggestion in
                    Button {
                        send(suggestion)
                    } label: {
                        Text(suggestion)
                            .font(.rounded(15, .medium))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .glassCard(cornerRadius: 16)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 4)
        }
        .padding(.top, 12)
    }

    @ViewBuilder
    private func bubble(_ message: Message) -> some View {
        switch message.role {
        case .user:
            HStack {
                Spacer(minLength: 40)
                Text(message.text)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .foregroundStyle(Color.white)
                    .background(Color.brand, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        case .assistant:
            VStack(alignment: .leading, spacing: 8) {
                ForEach(message.actions) { action in
                    actionCard(action)
                }
                Text(message.text)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .glassCard(cornerRadius: 18)
            }
            .padding(.trailing, 40)
        }
    }

    private func actionCard(_ action: AgentActions.PerformedAction) -> some View {
        let isUndone = undone.contains(action.id)
        return HStack(spacing: 12) {
            IconTile(systemName: isUndone ? "arrow.uturn.backward" : action.icon,
                     color: isUndone ? Color.secondary : Color.success, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(isUndone ? "Desfeito" : action.title)
                    .font(.rounded(15, .semibold))
                    .strikethrough(isUndone)
                Text(action.detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !isUndone {
                Button("Desfazer") {
                    engine?.actions.undo(action)
                    undone.insert(action.id)
                    Haptics.warning()
                }
                .font(.rounded(14, .semibold))
                .buttonStyle(.bordered)
            }
        }
        .padding(12)
        .glassCard(cornerRadius: 16)
    }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 10) {
            if inputFocused {
                Button {
                    inputFocused = false
                } label: {
                    Image(systemName: "keyboard.chevron.compact.down")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 42, height: 42)
                        .glassCircle()
                }
                .accessibilityLabel("Fechar teclado")
            }
            TextField("Ex.: abasteci 100 reais", text: $input, axis: .vertical)
                .lineLimit(1...4)
                .focused($inputFocused)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .glassCard(cornerRadius: 22)
                .submitLabel(.send)
                .onSubmit { send(input) }
            Button {
                send(input)
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Color.white)
                    .frame(width: 42, height: 42)
                    .background(canSend ? Color.brand : Color.secondary.opacity(0.4), in: Circle())
            }
            .disabled(!canSend)
            .accessibilityLabel("Enviar")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var canSend: Bool { !input.trimmed.isEmpty && !thinking }

    // MARK: Enviar

    private func send(_ text: String) {
        let trimmed = text.trimmed
        guard !trimmed.isEmpty, !thinking, let engine else { return }
        input = ""
        inputFocused = false
        messages.append(Message(role: .user, text: trimmed))
        thinking = true
        Task {
            let result = await engine.send(trimmed)
            thinking = false
            var reply = result.reply
            // A IA às vezes diz que registrou sem ter registrado: avisa para não perder o gasto.
            let lower = reply.lowercased()
            if result.performed.isEmpty, !reply.contains("?"),
               lower.contains("registrad") || lower.contains("lançad") || lower.contains("anotad") || lower.contains("atualizad") {
                reply += "\n\n⚠️ Não consegui salvar desta vez. Tente numa frase só, por exemplo: \"abasteci 100 reais, 14,75 litros\"."
            }
            messages.append(Message(role: .assistant, text: reply, actions: result.performed))
            if !result.performed.isEmpty { Haptics.success() }
        }
    }
}
#endif

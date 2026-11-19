import Foundation

/// Entende frases simples de lançamento sem depender da IA ("abasteci 100 reais", "multa de 195",
/// "troquei o óleo por 250", "meu km é 34.800"). Assim o registro acontece sempre, mesmo quando
/// o modelo da Apple responde sem chamar a ferramenta.
enum QuickCommand {
    case fuel(amount: Double?, liters: Double?, pricePerLiter: Double?, odometer: Int?, fuelType: String?, date: String?)
    case service(title: String, amount: Double?, odometer: Int?, intervalKm: Int?, intervalMonths: Int?, date: String?)
    case expense(kind: String, description: String?, amount: Double?, date: String?)
    case odometer(Int)
    /// Só complementos de um abastecimento ("14,75 L", "a 5,89 o litro").
    case fuelDetails(liters: Double?, pricePerLiter: Double?, odometer: Int?)

    enum Unit { case money, pricePerLiter, liters, km, months, none }

    struct Number {
        var value: Double
        var unit: Unit
        var isInterval: Bool
    }

    var isComplete: Bool {
        switch self {
        case let .fuel(amount, liters, pricePerLiter, _, _, _):
            return (amount ?? 0) > 0 || ((liters ?? 0) > 0 && (pricePerLiter ?? 0) > 0)
        case let .service(_, amount, _, _, _, _):
            return (amount ?? 0) > 0
        case let .expense(_, _, amount, _):
            return (amount ?? 0) > 0
        case .odometer, .fuelDetails:
            return true
        }
    }

    var missingQuestion: String {
        switch self {
        case .fuel: return "Quanto você pagou no abastecimento?"
        case .service: return "Quanto custou o serviço? (Se não quiser informar, diga 0.)"
        case .expense: return "Qual foi o valor?"
        case .odometer, .fuelDetails: return ""
        }
    }

    // MARK: Leitura da frase

    static func parse(_ raw: String) -> QuickCommand? {
        let text = raw.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "pt_BR"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !text.contains("?") else { return nil }
        let questionStarts = ["quanto", "qual", "quais", "como", "quando", "onde", "por que", "porque", "me fala", "me diga", "mostra", "resumo"]
        if questionStarts.contains(where: { text.hasPrefix($0) }) { return nil }

        func has(_ words: [String]) -> Bool { words.contains { text.contains($0) } }

        let found = numbers(in: text)
        let date = dateString(text)
        let money = found.first { $0.unit == .money }?.value
        let plain = found.first { $0.unit == .none }?.value
        let liters = found.first { $0.unit == .liters }?.value
        let pricePerLiter = found.first { $0.unit == .pricePerLiter }?.value
        let kmReading = found.first { $0.unit == .km && !$0.isInterval }.map { Int($0.value) }
        let kmInterval = found.first { $0.unit == .km && $0.isInterval }.map { Int($0.value) }
        let months = found.first { $0.unit == .months }.map { Int($0.value) }
        let amount = money ?? plain

        // Outros gastos
        let expenseKinds: [(word: String, kind: String, description: String?)] = [
            ("multa", "multa", nil), ("seguro", "seguro", nil), ("ipva", "ipva", nil),
            ("licenciamento", "licenciamento", nil), ("pedagio", "pedágio", "Pedágio"),
            ("estacionamento", "estacionamento", "Estacionamento"), ("lavagem", "outros", "Lavagem"),
            ("lava jato", "outros", "Lavagem"), ("lava-jato", "outros", "Lavagem"),
        ]
        if let match = expenseKinds.first(where: { text.contains($0.word) }) {
            return .expense(kind: match.kind, description: match.description, amount: amount, date: date)
        }

        // Manutenção
        let fuelWords = ["abastec", "gasolina", "etanol", "alcool", "diesel", "gnv", "combustivel", "enchi o tanque", "tanque cheio"]
        let serviceTitles: [(word: String, title: String)] = [
            ("oleo", "Troca de óleo"), ("alinhamento", "Alinhamento e balanceamento"),
            ("balanceamento", "Alinhamento e balanceamento"), ("pneu", "Troca de pneus"),
            ("pastilha", "Pastilhas de freio"), ("freio", "Freios"), ("filtro", "Troca de filtro"),
            ("revisao", "Revisão"), ("correia", "Correia dentada"), ("embreagem", "Embreagem"),
            ("amortecedor", "Amortecedores"), ("suspensao", "Suspensão"), ("bateria", "Bateria"),
            ("ar condicionado", "Ar-condicionado"), ("velas", "Velas de ignição"),
        ]
        let serviceVerbs = ["troquei", "manutencao", "oficina", "mecanico", "consertei", "conserto"]
        if let title = serviceTitles.first(where: { text.contains($0.word) })?.title
            ?? (has(serviceVerbs) && !has(fuelWords) ? "Manutenção" : nil) {
            return .service(title: title, amount: amount, odometer: kmReading,
                            intervalKm: kmInterval, intervalMonths: months, date: date)
        }

        // Abastecimento
        if has(fuelWords) || text.hasPrefix("coloquei") {
            var fuelType: String?
            if text.contains("aditivada") { fuelType = "gasolina aditivada" }
            else if text.contains("gasolina") { fuelType = "gasolina" }
            else if text.contains("etanol") || text.contains("alcool") { fuelType = "etanol" }
            else if text.contains("diesel") { fuelType = "diesel" }
            else if text.contains("gnv") { fuelType = "gnv" }
            return .fuel(amount: amount, liters: liters, pricePerLiter: pricePerLiter,
                         odometer: kmReading, fuelType: fuelType, date: date)
        }

        // Quilometragem
        if has(["km", "hodometro", "odometro", "quilometragem"]), money == nil,
           let km = kmReading ?? plain.map({ Int($0) }), km >= 100 {
            return .odometer(km)
        }

        // Complemento de abastecimento ("14,75 L")
        let detailUnits: [Unit] = [.liters, .pricePerLiter, .km]
        if !found.isEmpty, liters != nil || pricePerLiter != nil,
           found.allSatisfy({ detailUnits.contains($0.unit) }) {
            return .fuelDetails(liters: liters, pricePerLiter: pricePerLiter, odometer: kmReading)
        }
        return nil
    }

    private static let numberRegex = try? NSRegularExpression(
        pattern: #"\d+\.\d{1,2}(?![\d.])|\d{1,3}(?:\.\d{3})+(?:,\d+)?|\d+(?:,\d+)?"#
    )

    static func numbers(in text: String) -> [Number] {
        guard let regex = numberRegex else { return [] }
        let ns = text as NSString
        var result: [Number] = []
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let token = ns.substring(with: match.range)
            guard var value = numberValue(token) else { continue }
            var after = ns.substring(from: match.range.location + match.range.length)
                .trimmingCharacters(in: .whitespaces)
            let start = max(0, match.range.location - 20)
            let before = ns.substring(with: NSRange(location: start, length: match.range.location - start))

            if starts(after, #"mil\b"#) {
                value *= 1000
                after = String(after.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            }

            var unit = Unit.none
            if starts(after, #"(reais|real|contos|conto|pila)\b"#) || before.range(of: #"r\$\s*$"#, options: .regularExpression) != nil {
                unit = .money
                let rest = after.replacingOccurrences(of: #"^(reais|real|contos|conto|pila)\b"#, with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespaces)
                if starts(rest, #"(o litro|por litro|cada litro|/l\b|o l\b)"#) { unit = .pricePerLiter }
            } else if starts(after, #"(o litro|por litro|cada litro|/l\b)"#) {
                unit = .pricePerLiter
            } else if starts(after, #"(l|lt|lts|litro|litros)\b"#) {
                unit = .liters
            } else if starts(after, "(km|quil)") {
                unit = .km
            } else if starts(after, #"(mes|meses)\b"#) {
                unit = .months
            } else if starts(after, #"(ano|anos)\b"#) {
                unit = .months
                value *= 12
            } else if before.range(of: #"(km|hodometro|odometro|quilometragem)[^0-9]*$"#, options: .regularExpression) != nil {
                unit = .km
            }
            let isInterval = before.range(of: "(cada|proxim|daqui)", options: .regularExpression) != nil
            result.append(Number(value: value, unit: unit, isInterval: isInterval))
        }
        return result
    }

    static func numberValue(_ token: String) -> Double? {
        if token.contains(",") {
            return Double(token.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: "."))
        }
        if token.range(of: #"^\d{1,3}(\.\d{3})+$"#, options: .regularExpression) != nil {
            return Double(token.replacingOccurrences(of: ".", with: ""))
        }
        return Double(token)
    }

    private static func starts(_ text: String, _ pattern: String) -> Bool {
        text.range(of: "^" + pattern, options: .regularExpression) != nil
    }

    static func dateString(_ text: String) -> String? {
        let days: Int
        if text.contains("anteontem") { days = -2 }
        else if text.contains("ontem") { days = -1 }
        else { return nil }
        guard let date = Calendar.current.date(byAdding: .day, value: days, to: .now) else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

/// Executa os comandos simples e lembra do contexto da conversa
/// (valor que faltou, litros informados depois).
@MainActor
final class QuickCommandHandler {
    private var pendingText: String?
    private var lastFuel: Expense?
    private var lastDetail: String?

    func reset() {
        pendingText = nil
        lastFuel = nil
        lastDetail = nil
    }

    /// Retorna a resposta quando a frase foi resolvida sem a IA; nil = deixar para a IA.
    func handle(_ text: String, actions: AgentActions) -> String? {
        // Completa um pedido anterior que ficou sem valor ("abasteci de gasolina" → "100").
        if let pending = pendingText {
            pendingText = nil
            if let command = QuickCommand.parse(pending + " " + text), command.isComplete {
                return execute(command, actions: actions)
            }
        }

        guard let command = QuickCommand.parse(text) else {
            if lastDetail != nil, isConfirmation(text) {
                return "Já está lançado ✅"
            }
            return nil
        }

        if case let .fuelDetails(liters, pricePerLiter, odometer) = command {
            guard let lastFuel else { return nil }
            let reply = actions.updateFuel(lastFuel, liters: liters, pricePerLiter: pricePerLiter, odometer: odometer)
            lastDetail = reply
            return reply
        }

        guard command.isComplete else {
            pendingText = text
            return command.missingQuestion
        }
        return execute(command, actions: actions)
    }

    private func execute(_ command: QuickCommand, actions: AgentActions) -> String? {
        switch command {
        case let .fuel(amount, liters, pricePerLiter, odometer, fuelType, date):
            let value = amount ?? ((liters ?? 0) * (pricePerLiter ?? 0))
            _ = actions.addFuel(amount: value, liters: liters, pricePerLiter: pricePerLiter, odometer: odometer,
                                station: nil, fuelType: fuelType, date: date)
            guard let action = actions.performed.last else { return nil }
            lastFuel = action.expense
            lastDetail = action.detail
            var reply = "Pronto, lancei o abastecimento: \(action.detail) ✅"
            if lastFuel?.liters == nil {
                reply += "\nSe quiser, me diga os litros (ex.: 14,75 L) para eu calcular o consumo."
            }
            return reply
        case let .service(title, amount, odometer, intervalKm, intervalMonths, date):
            _ = actions.addService(title: title, amount: amount, place: nil, odometer: odometer,
                                   intervalKm: intervalKm, intervalMonths: intervalMonths, date: date)
            guard let action = actions.performed.last else { return nil }
            lastDetail = action.detail
            return "Pronto, registrei o serviço: \(action.detail) ✅"
        case let .expense(kind, description, amount, date):
            _ = actions.addExpense(kind: kind, description: description, amount: amount ?? 0, date: date)
            guard let action = actions.performed.last else { return nil }
            lastDetail = action.detail
            return "Pronto, registrei: \(action.detail) ✅"
        case let .odometer(km):
            let result = actions.updateOdometer(km)
            lastDetail = result
            return result
        case .fuelDetails:
            return nil
        }
    }

    private func isConfirmation(_ text: String) -> Bool {
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .trimmingCharacters(in: .punctuationCharacters.union(.whitespacesAndNewlines))
        return ["sim", "isso", "ok", "certo", "pode", "pode sim", "isso mesmo", "beleza", "blz"].contains(folded)
    }
}

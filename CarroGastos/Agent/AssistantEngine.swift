#if canImport(FoundationModels)
import Foundation
import FoundationModels

// Ferramentas que a IA da Apple (no próprio iPhone) pode chamar para agir no app.

@available(iOS 26.0, *)
struct RegisterFuelTool: Tool {
    let actions: AgentActions
    let name = "registrarAbastecimento"
    let description = "Registra um abastecimento de combustível. Use quando a pessoa disser que abasteceu ou colocou combustível."

    @Generable
    struct Arguments {
        @Guide(description: "Valor total pago em reais. Ex.: 100")
        var valor: Double
        @Guide(description: "Quantidade de litros, somente se a pessoa informar")
        var litros: Double?
        @Guide(description: "Preço por litro em reais, somente se a pessoa informar")
        var precoPorLitro: Double?
        @Guide(description: "Leitura do hodômetro em km, somente se a pessoa informar")
        var km: Int?
        @Guide(description: "Nome do posto, somente se a pessoa informar")
        var posto: String?
        @Guide(description: "Combustível: gasolina, gasolina aditivada, etanol, diesel ou GNV, somente se informado")
        var combustivel: String?
        @Guide(description: "Data no formato AAAA-MM-DD, somente se a pessoa citar um dia diferente de hoje")
        var data: String?
    }

    func call(arguments: Arguments) async throws -> String {
        await actions.addFuel(amount: arguments.valor, liters: arguments.litros, pricePerLiter: arguments.precoPorLitro,
                              odometer: arguments.km, station: arguments.posto, fuelType: arguments.combustivel, date: arguments.data)
    }
}

@available(iOS 26.0, *)
struct RegisterServiceTool: Tool {
    let actions: AgentActions
    let name = "registrarServico"
    let description = "Registra uma manutenção ou serviço no carro (troca de óleo, pneus, revisão, freios, alinhamento etc.), opcionalmente com lembrete da próxima vez."

    @Generable
    struct Arguments {
        @Guide(description: "Nome do serviço. Ex.: Troca de óleo")
        var servico: String
        @Guide(description: "Valor pago em reais, se informado")
        var valor: Double?
        @Guide(description: "Oficina ou local, se informado")
        var local: String?
        @Guide(description: "Km do carro no serviço, se informado")
        var km: Int?
        @Guide(description: "Repetir a cada quantos km, se a pessoa disser (ex.: 10000)")
        var aCadaKm: Int?
        @Guide(description: "Repetir a cada quantos meses, se a pessoa disser (ex.: 12)")
        var aCadaMeses: Int?
        @Guide(description: "Data no formato AAAA-MM-DD, somente se diferente de hoje")
        var data: String?
    }

    func call(arguments: Arguments) async throws -> String {
        await actions.addService(title: arguments.servico, amount: arguments.valor, place: arguments.local, odometer: arguments.km,
                                 intervalKm: arguments.aCadaKm, intervalMonths: arguments.aCadaMeses, date: arguments.data)
    }
}

@available(iOS 26.0, *)
struct RegisterExpenseTool: Tool {
    let actions: AgentActions
    let name = "registrarGasto"
    let description = "Registra outros gastos do carro: multa, seguro, IPVA, licenciamento, pedágio, estacionamento, lavagem, taxas ou outros."

    @Generable
    struct Arguments {
        @Guide(description: "Tipo: multa, seguro, ipva, licenciamento, taxa, pedágio, estacionamento ou outros")
        var tipo: String
        @Guide(description: "Descrição curta, se houver. Ex.: excesso de velocidade")
        var descricao: String?
        @Guide(description: "Valor em reais")
        var valor: Double
        @Guide(description: "Data no formato AAAA-MM-DD, somente se diferente de hoje")
        var data: String?
    }

    func call(arguments: Arguments) async throws -> String {
        await actions.addExpense(kind: arguments.tipo, description: arguments.descricao, amount: arguments.valor, date: arguments.data)
    }
}

@available(iOS 26.0, *)
struct UpdateOdometerTool: Tool {
    let actions: AgentActions
    let name = "atualizarKm"
    let description = "Atualiza a quilometragem (hodômetro) atual do carro."

    @Generable
    struct Arguments {
        @Guide(description: "Km atual do hodômetro. Ex.: 34600")
        var km: Int
    }

    func call(arguments: Arguments) async throws -> String {
        await actions.updateOdometer(arguments.km)
    }
}

@available(iOS 26.0, *)
struct SummaryTool: Tool {
    let actions: AgentActions
    let name = "consultarResumo"
    let description = "Consulta os dados do carro: gastos por período e categoria, consumo médio, custo por km, km, FIPE, orçamento, próximos serviços, documentos e preço médio do combustível na cidade."

    @Generable
    struct Arguments {
        @Guide(description: "Período: 'mes' (este mês), 'mes passado', 'ano' ou 'tudo'")
        var periodo: String
    }

    func call(arguments: Arguments) async throws -> String {
        await actions.summary(period: arguments.periodo)
    }
}

/// Conversa com a IA da Apple. Sem internet, sem custo, os dados não saem do iPhone.
@available(iOS 26.0, *)
@MainActor
final class AssistantEngine {
    let actions: AgentActions
    private var session: LanguageModelSession
    private let quick = QuickCommandHandler()

    init(actions: AgentActions) {
        self.actions = actions
        self.session = Self.makeSession(actions: actions)
    }

    private static func makeSession(actions: AgentActions) -> LanguageModelSession {
        let today = Date().formatted(.iso8601.year().month().day())
        let vehicle = actions.vehicle
        let instructions = """
        Você é o assistente do app Auto Check. Responda sempre em português do Brasil, de forma curta e simpática.
        Hoje é \(today). O carro ativo é \(vehicle.name) (\(vehicle.subtitle)), com \(vehicle.currentOdometer) km.
        Quando a pessoa contar um gasto (abastecimento, serviço, multa, seguro, IPVA etc.) ou um km, chame a ferramenta certa NA HORA.
        Não peça confirmação: se o valor foi informado, registre direto. Ex.: "abasteci 100 reais de gasolina" → chame registrarAbastecimento com valor 100 e combustivel gasolina.
        Se a pessoa mandar só um complemento (ex.: "14,75L" ou "sim"), junte com o que ela disse antes e chame a ferramenta.
        Você só consegue salvar algo chamando uma ferramenta. Nunca diga que registrou sem ter chamado a ferramenta.
        Nunca invente valores: se faltar o valor em reais de um gasto, pergunte.
        Para perguntas sobre gastos, consumo, km, FIPE, documentos ou preços, use consultarResumo e responda com base no resultado.
        Depois de registrar, confirme em uma frase o que foi lançado.
        Valores em reais (R$) com vírgula decimal.
        """
        let tools: [any Tool] = [
            RegisterFuelTool(actions: actions),
            RegisterServiceTool(actions: actions),
            RegisterExpenseTool(actions: actions),
            UpdateOdometerTool(actions: actions),
            SummaryTool(actions: actions),
        ]
        return LanguageModelSession(tools: tools, instructions: instructions)
    }

    func send(_ text: String) async -> (reply: String, performed: [AgentActions.PerformedAction]) {
        actions.beginTurn()
        // Lançamentos simples são feitos direto pelo app (sempre funcionam).
        if let reply = quick.handle(text, actions: actions) {
            return (reply, actions.performed)
        }
        do {
            let response = try await session.respond(to: text)
            return (response.content, actions.performed)
        } catch let error as LanguageModelSession.GenerationError {
            if case .exceededContextWindowSize = error {
                session = Self.makeSession(actions: actions)
                return ("A conversa ficou longa e eu recomecei. Pode repetir o pedido?", actions.performed)
            }
            return ("Não consegui entender agora. Pode dizer de outro jeito?", actions.performed)
        } catch {
            return ("Algo deu errado: \(error.localizedDescription)", actions.performed)
        }
    }

    func reset() {
        quick.reset()
        session = Self.makeSession(actions: actions)
    }
}
#endif

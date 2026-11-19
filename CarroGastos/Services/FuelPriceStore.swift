import Foundation
import Observation

/// Preço médio por cidade, da pesquisa semanal da ANP.
struct FuelCityPrices: Codable {
    var gasolina: Double?
    var gasolinaAditivada: Double?
    var etanol: Double?
    var diesel: Double?
    var dieselS10: Double?
    var gnv: Double?
    var postos: Int?
}

struct FuelPriceFile: Codable {
    var atualizado: String
    var periodo: String?
    var cidades: [String: FuelCityPrices]
}

/// Baixa o resumo semanal gerado pelo robô do GitHub (dados da ANP) e guarda uma cópia no aparelho.
@MainActor
@Observable
final class FuelPriceStore {
    static let shared = FuelPriceStore()

    /// Arquivo gerado toda semana pela automação do GitHub (repositório público).
    static let dataURL = URL(string: "https://raw.githubusercontent.com/matheussrodrigues06-alt/appcarro/main/data/combustivel.json")!

    private(set) var file: FuelPriceFile? = nil
    private(set) var lastFetch: Date? = nil
    private(set) var failed = false
    private(set) var cityKey: String

    private var cacheURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("combustivel.json")
    }

    init() {
        cityKey = UserDefaults.standard.string(forKey: "fuelCityKey") ?? ""
        if let data = try? Data(contentsOf: cacheURL) {
            file = try? JSONDecoder().decode(FuelPriceFile.self, from: data)
        }
    }

    var hasCity: Bool { !cityKey.isEmpty }

    var prices: FuelCityPrices? { file?.cidades[cityKey] }

    var cities: [String] { file?.cidades.keys.sorted() ?? [] }

    var cityLabel: String { Self.label(for: cityKey) }

    static let stateNames: [String: String] = [
        "AC": "Acre", "AL": "Alagoas", "AP": "Amapá", "AM": "Amazonas", "BA": "Bahia", "CE": "Ceará",
        "DF": "Distrito Federal", "ES": "Espírito Santo", "GO": "Goiás", "MA": "Maranhão", "MT": "Mato Grosso",
        "MS": "Mato Grosso do Sul", "MG": "Minas Gerais", "PA": "Pará", "PB": "Paraíba", "PR": "Paraná",
        "PE": "Pernambuco", "PI": "Piauí", "RJ": "Rio de Janeiro", "RN": "Rio Grande do Norte",
        "RS": "Rio Grande do Sul", "RO": "Rondônia", "RR": "Roraima", "SC": "Santa Catarina",
        "SP": "São Paulo", "SE": "Sergipe", "TO": "Tocantins",
    ]

    /// "PR/APUCARANA" → "PR"
    static func state(of key: String) -> String {
        String(key.split(separator: "/", maxSplits: 1).first ?? "")
    }

    /// Texto usado na busca: cidade, sigla e nome do estado ("Apucarana PR Paraná").
    static func searchText(for key: String) -> String {
        let uf = state(of: key)
        return "\(label(for: key)) \(stateNames[uf] ?? "")"
    }

    static func label(for key: String) -> String {
        let parts = key.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return key }
        return "\(parts[1].capitalized) - \(parts[0])"
    }

    func setCity(_ key: String) {
        cityKey = key
        UserDefaults.standard.set(key, forKey: "fuelCityKey")
    }

    /// Preço médio para o tipo de combustível usado no app.
    func average(for fuelType: String) -> Double? {
        guard let p = prices else { return nil }
        switch fuelType {
        case "Gasolina comum": return p.gasolina
        case "Gasolina aditivada": return p.gasolinaAditivada ?? p.gasolina
        case "Etanol": return p.etanol
        case "Diesel": return p.dieselS10 ?? p.diesel
        case "GNV": return p.gnv
        default: return nil
        }
    }

    func refreshIfNeeded() async {
        if let lastFetch, Date().timeIntervalSince(lastFetch) < 6 * 3600 { return }
        await refresh()
    }

    func refresh() async {
        do {
            var request = URLRequest(url: Self.dataURL)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.timeoutInterval = 20
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { failed = true; return }
            file = try JSONDecoder().decode(FuelPriceFile.self, from: data)
            lastFetch = .now
            failed = false
            try? data.write(to: cacheURL, options: .atomic)
        } catch {
            failed = true
        }
    }
}

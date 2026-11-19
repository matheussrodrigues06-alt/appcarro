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

    // Onde a pessoa mora (qualquer município do Brasil).
    private(set) var homeName: String
    private(set) var homeUF: String
    private(set) var homeLat: Double
    private(set) var homeLon: Double
    /// Distância até a cidade pesquisada pela ANP usada no lugar da sua (nil = é a própria cidade).
    private(set) var approxKm: Double?

    private var cacheURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("combustivel.json")
    }

    init() {
        let defaults = UserDefaults.standard
        cityKey = defaults.string(forKey: "fuelCityKey") ?? ""
        homeName = defaults.string(forKey: "homeName") ?? ""
        homeUF = defaults.string(forKey: "homeUF") ?? ""
        homeLat = defaults.double(forKey: "homeLat")
        homeLon = defaults.double(forKey: "homeLon")
        approxKm = defaults.object(forKey: "fuelApproxKm") as? Double
        if let data = try? Data(contentsOf: cacheURL) {
            file = try? JSONDecoder().decode(FuelPriceFile.self, from: data)
        }
    }

    var hasCity: Bool { !cityKey.isEmpty }
    var hasHome: Bool { !homeName.isEmpty }

    var home: Municipio? {
        hasHome ? Municipio(name: homeName, uf: homeUF, lat: homeLat, lon: homeLon) : nil
    }

    /// Nome da cidade para mostrar: a de casa, se escolhida; senão a cidade da ANP.
    var placeLabel: String { home?.label ?? cityLabel }

    /// Explica de onde vem o preço quando a cidade da pessoa não é pesquisada pela ANP.
    var sourceNote: String? {
        guard let approxKm, hasHome else { return nil }
        return "\(homeName) não entra na pesquisa da ANP. Usamos o preço de \(cityLabel), a cerca de \(Int(approxKm.rounded())) km, a cidade pesquisada mais próxima."
    }

    /// Define onde a pessoa mora e escolhe a cidade da ANP (a própria ou a mais próxima).
    func setHome(_ place: Municipio, places: [Municipio]) {
        homeName = place.name
        homeUF = place.uf
        homeLat = place.lat
        homeLon = place.lon
        let defaults = UserDefaults.standard
        defaults.set(place.name, forKey: "homeName")
        defaults.set(place.uf, forKey: "homeUF")
        defaults.set(place.lat, forKey: "homeLat")
        defaults.set(place.lon, forKey: "homeLon")
        resolveCity(places: places)
    }

    /// Escolhe a cidade pesquisada pela ANP para a cidade de casa.
    func resolveCity(places: [Municipio]) {
        guard let home, let file else { return }
        if file.cidades[home.anpKey] != nil {
            setCity(home.anpKey)
            setApprox(nil)
            return
        }
        // Coordenadas das cidades pesquisadas (pelo nome, na lista do IBGE).
        let byKey = Dictionary(places.map { ($0.anpKey, $0) }, uniquingKeysWith: { first, _ in first })
        let candidates = file.cidades.keys.compactMap { byKey[$0] }
        let sameState = candidates.filter { $0.uf == home.uf }
        let pool = sameState.isEmpty ? candidates : sameState
        if let nearest = pool.min(by: { home.distanceKm(to: $0) < home.distanceKm(to: $1) }) {
            setCity(nearest.anpKey)
            setApprox(home.distanceKm(to: nearest))
        }
    }

    private func setApprox(_ km: Double?) {
        approxKm = km
        UserDefaults.standard.set(km, forKey: "fuelApproxKm")
    }

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
            if hasHome, file?.cidades[cityKey] == nil {
                resolveCity(places: PlacesStore.shared.municipios)
            }
            try? data.write(to: cacheURL, options: .atomic)
        } catch {
            failed = true
        }
    }
}

import Foundation
import CoreLocation
import Observation

/// Município brasileiro (IBGE) com coordenadas.
struct Municipio: Hashable, Identifiable {
    let name: String
    let uf: String
    let lat: Double
    let lon: Double

    var id: String { "\(uf)/\(name)" }
    var label: String { "\(name) - \(uf)" }
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lon) }

    /// Mesmo formato das chaves da ANP: "PR/SAO JOSE DOS PINHAIS".
    var anpKey: String { "\(uf)/\(Municipio.fold(name))" }

    /// Texto usado na busca: cidade, sigla e nome do estado.
    var searchText: String { "\(name) \(uf) \(FuelPriceStore.stateNames[uf] ?? "")" }

    static func fold(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "pt_BR"))
            .uppercased()
            .split(separator: " ").joined(separator: " ")   // igual ao robô da ANP (mantém hífen e apóstrofo)
    }

    func distanceKm(to other: Municipio) -> Double {
        CLLocation(latitude: lat, longitude: lon).distance(from: CLLocation(latitude: other.lat, longitude: other.lon)) / 1000
    }
}

/// Praça de pedágio federal (ANTT), com valor aproximado para carro.
struct TollPlaza: Hashable, Identifiable, Decodable {
    let nome: String
    let concessionaria: String
    let rodovia: String
    let uf: String?
    let lat: Double
    let lon: Double
    let freeFlow: Bool
    let sentido: String?
    let valor: Double?
    /// nil = calculado para esta praça; "concessionaria"/"estado" = média (praça sem dados próprios).
    let estimado: String?

    var id: String { "\(concessionaria)|\(nome)|\(lat)|\(lon)" }
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lon) }

    var estimateNote: String? {
        switch estimado {
        case "concessionaria": return "Estimado pela média da concessionária"
        case "estado": return "Estimado pela média do estado"
        default: return nil
        }
    }

    /// Nome sem códigos internos ("P03 ORTIGUEIRA" → "Ortigueira").
    var displayName: String {
        var text = nome.replacingOccurrences(of: "\"", with: "")
        text = text.replacingOccurrences(of: #"(?i)free\s*flow"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: #"(?i)[-–]?\s*(de)?crescente"#, with: "", options: .regularExpression)
        text = text.trimmingCharacters(in: CharacterSet(charactersIn: " -–_"))
        text = text.replacingOccurrences(of: #"(?i)^(praça\s*)?(p|pe)\s?\d+\s*[-–]?\s*"#, with: "", options: .regularExpression)
        text = text.trimmingCharacters(in: CharacterSet(charactersIn: " -–_"))
        return text.isEmpty ? nome : text.capitalized(with: Locale(identifier: "pt_BR"))
    }
}

/// Baixa um arquivo de dados gerado pelos robôs do GitHub e guarda uma cópia no aparelho.
enum RemoteDataFile {
    static let base = "https://raw.githubusercontent.com/matheussrodrigues06-alt/appcarro/main/data/"

    static func cacheURL(_ name: String) -> URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent(name)
    }

    static func cached(_ name: String) -> Data? {
        try? Data(contentsOf: cacheURL(name))
    }

    static func download(_ name: String) async -> Data? {
        guard let url = URL(string: base + name) else { return nil }
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 30
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        try? data.write(to: cacheURL(name), options: .atomic)
        return data
    }
}

/// Municípios do Brasil (IBGE) e praças de pedágio (ANTT).
@MainActor
@Observable
final class PlacesStore {
    static let shared = PlacesStore()

    private(set) var municipios: [Municipio] = []
    private(set) var tolls: [TollPlaza] = []
    private(set) var tollsUpdated: String?
    private(set) var loading = false
    private(set) var failed = false
    private var lastFetch: Date?

    private struct MunicipiosFile: Decodable {
        let municipios: [[Value]]
        enum Value: Decodable {
            case text(String), number(Double)
            init(from decoder: Decoder) throws {
                let c = try decoder.singleValueContainer()
                if let d = try? c.decode(Double.self) { self = .number(d) } else { self = .text(try c.decode(String.self)) }
            }
            var text: String { if case .text(let s) = self { return s }; return "" }
            var number: Double { if case .number(let d) = self { return d }; return 0 }
        }
    }

    private struct TollFile: Decodable {
        let atualizado: String?
        let pracas: [TollPlaza]
    }

    init() {
        if let data = RemoteDataFile.cached("municipios.json") { municipios = Self.decodeMunicipios(data) }
        if let data = RemoteDataFile.cached("pedagios.json") { applyTolls(data) }
    }

    func refreshIfNeeded() async {
        if let lastFetch, Date().timeIntervalSince(lastFetch) < 24 * 3600, !municipios.isEmpty { return }
        await refresh()
    }

    func refresh() async {
        loading = true
        defer { loading = false }
        async let m = RemoteDataFile.download("municipios.json")
        async let t = RemoteDataFile.download("pedagios.json")
        let (mData, tData) = await (m, t)
        if let mData {
            let decoded = await Task.detached { Self.decodeMunicipios(mData) }.value
            if !decoded.isEmpty { municipios = decoded }
        }
        if let tData { applyTolls(tData) }
        failed = municipios.isEmpty
        if !municipios.isEmpty { lastFetch = .now }
    }

    private func applyTolls(_ data: Data) {
        if let file = try? JSONDecoder().decode(TollFile.self, from: data) {
            tolls = file.pracas
            tollsUpdated = file.atualizado
        }
    }

    nonisolated private static func decodeMunicipios(_ data: Data) -> [Municipio] {
        guard let file = try? JSONDecoder().decode(MunicipiosFile.self, from: data) else { return [] }
        return file.municipios.compactMap { row in
            guard row.count >= 4 else { return nil }
            return Municipio(name: row[0].text, uf: row[1].text, lat: row[2].number, lon: row[3].number)
        }
    }

    func municipio(named name: String, uf: String) -> Municipio? {
        let key = "\(uf)/\(Municipio.fold(name))"
        return municipios.first { $0.anpKey == key }
    }
}

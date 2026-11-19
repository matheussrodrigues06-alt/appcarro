import Foundation
import SwiftData

/// API pública e gratuita da Tabela FIPE (parallelum.com.br), sem cadastro.
enum FipeAPI {
    static let base = URL(string: "https://parallelum.com.br/fipe/api/v1/carros")!

    struct Item: Decodable, Identifiable, Hashable {
        let codigo: String
        let nome: String
        var id: String { codigo }

        enum CodingKeys: String, CodingKey { case codigo, nome }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            nome = try c.decode(String.self, forKey: .nome)
            if let text = try? c.decode(String.self, forKey: .codigo) {
                codigo = text
            } else {
                codigo = String(try c.decode(Int.self, forKey: .codigo))
            }
        }
    }

    struct ModelsResponse: Decodable { let modelos: [Item] }

    struct Price: Decodable {
        let Valor: String
        let Marca: String
        let Modelo: String
        let AnoModelo: Int
        let Combustivel: String
        let CodigoFipe: String
        let MesReferencia: String
    }

    static func brands() async throws -> [Item] {
        try await get("marcas")
    }

    static func models(brand: String) async throws -> [Item] {
        let response: ModelsResponse = try await get("marcas/\(brand)/modelos")
        return response.modelos
    }

    static func years(brand: String, model: String) async throws -> [Item] {
        try await get("marcas/\(brand)/modelos/\(model)/anos")
    }

    static func price(brand: String, model: String, year: String) async throws -> Price {
        try await get("marcas/\(brand)/modelos/\(model)/anos/\(year)")
    }

    private static func get<T: Decodable>(_ path: String) async throws -> T {
        var request = URLRequest(url: base.appending(path: path))
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

/// Mantém a FIPE dos carros vinculados sempre atualizada (confere a cada 3 dias, ao abrir o app).
@MainActor
enum FipeUpdater {
    static func refreshIfNeeded(_ vehicles: [Vehicle], context: ModelContext) async {
        for vehicle in vehicles where vehicle.isFipeLinked {
            // Confere a cada 3 dias (a tabela muda uma vez por mês; a consulta é grátis).
            if let last = vehicle.fipeUpdatedAt, Date().timeIntervalSince(last) < 3 * 86_400 {
                continue
            }
            await update(vehicle, context: context)
        }
    }

    @discardableResult
    static func update(_ vehicle: Vehicle, context: ModelContext) async -> Bool {
        guard vehicle.isFipeLinked else { return false }
        do {
            let price = try await FipeAPI.price(brand: vehicle.fipeBrandCode, model: vehicle.fipeModelCode, year: vehicle.fipeYearCode)
            guard let value = parseBrazilianNumber(price.Valor), value > 0 else { return false }
            let reference = price.MesReferencia.trimmed
            vehicle.fipeValue = value
            vehicle.fipeCode = price.CodigoFipe
            vehicle.fipeReference = reference
            vehicle.fipeUpdatedAt = .now
            if vehicle.sortedFipeHistory.last?.reference != reference {
                let entry = FipeEntry(reference: reference, value: value)
                context.insert(entry)
                vehicle.fipeHistory.append(entry)
            }
            try? context.save()
            return true
        } catch {
            return false
        }
    }
}

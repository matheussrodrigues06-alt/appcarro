import SwiftUI
import SwiftData

/// Busca o carro na Tabela FIPE: marca → modelo → ano. Depois disso o valor se atualiza sozinho.
struct FipeSearchView: View {
    @Environment(\.dismiss) private var dismiss
    let vehicle: Vehicle

    var body: some View {
        NavigationStack {
            FipeStepList(
                title: "Marca",
                prompt: "Buscar marca",
                initialSearch: vehicle.brand,
                load: { try await FipeAPI.brands() }
            ) { brand in
                FipeStepList(
                    title: brand.nome,
                    prompt: "Buscar modelo",
                    initialSearch: vehicle.modelName,
                    load: { try await FipeAPI.models(brand: brand.codigo) }
                ) { model in
                    FipeYearList(vehicle: vehicle, brand: brand, model: model) { dismiss() }
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
            }
        }
        .appSheetStyle()
    }
}

/// Lista com busca usada nas etapas de marca e modelo.
struct FipeStepList<Destination: View>: View {
    let title: String
    let prompt: String
    let load: () async throws -> [FipeAPI.Item]
    let destination: (FipeAPI.Item) -> Destination

    @State private var search: String
    @State private var items: [FipeAPI.Item] = []
    @State private var loading = true
    @State private var failed = false

    init(title: String, prompt: String, initialSearch: String = "",
         load: @escaping () async throws -> [FipeAPI.Item],
         @ViewBuilder destination: @escaping (FipeAPI.Item) -> Destination) {
        self.title = title
        self.prompt = prompt
        self.load = load
        self.destination = destination
        _search = State(initialValue: initialSearch)
    }

    private var filtered: [FipeAPI.Item] {
        let query = search.trimmed
        guard !query.isEmpty else { return items }
        let words = query.split(separator: " ").map(String.init)
        let matches = items.filter { item in words.allSatisfy { item.nome.localizedStandardContains($0) } }
        return matches.isEmpty ? items : matches
    }

    var body: some View {
        List {
            if loading {
                HStack(spacing: 10) { ProgressView(); Text("Carregando Tabela FIPE…").foregroundStyle(.secondary) }
            } else if failed {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Não consegui acessar a Tabela FIPE.").font(.rounded(16, .semibold))
                    Text("Verifique a internet e tente de novo.").foregroundStyle(.secondary)
                    Button("Tentar de novo") { Task { await reload() } }
                }
            } else {
                ForEach(filtered) { item in
                    NavigationLink(item.nome) { destination(item) }
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search, prompt: prompt)
        .task { if items.isEmpty { await reload() } }
    }

    private func reload() async {
        loading = true
        failed = false
        do {
            items = try await load()
        } catch {
            failed = true
        }
        loading = false
    }
}

/// Última etapa: escolher ano/combustível e vincular.
struct FipeYearList: View {
    @Environment(\.modelContext) private var context
    let vehicle: Vehicle
    let brand: FipeAPI.Item
    let model: FipeAPI.Item
    let onDone: () -> Void

    @State private var years: [FipeAPI.Item] = []
    @State private var loading = true
    @State private var saving = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                if loading {
                    HStack(spacing: 10) { ProgressView(); Text("Carregando anos…").foregroundStyle(.secondary) }
                } else {
                    ForEach(years) { year in
                        Button {
                            select(year)
                        } label: {
                            HStack {
                                Text(year.nome).foregroundStyle(.primary)
                                Spacer()
                                if saving { ProgressView() }
                            }
                        }
                        .disabled(saving)
                    }
                }
            } header: {
                Text(model.nome)
            } footer: {
                Text(errorMessage ?? "Escolha o ano do modelo e o combustível do seu carro.")
            }
        }
        .navigationTitle("Ano")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            years = (try? await FipeAPI.years(brand: brand.codigo, model: model.codigo)) ?? []
            loading = false
            if years.isEmpty { errorMessage = "Não consegui carregar os anos. Tente de novo." }
        }
    }

    private func select(_ year: FipeAPI.Item) {
        saving = true
        errorMessage = nil
        let previous = (vehicle.fipeBrandCode, vehicle.fipeModelCode, vehicle.fipeYearCode, vehicle.fipeModelName)
        if vehicle.fipeYearCode != year.codigo || vehicle.fipeModelCode != model.codigo {
            for entry in vehicle.fipeHistory { context.delete(entry) }
            vehicle.fipeHistory.removeAll()
        }
        vehicle.fipeBrandCode = brand.codigo
        vehicle.fipeModelCode = model.codigo
        vehicle.fipeYearCode = year.codigo
        vehicle.fipeModelName = "\(brand.nome) \(model.nome) · \(year.nome)"
        Task {
            let ok = await FipeUpdater.update(vehicle, context: context)
            saving = false
            if ok {
                Haptics.success()
                onDone()
            } else {
                (vehicle.fipeBrandCode, vehicle.fipeModelCode, vehicle.fipeYearCode, vehicle.fipeModelName) = previous
                errorMessage = "Não consegui buscar o valor agora. Verifique a internet e tente de novo."
                Haptics.warning()
            }
        }
    }
}

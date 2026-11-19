import SwiftUI

/// O que a pessoa escolheu na Tabela FIPE (marca → modelo → ano).
struct FipeSelection: Equatable {
    let brand: FipeAPI.Item
    let model: FipeAPI.Item
    let year: FipeAPI.Item

    /// "ix35 2.0 16V 2WD Flex Aut." → modelo "ix35", versão "2.0 16V 2WD Flex Aut."
    var modelName: String {
        String(model.nome.split(separator: " ").first ?? Substring(model.nome))
    }

    var version: String {
        let parts = model.nome.split(separator: " ", maxSplits: 1)
        return parts.count > 1 ? String(parts[1]) : ""
    }

    /// Código do ano na FIPE: "2020-1" (32000 = zero km).
    var yearNumber: Int {
        let value = Int(year.codigo.split(separator: "-").first ?? "") ?? 0
        return value == 32000 ? Calendar.current.component(.year, from: .now) : value
    }

    var displayName: String { "\(brand.nome) \(model.nome) · \(year.nome)" }
}

/// Catálogo da Tabela FIPE para escolher o carro sem digitar: marca → modelo → ano.
struct FipeCatalogPicker: View {
    @Environment(\.dismiss) private var dismiss
    let onPick: (FipeSelection) -> Void

    var body: some View {
        NavigationStack {
            FipeStepList(
                title: "Marca",
                prompt: "Buscar marca",
                load: { try await FipeAPI.brands() }
            ) { brand in
                FipeStepList(
                    title: brand.nome,
                    prompt: "Buscar modelo",
                    load: { try await FipeAPI.models(brand: brand.codigo) }
                ) { model in
                    FipeCatalogYearList(brand: brand, model: model) { year in
                        onPick(FipeSelection(brand: brand, model: model, year: year))
                        dismiss()
                    }
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

private struct FipeCatalogYearList: View {
    let brand: FipeAPI.Item
    let model: FipeAPI.Item
    let onPick: (FipeAPI.Item) -> Void

    @State private var years: [FipeAPI.Item] = []
    @State private var loading = true
    @State private var failed = false

    var body: some View {
        List {
            Section {
                if loading {
                    HStack(spacing: 10) { ProgressView(); Text("Carregando anos…").foregroundStyle(.secondary) }
                } else if failed {
                    Button("Não consegui carregar. Tentar de novo") { Task { await load() } }
                } else {
                    ForEach(years) { year in
                        Button {
                            Haptics.success()
                            onPick(year)
                        } label: {
                            HStack {
                                Text(year.nome.replacingOccurrences(of: "32000", with: "Zero km"))
                                    .foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
            } header: {
                Text(model.nome)
            } footer: {
                Text("Escolha o ano do modelo e o combustível.")
            }
        }
        .navigationTitle("Ano")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        loading = true
        failed = false
        do {
            years = try await FipeAPI.years(brand: brand.codigo, model: model.codigo)
        } catch {
            failed = true
        }
        loading = false
    }
}

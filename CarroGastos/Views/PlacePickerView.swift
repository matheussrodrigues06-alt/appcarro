import SwiftUI

/// Lista de todos os municípios do Brasil (IBGE), com busca por cidade ou estado.
struct PlacePickerView: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    var prompt = "Cidade ou estado (ex.: Apucarana)"
    var footer: String?
    var selectedID: String?
    let onPick: (Municipio) -> Void

    @State private var search = ""
    private var places: PlacesStore { PlacesStore.shared }

    private var results: [Municipio] {
        let query = search.trimmed
        guard !query.isEmpty else { return [] }
        let words = query.split(separator: " ").map(String.init)
        let matches = places.municipios.filter { place in
            words.allSatisfy { place.searchText.localizedStandardContains($0) }
        }
        // Começa pelo nome exato/início do nome
        let folded = Municipio.fold(query)
        return Array(matches.sorted { lhs, rhs in
            let l = Municipio.fold(lhs.name).hasPrefix(folded), r = Municipio.fold(rhs.name).hasPrefix(folded)
            if l != r { return l }
            return lhs.label.localizedStandardCompare(rhs.label) == .orderedAscending
        }.prefix(80))
    }

    var body: some View {
        NavigationStack {
            List {
                if places.municipios.isEmpty {
                    Section {
                        if places.failed && !places.loading {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Não consegui carregar as cidades.").font(.rounded(16, .semibold))
                                Text("Verifique a internet e tente de novo.").foregroundStyle(.secondary)
                                Button("Tentar de novo") { Task { await places.refresh() } }
                            }
                        } else {
                            HStack(spacing: 10) { ProgressView(); Text("Carregando cidades…").foregroundStyle(.secondary) }
                        }
                    }
                } else if search.trimmed.isEmpty {
                    Section {
                        Label("Digite o nome da sua cidade ou do estado. Todas as 5.570 cidades do Brasil estão aqui.",
                              systemImage: "magnifyingglass")
                            .foregroundStyle(.secondary)
                    } footer: {
                        if let footer { Text(footer) }
                    }
                } else if results.isEmpty {
                    Section {
                        Text("Nenhuma cidade encontrada com \"\(search.trimmed)\".").foregroundStyle(.secondary)
                    }
                } else {
                    Section {
                        ForEach(results) { place in
                            Button {
                                Haptics.success()
                                onPick(place)
                                dismiss()
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(place.name).foregroundStyle(.primary)
                                        Text(FuelPriceStore.stateNames[place.uf] ?? place.uf)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if place.id == selectedID {
                                        Image(systemName: "checkmark").foregroundStyle(Color.brand)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                        }
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: prompt)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fechar") { dismiss() }
                }
            }
            .task { await places.refreshIfNeeded() }
        }
        .appSheetStyle()
    }
}

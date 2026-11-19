import SwiftUI

/// Escolha da cidade para comparar com o preço médio da ANP.
struct FuelCityPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    private var store: FuelPriceStore { FuelPriceStore.shared }

    private var filtered: [String] {
        let query = search.trimmed
        guard !query.isEmpty else { return store.cities }
        // Busca por cidade, sigla ou nome do estado ("Paraná" mostra todas do PR).
        let words = query.split(separator: " ").map(String.init)
        return store.cities.filter { key in
            let text = FuelPriceStore.searchText(for: key)
            return words.allSatisfy { text.localizedStandardContains($0) }
        }
    }

    private struct StateGroup: Identifiable {
        let state: String
        let cities: [String]
        var id: String { state }
        var name: String { FuelPriceStore.stateNames[state] ?? state }
    }

    /// Cidades agrupadas por estado, em ordem alfabética do nome do estado.
    private var grouped: [StateGroup] {
        Dictionary(grouping: filtered) { FuelPriceStore.state(of: $0) }
            .map { StateGroup(state: $0.key, cities: $0.value.sorted { FuelPriceStore.label(for: $0) < FuelPriceStore.label(for: $1) }) }
            .sorted { $0.name < $1.name }
    }

    var body: some View {
        NavigationStack {
            List {
                if store.file == nil {
                    Section {
                        if store.failed {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Dados da ANP indisponíveis no momento.").font(.rounded(16, .semibold))
                                Text("Verifique a internet e tente de novo.").foregroundStyle(.secondary)
                                Button("Tentar de novo") { Task { await store.refresh() } }
                            }
                        } else {
                            HStack(spacing: 10) { ProgressView(); Text("Carregando cidades…").foregroundStyle(.secondary) }
                        }
                    }
                } else {
                    if filtered.isEmpty {
                        Section {
                            Text("Nenhuma cidade encontrada. A ANP pesquisa cerca de 400 cidades; escolha a mais próxima da sua.")
                                .foregroundStyle(.secondary)
                        }
                    }
                    ForEach(grouped) { group in
                        Section(group.name) {
                            ForEach(group.cities, id: \.self) { key in
                                Button {
                                    store.setCity(key)
                                    Haptics.success()
                                    dismiss()
                                } label: {
                                    HStack {
                                        Text(FuelPriceStore.label(for: key)).foregroundStyle(.primary)
                                        Spacer()
                                        if key == store.cityKey {
                                            Image(systemName: "checkmark").foregroundStyle(Color.brand)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    if let file = store.file {
                        Section {
                        } footer: {
                            Text("Fonte: ANP, pesquisa semanal de preços (\(file.periodo ?? file.atualizado)). Busque pelo nome da cidade ou do estado. Se a sua cidade não aparecer, escolha a mais próxima.")
                        }
                    }
                }
            }
            .navigationTitle("Sua cidade")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $search, prompt: "Cidade ou estado (ex.: Apucarana)")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fechar") { dismiss() }
                }
            }
            .task { await store.refreshIfNeeded() }
        }
        .appSheetStyle()
    }
}

/// Cartão do Início com o preço médio da semana na cidade escolhida.
struct FuelPriceCard: View {
    let vehicle: Vehicle
    let onChooseCity: () -> Void
    private var store: FuelPriceStore { FuelPriceStore.shared }

    var body: some View {
        Button(action: onChooseCity) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    IconTile(systemName: "fuelpump.fill", color: Color.fuelBlue, size: 36)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Combustível na sua cidade").font(.rounded(16, .semibold))
                        Text(store.hasCity ? store.cityLabel : "Toque para escolher sua cidade")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.footnote.bold()).foregroundStyle(.tertiary)
                }
                if let prices = store.prices {
                    HStack(spacing: 0) {
                        priceColumn("Gasolina", prices.gasolina)
                        priceColumn("Etanol", prices.etanol)
                        priceColumn("Diesel S10", prices.dieselS10 ?? prices.diesel)
                    }
                    if let g = prices.gasolina, let e = prices.etanol, g > 0 {
                        let ratio = e / g
                        Label(ratio <= 0.7
                              ? "Etanol compensa (\(ratio.formatted(.percent.precision(.fractionLength(0)))) da gasolina)"
                              : "Gasolina compensa (etanol a \(ratio.formatted(.percent.precision(.fractionLength(0)))))",
                              systemImage: ratio <= 0.7 ? "leaf.fill" : "flame.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(ratio <= 0.7 ? Color.success : Color.brand)
                    }
                    if let last = vehicle.lastFuel, let paid = last.pricePerLiter, let average = store.average(for: last.fuelType.isEmpty ? "Gasolina comum" : last.fuelType), average > 0 {
                        let diff = (paid - average) / average
                        Text("Seu último abastecimento: \(paid.brl)/L, \(abs(diff).formatted(.percent.precision(.fractionLength(0)))) \(diff >= 0 ? "acima" : "abaixo") da média.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else if store.hasCity {
                    Text(store.failed ? "Dados da ANP indisponíveis no momento." : "Carregando preços…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard()
            .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
    }

    private func priceColumn(_ title: String, _ value: Double?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value.map { $0.brl } ?? "—").font(.rounded(17, .bold)).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

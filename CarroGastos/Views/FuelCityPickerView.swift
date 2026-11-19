import SwiftUI

/// "Onde você mora": qualquer cidade do Brasil. O preço do combustível vem da ANP;
/// se a cidade não for pesquisada, usa a cidade pesquisada mais próxima (e o app explica isso).
struct FuelCityPickerView: View {
    private var store: FuelPriceStore { FuelPriceStore.shared }

    var body: some View {
        PlacePickerView(
            title: "Onde você mora",
            footer: "Usamos sua cidade para mostrar o preço médio do combustível (pesquisa semanal da ANP) e como ponto de partida das viagens. Se a ANP não pesquisa sua cidade, usamos a cidade pesquisada mais próxima e avisamos.",
            selectedID: store.home?.id
        ) { place in
            let places = PlacesStore.shared.municipios
            store.setHome(place, places: places)
            Task {
                await store.refreshIfNeeded()
                store.resolveCity(places: places)
            }
        }
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
                        Text(store.hasCity ? store.placeLabel : "Toque para escolher onde você mora")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.footnote.bold()).foregroundStyle(.tertiary)
                }
                if let note = store.sourceNote {
                    Label(note, systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
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

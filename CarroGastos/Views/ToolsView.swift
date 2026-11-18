import SwiftUI

/// Linha de formulário com rótulo à esquerda e número à direita.
struct FormNumberRow: View {
    let label: String
    @Binding var text: String
    var placeholder = "0"
    var keyboard: UIKeyboardType = .decimalPad

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            TextField(placeholder, text: $text)
                .keyboardType(keyboard)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
        }
    }
}

// MARK: - Etanol ou gasolina?

struct FuelCompareView: View {
    @Environment(\.dismiss) private var dismiss
    let vehicle: Vehicle
    @State private var ethanolText = ""
    @State private var gasolineText = ""

    private var ethanol: Double? { Double.parse(ethanolText) }
    private var gasoline: Double? { Double.parse(gasolineText) }

    private var ratio: Double? {
        guard let ethanol, let gasoline, ethanol > 0, gasoline > 0 else { return nil }
        return ethanol / gasoline
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    FormNumberRow(label: "Etanol (R$/L)", text: $ethanolText, placeholder: "0,00")
                    FormNumberRow(label: "Gasolina (R$/L)", text: $gasolineText, placeholder: "0,00")
                } header: {
                    Text(FuelPriceStore.shared.prices != nil ? "Preço médio em \(FuelPriceStore.shared.cityLabel)" : "Preço no posto")
                } footer: {
                    Text("Regra prática: o etanol rende cerca de 30% menos, então compensa quando custa até 70% do preço da gasolina.")
                }

                if let ratio {
                    Section {
                        let ethanolWins = ratio <= 0.7
                        VStack(spacing: 12) {
                            Image(systemName: ethanolWins ? "leaf.fill" : "flame.fill")
                                .font(.system(size: 30, weight: .semibold))
                                .foregroundStyle(Color.white)
                                .frame(width: 64, height: 64)
                                .background(ethanolWins ? Color.success : Color.brand, in: Circle())
                            Text(ethanolWins ? "Abasteça com etanol" : "Abasteça com gasolina")
                                .font(.rounded(22, .bold))
                            Text("O etanol está custando \(ratio.formatted(.percent.precision(.fractionLength(0)))) do preço da gasolina.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                            ProgressView(value: min(ratio, 1))
                                .tint(ethanolWins ? Color.success : Color.brand)
                                .overlay(alignment: .leading) {
                                    GeometryReader { proxy in
                                        Rectangle()
                                            .fill(Color.primary)
                                            .frame(width: 2, height: 14)
                                            .offset(x: proxy.size.width * 0.7 - 1, y: -5)
                                    }
                                }
                                .padding(.top, 6)
                            Text("Linha = limite de 70%").font(.caption2).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    }
                }
            }
            .navigationTitle("Etanol ou gasolina?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { dismiss() }.fontWeight(.bold)
                }
            }
            .onAppear {
                let city = FuelPriceStore.shared.prices
                if ethanolText.isEmpty, let price = city?.etanol ?? vehicle.lastFuelPrice(containing: "Etanol") {
                    ethanolText = price.decimalInput
                }
                if gasolineText.isEmpty, let price = city?.gasolina ?? vehicle.lastFuelPrice(containing: "Gasolina") {
                    gasolineText = price.decimalInput
                }
            }
        }
        .presentationDetents([.medium, .large])
        .appSheetStyle()
    }
}

// MARK: - Custo de viagem

struct TripCostView: View {
    @Environment(\.dismiss) private var dismiss
    let vehicle: Vehicle
    @State private var distanceText = ""
    @State private var roundTrip = true
    @State private var tollsText = ""
    @State private var consumptionText = ""
    @State private var priceText = ""
    @State private var people = 1

    private var multiplier: Double { roundTrip ? 2 : 1 }
    private var distance: Double? { Double.parse(distanceText).map { $0 * multiplier } }
    private var tolls: Double { (Double.parse(tollsText) ?? 0) * multiplier }

    private var liters: Double? {
        guard let distance, let consumption = Double.parse(consumptionText), consumption > 0 else { return nil }
        return distance / consumption
    }

    private var fuelCost: Double? {
        guard let liters, let price = Double.parse(priceText), price > 0 else { return nil }
        return liters * price
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Viagem") {
                    FormNumberRow(label: "Distância (km, só ida)", text: $distanceText, keyboard: .numberPad)
                    Toggle("Ida e volta", isOn: $roundTrip)
                    FormNumberRow(label: "Pedágios (R$, só ida)", text: $tollsText, placeholder: "0,00")
                }

                Section {
                    FormNumberRow(label: "Consumo (km/l)", text: $consumptionText, placeholder: "10")
                    FormNumberRow(label: "Preço do litro (R$)", text: $priceText, placeholder: "0,00")
                } header: {
                    Text("Carro")
                } footer: {
                    if vehicle.fuelEfficiency != nil {
                        Text("Preenchido com o consumo médio e o último preço registrados no app.")
                    }
                }

                Section("Dividir entre") {
                    Stepper(people == 1 ? "1 pessoa" : "\(people) pessoas", value: $people, in: 1...8)
                }

                if let distance, let liters, let fuelCost {
                    let total = fuelCost + tolls
                    Section("Resultado") {
                        LabeledContent("Distância total", value: Int(distance.rounded()).km)
                        LabeledContent("Combustível",
                                       value: "\(liters.formatted(.number.precision(.fractionLength(1)))) L · \(fuelCost.brl)")
                        if tolls > 0 {
                            LabeledContent("Pedágios", value: tolls.brl)
                        }
                        LabeledContent {
                            Text(total.brl).font(.rounded(20, .bold)).foregroundStyle(Color.brand)
                        } label: {
                            Text("Total").font(.rounded(17, .semibold))
                        }
                        if people > 1 {
                            LabeledContent("Por pessoa", value: (total / Double(people)).brl)
                        }
                    }
                }
            }
            .navigationTitle("Custo de viagem")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { dismiss() }.fontWeight(.bold)
                }
            }
            .onAppear {
                if consumptionText.isEmpty, let efficiency = vehicle.fuelEfficiency {
                    consumptionText = efficiency.formatted(.number.precision(.fractionLength(1)).grouping(.never))
                }
                if priceText.isEmpty, let price = vehicle.lastFuel?.pricePerLiter {
                    priceText = price.decimalInput
                }
            }
        }
        .appSheetStyle()
    }
}

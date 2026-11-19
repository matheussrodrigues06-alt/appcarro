import SwiftUI
import SwiftData
import MapKit

/// Planejar viagem: rota no mapa (Apple Mapas), pedágios no caminho (ANTT),
/// combustível pela média do carro e preço da cidade, e quantos tanques a viagem gasta.
struct TripPlannerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    let vehicle: Vehicle

    private enum PickTarget: String, Identifiable {
        case origin, destination
        var id: String { rawValue }
    }

    @State private var origin: Municipio?
    @State private var destination: Municipio?
    @State private var picking: PickTarget?
    @State private var roundTrip = true
    @State private var consumptionText = ""
    @State private var priceText = ""
    @State private var tankText = ""
    @State private var extraTollText = ""
    @State private var people = 1
    @State private var route: MKRoute?
    @State private var routeTolls: [TollPlaza] = []
    @State private var calculating = false
    @State private var errorMessage: String?
    @State private var camera: MapCameraPosition = .automatic
    @State private var loaded = false
    @State private var overrides: [String: Double] = TollOverrides.load()
    @State private var editingToll: TollPlaza?
    @State private var tollText = ""

    private var places: PlacesStore { PlacesStore.shared }
    private var fuelStore: FuelPriceStore { FuelPriceStore.shared }

    // MARK: Contas

    private var multiplier: Double { roundTrip ? 2 : 1 }
    private var oneWayKm: Double? { route.map { $0.distance / 1000 } }
    private var totalKm: Double? { oneWayKm.map { $0 * multiplier } }
    private var consumption: Double? { Double.parse(consumptionText).flatMap { $0 > 0 ? $0 : nil } }
    private var price: Double? { Double.parse(priceText).flatMap { $0 > 0 ? $0 : nil } }
    private var tank: Double? { Double.parse(tankText).flatMap { $0 > 0 ? $0 : nil } }

    private var liters: Double? {
        guard let totalKm, let consumption else { return nil }
        return totalKm / consumption
    }
    private var fuelCost: Double? {
        guard let liters, let price else { return nil }
        return liters * price
    }
    /// Valor que você informou (se houver) ou o aproximado da ANTT.
    private func value(of toll: TollPlaza) -> Double? { overrides[toll.id] ?? toll.valor }

    private var tolls: Double {
        let known = routeTolls.compactMap { value(of: $0) }.reduce(0, +)
        return (known + (Double.parse(extraTollText) ?? 0)) * multiplier
    }
    private var missingTollValues: Int { routeTolls.filter { value(of: $0) == nil }.count }

    private var routeKey: String { "\(origin?.id ?? "")>\(destination?.id ?? "")" }

    var body: some View {
        NavigationStack {
            Form {
                routeSection
                if calculating {
                    Section {
                        HStack(spacing: 10) { ProgressView(); Text("Calculando a rota…").foregroundStyle(.secondary) }
                    }
                }
                if let errorMessage {
                    Section { Label(errorMessage, systemImage: "exclamationmark.triangle").foregroundStyle(Color.danger) }
                }
                if let route {
                    mapSection(route)
                    tollSection(route)
                }
                carSection
                if route != nil { resultSection }
            }
            .navigationTitle("Planejar viagem")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fechar") { dismiss() }
                }
            }
            .sheet(item: $picking) { target in
                PlacePickerView(
                    title: target == .origin ? "Saindo de" : "Indo para",
                    selectedID: (target == .origin ? origin : destination)?.id
                ) { place in
                    if target == .origin { origin = place } else { destination = place }
                }
            }
            .task(id: routeKey) { await calculate() }
            .task { await places.refreshIfNeeded() }
            .onChange(of: places.tolls.count) { _, _ in
                if let route { routeTolls = Self.tolls(on: route, from: places.tolls) }
            }
            .alert("Valor do pedágio", isPresented: Binding(
                get: { editingToll != nil },
                set: { if !$0 { editingToll = nil } }
            ), presenting: editingToll) { toll in
                TextField("R$ (só ida, carro)", text: $tollText)
                    .keyboardType(.decimalPad)
                Button("Salvar") {
                    if let v = Double.parse(tollText), v > 0 {
                        overrides[toll.id] = v
                        TollOverrides.save(overrides)
                    }
                }
                if overrides[toll.id] != nil {
                    Button("Voltar ao valor da ANTT", role: .destructive) {
                        overrides[toll.id] = nil
                        TollOverrides.save(overrides)
                    }
                }
                Button("Cancelar", role: .cancel) {}
            } message: { toll in
                Text("\(toll.displayName) (\(toll.rodovia)). Valor para carro, em um sentido.")
            }
            .onAppear(perform: load)
            .onDisappear(perform: saveTank)
        }
        .appSheetStyle()
    }

    // MARK: Seções

    private var routeSection: some View {
        Section {
            placeRow(title: "Saindo de", icon: "house.fill", place: origin) { picking = .origin }
            placeRow(title: "Indo para", icon: "flag.checkered", place: destination) { picking = .destination }
            Toggle("Ida e volta", isOn: $roundTrip)
        } header: {
            Text("Rota")
        } footer: {
            Text("A rota de carro é calculada pelo Apple Mapas.")
        }
    }

    private func placeRow(title: String, icon: String, place: Municipio?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Label(title, systemImage: icon).foregroundStyle(.primary)
                Spacer()
                Text(place?.label ?? "Escolher")
                    .foregroundStyle(place == nil ? Color.brand : Color.secondary)
                    .lineLimit(1)
                Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
    }

    private func mapSection(_ route: MKRoute) -> some View {
        Section {
            Map(position: $camera) {
                MapPolyline(route.polyline)
                    .stroke(Color.brand, lineWidth: 5)
                if let origin {
                    Marker("Saída", systemImage: "house.fill", coordinate: origin.coordinate)
                        .tint(Color.fuelBlue)
                }
                if let destination {
                    Marker(destination.name, systemImage: "flag.checkered", coordinate: destination.coordinate)
                        .tint(Color.brand)
                }
                ForEach(routeTolls) { toll in
                    Annotation(toll.displayName, coordinate: toll.coordinate) {
                        Image(systemName: toll.freeFlow ? "antenna.radiowaves.left.and.right" : "dollarsign")
                            .font(.caption.bold())
                            .foregroundStyle(Color.white)
                            .frame(width: 26, height: 26)
                            .background(Color.warning, in: Circle())
                            .overlay(Circle().strokeBorder(Color.white, lineWidth: 2))
                    }
                }
            }
            .mapStyle(.standard(pointsOfInterest: .excludingAll))
            .frame(height: 260)
            .listRowInsets(EdgeInsets())

            LabeledContent("Distância (só ida)", value: Int((route.distance / 1000).rounded()).km)
            LabeledContent("Tempo estimado (só ida)", value: Duration.seconds(route.expectedTravelTime)
                .formatted(.units(allowed: [.hours, .minutes], width: .abbreviated)))
        }
    }

    @ViewBuilder
    private func tollSection(_ route: MKRoute) -> some View {
        Section {
            if routeTolls.isEmpty {
                Text(route.hasTolls
                     ? "O Apple Mapas indica pedágio nesta rota, mas ele não está na base federal (pode ser rodovia estadual). Informe o valor abaixo, se souber."
                     : "Nenhum pedágio encontrado nesta rota.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ForEach(routeTolls) { toll in
                Button {
                    tollText = value(of: toll)?.decimalInput ?? ""
                    editingToll = toll
                } label: {
                    HStack(spacing: 12) {
                        IconTile(systemName: toll.freeFlow ? "antenna.radiowaves.left.and.right" : "dollarsign",
                                 color: Color.warning, size: 34)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(toll.displayName).font(.rounded(15, .semibold)).foregroundStyle(.primary)
                                if toll.freeFlow {
                                    Text("FREE FLOW")
                                        .font(.system(size: 9, weight: .heavy))
                                        .padding(.horizontal, 5).padding(.vertical, 2)
                                        .background(Color.fuelBlue.opacity(0.15), in: Capsule())
                                        .foregroundStyle(Color.fuelBlue)
                                }
                            }
                            Text("\(toll.rodovia) · \(toll.concessionaria.capitalized(with: Locale(identifier: "pt_BR")))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            if overrides[toll.id] == nil, toll.isOfficial {
                                Text("Valor oficial da concessionária")
                                    .font(.caption2)
                                    .foregroundStyle(Color.success)
                            } else if overrides[toll.id] == nil, let note = toll.estimateNote {
                                Text(note)
                                    .font(.caption2)
                                    .foregroundStyle(Color.warning)
                            } else if overrides[toll.id] != nil {
                                Text("Valor informado por você")
                                    .font(.caption2)
                                    .foregroundStyle(Color.success)
                            }
                        }
                        Spacer()
                        if let v = value(of: toll) {
                            Text(overrides[toll.id] != nil || toll.isOfficial ? v.brl : "≈ \(v.brl)")
                                .font(.rounded(15, .semibold))
                                .monospacedDigit()
                                .foregroundStyle(.primary)
                        } else {
                            Text("Informar")
                                .font(.rounded(15, .semibold))
                                .foregroundStyle(Color.brand)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            FormNumberRow(label: "Outros pedágios (R$, só ida)", text: $extraTollText, placeholder: "0,00")
        } header: {
            Text(routeTolls.isEmpty ? "Pedágios" : "Pedágios no caminho (\(routeTolls.count))")
        } footer: {
            Text("Toque num pedágio para informar ou corrigir o valor; o app guarda para as próximas viagens. \"≈\" = valor aproximado para carro, calculado com dados abertos da ANTT (rodovias federais). No free flow não há cabine: a cobrança é pela placa, pelo app ou site da concessionária.")
        }
    }

    private var carSection: some View {
        Section {
            FormNumberRow(label: "Consumo (km/l)", text: $consumptionText, placeholder: "10")
            FormNumberRow(label: "Preço do litro (R$)", text: $priceText, placeholder: "0,00")
            FormNumberRow(label: "Tanque (litros)", text: $tankText, placeholder: "Ex.: 50", keyboard: .numberPad)
        } header: {
            Text("Seu carro")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text(vehicle.fuelEfficiency != nil
                     ? "Consumo: a média do seu carro registrada no app."
                     : "Consumo: informe o do seu carro. Depois de alguns abastecimentos com tanque cheio, o app calcula sozinho.")
                if fuelStore.prices != nil {
                    Text("Preço: média da ANP em \(fuelStore.cityLabel).")
                }
                if let note = fuelStore.sourceNote { Text(note) }
            }
        }
    }

    private var resultSection: some View {
        Section {
            if let totalKm {
                LabeledContent(roundTrip ? "Distância (ida e volta)" : "Distância", value: Int(totalKm.rounded()).km)
            }
            if let liters {
                LabeledContent("Combustível", value: "\(liters.formatted(.number.precision(.fractionLength(1)))) L")
                if let tank {
                    LabeledContent("Tanques", value: tanksText(liters / tank))
                }
            }
            if let fuelCost {
                LabeledContent("Gasto com combustível", value: fuelCost.brl)
            }
            LabeledContent("Pedágios", value: tolls > 0 ? "≈ \(tolls.brl)" : "R$ 0,00")
            if let fuelCost {
                let total = fuelCost + tolls
                LabeledContent {
                    Text(total.brl).font(.rounded(20, .bold)).foregroundStyle(Color.brand)
                } label: {
                    Text("Total da viagem").font(.rounded(17, .semibold))
                }
                Stepper(people == 1 ? "Dividir: só eu" : "Dividir entre \(people) pessoas", value: $people, in: 1...8)
                if people > 1 {
                    LabeledContent("Por pessoa", value: (total / Double(people)).brl)
                }
            } else {
                Text("Preencha o consumo e o preço do litro para ver o total.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Quanto vai custar")
        } footer: {
            if missingTollValues > 0 {
                Text("\(missingTollValues) pedágio(s) sem valor na base não entraram na conta. Some em \"Outros pedágios\", se souber.")
            }
        }
    }

    private func tanksText(_ tanks: Double) -> String {
        if tanks < 1 { return "\((tanks * 100).formatted(.number.precision(.fractionLength(0))))% de um tanque" }
        return "\(tanks.formatted(.number.precision(.fractionLength(1)))) tanques"
    }

    // MARK: Dados

    private func load() {
        guard !loaded else { return }
        loaded = true
        origin = fuelStore.home
        if let efficiency = vehicle.fuelEfficiency {
            consumptionText = efficiency.formatted(.number.precision(.fractionLength(1)).grouping(.never))
        }
        let fuelType = vehicle.lastFuel?.fuelType ?? "Gasolina comum"
        if let price = fuelStore.average(for: fuelType.isEmpty ? "Gasolina comum" : fuelType) ?? vehicle.lastFuel?.pricePerLiter {
            priceText = price.decimalInput
        }
        if vehicle.tankCapacity > 0 {
            tankText = String(Int(vehicle.tankCapacity))
        }
    }

    private func saveTank() {
        let value = tank ?? 0
        if value != vehicle.tankCapacity {
            vehicle.tankCapacity = value
            try? context.save()
        }
    }

    private func calculate() async {
        guard let origin, let destination else {
            route = nil
            routeTolls = []
            return
        }
        calculating = true
        errorMessage = nil
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: origin.coordinate))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination.coordinate))
        request.transportType = .automobile
        do {
            let response = try await MKDirections(request: request).calculate()
            if let first = response.routes.first {
                route = first
                routeTolls = Self.tolls(on: first, from: places.tolls)
                let rect = first.polyline.boundingMapRect
                camera = .rect(rect.insetBy(dx: -rect.size.width * 0.12, dy: -rect.size.height * 0.12))
            } else {
                route = nil
                errorMessage = "Não encontrei uma rota de carro entre essas cidades."
            }
        } catch {
            if !Task.isCancelled {
                route = nil
                errorMessage = "Não consegui calcular a rota. Verifique a internet e tente de novo."
            }
        }
        calculating = false
    }

    // MARK: Pedágios no caminho

    /// Praças perto da rota (até ~900 m; 3 km se a localização vier arredondada), na ordem do caminho, sem repetir a mesma praça nos dois sentidos.
    static func tolls(on route: MKRoute, from plazas: [TollPlaza]) -> [TollPlaza] {
        let polyline = route.polyline
        let count = polyline.pointCount
        guard count > 1, !plazas.isEmpty else { return [] }
        let points = polyline.points()
        let margin = MKMapPointsPerMeterAtLatitude(polyline.coordinate.latitude) * 4000
        let box = polyline.boundingMapRect.insetBy(dx: -margin, dy: -margin)

        var found: [(plaza: TollPlaza, index: Int)] = []
        for plaza in plazas {
            let p = MKMapPoint(plaza.coordinate)
            guard box.contains(p) else { continue }
            var best = Double.greatestFiniteMagnitude
            var bestIndex = 0
            for i in 0..<(count - 1) {
                let d = segmentDistance(p, points[i], points[i + 1])
                if d < best {
                    best = d
                    bestIndex = i
                }
            }
            // Algumas praças vêm da ANTT com localização arredondada (2 casas decimais, até ~1 km de erro):
            // para essas, aceita uma distância maior até a rota.
            let limit: Double = plaza.hasRoundedLocation ? 3000 : 900
            if best * MKMetersPerMapPointAtLatitude(plaza.lat) <= limit {
                found.append((plaza, bestIndex))
            }
        }

        var kept: [TollPlaza] = []
        for item in found.sorted(by: { $0.index < $1.index }) {
            let here = CLLocation(latitude: item.plaza.lat, longitude: item.plaza.lon)
            if let i = kept.firstIndex(where: {
                $0.concessionaria == item.plaza.concessionaria
                    && CLLocation(latitude: $0.lat, longitude: $0.lon).distance(from: here) < 1500
            }) {
                if kept[i].valor == nil, item.plaza.valor != nil { kept[i] = item.plaza }
            } else {
                kept.append(item.plaza)
            }
        }
        return kept
    }

    private static func segmentDistance(_ p: MKMapPoint, _ a: MKMapPoint, _ b: MKMapPoint) -> Double {
        let dx = b.x - a.x, dy = b.y - a.y
        let length2 = dx * dx + dy * dy
        var t = length2 > 0 ? ((p.x - a.x) * dx + (p.y - a.y) * dy) / length2 : 0
        t = max(0, min(1, t))
        let x = a.x + t * dx - p.x, y = a.y + t * dy - p.y
        return (x * x + y * y).squareRoot()
    }
}

/// Valores de pedágio informados pela pessoa (guardados no aparelho).
enum TollOverrides {
    private static let key = "tollOverrides"

    static func load() -> [String: Double] {
        UserDefaults.standard.dictionary(forKey: key) as? [String: Double] ?? [:]
    }

    static func save(_ values: [String: Double]) {
        UserDefaults.standard.set(values, forKey: key)
    }
}

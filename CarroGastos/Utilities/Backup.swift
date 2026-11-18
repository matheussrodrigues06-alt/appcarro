import Foundation
import SwiftData

/// Backup completo em JSON (inclui fotos dos comprovantes).
struct BackupFile: Codable {
    var version = 1
    var exportedAt = Date()
    var vehicles: [VehicleDTO]
}

struct VehicleDTO: Codable {
    var uuid: UUID
    var name: String
    var brand: String
    var modelName: String
    var version: String
    var year: Int
    var plate: String
    var initialOdometer: Int
    var odometer: Int
    var odometerUpdatedAt: Date
    var batteryChangedAt: Date?
    var fipeValue: Double
    var ipvaRate: Double
    var createdAt: Date
    var expenses: [ExpenseDTO]
}

struct ExpenseDTO: Codable {
    var categoryRaw: String
    var title: String
    var place: String
    var amount: Double
    var date: Date
    var odometer: Int?
    var liters: Double?
    var fuelType: String
    var isFullTank: Bool
    var intervalKm: Int?
    var intervalMonths: Int?
    var referenceYear: Int?
    var notes: String
    var receiptData: Data?
}

enum BackupService {
    static func makeFile(vehicles: [Vehicle]) throws -> URL {
        let file = BackupFile(vehicles: vehicles.map { v in
            VehicleDTO(
                uuid: v.uuid, name: v.name, brand: v.brand, modelName: v.modelName, version: v.version,
                year: v.year, plate: v.plate, initialOdometer: v.initialOdometer, odometer: v.odometer,
                odometerUpdatedAt: v.odometerUpdatedAt, batteryChangedAt: v.batteryChangedAt,
                fipeValue: v.fipeValue, ipvaRate: v.ipvaRate, createdAt: v.createdAt,
                expenses: v.expenses.map { e in
                    ExpenseDTO(
                        categoryRaw: e.categoryRaw, title: e.title, place: e.place, amount: e.amount,
                        date: e.date, odometer: e.odometer, liters: e.liters, fuelType: e.fuelType,
                        isFullTank: e.isFullTank, intervalKm: e.intervalKm, intervalMonths: e.intervalMonths,
                        referenceYear: e.referenceYear, notes: e.notes, receiptData: e.receiptData
                    )
                }
            )
        })
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(file)
        let stamp = Date().formatted(.iso8601.year().month().day())
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("backup-gastos-carro-\(stamp).json")
        try data.write(to: url, options: .atomic)
        return url
    }

    /// Importa carros do backup. Carros que já existem (mesmo identificador) são ignorados.
    /// Retorna quantos carros e registros foram importados.
    @MainActor
    static func restore(from url: URL, into context: ModelContext, existing: [Vehicle]) throws -> (vehicles: Int, expenses: Int) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let file = try decoder.decode(BackupFile.self, from: Data(contentsOf: url))

        let existingIDs = Set(existing.map(\.uuid))
        var vehicleCount = 0
        var expenseCount = 0

        for dto in file.vehicles where !existingIDs.contains(dto.uuid) {
            let vehicle = Vehicle(name: dto.name)
            vehicle.uuid = dto.uuid
            vehicle.brand = dto.brand
            vehicle.modelName = dto.modelName
            vehicle.version = dto.version
            vehicle.year = dto.year
            vehicle.plate = dto.plate
            vehicle.initialOdometer = dto.initialOdometer
            vehicle.odometer = dto.odometer
            vehicle.odometerUpdatedAt = dto.odometerUpdatedAt
            vehicle.batteryChangedAt = dto.batteryChangedAt
            vehicle.fipeValue = dto.fipeValue
            vehicle.ipvaRate = dto.ipvaRate
            vehicle.createdAt = dto.createdAt
            context.insert(vehicle)

            for e in dto.expenses {
                let expense = Expense(amount: e.amount, date: e.date)
                expense.categoryRaw = e.categoryRaw
                expense.title = e.title
                expense.place = e.place
                expense.odometer = e.odometer
                expense.liters = e.liters
                expense.fuelType = e.fuelType
                expense.isFullTank = e.isFullTank
                expense.intervalKm = e.intervalKm
                expense.intervalMonths = e.intervalMonths
                expense.referenceYear = e.referenceYear
                expense.notes = e.notes
                expense.receiptData = e.receiptData
                context.insert(expense)
                vehicle.expenses.append(expense)
                expenseCount += 1
            }
            vehicleCount += 1
        }
        try context.save()
        return (vehicleCount, expenseCount)
    }
}

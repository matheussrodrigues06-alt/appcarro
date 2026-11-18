import Foundation
import UserNotifications

/// Agenda notificações locais a partir dos dados dos carros.
enum ReminderScheduler {
    static let enabledKey = "notificationsEnabled"

    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }

    static func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    static func reschedule(vehicles: [Vehicle]) {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        guard isEnabled, !vehicles.isEmpty else { return }

        let calendar = Calendar.current
        let now = Date()
        var requests: [UNNotificationRequest] = []

        func atNine(_ date: Date) -> Date? {
            calendar.date(bySettingHour: 9, minute: 0, second: 0, of: date)
        }

        for vehicle in vehicles {
            // Serviços com vencimento por data
            for reminder in vehicle.serviceReminders {
                guard let due = reminder.dueDate else { continue }
                for (offset, text) in [(-7, "vence em 7 dias"), (0, "vence hoje")] {
                    guard let day = calendar.date(byAdding: .day, value: offset, to: due),
                          let fire = atNine(day), fire > now else { continue }
                    requests.append(request(
                        id: "service-\(vehicle.uuid.uuidString)-\(reminder.title)-\(offset)",
                        title: "\(vehicle.name): \(reminder.title)",
                        body: "O serviço \(text). Toque para ver os detalhes.",
                        date: fire
                    ))
                }
            }

            // IPVA do próximo ano (10 de janeiro)
            let nextYear = Vehicle.currentYear + 1
            if vehicle.payment(.ipva, year: nextYear) == nil,
               let jan = calendar.date(from: DateComponents(year: nextYear, month: 1, day: 10, hour: 9)), jan > now {
                requests.append(request(
                    id: "ipva-\(vehicle.uuid.uuidString)-\(nextYear)",
                    title: "IPVA \(nextYear) · \(vehicle.name)",
                    body: "Os boletos do IPVA costumam sair agora. Confira o calendário do seu estado.",
                    date: jan
                ))
            }

            // IPVA/licenciamento do ano atual ainda pendentes: lembrete em 15 dias
            if vehicle.paidObligations(year: Vehicle.currentYear) < 2,
               let day = calendar.date(byAdding: .day, value: 15, to: now), let fire = atNine(day) {
                requests.append(request(
                    id: "docs-\(vehicle.uuid.uuidString)",
                    title: "Documentação pendente · \(vehicle.name)",
                    body: "IPVA ou licenciamento de \(Vehicle.currentYear) ainda não foi marcado como pago.",
                    date: fire
                ))
            }

            // Bateria perto do fim da vida útil (33 meses)
            if let changed = vehicle.batteryChangedAt,
               let day = calendar.date(byAdding: .month, value: 33, to: changed),
               let fire = atNine(day), fire > now {
                requests.append(request(
                    id: "battery-\(vehicle.uuid.uuidString)",
                    title: "Bateria 12V · \(vehicle.name)",
                    body: "Sua bateria está perto do fim da vida útil média. Vale fazer um teste de carga.",
                    date: fire
                ))
            }
        }

        // Lembrete semanal para atualizar o km (domingo, 19h)
        let weekly = UNMutableNotificationContent()
        weekly.title = "Atualize o hodômetro"
        weekly.body = "Leva 5 segundos e mantém seus lembretes de serviço em dia."
        weekly.sound = .default
        requests.append(UNNotificationRequest(
            identifier: "weekly-odometer",
            content: weekly,
            trigger: UNCalendarNotificationTrigger(dateMatching: DateComponents(hour: 19, weekday: 1), repeats: true)
        ))

        // O iOS mantém no máximo 64 notificações pendentes
        for item in requests.prefix(60) {
            center.add(item)
        }
    }

    private static func request(id: String, title: String, body: String, date: Date) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return UNNotificationRequest(
            identifier: id,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        )
    }
}

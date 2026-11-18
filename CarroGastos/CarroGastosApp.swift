import SwiftUI
import SwiftData

@main
struct CarroGastosApp: App {
    var body: some Scene {
        WindowGroup {
            AppShell()
                .tint(Color.brand)
        }
        .modelContainer(for: [Vehicle.self, Expense.self, FipeEntry.self])
    }
}

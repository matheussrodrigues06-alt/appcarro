import SwiftUI
import SwiftData

@main
struct CarroGastosApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .tint(Color.brand)
        }
        .modelContainer(for: [Vehicle.self, Expense.self, FipeEntry.self])
    }
}

import SwiftUI
import SwiftData

@main
struct CarroGastosApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
                .tint(Color.lime)
        }
        .modelContainer(for: [Vehicle.self, Expense.self])
    }
}

import SwiftUI
import SwiftData

struct ServicesView: View {
    let vehicle: Vehicle
    @Binding var selectedID: String
    @Environment(\.modelContext) private var context
    @State private var showingNew = false
    @State private var editing: Expense?

    private var services: [Expense] {
        vehicle.expenses.filter { $0.category == .maintenance }.sorted { $0.date > $1.date }
    }

    var body: some View {
        NavigationStack {
            List {
                let reminders = vehicle.serviceReminders
                Section {
                    if reminders.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("Nenhum lembrete ativo", systemImage: "bell.slash")
                                .font(.rounded(16, .semibold))
                            Text("Ao registrar um serviço, informe \"a cada X km\" ou \"a cada X meses\" para acompanhar o próximo.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 6)
                    } else {
                        ForEach(reminders) { reminder in
                            Button { editing = reminder.expense } label: {
                                ReminderRow(reminder: reminder)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } header: {
                    Text("Próximas manutenções")
                } footer: {
                    if !reminders.isEmpty {
                        Text("A barra mostra quanto do intervalo já foi usado.")
                    }
                }

                Section {
                    Button { showingNew = true } label: {
                        Label("Registrar serviço", systemImage: "plus.circle.fill")
                            .font(.rounded(16, .semibold))
                    }
                }

                Section("Histórico") {
                    if services.isEmpty {
                        Text("Nenhum serviço registrado.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(services) { service in
                            Button { editing = service } label: {
                                ExpenseRow(expense: service)
                            }
                            .buttonStyle(.plain)
                        }
                        .onDelete(perform: delete)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Serviços")
            .appToolbar(vehicle: vehicle, selectedID: $selectedID)
            .sheet(isPresented: $showingNew) {
                ExpenseFormView(vehicle: vehicle, category: .maintenance)
            }
            .sheet(item: $editing) { expense in
                ExpenseFormView(vehicle: vehicle, expense: expense)
            }
        }
    }

    private func delete(at offsets: IndexSet) {
        let items = offsets.map { services[$0] }
        for item in items {
            vehicle.expenses.removeAll { $0 == item }
            context.delete(item)
        }
        try? context.save()
    }
}

struct ReminderRow: View {
    let reminder: ServiceReminder

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                IconTile(systemName: "wrench.and.screwdriver.fill", color: reminder.status.color, size: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text(reminder.title).font(.rounded(16, .semibold))
                    Text(reminder.summary).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                StatusBadge(status: reminder.status)
            }
            ProgressView(value: min(reminder.progress, 1))
                .tint(reminder.status.color)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

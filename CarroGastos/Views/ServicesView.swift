import SwiftUI

struct ServicesView: View {
    let vehicle: Vehicle
    @State private var showingNew = false
    @State private var editing: Expense?

    private var services: [Expense] {
        vehicle.expenses.filter { $0.category == .maintenance }.sorted { $0.date > $1.date }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ScreenTitle(text: "Central de serviços")
                    .padding(.bottom, 4)

                SectionLabel("Próximos serviços")
                let reminders = vehicle.serviceReminders
                if reminders.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Nada com alerta ainda")
                            .font(.system(size: 18, weight: .bold))
                        Text("Registre um serviço com intervalo para acompanhar o próximo vencimento.")
                            .font(.system(size: 15))
                            .foregroundStyle(Color.textSecondary)
                    }
                    .darkCard()
                } else {
                    ForEach(reminders) { reminder in
                        Button { editing = reminder.expense } label: {
                            ReminderCard(reminder: reminder)
                        }
                        .buttonStyle(PressableStyle())
                    }
                }

                Button("Registrar serviço") { showingNew = true }
                    .buttonStyle(LimeButtonStyle())
                    .padding(.vertical, 8)

                SectionLabel("Histórico")
                if services.isEmpty {
                    Text("Nenhum serviço registrado.")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.textSecondary)
                        .darkCard()
                } else {
                    ForEach(services) { service in
                        Button { editing = service } label: {
                            ServiceHistoryCard(expense: service)
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .sheet(isPresented: $showingNew) {
            ExpenseFormView(vehicle: vehicle, category: .maintenance)
        }
        .sheet(item: $editing) { expense in
            ExpenseFormView(vehicle: vehicle, expense: expense)
        }
    }
}

struct ReminderCard: View {
    let reminder: ServiceReminder

    var body: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 2)
                .fill(reminder.status.color)
                .frame(width: 4)
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(reminder.title)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Color.white)
                    Spacer()
                    Text(statusLabel)
                        .font(.system(size: 12, weight: .bold))
                        .tracking(1)
                        .foregroundStyle(reminder.status.color)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(reminder.status.color.opacity(0.14), in: Capsule())
                }
                Text(reminder.summary)
                    .font(.system(size: 15))
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .darkCard(padding: 18)
    }

    private var statusLabel: String {
        switch reminder.status {
        case .ok: "EM DIA"
        case .soon: "EM BREVE"
        case .overdue: "VENCIDO"
        }
    }
}

struct ServiceHistoryCard: View {
    let expense: Expense

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(expense.displayTitle)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Color.white)
                    if !expense.place.isEmpty && expense.place != expense.title {
                        Text("· \(expense.place)")
                            .font(.system(size: 16))
                            .foregroundStyle(Color.textSecondary)
                    }
                }
                .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 15))
                    .foregroundStyle(Color.textSecondary)
            }
            Spacer()
            Text(expense.amount.brl)
                .font(.money(17))
                .foregroundStyle(Color.white.opacity(0.85))
        }
        .darkCard(padding: 20)
    }

    private var subtitle: String {
        var parts = [expense.date.formatted(date: .numeric, time: .omitted)]
        if let km = expense.odometer { parts.append(km.km) }
        if expense.hasReceipt { parts.append("📎") }
        return parts.joined(separator: " · ")
    }
}

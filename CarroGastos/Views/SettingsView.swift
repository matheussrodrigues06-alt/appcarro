import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Vehicle.createdAt) private var vehicles: [Vehicle]
    let vehicle: Vehicle

    @AppStorage(ReminderScheduler.enabledKey) private var notificationsEnabled = false
    @State private var editingVehicle = false
    @State private var editingFipe = false
    @State private var editingBattery = false
    @State private var backupURL: URL?
    @State private var showingImporter = false
    @State private var alertMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Carro ativo · \(vehicle.name)") {
                    Button { editingVehicle = true } label: {
                        Label("Editar dados do carro", systemImage: "car.side")
                    }
                    Button { editingFipe = true } label: {
                        Label("Valor FIPE e alíquota do IPVA", systemImage: "dollarsign.circle")
                    }
                    Button { editingBattery = true } label: {
                        Label("Data da troca da bateria", systemImage: "minus.plus.batteryblock")
                    }
                }
                .foregroundStyle(Color.white)

                Section {
                    Toggle(isOn: $notificationsEnabled) {
                        Label("Lembretes", systemImage: "bell.badge")
                    }
                    .onChange(of: notificationsEnabled) { _, enabled in
                        Task { await updateNotifications(enabled) }
                    }
                } header: {
                    Text("Notificações")
                } footer: {
                    Text("Avisa sobre serviços vencendo, IPVA, documentação pendente, bateria e lembra de atualizar o km aos domingos.")
                }

                Section {
                    if let backupURL {
                        ShareLink(item: backupURL) {
                            Label("Salvar backup…", systemImage: "square.and.arrow.up.on.square")
                        }
                    } else {
                        Button { makeBackup() } label: {
                            Label("Gerar backup completo", systemImage: "externaldrive.badge.checkmark")
                        }
                    }
                    Button { showingImporter = true } label: {
                        Label("Restaurar backup", systemImage: "arrow.down.doc")
                    }
                    ShareLink(
                        item: CSVExport(fileName: "gastos-\(vehicle.plate.isEmpty ? "carro" : vehicle.plate.lowercased()).csv", content: vehicle.csv),
                        preview: SharePreview("Gastos – \(vehicle.name)")
                    ) {
                        Label("Exportar planilha (CSV)", systemImage: "tablecells")
                    }
                } header: {
                    Text("Backup")
                } footer: {
                    Text("Guarde o backup no app Arquivos ou no iCloud Drive. Ele inclui todos os carros, registros e fotos dos comprovantes.")
                }
                .foregroundStyle(Color.white)

                Section {
                    LabeledContent("Registros", value: "\(vehicle.expenses.count)")
                    LabeledContent("Total gasto", value: vehicle.totalSpent.brl)
                    LabeledContent("Versão", value: appVersion)
                } footer: {
                    Text("Seus dados ficam salvos somente neste iPhone.")
                }
            }
            .darkForm()
            .navigationTitle("Ajustes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { dismiss() }.fontWeight(.bold)
                }
            }
            .sheet(isPresented: $editingVehicle) { VehicleFormView(vehicle: vehicle) }
            .sheet(isPresented: $editingFipe) { FipeFormView(vehicle: vehicle) }
            .sheet(isPresented: $editingBattery) { BatteryFormView(vehicle: vehicle) }
            .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.json]) { result in
                restore(result)
            }
            .alert("Backup", isPresented: Binding(get: { alertMessage != nil }, set: { if !$0 { alertMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(alertMessage ?? "")
            }
        }
        .appSheetStyle()
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private func updateNotifications(_ enabled: Bool) async {
        if enabled {
            let granted = await ReminderScheduler.requestAuthorization()
            if !granted {
                notificationsEnabled = false
                alertMessage = "Permita as notificações em Ajustes do iPhone → Gastos do Carro → Notificações."
                return
            }
        }
        ReminderScheduler.reschedule(vehicles: vehicles)
    }

    private func makeBackup() {
        do {
            backupURL = try BackupService.makeFile(vehicles: vehicles)
        } catch {
            alertMessage = "Não foi possível gerar o backup: \(error.localizedDescription)"
        }
    }

    private func restore(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            do {
                let count = try BackupService.restore(from: url, into: context, existing: vehicles)
                Haptics.success()
                alertMessage = count.vehicles == 0
                    ? "Nenhum carro novo encontrado. Os carros do backup já estão no app."
                    : "Importados \(count.vehicles) carro(s) e \(count.expenses) registro(s)."
            } catch {
                alertMessage = "Arquivo de backup inválido."
            }
        case .failure(let error):
            alertMessage = error.localizedDescription
        }
    }
}

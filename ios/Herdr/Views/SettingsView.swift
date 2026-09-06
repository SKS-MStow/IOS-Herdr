import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var preferences = Preferences()
    @State private var notice: String?
    @State private var confirmDisconnect = false
    @State private var saving = false
    var body: some View {
        Form {
            Section("Controller") {
                Text(model.isDemo ? "Sample data" : model.connection?.serverURL ?? "Not paired").font(.footnote).textSelection(.enabled)
                LabeledContent("Connection", value: model.isDemo ? "Demo" : model.connected ? "Connected" : "Offline")
            }.listRowBackground(Theme.surface)
            Section {
                LabeledContent("iPhone permission", value: model.notificationPermission)
                LabeledContent("Push service", value: model.state?.notifications.configured == true ? "Configured" : "Needs APNs key")
                Button("Enable notifications") { Task { do { try await model.enableNotifications() } catch { notice = error.localizedDescription } } }.disabled(model.isDemo)
                if model.notificationPermission == "Off in iOS Settings", let url = URL(string: UIApplication.openSettingsURLString) { Link("Open iOS Settings", destination: url) }
                Button("Send a test notification") { Task { do { try await model.testNotification(); notice = "Apple accepted the test notification. Check this iPhone for the alert." } catch { notice = error.localizedDescription } } }.disabled(!model.connected || model.state?.notifications.configured != true)
                if let error = model.state?.notifications.lastError { Text(error).font(.footnote).foregroundStyle(Theme.attention) }
            } header: { Text("Notifications") } footer: { Text("Alerts are sent by the Mac. It must be awake and connected. Apple notification settings and Focus can affect when alerts appear.") }.listRowBackground(Theme.surface)
            Section {
                Toggle("Agent needs a response", isOn: $preferences.attention)
                Toggle("Agent finishes a task", isOn: $preferences.completion)
                Toggle("Machine connection changes", isOn: $preferences.connection)
                Toggle("Include agent and machine names", isOn: $preferences.previews)
                Button(saving ? "Saving…" : "Save notification preferences") {
                    Task { saving = true; defer { saving = false }; do { try await model.savePreferences(preferences); notice = "Notification preferences saved." } catch { notice = error.localizedDescription } }
                }.disabled(saving || !model.connected && !model.isDemo)
            } header: { Text("Send alerts for") } footer: { Text("Notification previews hide agent names by default. Terminal output is never included in push notifications.") }.listRowBackground(Theme.surface)
            Section {
                LabeledContent("Version", value: "\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"))")
                Text("Herdr for iPhone connects to your private Herdr controller. It does not move your project folders or provider accounts.").font(.footnote).foregroundStyle(Theme.secondary)
                Button(model.isDemo ? "Leave demo" : "Unpair this iPhone", role: .destructive) { confirmDisconnect = true }
            }.listRowBackground(Theme.surface)
        }.scrollContentBackground(.hidden).herdrScreen().navigationTitle("Settings").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task { preferences = model.preferences; await model.updateNotificationPermission() }
            .alert("Herdr", isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) { Button("OK", role: .cancel) {} } message: { Text(notice ?? "") }
            .confirmationDialog(model.isDemo ? "Leave sample mode?" : "Unpair this iPhone?", isPresented: $confirmDisconnect, titleVisibility: .visible) {
                Button(model.isDemo ? "Leave demo" : "Revoke this iPhone’s access", role: .destructive) { Task { do { try await model.disconnect(); dismiss() } catch { notice = error.localizedDescription } } }
            } message: { Text("Your agents continue running. You can pair again using a new code.") }
    }
}

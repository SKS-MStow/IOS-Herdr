import SwiftUI

struct NewAgentView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    var initialMachine: String?
    @State private var machineId = ""
    @State private var useExisting = false
    @State private var paneId = ""
    @State private var label = ""
    @State private var cwd = ""
    @State private var name = ""
    @State private var kind = "codex"
    @State private var busy = false
    @State private var progress = ""
    @State private var error: String?
    @State private var createdPane: String?
    @State private var confirmClear = false
    private var machine: Machine? { model.machines.first { $0.id == machineId } }
    private var availablePanes: [Pane] { machine?.panes.filter { pane in !model.agents.contains { $0.machineId == machineId && $0.paneId == pane.id } } ?? [] }
    private var valid: Bool { !name.isEmpty && machine != nil && (useExisting ? !paneId.isEmpty : !label.isEmpty && !cwd.isEmpty) && !busy && model.connected }
    private var scope: String { "create-\(machineId)" }
    var body: some View {
        Form {
            Section {
                Picker("Run on", selection: $machineId) {
                    Text("Choose a machine").tag("")
                    ForEach(model.machines.filter { $0.state == "online" }) { Text($0.name).tag($0.id) }
                }.disabled(busy || createdPane != nil)
            } footer: { Text("Select where the files and agent sign-in live. The app uses the agent already installed on that machine.") }.listRowBackground(Theme.surface)
            if let machine {
                Section("Workspace on \(machine.name)") {
                    if !availablePanes.isEmpty { Toggle("Use an open shell pane", isOn: $useExisting).disabled(createdPane != nil) }
                    if useExisting {
                        Picker("Pane", selection: $paneId) { Text("Choose a pane").tag(""); ForEach(availablePanes) { Text("\($0.id) · \($0.cwd)").tag($0.id) } }
                    } else {
                        TextField("Workspace label", text: $label)
                        TextField(machine.platform == "mac" ? "/Users/mark/Projects/MyProject" : "C:\\Projects\\MyProject", text: $cwd).textInputAutocapitalization(.never).autocorrectionDisabled()
                        Text("Use an existing absolute folder path on \(machine.name).").font(.caption).foregroundStyle(Theme.secondary)
                    }
                    if let createdPane { Label("Workspace created · \(createdPane)", systemImage: "checkmark.circle").foregroundStyle(Theme.mint) }
                }.disabled(busy || createdPane != nil).listRowBackground(Theme.surface)
                Section("Agent") {
                    TextField("Name, e.g. iphone-task", text: $name).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Picker("Provider", selection: $kind) { Text("Codex").tag("codex"); Text("Claude").tag("claude"); Text("Gemini").tag("gemini"); Text("Hermes").tag("hermes") }
                }.disabled(busy).listRowBackground(Theme.surface)
                Section {
                    if let error { Text(error).foregroundStyle(Theme.attention) }
                    if busy { HStack { ProgressView(); Text(progress).padding(.leading, 8) } }
                    Button { Task { await start() } } label: { Label(createdPane == nil ? "Start agent on \(machine.name)" : "Start agent in created workspace", systemImage: "play.fill") }.disabled(!valid)
                    if model.pending[scope] != nil || model.pending["start-\(machineId)"] != nil {
                        Button("I checked the machine; allow a new attempt") { confirmClear = true }.foregroundStyle(Theme.attention)
                    }
                } footer: { Text("If startup fails, the workspace stays available. Herdr does not repeat commands after uncertain delivery.") }.listRowBackground(Theme.surface)
            }
        }.scrollContentBackground(.hidden).herdrScreen().navigationTitle("Start an agent").navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(busy)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(busy) } }
            .onAppear { machineId = initialMachine ?? model.machines.first(where: { $0.state == "online" })?.id ?? "" }
            .onChange(of: machineId) { _, _ in paneId = ""; useExisting = false; createdPane = nil; cwd = ""; kind = machine?.platform == "mac" ? "codex" : "claude" }
            .confirmationDialog("You inspected the execution machine?", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("Allow a new attempt") { model.clearPending(scope); model.clearPending("start-\(machineId)"); error = nil }
            } message: { Text("A previous workspace or agent may already exist. Check Machines before proceeding.") }
    }
    private func start() async {
        busy = true; error = nil; defer { busy = false }
        do {
            var target = useExisting ? paneId : createdPane
            if target == nil {
                progress = "Creating workspace…"
                let result = try await model.perform(path: "/api/workspaces", scope: scope, body: ["machineId": machineId, "label": label, "cwd": cwd])
                guard result.state == "accepted", let pane = result.result?.paneId else { error = result.message; return }
                target = pane; createdPane = pane
            }
            guard let target else { return }
            progress = "Waiting for \(kind.capitalized) to be ready…"
            let result = try await model.perform(path: "/api/agents/start", scope: "start-\(machineId)", body: ["machineId": machineId, "paneId": target, "name": name, "kind": kind])
            guard result.state == "accepted" else { error = result.message; return }
            await model.refresh(); dismiss()
            if let id = result.result?.agentId { model.openAgent(id) }
        } catch { self.error = error.localizedDescription }
    }
}

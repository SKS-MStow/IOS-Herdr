import SwiftUI

struct WorkspaceAgentDraft: Codable {
    let machineId: String; let useExisting: Bool; let paneId: String; let label: String
    let cwd: String; let name: String; let kind: String; let createdPane: String?; let startedAgentId: String?
}

struct NewAgentView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    var initialMachine: String?
    var sharedWorkspaceId: String?
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
    @State private var startedAgentId: String?
    @State private var confirmClear = false
    private var machine: Machine? { model.machines.first { $0.id == machineId } }
    private var availablePanes: [Pane] { machine?.panes.filter { pane in !model.agents.contains { $0.machineId == machineId && $0.paneId == pane.id } } ?? [] }
    private var executionLocked: Bool { busy || createdPane != nil || startedAgentId != nil || model.pending[scope] != nil || model.pending[startScope] != nil }
    private var agentOptionsLocked: Bool { busy || startedAgentId != nil || model.pending[startScope] != nil }
    private var valid: Bool { (startedAgentId != nil || (name.range(of: "^[a-z][a-z0-9_-]{0,31}$", options: .regularExpression) != nil && machine != nil && (useExisting ? !paneId.isEmpty : !label.isEmpty && !cwd.isEmpty))) && !busy && model.connected }
    private var scope: String { sharedWorkspaceId.map { "shared-create-\($0)-\(machineId)" } ?? "create-\(machineId)" }
    private var startScope: String { sharedWorkspaceId.map { "shared-start-\($0)-\(machineId)" } ?? "start-\(machineId)" }
    init(initialMachine: String? = nil, sharedWorkspaceId: String? = nil) {
        self.initialMachine = initialMachine; self.sharedWorkspaceId = sharedWorkspaceId
        if let id = sharedWorkspaceId, let data = UserDefaults.standard.data(forKey: "workspaceAgentDraft-\(id)"), let draft = try? JSONDecoder().decode(WorkspaceAgentDraft.self, from: data) {
            _machineId = State(initialValue: draft.machineId); _useExisting = State(initialValue: draft.useExisting)
            _paneId = State(initialValue: draft.paneId); _label = State(initialValue: draft.label); _cwd = State(initialValue: draft.cwd)
            _name = State(initialValue: draft.name); _kind = State(initialValue: draft.kind); _createdPane = State(initialValue: draft.createdPane)
            _startedAgentId = State(initialValue: draft.startedAgentId)
        }
    }
    var body: some View {
        Form {
            if let sharedWorkspaceId, let workspace = model.sharedWorkspace(sharedWorkspaceId) {
                Section { LabeledContent("Add to workspace", value: workspace.label) }.listRowBackground(Theme.surface)
            }
            Section {
                Picker("Run on", selection: $machineId) {
                    Text("Choose a machine").tag("")
                    ForEach(model.machines.filter { $0.state == "online" }) { Text($0.name).tag($0.id) }
                }.disabled(executionLocked)
            } footer: { Text("Select where the files and agent sign-in live. The app uses the agent already installed on that machine.") }.listRowBackground(Theme.surface)
            if let machine {
                Section("Workspace on \(machine.name)") {
                    if !availablePanes.isEmpty { Toggle("Use an open shell pane", isOn: $useExisting).disabled(executionLocked) }
                    if useExisting {
                        Picker("Pane", selection: $paneId) { Text("Choose a pane").tag(""); ForEach(availablePanes) { Text("\($0.id) · \($0.cwd)").tag($0.id) } }
                    } else {
                        TextField("Workspace label", text: $label)
                        TextField(machine.platform == "mac" ? "/Users/mark/Projects/MyProject" : "C:\\Projects\\MyProject", text: $cwd).textInputAutocapitalization(.never).autocorrectionDisabled()
                        Text("Use an existing absolute folder path on \(machine.name).").font(.caption).foregroundStyle(Theme.secondary)
                    }
                    if let createdPane { Label("Workspace created · \(createdPane)", systemImage: "checkmark.circle").foregroundStyle(Theme.mint) }
                }.disabled(executionLocked).listRowBackground(Theme.surface)
                Section("Agent") {
                    TextField("Name, e.g. iphone-task", text: $name).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Picker("Provider", selection: $kind) { Text("Codex").tag("codex"); Text("Claude").tag("claude"); Text("Gemini").tag("gemini"); Text("Hermes").tag("hermes") }
                }.disabled(agentOptionsLocked).listRowBackground(Theme.surface)
                Section {
                    if let error { Text(error).foregroundStyle(Theme.attention) }
                    if busy { HStack { ProgressView(); Text(progress).padding(.leading, 8) } }
                    Button { Task { await start() } } label: { Label(startedAgentId != nil ? "Finish adding to workspace" : createdPane == nil ? "Start agent on \(machine.name)" : "Start agent in created workspace", systemImage: "play.fill") }.disabled(!valid)
                    if let startedAgentId { Text("Agent started: \(startedAgentId). This step only adds it to the workspace.").font(.caption).foregroundStyle(Theme.secondary) }
                    if model.pending[scope] != nil || model.pending[startScope] != nil {
                        Button("I checked the machine; allow a new attempt") { confirmClear = true }.foregroundStyle(Theme.attention)
                    }
                } footer: { Text("If startup fails, the workspace stays available. Herdr does not repeat commands after uncertain delivery.") }.listRowBackground(Theme.surface)
            }
        }.scrollContentBackground(.hidden).herdrScreen().navigationTitle("Start an agent").navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(busy)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(busy) } }
            .onAppear { if machineId.isEmpty { machineId = initialMachine ?? model.machines.first(where: { $0.state == "online" })?.id ?? "" } }
            .onChange(of: machineId) { _, _ in guard !executionLocked else { return }; paneId = ""; useExisting = false; createdPane = nil; cwd = ""; kind = machine?.platform == "mac" ? "codex" : "claude" }
            .confirmationDialog("You inspected the execution machine?", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("Allow a new attempt") { model.clearPending(scope); model.clearPending(startScope); error = nil }
            } message: { Text("A previous workspace or agent may already exist. Check Machines before proceeding.") }
    }
    private func start() async {
        busy = true; error = nil; defer { busy = false }
        do {
            saveDraft()
            if startedAgentId == nil {
            var target = useExisting ? paneId : createdPane
            if target == nil {
                progress = "Creating workspace…"
                let result = try await model.perform(path: "/api/workspaces", scope: scope, body: ["machineId": machineId, "label": label, "cwd": cwd], retainAccepted: sharedWorkspaceId != nil)
                guard result.state == "accepted", let pane = result.result?.paneId else { error = result.message; return }
                target = pane; createdPane = pane
                saveDraft(); model.clearPending(scope)
            }
            guard let target else { return }
            progress = "Waiting for \(kind.capitalized) to be ready…"
            if startedAgentId == nil {
                let result = try await model.perform(path: "/api/agents/start", scope: startScope, body: ["machineId": machineId, "paneId": target, "name": name, "kind": kind], retainAccepted: sharedWorkspaceId != nil)
                guard result.state == "accepted", let agentId = result.result?.agentId else { error = result.message; return }
                startedAgentId = agentId; saveDraft(); model.clearPending(startScope)
            }
            }
            if let sharedWorkspaceId, let agentId = startedAgentId {
                progress = "Adding agent to workspace…"
                if model.pendingSharedChange != nil { try await model.resumeSharedWorkspaceChange() }
                await model.refresh()
                guard let agent = model.agents.first(where: { $0.id == agentId }) else { error = "The agent started. Reconnect its machine to finish adding it; it will not be started again."; return }
                if model.sharedWorkspace(sharedWorkspaceId)?.members.contains(where: { $0.matches(agent) }) != true {
                    try await model.changeSharedWorkspace("add", id: sharedWorkspaceId, member: SharedMember(agent: agent))
                }
                UserDefaults.standard.removeObject(forKey: "workspaceAgentDraft-\(sharedWorkspaceId)")
            }
            await model.refresh(); dismiss()
            if let id = startedAgentId { model.openAgent(id) }
        } catch { self.error = error.localizedDescription }
    }
    private func saveDraft() {
        guard let id = sharedWorkspaceId else { return }
        let draft = WorkspaceAgentDraft(machineId: machineId, useExisting: useExisting, paneId: paneId, label: label, cwd: cwd, name: name, kind: kind, createdPane: createdPane, startedAgentId: startedAgentId)
        UserDefaults.standard.set(try? JSONEncoder().encode(draft), forKey: "workspaceAgentDraft-\(id)")
    }
}

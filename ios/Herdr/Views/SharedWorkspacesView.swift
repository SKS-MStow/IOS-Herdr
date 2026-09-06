import SwiftUI

struct SharedWorkspacesView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showCreate = false
    @State private var showSettings = false
    @State private var name = ""
    @State private var error: String?
    var body: some View {
        List {
            Section {
                NavigationLink(value: AppRoute.allAgents) { browseLabel("All agents", icon: "terminal") }
                NavigationLink(value: AppRoute.unassigned) { browseLabel("Unassigned", icon: "tray") }
            }.listRowBackground(Theme.background)
            Section {
                ForEach(model.sharedWorkspaces) { workspace in
                    NavigationLink(value: AppRoute.workspace(workspace.id)) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(workspace.label).font(.headline)
                            Text(summary(workspace)).font(.footnote).foregroundStyle(Theme.secondary)
                        }.padding(.vertical, 4)
                    }.accessibilityIdentifier("workspace-\(workspace.id)")
                }
                if model.sharedWorkspaces.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Bring your agents together").font(.headline)
                        Text("Create a workspace, then add agents from any of your machines.").font(.subheadline).foregroundStyle(Theme.secondary)
                        Button("Create workspace", systemImage: "plus") { name = ""; showCreate = true }.disabled(!model.canEditSharedWorkspaces)
                    }.padding(.vertical, 8)
                }
            } header: { Text("Your workspaces") }
              footer: { Text("Agents keep running on their own machines. A workspace brings them into one list.") }
              .listRowBackground(Theme.background)
            WorkspaceConnectionSection(error: error)
        }.listStyle(.plain).scrollContentBackground(.hidden).herdrScreen()
            .navigationTitle(model.isDemo ? "Demo · Workspaces" : "Workspaces").navigationBarTitleDisplayMode(.inline)
            .refreshable { await model.refresh() }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack {
                        Button { name = ""; showCreate = true } label: { Image(systemName: "plus") }.accessibilityLabel("Create workspace").disabled(!model.canEditSharedWorkspaces)
                        Button { showSettings = true } label: { Image(systemName: "gearshape") }.accessibilityLabel("Settings")
                    }
                }
            }
            .alert("New workspace", isPresented: $showCreate) {
                TextField("Workspace name", text: $name)
                Button("Cancel", role: .cancel) { }
                Button("Create") { Task { await create() } }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } message: { Text("Choose a name for this group of agents.") }
            .sheet(isPresented: $showSettings) { NavigationStack { SettingsView() } }
    }
    @ViewBuilder private func browseLabel(_ title: String, icon: String) -> some View {
        if dynamicTypeSize.isAccessibilitySize { Text(title).fixedSize(horizontal: false, vertical: true) }
        else { Label(title, systemImage: icon) }
    }
    private func summary(_ workspace: SharedWorkspace) -> String {
        let members = workspace.members.count
        let machines = Set(workspace.members.map(\.machineId)).count
        return members == 0 ? "No agents yet" : "\(members) \(members == 1 ? "agent" : "agents") · \(machines) \(machines == 1 ? "machine" : "machines")"
    }
    private func create() async {
        do {
            if let id = try await model.changeSharedWorkspace("create", label: name.trimmingCharacters(in: .whitespacesAndNewlines)) { model.agentPath.append(.workspace(id)) }
            error = nil
        } catch { self.error = error.localizedDescription }
    }
}

struct WorkspaceConnectionSection: View {
    @EnvironmentObject private var model: AppModel
    var error: String?
    @State private var recoveryError: String?
    var body: some View {
        Section {
            if let error = error ?? recoveryError ?? model.error { Notice(text: error) }
            if model.sharedCatalog?.available != true || model.sharedCatalog?.stale == true {
                Text(model.sharedCatalog?.error ?? "Waiting for shared workspaces on the Mac. All agents remain available above.").font(.footnote).foregroundStyle(Theme.secondary)
            }
            if model.pendingSharedChange != nil && !model.isDemo {
                Button("Check pending workspace change") { Task { do { try await model.resumeSharedWorkspaceChange(); recoveryError = nil } catch { recoveryError = error.localizedDescription } } }
                    .disabled(!model.connected || model.sharedBusy)
            }
            if model.sharedBusy { ProgressView("Saving workspace…") }
        }.listRowBackground(Theme.background)
    }
}

struct SharedWorkspaceDetailView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let workspaceId: String
    @State private var showAdd = false
    @State private var showStart = false
    @State private var showRename = false
    @State private var showDelete = false
    @State private var name = ""
    @State private var error: String?
    private var workspace: SharedWorkspace? { model.sharedWorkspace(workspaceId) }
    var body: some View {
        List {
            if let workspace {
                if workspace.members.isEmpty {
                    ContentUnavailableView {
                        Label("No agents yet", systemImage: "terminal")
                    } description: { Text("Add existing agents from your Mac or Home PC, or start one for this workspace.") }
                    actions: { Button("Add existing agents") { showAdd = true }.disabled(!model.canEditSharedWorkspaces) }
                    .listRowSeparator(.hidden).listRowBackground(Theme.background)
                }
                ForEach(workspace.members) { member in
                    if let agent = model.agents.first(where: { member.matches($0) }) {
                        NavigationLink(value: AppRoute.agent(agent.id)) { AgentRow(agent: agent) }
                            .accessibilityIdentifier("workspace-agent-\(agent.id)")
                            .swipeActions { Button("Remove", role: .destructive) { Task { await remove(member) } }.disabled(!model.canEditSharedWorkspaces) }
                            .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                            .listRowBackground(Theme.background)
                    } else {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(unavailableLabel(member)).font(.headline)
                            Text("\(model.machines.first { $0.id == member.machineId }?.name ?? "Unavailable machine") · Saved agent").font(.footnote).foregroundStyle(Theme.secondary)
                        }.padding(.vertical, 8)
                            .swipeActions { Button("Remove", role: .destructive) { Task { await remove(member) } }.disabled(!model.canEditSharedWorkspaces) }
                            .listRowBackground(Theme.background)
                    }
                }
                Section {
                    Button("Add existing agents", systemImage: "plus") { showAdd = true }.disabled(!model.canEditSharedWorkspaces)
                    Button("Start a new agent", systemImage: "play") { showStart = true }.disabled(!model.connected || !model.canEditSharedWorkspaces)
                }.listRowBackground(Theme.background)
                WorkspaceConnectionSection(error: error)
            } else {
                ContentUnavailableView("Workspace removed", systemImage: "folder", description: Text("Its agents are still available in All agents."))
                    .listRowBackground(Theme.background)
            }
        }.listStyle(.plain).scrollContentBackground(.hidden).herdrScreen()
            .navigationTitle(model.isDemo ? "Demo · \(workspace?.label ?? "Workspace")" : workspace?.label ?? "Workspace").navigationBarTitleDisplayMode(.inline)
            .refreshable { await model.refresh() }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Rename", systemImage: "pencil") { name = workspace?.label ?? ""; showRename = true }
                        Button("Delete workspace", systemImage: "trash", role: .destructive) { showDelete = true }
                    } label: { Image(systemName: "ellipsis") }.accessibilityLabel("Workspace options").disabled(!model.canEditSharedWorkspaces || workspace == nil)
                }
            }
            .sheet(isPresented: $showAdd) { NavigationStack { AddWorkspaceAgentsView(workspaceId: workspaceId) } }
            .sheet(isPresented: $showStart) { NavigationStack { NewAgentView(sharedWorkspaceId: workspaceId) } }
            .alert("Rename workspace", isPresented: $showRename) {
                TextField("Workspace name", text: $name)
                Button("Cancel", role: .cancel) { }
                Button("Save") { Task { do { try await model.changeSharedWorkspace("rename", id: workspaceId, label: name.trimmingCharacters(in: .whitespacesAndNewlines)) } catch { self.error = error.localizedDescription } } }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .confirmationDialog("Delete this workspace?", isPresented: $showDelete, titleVisibility: .visible) {
                Button("Delete workspace", role: .destructive) { Task { do { try await model.changeSharedWorkspace("delete", id: workspaceId); dismiss() } catch { self.error = error.localizedDescription } } }
            } message: { Text("This removes the group. Its agents keep running on their machines.") }
    }
    private func unavailableLabel(_ member: SharedMember) -> String { model.machines.first { $0.id == member.machineId }?.isOnline == true ? "Session ended" : "Machine unavailable" }
    private func remove(_ member: SharedMember) async { do { try await model.changeSharedWorkspace("remove", id: workspaceId, member: member); error = nil } catch { self.error = error.localizedDescription } }
}

struct AddWorkspaceAgentsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let workspaceId: String
    @State private var query = ""
    @State private var error: String?
    private var agents: [Agent] { model.agents.filter { query.isEmpty || "\($0.name) \($0.machineName)".localizedCaseInsensitiveContains(query) } }
    var body: some View {
        List {
            Section {
                ForEach(agents) { agent in
                    let included = model.sharedWorkspace(workspaceId)?.members.contains(where: { $0.matches(agent) }) == true
                    Button { Task { do { try await model.changeSharedWorkspace(included ? "remove" : "add", id: workspaceId, member: SharedMember(agent: agent)); error = nil } catch { self.error = error.localizedDescription } } } label: {
                        HStack(spacing: 12) {
                            AgentRow(agent: agent)
                            Image(systemName: included ? "checkmark.circle.fill" : "plus.circle").foregroundStyle(Theme.mint)
                        }
                    }.disabled(!model.canEditSharedWorkspaces)
                        .accessibilityLabel("\(included ? "Remove" : "Add") \(agent.name), \(agent.machineName)")
                        .accessibilityIdentifier("membership-\(agent.id)")
                        .listRowBackground(Theme.background)
                }
            } footer: { Text("An agent can belong to more than one workspace. Adding or removing it here does not restart it.") }
            WorkspaceConnectionSection(error: error)
        }.listStyle(.plain).scrollContentBackground(.hidden).herdrScreen()
            .navigationTitle(model.isDemo ? "Demo · Add agents" : "Add agents").navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Agent or machine")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
    }
}

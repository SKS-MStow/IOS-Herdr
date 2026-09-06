import SwiftUI

struct MainView: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        TabView(selection: $model.selectedTab) {
            NavigationStack(path: $model.agentPath) {
                SharedWorkspacesView().navigationDestination(for: AppRoute.self) { route in
                    switch route {
                    case .workspace(let id): SharedWorkspaceDetailView(workspaceId: id)
                    case .agent(let id): SessionView(agentId: id)
                    case .allAgents: AgentsView()
                    case .unassigned: AgentsView(unassignedOnly: true)
                    }
                }
            }.tabItem { Label("Workspaces", systemImage: "folder") }.tag(0)
            NavigationStack { InboxView() }.tabItem { Label("Inbox", systemImage: "bubble.left.and.bubble.right") }.badge(model.unreadCount).tag(1)
            NavigationStack { MachinesView() }.tabItem { Label("Machines", systemImage: "desktopcomputer") }.tag(2)
        }.tint(Theme.mint)
    }
}

struct AgentsView: View {
    var unassignedOnly = false
    @EnvironmentObject private var model: AppModel
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var filter = "all"
    @State private var showSettings = false
    @State private var showNewAgent = false
    private var filtered: [Agent] {
        model.agents.filter { agent in (filter == "all" || agent.machineId == filter) && (!unassignedOnly || !model.isAssigned(agent)) }.sorted {
            let leftNeedsYou = $0.needsAttention && !$0.stale
            let rightNeedsYou = $1.needsAttention && !$1.stale
            if leftNeedsYou != rightNeedsYou { return leftNeedsYou }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }
    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                HStack(spacing: 7) {
                    if !typeSize.isAccessibilitySize {
                        Image(systemName: model.isDemo ? "sparkles" : model.connected ? "circle.fill" : "wifi.slash")
                            .imageScale(.small).foregroundStyle(model.connected || model.isDemo ? Theme.mint : Theme.attention)
                    }
                    Text(model.isDemo ? "Sample activity" : model.connected ? "Mac controller connected" : "Connecting to Mac…")
                    Spacer()
                    if model.state != nil && !typeSize.isAccessibilitySize { Text("\(filtered.count) \(filtered.count == 1 ? "agent" : "agents")").monospacedDigit() }
                }.font(.caption).foregroundStyle(Theme.secondary).accessibilityElement(children: .combine)
                if let error = model.error { Notice(text: error) }
                Picker("Machine", selection: $filter) {
                    Text("All").tag("all")
                    ForEach(model.machines.filter { $0.state != "pending" }) { Text($0.name).tag($0.id) }
                }.pickerStyle(.segmented)
            }.padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 12)
            List {
                if filtered.isEmpty {
                    ContentUnavailableView {
                        Label(model.connected || model.isDemo ? "No running agents" : "Waiting for your Mac", systemImage: "terminal")
                    } description: {
                        Text(model.connected || model.isDemo ? "Start an agent on a connected machine. Its sign-in and files stay there." : "Connect to Tailscale and keep your Mac awake. Your sessions continue on their machines.")
                    } actions: {
                        if model.connected { Button("Start an agent") { showNewAgent = true }.buttonStyle(.borderedProminent) }
                    }.listRowSeparator(.hidden).listRowBackground(Theme.background)
                } else {
                    ForEach(filtered) { agent in
                        NavigationLink(value: AppRoute.agent(agent.id)) { AgentRow(agent: agent) }
                            .accessibilityIdentifier("agent-\(agent.id)")
                            .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                            .listRowBackground(Theme.background)
                    }
                }
            }.listStyle(.plain).scrollContentBackground(.hidden).refreshable { await model.refresh() }
        }.herdrScreen().navigationTitle(unassignedOnly ? "Unassigned" : "Agents").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Text("herdr").font(.headline).foregroundStyle(Theme.mint).fixedSize() }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack {
                        if model.isDemo { Text("DEMO").font(.caption).foregroundStyle(Theme.secondary) }
                        Button { showNewAgent = true } label: { Image(systemName: "plus") }.disabled(!model.connected && !model.isDemo).accessibilityLabel("Start an agent")
                        Button { showSettings = true } label: { Image(systemName: "gearshape") }.accessibilityLabel("Settings")
                    }
                }
            }
            .sheet(isPresented: $showSettings) { NavigationStack { SettingsView() } }
            .sheet(isPresented: $showNewAgent) { NavigationStack { NewAgentView() } }
    }
}

struct AgentRow: View {
    let agent: Agent
    @Environment(\.dynamicTypeSize) private var typeSize
    private var rowStatus: String { !agent.stale && agent.status == "idle" ? "Ready" : agent.statusLabel }
    private var status: some View {
        HStack(spacing: 4) {
            if !typeSize.isAccessibilitySize {
                Image(systemName: agent.stale ? "clock" : agent.needsAttention ? "exclamationmark.circle" : "circle.fill")
                    .font(.caption2).imageScale(.small).accessibilityHidden(true)
            }
            Text(rowStatus).font(.caption.weight(.medium))
        }.foregroundStyle(Theme.status(agent)).fixedSize(horizontal: !typeSize.isAccessibilitySize, vertical: true)
    }
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if !typeSize.isAccessibilitySize {
                Image(systemName: "terminal").font(.subheadline).foregroundStyle(Theme.secondary)
                    .frame(width: 20).padding(.top, 2).accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 5) {
                if typeSize.isAccessibilitySize {
                    Text(agent.name).font(.headline).foregroundStyle(.primary).fixedSize(horizontal: false, vertical: true)
                    status
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(agent.name).font(.headline).foregroundStyle(.primary).lineLimit(2)
                        Spacer(minLength: 4)
                        status
                    }
                }
                Text("\(agent.machineName) · \(agent.provider) · \(agent.folder)")
                    .font(.footnote).foregroundStyle(Theme.secondary)
                    .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
                    .truncationMode(.middle)
            }
        }.frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(agent.name), \(agent.statusLabel), \(agent.machineName), \(agent.provider), \(agent.folder)")
            .accessibilityHint("Opens the session")
    }
}

struct InboxView: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        Group {
            if model.events.isEmpty {
                ContentUnavailableView("All quiet", systemImage: "bell.badge", description: Text("Replies needed, finished tasks and connection changes will appear here."))
            } else {
                List(model.events) { event in
                    Button {
                        if let agentId = event.agentId { model.openAgent(agentId) } else { model.selectedTab = 2 }
                    } label: {
                        HStack(alignment: .top, spacing: 14) {
                            Image(systemName: event.kind == "attention" ? "bubble.left.and.exclamationmark.bubble.right" : event.kind == "completion" ? "checkmark.circle" : "network")
                                .font(.title2).foregroundStyle(event.kind == "attention" ? Theme.attention : Theme.mint).frame(width: 32)
                            VStack(alignment: .leading, spacing: 7) {
                                HStack { Text(event.title).font(.headline); Spacer(); if !event.read { Image(systemName: "circle.fill").font(.caption2).foregroundStyle(Theme.mint).accessibilityLabel("Unread") } }
                                Text(event.body).font(.subheadline).foregroundStyle(Theme.secondary)
                                Text(event.createdAt, style: .relative).font(.caption).foregroundStyle(Theme.secondary)
                            }
                        }.padding(.vertical, 10).foregroundStyle(.primary)
                    }.listRowBackground(Theme.background)
                }.listStyle(.plain).scrollContentBackground(.hidden)
            }
        }.herdrScreen().navigationTitle("Inbox").refreshable { await model.refresh() }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { if model.isDemo { Text("DEMO").font(.caption).foregroundStyle(Theme.secondary) } }
                ToolbarItem(placement: .topBarTrailing) { Button("Mark read") { Task { await model.markRead() } }.disabled(model.unreadCount == 0) }
            }
    }
}

struct MachinesView: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        List {
            Section {
                ForEach(model.machines) { machine in
                    NavigationLink { MachineDetailView(machineId: machine.id) } label: {
                        HStack(spacing: 16) {
                            Image(systemName: machine.symbol).font(.title2).foregroundStyle(machine.isOnline ? Theme.mint : Theme.secondary).frame(width: 40)
                            VStack(alignment: .leading, spacing: 7) {
                                Text(machine.name).font(.headline)
                                Text(machine.state == "pending" ? "Setup pending" : machine.isOnline && model.connected ? "Connected · \(model.agents.filter { $0.machineId == machine.id }.count) agents" : model.isDemo ? "Sample connection" : "Offline").font(.subheadline).foregroundStyle(Theme.secondary)
                            }
                        }.padding(.vertical, 12)
                    }.listRowBackground(Theme.surface)
                }
            } footer: { Text("Your Mac is the controller. Projects, sign-ins and agent processes belong to the machine where they run.") }
        }.scrollContentBackground(.hidden).herdrScreen().navigationTitle("Machines").refreshable { await model.refresh() }
    }
}

struct MachineDetailView: View {
    @EnvironmentObject private var model: AppModel
    let machineId: String
    @State private var showStart = false
    private var machine: Machine? { model.machines.first { $0.id == machineId } }
    var body: some View {
        List {
            if let machine {
                Section("Connection") {
                    LabeledContent("State", value: machine.state.capitalized)
                    if let lastSeen = machine.lastSeen { LabeledContent("Last seen") { Text(lastSeen, style: .relative) } }
                    if let error = machine.error { Text(error).foregroundStyle(Theme.attention) }
                }.listRowBackground(Theme.surface)
                Section("Workspaces") {
                    if machine.workspaces.isEmpty { Text(machine.state == "pending" ? "Worker setup is required first." : "No open workspaces.").foregroundStyle(Theme.secondary) }
                    ForEach(machine.workspaces) { workspace in
                        VStack(alignment: .leading, spacing: 6) { Text(workspace.label); Text("\(workspace.paneCount) panes").font(.caption).foregroundStyle(Theme.secondary) }
                    }
                }.listRowBackground(Theme.surface)
                Section("Agents") {
                    ForEach(model.agents.filter { $0.machineId == machineId }) { agent in
                        Button { model.openAgent(agent.id) } label: { VStack(alignment: .leading, spacing: 7) { Text(agent.name); StatusLabel(agent: agent) } }
                    }
                    if machine.state == "online" { Button("Start an agent here", systemImage: "plus") { showStart = true } }
                }.listRowBackground(Theme.surface)
            }
        }.scrollContentBackground(.hidden).herdrScreen().navigationTitle(machine?.name ?? "Machine").navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showStart) { NavigationStack { NewAgentView(initialMachine: machineId) } }
    }
}

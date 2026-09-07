import Foundation

struct Agent: Codable, Identifiable, Hashable {
    let id: String
    let machineId: String
    let machineName: String
    let terminalId: String
    var session: String? = nil
    let paneId: String
    let workspaceId: String
    let workspace: String
    let name: String
    let kind: String
    let status: String
    let cwd: String
    let sequence: Int
    let ready: Bool
    var stale: Bool
    let updatedAt: Date
    var provider: String { kind == "codex" ? "Codex" : kind == "claude" ? "Claude" : kind.capitalized }
    var statusLabel: String {
        if stale { return "Last known state" }
        switch status { case "working": return "Working"; case "blocked": return "Needs you"; case "done": return "Finished"; case "idle": return "Ready for input"; default: return "Status unknown" }
    }
    var needsAttention: Bool { status == "blocked" }
    var folder: String { cwd.replacingOccurrences(of: "\\", with: "/").split(separator: "/").last.map(String.init) ?? workspace }
}
struct Machine: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let platform: String
    var state: String
    let lastSeen: Date?
    let error: String?
    let workspaces: [Workspace]
    let panes: [Pane]
    var isOnline: Bool { state == "online" && (lastSeen.map { Date().timeIntervalSince($0) < 30 } ?? false) }
    var symbol: String { platform == "mac" ? "laptopcomputer" : "desktopcomputer" }
}
struct Workspace: Codable, Identifiable, Hashable { let id: String; let label: String; let paneCount: Int }
struct Pane: Codable, Identifiable, Hashable { let id: String; let terminalId: String?; let cwd: String; let workspaceId: String }
struct PushStatus: Codable { let configured: Bool; let lastError: String?; let topic: String }
struct SharedMember: Codable, Hashable, Identifiable {
    let machineId: String
    let session: String
    let terminalId: String
    var id: String { "\(machineId)/\(session)/\(terminalId)" }
    func matches(_ agent: Agent) -> Bool { machineId == agent.machineId && terminalId == agent.terminalId && session == (agent.session ?? "shared") }
    init(agent: Agent) { machineId = agent.machineId; session = agent.session ?? "shared"; terminalId = agent.terminalId }
    init(machineId: String, session: String, terminalId: String) { self.machineId = machineId; self.session = session; self.terminalId = terminalId }
}
struct SharedWorkspace: Codable, Identifiable, Hashable { let id: String; var label: String; var members: [SharedMember] }
struct SharedWorkspaceCatalog: Codable {
    var available: Bool
    var stale: Bool
    var revision: Int
    var workspaces: [SharedWorkspace]
    var error: String? = nil
}
enum AppRoute: Hashable { case workspace(String), agent(String), allAgents, unassigned }
struct SharedChange: Codable {
    let requestId: String
    let expectedRevision: Int
    let action: String
    let id: String?
    let label: String?
    let member: SharedMember?
}
struct ControllerState: Codable { let generatedAt: Date; var machines: [Machine]; var agents: [Agent]; let notifications: PushStatus; var sharedWorkspaceCatalog: SharedWorkspaceCatalog? = nil }
struct InboxEvent: Codable, Identifiable, Hashable {
    let id: Int; let kind: String; let agentId: String?; let machineId: String; let title: String; let body: String; let createdAt: Date; var read: Bool
}
struct InboxResponse: Codable { let events: [InboxEvent] }
struct Preferences: Codable, Equatable { var attention = true; var completion = true; var connection = true; var previews = false }
struct DeviceSettings: Codable { let preferences: Preferences; let push: PushStatus; let pushRegistered: Bool; let deviceId: String }
struct SessionOutput: Codable { let agentId: String; let text: String; let readAt: Date; let source: String; let sequence: Int; var runs: [TerminalRun]? = nil }
struct PairResponse: Codable { let deviceId: String; let token: String }
struct Connection: Codable { let serverURL: String; let deviceId: String; let token: String }
struct Operation: Codable {
    let id: String; let state: String; let result: OperationResult?
    var message: String { result?.message ?? (state == "sending" ? "The controller is still processing this action." : "Delivery is uncertain. Read the session before sending again.") }
}
struct OperationResult: Codable { let message: String?; let code: String?; let agentId: String?; let machineId: String?; let paneId: String?; let workspaceId: String?; var sharedWorkspaceId: String? = nil }
struct EmptyResponse: Codable {}
struct APIError: LocalizedError {
    let message: String; let code: String
    var errorDescription: String? { message }
}
struct ErrorEnvelope: Codable { let error: Details; struct Details: Codable { let code: String; let message: String } }

enum SampleData {
    static let mac = Machine(id: "mac", name: "Mac", platform: "mac", state: "online", lastSeen: Date(), error: nil, workspaces: [Workspace(id: "w1", label: "Scratch", paneCount: 1)], panes: [])
    static let home = Machine(id: "home", name: "Home PC", platform: "windows", state: "online", lastSeen: Date(), error: nil, workspaces: [Workspace(id: "w1", label: "Scratch", paneCount: 1)], panes: [])
    static let pending = Machine(id: "work-laptop", name: "Work laptop", platform: "windows", state: "pending", lastSeen: nil, error: "STO-WKS-113 needs its Herdr worker setup.", workspaces: [], panes: [])
    static let agents = [
        Agent(id: "home/sample", machineId: "home", machineName: "Home PC", terminalId: "sample", paneId: "w1:p1", workspaceId: "w1", workspace: "Scratch", name: "home-pc-claude", kind: "claude", status: "blocked", cwd: "C:\\Users\\Mark\\Documents\\Herdr\\Scratch", sequence: 1, ready: true, stale: false, updatedAt: Date()),
        Agent(id: "mac/sample", machineId: "mac", machineName: "Mac", terminalId: "sample", paneId: "w1:p1", workspaceId: "w1", workspace: "Scratch", name: "mac-codex", kind: "codex", status: "working", cwd: "/Users/mark/Documents/Herdr/Scratch", sequence: 1, ready: true, stale: false, updatedAt: Date())
    ]
    static var state: ControllerState {
        var state = ControllerState(generatedAt: Date(), machines: [mac, home, pending], agents: agents, notifications: PushStatus(configured: false, lastError: nil, topic: "xyz.verdalecres.herdr"))
        state.sharedWorkspaceCatalog = SharedWorkspaceCatalog(available: true, stale: false, revision: 1, workspaces: [
            SharedWorkspace(id: "sample-project", label: "Herdr updates", members: agents.map(SharedMember.init(agent:))),
            SharedWorkspace(id: "sample-empty", label: "Next project", members: [])
        ])
        return state
    }
    #if DEBUG
    static var compactListState: ControllerState {
        let examples = [
            ("api-cleanup", "working", mac, "codex", "Backend"),
            ("docs-update", "idle", home, "claude", "Documentation"),
            ("interface-refresh", "working", mac, "codex", "IOS-Herdr"),
            ("project-review", "done", home, "claude", "Website"),
            ("release-check", "idle", mac, "codex", "Release"),
            ("workspace-with-a-long-agent-name", "working", home, "claude", "ProjectWithALongerFolderName")
        ]
        let more = examples.enumerated().map { index, example in
            let (name, status, machine, kind, folder) = example
            return Agent(id: "\(machine.id)/compact-\(index)", machineId: machine.id, machineName: machine.name, terminalId: "sample-\(index)", paneId: "w\(index + 2):p1", workspaceId: "w\(index + 2)", workspace: folder, name: name, kind: kind, status: status, cwd: machine.id == "mac" ? "/Users/mark/Projects/\(folder)" : "C:\\Projects\\\(folder)", sequence: 1, ready: true, stale: false, updatedAt: Date())
        }
        return ControllerState(generatedAt: Date(), machines: [mac, home, pending], agents: agents + more, notifications: state.notifications)
    }
    #endif
    static var events: [InboxEvent] { [InboxEvent(id: 1, kind: "attention", agentId: "home/sample", machineId: "home", title: "An agent needs you", body: "home-pc-claude · Home PC", createdAt: Date().addingTimeInterval(-120), read: false)] }
}

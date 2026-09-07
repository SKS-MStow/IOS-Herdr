import SwiftUI
import UserNotifications

@MainActor final class AppModel: ObservableObject {
    @Published var connection: Connection?
    @Published var state: ControllerState?
    @Published var events: [InboxEvent] = []
    @Published var preferences = Preferences()
    @Published var connected = false
    @Published var error: String?
    @Published var isDemo = false
    @Published var selectedTab = 0
    @Published var agentPath: [AppRoute] = []
    @Published var pending: [String: String] = [:]
    @Published var notificationPermission = "Not enabled"
    @Published var settings: DeviceSettings?
    @Published var pairingServer = "https://marks-macbook-air.tail79ccb5.ts.net:8443"
    @Published var pairingCode = ""
    @Published var showPairing = false
    @Published var sharedBusy = false
    @Published var pendingSharedChange: SharedChange?
    private var refreshing = false
    var client: ControllerClient? { connection.map { ControllerClient(connection: $0) } }
    var hasSession: Bool { connection != nil || isDemo }
    var unreadCount: Int { events.filter { !$0.read }.count }
    var agents: [Agent] { state?.agents ?? [] }
    var machines: [Machine] { state?.machines ?? [] }
    var pollIdentity: String { isDemo ? "demo" : connection?.deviceId ?? "unpaired" }

    init() {
        connection = Keychain.load()
        if let data = UserDefaults.standard.data(forKey: "pendingSharedChange") { pendingSharedChange = try? JSONDecoder().decode(SharedChange.self, from: data) }
        if let connection { pairingServer = connection.serverURL }
        pending = UserDefaults.standard.dictionary(forKey: "pendingOperations") as? [String: String] ?? [:]
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--demo") { enableDemo() }
        if ProcessInfo.processInfo.arguments.contains("--demo-list") { enableDemo(); state = SampleData.compactListState }
        if ProcessInfo.processInfo.arguments.contains("--demo-stale") {
            enableDemo()
            if var cached = state { for index in cached.agents.indices { cached.agents[index].stale = true }; state = cached }
        }
        #endif
    }
    func enableDemo() { isDemo = true; state = SampleData.state; events = SampleData.events; connected = false; error = nil }
    func leaveDemo() { isDemo = false; state = nil; events = []; agentPath = [] }
    func pair() async throws {
        let url = try ControllerClient.validatedURL(pairingServer)
        let temporary = ControllerClient(connection: Connection(serverURL: url.absoluteString, deviceId: "", token: ""))
        let result: PairResponse = try await temporary.request("/api/pair", method: "POST", body: ["code": pairingCode, "name": UIDevice.current.name])
        let newConnection = Connection(serverURL: url.absoluteString, deviceId: result.deviceId, token: result.token)
        try Keychain.save(newConnection)
        clearSharedWorkspaceRecovery()
        connection = newConnection; pairingCode = ""; isDemo = false; showPairing = false; agentPath = []; state = nil; events = []; error = nil
        pending = [:]; savePending()
        await refresh(); await registerSavedPushToken()
    }
    func refresh() async {
        guard !isDemo, let client, !refreshing else { return }
        refreshing = true; defer { refreshing = false }
        do {
            async let snapshot: ControllerState = client.request("/api/state")
            async let inbox: InboxResponse = client.request("/api/inbox")
            async let device: DeviceSettings = client.request("/api/settings")
            let (newState, newInbox, newSettings) = try await (snapshot, inbox, device)
            guard connection?.deviceId == client.connection.deviceId, !isDemo else { return }
            state = newState; events = newInbox.events; preferences = newSettings.preferences; settings = newSettings
            connected = true; error = nil
        } catch {
            guard connection?.deviceId == client.connection.deviceId, !isDemo else { return }
            connected = false
            self.error = (error as? APIError)?.message ?? "Cannot reach the Mac. Check Tailscale and make sure the Mac is awake."
            if var cached = state { for index in cached.agents.indices { cached.agents[index].stale = true }; state = cached }
        }
    }
    func output(for id: String) async throws -> SessionOutput {
        if isDemo {
            let runs = [
                TerminalRun(text: "Preview ready\n", color: "#A8D5A2", bold: true),
                TerminalRun(text: "The layout is updated. Open the preview to check it on your phone.\n\n"),
                TerminalRun(text: String(repeating: "─", count: 120) + "\n"),
                TerminalRun(text: "Changes\n", bold: true),
                TerminalRun(text: "+ Added a compact agent list\n", color: "#A8D5A2"),
                TerminalRun(text: "− Removed oversized badges\n", color: "#F28B82"),
                TerminalRun(text: "\nPrivate preview\n", bold: true),
                TerminalRun(text: "http://localhost:5173/\n", color: "#8AB4F8"),
                TerminalRun(text: "\nOpen the Herdr screenshots", link: "http://100.103.121.43:8765/"),
                TerminalRun(text: "\n\nReady for your feedback.", dim: true)
            ]
            return SessionOutput(agentId: id, text: runs.map(\.text).joined(), readAt: Date(), source: "sample", sequence: 1, runs: runs)
        }
        guard let client else { throw APIError(message: "Pair your iPhone first.", code: "unpaired") }
        return try await client.request("/api/agents/\(ControllerClient.agentPath(id))/output")
    }
    func perform(path: String, scope: String, body: [String: Any], retainAccepted: Bool = false) async throws -> Operation {
        if isDemo { throw APIError(message: "This is sample data. Pair with your Mac to send real commands.", code: "demo") }
        guard connected, let client else { throw APIError(message: "Reconnect to the Mac before sending.", code: "offline") }
        if let requestID = pending[scope] {
            let existing: Operation = try await client.request("/api/operations/\(requestID)")
            if (existing.state == "accepted" && !retainAccepted) || existing.state == "rejected" { clearPending(scope) }
            return existing
        }
        let requestID = UUID().uuidString.lowercased()
        pending[scope] = requestID; savePending()
        var payload = body; payload["requestId"] = requestID
        do {
            let result: Operation = try await client.request(path, method: "POST", body: payload)
            if (result.state == "accepted" && !retainAccepted) || result.state == "rejected" { clearPending(scope) }
            return result
        } catch {
            if let apiError = error as? APIError, ["invalid_request", "invalid_attachment", "unauthorized", "rate_limited", "origin", "request_conflict"].contains(apiError.code) { clearPending(scope); throw error }
            throw APIError(message: "Delivery is unconfirmed. Your message is kept here. Check the session and delivery status before sending anything else.", code: "uncertain")
        }
    }
    func checkPending(_ scope: String) async throws -> Operation? {
        guard let requestID = pending[scope], let client else { return nil }
        let result: Operation = try await client.request("/api/operations/\(requestID)")
        if result.state == "accepted" || result.state == "rejected" { clearPending(scope) }
        return result
    }
    func clearPending(_ scope: String) { pending.removeValue(forKey: scope); savePending() }
    private func savePending() { UserDefaults.standard.set(pending, forKey: "pendingOperations") }
    func markRead() async {
        guard let latest = events.map(\.id).max() else { return }
        if isDemo { events = events.map { var event = $0; event.read = true; return event }; return }
        do { let _: EmptyResponse = try await client?.request("/api/inbox/read", method: "POST", body: ["through": latest]) ?? EmptyResponse(); await refresh() }
        catch { self.error = error.localizedDescription }
    }
    func savePreferences(_ value: Preferences) async throws {
        guard let client, !isDemo else { preferences = value; return }
        let body = try JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as! [String: Any]
        let _: EmptyResponse = try await client.request("/api/settings", method: "PUT", body: body)
        preferences = value
    }
    func updateNotificationPermission() async {
        let setting = await UNUserNotificationCenter.current().notificationSettings()
        switch setting.authorizationStatus { case .authorized, .provisional, .ephemeral: notificationPermission = "Allowed"; case .denied: notificationPermission = "Off in iOS Settings"; default: notificationPermission = "Not enabled" }
    }
    func enableNotifications() async throws {
        guard !isDemo else { return }
        if try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { UIApplication.shared.registerForRemoteNotifications() }
        await updateNotificationPermission()
    }
    func registerSavedPushToken() async {
        guard let token = UserDefaults.standard.string(forKey: "pushToken"), let client, !isDemo else { return }
        #if DEBUG
        let environment = "sandbox"
        #else
        let environment = "production"
        #endif
        do { let _: EmptyResponse = try await client.request("/api/push/register", method: "POST", body: ["token": token, "environment": environment]); await refresh() }
        catch { self.error = "Could not register this iPhone for alerts: \(error.localizedDescription)" }
    }
    func testNotification() async throws {
        guard let client, !isDemo else { throw APIError(message: "Pair your iPhone first.", code: "unpaired") }
        let _: EmptyResponse = try await client.request("/api/push/test", method: "POST", body: [:])
    }
    func disconnect() async throws {
        if isDemo { leaveDemo(); return }
        guard let client else { return }
        let _: EmptyResponse = try await client.request("/api/device", method: "DELETE")
        forgetConnection()
    }
    func forgetConnection() { clearSharedWorkspaceRecovery(); Keychain.clear(); connection = nil; state = nil; events = []; settings = nil; connected = false; error = nil; agentPath = []; pending = [:]; savePending() }
    func openAgent(_ id: String) { selectedTab = 0; agentPath = [.agent(id)] }
    func receivePairLink(_ url: URL) {
        guard url.scheme == "herdr-shared", url.host == "pair", let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let server = parts.queryItems?.first(where: { $0.name == "server" })?.value,
              let code = parts.queryItems?.first(where: { $0.name == "code" })?.value,
              (try? ControllerClient.validatedURL(server)) != nil else { return }
        pairingServer = server; pairingCode = code; if hasSession { showPairing = true }
    }
}

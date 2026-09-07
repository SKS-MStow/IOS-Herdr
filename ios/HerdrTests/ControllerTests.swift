import XCTest
import UIKit
@testable import Herdr

final class ControllerTests: XCTestCase {
    func testStyledOutputCompactsRulesAndPreservesLinksAndCodeIndentation() {
        let runs = [TerminalRun(text: "Title\n", color: "#8AB4F8", bold: true), TerminalRun(text: String(repeating: "─", count: 120) + "\n    code()   \n\n\nhttps://example.com/path?q=1\n"), TerminalRun(text: "Open", link: "https://example.com/other")]
        let output = SessionOutput(agentId: "a", text: runs.map(\.text).joined(), readAt: Date(), source: "visible", sequence: 1, runs: runs)
        let rich = TerminalText.attributed(output, monospaced: false)
        XCTAssertFalse(String(rich.characters).contains("─"))
        XCTAssertTrue(String(rich.characters).contains("    code()"))
        XCTAssertTrue(rich.runs.contains { $0.link?.absoluteString == "https://example.com/path?q=1" })
        XCTAssertTrue(rich.runs.contains { $0.link?.absoluteString == "https://example.com/other" })
        XCTAssertTrue(String(TerminalText.attributed(output, monospaced: true).characters).contains("─"))
        XCTAssertNil(TerminalText.safeURL("javascript:alert(1)"))
        XCTAssertTrue(TerminalText.isLocal(URL(string: "http://localhost:5173")!))
        XCTAssertFalse(TerminalText.isLocal(URL(string: "https://example.com")!))
    }

    func testPhotoPreparationRejectsInvalidDataAndBoundsImageSize() throws {
        XCTAssertThrowsError(try SessionPhoto.prepare(Data("not an image".utf8)))
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 4000, height: 1000))
        let data = renderer.pngData { context in UIColor.red.setFill(); context.fill(CGRect(x: 0, y: 0, width: 4000, height: 1000)) }
        let photo = try SessionPhoto.prepare(data)
        XCTAssertLessThanOrEqual(photo.image.size.width, 2400)
        XCTAssertLessThanOrEqual(photo.data.count, 3 * 1024 * 1024)
        XCTAssertEqual(photo.data.prefix(2), Data([255, 216]))
        let scope = "test-" + UUID().uuidString
        PhotoDrafts.save([photo], scope: scope)
        XCTAssertEqual(PhotoDrafts.load(scope).first?.data, photo.data)
        PhotoDrafts.save([], scope: scope)
        XCTAssertTrue(PhotoDrafts.load(scope).isEmpty)
    }

    func testControllerAddressRequiresHTTPSAndRejectsCredentialsOrExtraRoutes() throws {
        XCTAssertEqual(try ControllerClient.validatedURL("https://mac.example:8443/").absoluteString, "https://mac.example:8443")
        for value in ["http://mac.example", "https://user:secret@mac.example", "https://mac.example/api", "https://mac.example?token=bad", "https://mac.example#bad"] {
            XCTAssertThrowsError(try ControllerClient.validatedURL(value), value)
        }
    }
    func testAgentIdentityRemainsOneEncodedPathComponent() {
        XCTAssertEqual(ControllerClient.agentPath("mac/term_123"), "mac%2Fterm_123")
        XCTAssertEqual(ControllerClient.agentPath("mac/term?x#y"), "mac%2Fterm%3Fx%23y")
    }
    func testWireSnapshotDecodesEpochDatesAndOptionalNotificationState() throws {
        let json = """
        {"generatedAt":1788687000,"machines":[{"id":"mac","name":"Mac","platform":"mac","state":"online","lastSeen":1788687000,"error":null,"workspaces":[],"panes":[]}],"agents":[{"id":"mac/t","machineId":"mac","machineName":"Mac","terminalId":"t","paneId":"w1:p1","workspaceId":"w1","workspace":"Scratch","name":"codex","kind":"codex","status":"new_future_state","cwd":"/tmp","sequence":5,"ready":false,"stale":false,"updatedAt":1788687000}],"notifications":{"configured":false,"lastError":null,"topic":"xyz.verdalecres.herdr"}}
        """
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .secondsSince1970
        let state = try decoder.decode(ControllerState.self, from: Data(json.utf8))
        XCTAssertEqual(state.agents[0].statusLabel, "Status unknown")
        XCTAssertEqual(state.generatedAt.timeIntervalSince1970, 1788687000)
        XCTAssertFalse(state.notifications.configured)
        XCTAssertNil(state.sharedWorkspaceCatalog)
    }
    func testAStaleMachineCannotBeShownAsConnected() {
        let machine = Machine(id: "m", name: "Mac", platform: "mac", state: "online", lastSeen: Date().addingTimeInterval(-120), error: nil, workspaces: [], panes: [])
        XCTAssertFalse(machine.isOnline)
        var agent = SampleData.agents[0]; agent.stale = true
        XCTAssertEqual(agent.statusLabel, "Last known state")
    }
    func testWorkspaceMembershipUsesMachineSessionAndTerminalIdentity() {
        let agent = SampleData.agents[0]
        let reference = SharedMember(agent: agent)
        XCTAssertTrue(reference.matches(agent))
        XCTAssertFalse(SharedMember(machineId: "mac", session: "shared", terminalId: agent.terminalId).matches(agent))
        XCTAssertFalse(SharedMember(machineId: agent.machineId, session: "other", terminalId: agent.terminalId).matches(agent))
        XCTAssertFalse(SharedMember(machineId: agent.machineId, session: "shared", terminalId: "replacement").matches(agent))
    }
    @MainActor func testDemoWorkspaceRemovalLeavesAgentsAndNotificationNavigationIntact() async throws {
        let model = AppModel(); model.enableDemo(); model.pendingSharedChange = nil
        let original = model.agents.map(\.id)
        let id = try await model.changeSharedWorkspace("create", label: "Test")!
        try await model.changeSharedWorkspace("add", id: id, member: SharedMember(agent: model.agents[0]))
        try await model.changeSharedWorkspace("add", id: id, member: SharedMember(agent: model.agents[1]))
        XCTAssertEqual(model.sharedWorkspace(id)?.members.count, 2)
        try await model.changeSharedWorkspace("delete", id: id)
        XCTAssertEqual(model.agents.map(\.id), original)
        model.openAgent(original[1]); XCTAssertEqual(model.agentPath, [.agent(original[1])])
    }
    func testUncertainOperationIsNotPresentedAsSuccess() throws {
        let data = Data(#"{"id":"request","state":"uncertain","result":{"message":"Inspect the session","code":"unreachable"}}"#.utf8)
        let operation = try JSONDecoder().decode(Operation.self, from: data)
        XCTAssertEqual(operation.state, "uncertain")
        XCTAssertEqual(operation.message, "Inspect the session")
        XCTAssertNil(operation.result?.agentId)
    }
    @MainActor func testDefinitiveWorkspaceRejectionClearsRecoveryButTransportFailureKeepsIt() throws {
        let model = AppModel(); model.enableDemo()
        let change = SharedChange(requestId: "rejected-name", expectedRevision: 0, action: "create", id: nil, label: String(repeating: "x", count: 129), member: nil)
        model.pendingSharedChange = change
        UserDefaults.standard.set(try JSONEncoder().encode(change), forKey: "pendingSharedChange")
        model.clearDefinitivelyRejectedSharedChange(URLError(.timedOut))
        XCTAssertNotNil(model.pendingSharedChange)
        model.clearDefinitivelyRejectedSharedChange(APIError(message: "Try again later", code: "rate_limited"))
        XCTAssertNotNil(model.pendingSharedChange)
        model.clearDefinitivelyRejectedSharedChange(APIError(message: "Name too long", code: "invalid_request"))
        XCTAssertNil(model.pendingSharedChange)
        XCTAssertNil(UserDefaults.standard.data(forKey: "pendingSharedChange"))
        XCTAssertTrue(model.canEditSharedWorkspaces)
    }

}

import XCTest
@testable import Herdr

final class ControllerTests: XCTestCase {
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
    }
    func testAStaleMachineCannotBeShownAsConnected() {
        let machine = Machine(id: "m", name: "Mac", platform: "mac", state: "online", lastSeen: Date().addingTimeInterval(-120), error: nil, workspaces: [], panes: [])
        XCTAssertFalse(machine.isOnline)
        var agent = SampleData.agents[0]; agent.stale = true
        XCTAssertEqual(agent.statusLabel, "Last known state")
    }
    func testUncertainOperationIsNotPresentedAsSuccess() throws {
        let data = Data(#"{"id":"request","state":"uncertain","result":{"message":"Inspect the session","code":"unreachable"}}"#.utf8)
        let operation = try JSONDecoder().decode(Operation.self, from: data)
        XCTAssertEqual(operation.state, "uncertain")
        XCTAssertEqual(operation.message, "Inspect the session")
        XCTAssertNil(operation.result?.agentId)
    }
}

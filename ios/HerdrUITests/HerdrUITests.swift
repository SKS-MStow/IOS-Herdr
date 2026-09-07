import XCTest

final class HerdrUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    func capture(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    func testDemoNavigationAndDisabledLiveControls() {
        let app = XCUIApplication(); app.launchArguments = ["--demo"]; app.launch()
        XCTAssertTrue(app.staticTexts["Demo · Workspaces"].waitForExistence(timeout: 15))
        capture("10-workspaces", app: app)
        app.buttons["All agents"].tap()
        XCTAssertTrue(app.staticTexts["DEMO"].exists)
        capture("01-agents", app: app)
        app.buttons["agent-home/sample"].tap()
        XCTAssertTrue(app.staticTexts["Session output"].exists || app.staticTexts["Sample output"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Demo · commands are disabled"].exists)
        XCTAssertFalse(app.buttons["Send message"].isEnabled)
        capture("02-session", app: app)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.tabBars.buttons["Inbox"].tap()
        XCTAssertTrue(app.staticTexts["An agent needs you"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["DEMO"].exists)
        XCTAssertTrue(app.navigationBars["Inbox"].exists)
        capture("03-inbox", app: app)
        app.buttons["Mark read"].tap()
        XCTAssertFalse(app.buttons["Mark read"].isEnabled)
        app.tabBars.buttons["Machines"].tap()
        XCTAssertTrue(app.staticTexts["Work laptop"].waitForExistence(timeout: 5))
        capture("04-machines", app: app)
    }
    func testSessionReadingAndAttachmentControls() {
        let app = XCUIApplication(); app.launchArguments = ["--demo"]; app.launch()
        app.buttons["All agents"].tap()
        app.buttons["agent-mac/sample"].tap()
        XCTAssertTrue(app.buttons["Pause output to read"].waitForExistence(timeout: 10))
        app.buttons["Pause output to read"].tap()
        XCTAssertTrue(app.buttons["Resume live output"].exists)
        capture("20-session-reading", app: app)
        app.buttons["Attachments and terminal keys"].tap()
        XCTAssertTrue(app.buttons["Photo library"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Image from Files"].exists)
        capture("21-session-attachments", app: app)
        app.buttons["Show terminal keys"].tap()
        XCTAssertTrue(app.buttons["Esc"].exists)
        XCTAssertFalse(app.buttons["Esc"].isEnabled)
        app.buttons["Attachments and terminal keys"].tap()
        app.buttons["Photo library"].tap()
        let photo = app.images.matching(identifier: "PXGGridLayout-Info").firstMatch
        XCTAssertTrue(photo.waitForExistence(timeout: 10))
        // The system Photos grid exposes images with frames but no AX hit point.
        photo.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["Remove photo 1"].waitForExistence(timeout: 10))
        capture("24-photo-composer", app: app)
        app.buttons["Remove photo 1"].tap()
        XCTAssertFalse(app.buttons["Remove photo 1"].exists)
    }
    func testSessionReadingAtAccessibilitySize() {
        let app = XCUIApplication(); app.launchArguments = ["--demo", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]; app.launch()
        app.buttons["All agents"].tap(); app.buttons["agent-mac/sample"].tap()
        XCTAssertTrue(app.buttons["Attachments and terminal keys"].waitForExistence(timeout: 10))
        capture("22-session-accessibility", app: app)
        XCUIDevice.shared.orientation = .landscapeLeft
        capture("23-session-landscape", app: app)
        XCUIDevice.shared.orientation = .portrait
    }
    func testPairingStartsWithSendDisabled() throws {
        let app = XCUIApplication(); app.launchArguments = []; app.launch()
        if !app.textFields["controllerURL"].waitForExistence(timeout: 5) { throw XCTSkip("The simulator already has a paired controller.") }
        capture("05-pairing", app: app)
        XCTAssertTrue(app.buttons["Connect to Mac"].exists)
        XCTAssertFalse(app.buttons["Connect to Mac"].isEnabled)
    }

    func testStaleAttentionDoesNotClaimCurrentState() {
        let app = XCUIApplication(); app.launchArguments = ["--demo-stale"]; app.launch()
        app.buttons["All agents"].tap()
        let staleAgent = app.buttons["agent-home/sample"]
        XCTAssertTrue(staleAgent.waitForExistence(timeout: 10))
        XCTAssertTrue(staleAgent.label.contains("Last known state"))
        XCTAssertFalse(app.staticTexts["NEEDS YOU"].exists)
        XCTAssertFalse(app.staticTexts["Waiting for your response."].exists)
        capture("07-stale-agents", app: app)
    }

    func testCompactListFiltersAndOpensSession() {
        let app = XCUIApplication(); app.launchArguments = ["--demo-list"]; app.launch()
        app.buttons["All agents"].tap()
        XCTAssertTrue(app.buttons["agent-home/sample"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["agent-mac/compact-4"].isHittable)
        capture("08-compact-agents", app: app)
        app.segmentedControls.buttons["Home PC"].tap()
        XCTAssertTrue(app.buttons["agent-home/compact-1"].exists)
        XCTAssertFalse(app.buttons["agent-mac/sample"].exists)
        app.segmentedControls.buttons["Mac"].tap()
        XCTAssertTrue(app.buttons["agent-mac/sample"].exists)
        XCTAssertFalse(app.buttons["agent-home/sample"].exists)
        app.buttons["agent-mac/compact-2"].tap()
        XCTAssertTrue(app.navigationBars["interface-refresh"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Send message"].isEnabled)
    }

    func testCompactListAtAccessibilityTextSize() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo-list", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        app.buttons["All agents"].tap()
        let agent = app.buttons["agent-home/sample"]
        XCTAssertTrue(agent.waitForExistence(timeout: 10))
        XCTAssertTrue(agent.label.contains("Needs you"))
        XCTAssertTrue(agent.label.contains("Home PC"))
        capture("09-accessibility-agents", app: app)
        agent.tap()
        XCTAssertTrue(app.navigationBars["home-pc-claude"].waitForExistence(timeout: 5))
    }


    func testCreateWorkspaceWithAgentsFromBothMachines() {
        let app = XCUIApplication(); app.launchArguments = ["--demo"]; app.launch()
        XCTAssertTrue(app.staticTexts["Demo · Workspaces"].waitForExistence(timeout: 10))
        app.buttons["Create workspace"].tap()
        let alert = app.alerts["New workspace"]
        alert.textFields["Workspace name"].tap(); alert.textFields["Workspace name"].typeText("Website project")
        alert.buttons["Create"].tap()
        XCTAssertTrue(app.staticTexts["Demo · Website project"].waitForExistence(timeout: 5))
        app.buttons["Add existing agents"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Demo · Add agents"].waitForExistence(timeout: 5))
        app.buttons["membership-home/sample"].tap()
        app.buttons["membership-mac/sample"].tap()
        capture("12-add-workspace-agents", app: app)
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["workspace-agent-home/sample"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["workspace-agent-mac/sample"].exists)
        capture("11-mixed-machine-workspace", app: app)
        app.buttons["Add existing agents"].firstMatch.tap()
        app.buttons["membership-home/sample"].tap()
        app.buttons["Done"].tap()
        XCTAssertFalse(app.buttons["workspace-agent-home/sample"].exists)
        app.buttons["workspace-agent-mac/sample"].tap()
        XCTAssertTrue(app.navigationBars["mac-codex"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Send message"].isEnabled)
    }

    func testWorkspaceAtAccessibilitySize() {
        let app = XCUIApplication(); app.launchArguments = ["--demo", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]; app.launch()
        XCTAssertTrue(app.buttons["workspace-sample-project"].waitForExistence(timeout: 10))
        capture("13-workspaces-accessibility", app: app)
        app.buttons["workspace-sample-project"].tap()
        XCTAssertTrue(app.buttons["workspace-agent-home/sample"].waitForExistence(timeout: 5))
        capture("14-workspace-detail-accessibility", app: app)
    }

    // Run explicitly after scripts/prepare-simulator-pairing.mjs. No credentials enter test source or logs.
    func testPreparedLivePairing() throws {
        guard ProcessInfo.processInfo.environment["HERDR_LIVE_PAIRING_TEST"] == "1" else { throw XCTSkip("Live pairing requires an explicit opt-in and a fresh one-time link.") }
        let app = XCUIApplication(); app.activate()
        let connect = app.buttons["Connect to Mac"]
        XCTAssertTrue(connect.waitForExistence(timeout: 10))
        let system = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            if system.alerts.buttons["Open"].exists { system.alerts.buttons["Open"].tap() }
            else if app.alerts.buttons["Open"].exists { app.alerts.buttons["Open"].tap() }
            return connect.isEnabled
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 60), .completed, "Deliver a one-time pairing link during this opt-in test.")
        connect.tap()
        XCTAssertTrue(app.staticTexts["Mac controller connected"].waitForExistence(timeout: 45))
        XCTAssertFalse(app.staticTexts["DEMO"].exists)
        app.tabBars.buttons["Machines"].tap()
        XCTAssertTrue(app.staticTexts["Home PC"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Work laptop"].exists)
        capture("06-live-machines", app: app)
        app.tabBars.buttons["Workspaces"].tap()
        app.buttons["Settings"].tap()
        app.swipeUp()
        app.buttons["Unpair this iPhone"].tap()
        app.buttons["Revoke this iPhone’s access"].tap()
        XCTAssertTrue(app.textFields["controllerURL"].waitForExistence(timeout: 15))
    }
}

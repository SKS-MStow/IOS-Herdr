import XCTest

final class HerdrUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    func capture(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    func testDemoNavigationAndDisabledLiveControls() {
        let app = XCUIApplication(); app.launchArguments = ["--demo"]; app.launch()
        XCTAssertTrue(app.navigationBars["Agents"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["DEMO"].exists)
        capture("01-agents", app: app)
        app.buttons["agent-home/sample"].tap()
        XCTAssertTrue(app.staticTexts["Session output"].exists || app.staticTexts["Sample output"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Demo · commands are disabled"].exists)
        XCTAssertFalse(app.buttons["Send message"].isEnabled)
        capture("02-session", app: app)
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
    func testPairingStartsWithSendDisabled() throws {
        let app = XCUIApplication(); app.launchArguments = []; app.launch()
        if !app.textFields["controllerURL"].waitForExistence(timeout: 5) { throw XCTSkip("The simulator already has a paired controller.") }
        capture("05-pairing", app: app)
        XCTAssertTrue(app.buttons["Connect to Mac"].exists)
        XCTAssertFalse(app.buttons["Connect to Mac"].isEnabled)
    }

    func testStaleAttentionDoesNotClaimCurrentState() {
        let app = XCUIApplication(); app.launchArguments = ["--demo-stale"]; app.launch()
        let staleAgent = app.buttons["agent-home/sample"]
        XCTAssertTrue(staleAgent.waitForExistence(timeout: 10))
        XCTAssertTrue(staleAgent.label.contains("Last known state"))
        XCTAssertFalse(app.staticTexts["NEEDS YOU"].exists)
        XCTAssertFalse(app.staticTexts["Waiting for your response."].exists)
        capture("07-stale-agents", app: app)
    }

    func testCompactListFiltersAndOpensSession() {
        let app = XCUIApplication(); app.launchArguments = ["--demo-list"]; app.launch()
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
        let agent = app.buttons["agent-home/sample"]
        XCTAssertTrue(agent.waitForExistence(timeout: 10))
        XCTAssertTrue(agent.label.contains("Needs you"))
        XCTAssertTrue(agent.label.contains("Home PC"))
        capture("09-accessibility-agents", app: app)
        agent.tap()
        XCTAssertTrue(app.navigationBars["home-pc-claude"].waitForExistence(timeout: 5))
    }

    // Run explicitly after scripts/prepare-simulator-pairing.mjs. No credentials enter test source or logs.
    func testPreparedLivePairing() throws {
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
        app.tabBars.buttons["Agents"].tap()
        app.buttons["Settings"].tap()
        app.swipeUp()
        app.buttons["Unpair this iPhone"].tap()
        app.buttons["Revoke this iPhone’s access"].tap()
        XCTAssertTrue(app.textFields["controllerURL"].waitForExistence(timeout: 15))
    }
}

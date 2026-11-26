// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Copyright (c) 2026 Parham Rahimi
// See LICENSE and NOTICE for license terms and required attribution.

import XCTest

final class WorkoutPlusUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    private func application(welcome: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-hasCompletedWelcome", welcome ? "NO" : "YES", "-remoteImagesEnabled", "NO", "-showWorkoutDetails", "NO", "-appLockEnabled", "NO"]
        app.launch()
        return app
    }
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<8 { if element.isHittable { return }; app.swipeUp() }
    }
    private func screenshot(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways
        add(attachment)
    }
    func testFirstRunGuidance() {
        let app = application(welcome: true)
        XCTAssertTrue(app.staticTexts["Welcome to Workout Plus"].waitForExistence(timeout: 10))
        screenshot("Welcome — synthetic clean install", app: app)
        let start = app.buttons["Start tracking"]
        reveal(start, in: app); start.tap()
        XCTAssertTrue(app.tabBars.buttons["Workouts"].exists)
    }
    func testCreateAndSelectPlan() {
        let app = application()
        app.buttons["Plans"].tap()
        app.buttons["Add plan"].tap()
        app.buttons["Create plan"].tap()
        let name = app.textFields["Name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        let previous = name.value as? String ?? ""
        name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: previous.count) + "Synthetic QA Plan")
        app.navigationBars.buttons["Save"].tap()
        let plan = app.buttons.containing(.staticText, identifier: "Synthetic QA Plan").firstMatch
        XCTAssertTrue(plan.waitForExistence(timeout: 5))
        plan.tap()
        expectation(for: NSPredicate(format: "value == %@", "Selected"), evaluatedWith: plan)
        waitForExpectations(timeout: 5)
        screenshot("Plans — synthetic plan", app: app)
    }
    func testPrivacyPolicyAndDefaultControls() {
        let app = application()
        app.buttons["Settings"].tap()
        let remote = app.switches["Allow exercise image downloads"]
        reveal(remote, in: app)
        XCTAssertEqual(remote.value as? String, "0")
        let details = app.switches["Show workout details in widgets and Live Activities"]
        reveal(details, in: app)
        XCTAssertEqual(details.value as? String, "0")
        let policy = app.buttons["Privacy policy"]
        reveal(policy, in: app); policy.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Your workout logs,")).firstMatch.waitForExistence(timeout: 5))
        screenshot("Privacy policy", app: app)
    }
}

// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Copyright (c) 2026 Parham Rahimi
// See LICENSE and NOTICE for license terms and required attribution.

import XCTest

/// Opt-in gallery: Tools/run_ui_checks.sh selects this suite only when
/// WORKOUT_CAPTURE_GALLERY=1. Every app launch uses simulator-only fake records.
final class FeatureGalleryTests: XCTestCase {
    private let workout = "Workout A — Pull-up, Chest & Side Delts"
    override func setUpWithError() throws { continueAfterFailure = false }

    private func demo() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--synthetic-screenshot-demo", "-hasCompletedWelcome", "YES", "-remoteImagesEnabled", "NO", "-showWorkoutDetails", "YES", "-appLockEnabled", "NO", "-hkSyncWorkouts", "NO", "-hkSyncBodyweight", "NO", "-hkWriteCalories", "NO", "-restAlertsEnabled", "NO", "-expiryAlertsEnabled", "NO"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Workouts"].waitForExistence(timeout: 15))
        return app
    }
    private func shot(_ name: String, _ app: XCUIApplication) {
        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = name; capture.lifetime = .keepAlways; add(capture)
    }
    private func reveal(_ element: XCUIElement, _ app: XCUIApplication) {
        for _ in 0..<12 { if element.isHittable { return }; app.swipeUp() }
        XCTAssertTrue(element.isHittable, "Could not reveal \(element)")
    }
    private func tapText(_ text: String, _ app: XCUIApplication) {
        let target = app.staticTexts[text].firstMatch
        reveal(target, app); target.tap()
    }
    private func goBack(_ app: XCUIApplication) { app.navigationBars.buttons.element(boundBy: 0).tap() }

    func testGallery01PlansAndEditors() {
        let app = demo()
        shot("01-workouts", app)
        app.buttons["Plans"].tap()
        shot("02-plans", app)
        let plan = app.buttons.containing(.staticText, identifier: "Three-Day Full-Body Plan").firstMatch
        plan.swipeRight()
        app.buttons["Edit"].tap()
        XCTAssertTrue(app.textFields["Name"].waitForExistence(timeout: 5))
        shot("03-plan-editor", app)
        tapText(workout, app)
        shot("04-workout-editor", app)
        tapText("Pull-up", app)
        XCTAssertTrue(app.textFields["Exercise name"].waitForExistence(timeout: 5))
        shot("05-exercise-editor", app)
    }

    func testGallery02LiveWorkoutAndLogging() {
        let app = demo()
        tapText(workout, app)
        XCTAssertTrue(app.buttons["Start Workout"].waitForExistence(timeout: 5))
        shot("06-workout-plan", app)
        app.buttons["Start Workout"].tap()
        XCTAssertTrue(app.buttons["Finish"].waitForExistence(timeout: 5))
        shot("07-active-workout", app)
        tapText("Pull-up", app)
        XCTAssertTrue(app.buttons["Log Sets"].waitForExistence(timeout: 5))
        shot("08-exercise-guide", app)
        app.swipeUp()
        shot("09-exercise-instructions", app)
        app.buttons["Swap this exercise for another"].tap()
        XCTAssertTrue(app.navigationBars["Swap Exercise"].waitForExistence(timeout: 5))
        shot("10-exercise-substitution", app)
        app.buttons["Cancel"].tap()
        app.buttons["Log Sets"].tap()
        XCTAssertTrue(app.navigationBars.buttons["Done"].waitForExistence(timeout: 5))
        shot("11-set-logging", app)
        let finishSet = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Finish set")).firstMatch
        if finishSet.exists { finishSet.tap() }
        else {
            let capitalized = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Finish Set")).firstMatch
            XCTAssertTrue(capitalized.exists); capitalized.tap()
        }
        shot("12-set-rest-timer", app)
        app.navigationBars.buttons["Done"].tap()
        goBack(app)
        XCTAssertTrue(app.buttons["Skip"].waitForExistence(timeout: 5))
        shot("13-workout-rest-timer", app)
        app.buttons["Finish"].tap()
        XCTAssertTrue(app.buttons["Finish & Save"].waitForExistence(timeout: 5))
        shot("14-finish-confirmation", app)
        app.buttons["Finish & Save"].tap()
        XCTAssertTrue(app.buttons["Start Workout"].waitForExistence(timeout: 5))
        goBack(app)
        app.tabBars.buttons["History"].tap()
        shot("15-saved-demo-workout", app)
    }

    func testGallery03HistoryAndSetEditing() {
        let app = demo()
        app.tabBars.buttons["History"].tap()
        XCTAssertTrue(app.navigationBars["History"].waitForExistence(timeout: 5))
        shot("16-history", app)
        let session = app.cells.containing(.staticText, identifier: "Workout C — Chest, Side Delts & Arms").firstMatch
        if session.exists { session.tap() }
        else { app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Workout C")).firstMatch.tap() }
        XCTAssertTrue(app.navigationBars.buttons.count > 0)
        shot("17-session-detail", app)
        let set = app.buttons.containing(.staticText, identifier: "Set 1").firstMatch
        XCTAssertTrue(set.exists); set.tap()
        shot("18-edit-recorded-set", app)
    }

    func testGallery04ProgressAndExport() {
        let app = demo()
        app.tabBars.buttons["Progress"].tap()
        XCTAssertTrue(app.navigationBars["Progress"].waitForExistence(timeout: 5))
        shot("19-measurement-trends", app)
        let progress = app.staticTexts["Exercise progress"].firstMatch
        reveal(progress, app)
        app.swipeUp()
        shot("20-exercise-progress", app)
        let volume = app.staticTexts["Weekly volume"].firstMatch
        reveal(volume, app)
        app.swipeUp()
        shot("21-weekly-volume", app)
        for _ in 0..<3 { app.swipeUp() }
        shot("22-progress-summary", app)
        app.buttons["Export and back up your data"].tap()
        XCTAssertTrue(app.navigationBars["Export Data"].waitForExistence(timeout: 5))
        shot("23-export-options", app)
        let prepare = app.buttons["Prepare backup file"]
        reveal(prepare, app); prepare.tap()
        let share = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Share workout-plus-backup.json")).firstMatch
        XCTAssertTrue(share.waitForExistence(timeout: 10))
        shot("24-synthetic-backup-ready", app)
    }

    func testGallery05BodyAndSyntheticPhotos() {
        let app = demo()
        app.tabBars.buttons["Body"].tap()
        XCTAssertTrue(app.navigationBars["Body"].waitForExistence(timeout: 5))
        shot("25-body-measurements", app)
        let photo = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "View progress photo from")).firstMatch
        XCTAssertTrue(photo.exists); photo.tap()
        shot("26-demo-illustration-viewer", app)
        // A new app launch leaves the fullscreen viewer without relying on an unlabeled close icon.
        app.terminate(); app.launch()
        app.tabBars.buttons["Body"].tap()
        app.buttons["Compare photos"].tap()
        XCTAssertTrue(app.navigationBars["Compare"].waitForExistence(timeout: 5))
        shot("27-demo-photo-comparison", app)
        app.buttons["Done"].tap()
        app.buttons["Add entry"].tap()
        XCTAssertTrue(app.navigationBars["New Entry"].waitForExistence(timeout: 5))
        shot("28-add-body-entry", app)
    }

    func testGallery06SettingsAndPrivacy() {
        let app = demo()
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        shot("29-settings-rest-and-health", app)
        let remote = app.switches["Allow exercise image downloads"]
        reveal(remote, app)
        shot("30-settings-image-controls", app)
        let profile = app.staticTexts["About you"].firstMatch
        reveal(profile, app)
        shot("31-optional-profile", app)
        let privacy = app.buttons["Privacy policy"]
        reveal(privacy, app)
        shot("32-settings-privacy-and-deletion", app)
        privacy.tap()
        shot("33-privacy-policy", app)
    }
}

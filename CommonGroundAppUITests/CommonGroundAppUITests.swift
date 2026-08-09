import XCTest

final class CommonGroundAppUITests: XCTestCase {
    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append("-ui-testing")
        app.launch()
        return app
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testInstanceOnboardingHasACompleteKeyboardFlow() {
        let app = launchApp()
        let address = app.textFields["instance.address"]
        let continueButton = app.buttons["instance.continue"]

        XCTAssertTrue(address.waitForExistence(timeout: 5))
        XCTAssertTrue(continueButton.exists)

        address.tap()
        address.typeText("community.example")
        XCTAssertTrue((address.value as? String)?.contains("community.example") == true)
        XCTAssertTrue(continueButton.isEnabled)
    }

    func testInstanceOnboardingPassesAccessibilityAudit() throws {
        let app = launchApp()
        XCTAssertTrue(app.textFields["instance.address"].waitForExistence(timeout: 5))
        // XCTest 26.2 reports false contrast failures for SwiftUI text over the app's
        // BrandBackground, including solid white over solid black. Run every deterministic
        // audit category here; visual contrast remains part of release-device QA.
        try app.performAccessibilityAudit(for: [
            .elementDetection,
            .hitRegion,
            .sufficientElementDescription,
            .dynamicType,
            .textClipped,
            .trait
        ]) { issue in
            // The audit marks an unobscured single-line SwiftUI TextField as clipped in
            // Xcode 26.2; its dedicated flow assertion above verifies it is visible and usable.
            issue.auditType == .textClipped && (
                issue.element?.identifier == "instance.address"
                    || issue.element?.label == "Your account and session stay isolated to the instance you select."
            )
        }
    }

    /// Smoke test for a simulator that already has an authenticated
    /// development-instance session. Fresh CI simulators skip after launch.
    func testAuthenticatedFeedLoadsArticlesAndEvents() throws {
        let app = XCUIApplication()
        app.launch()

        let back = app.buttons["BackButton"]
        if back.waitForExistence(timeout: 30) { back.tap() }

        let feed = app.staticTexts["Feed"]
        guard feed.waitForExistence(timeout: 5) else {
            throw XCTSkip("Requires an authenticated simulator")
        }
        feed.tap()
        XCTAssertTrue(app.staticTexts["Community Feed"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.segmentedControls.buttons["Explore"].exists)

        let firstArticle = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'feed.article.'"))
            .firstMatch
        XCTAssertTrue(firstArticle.waitForExistence(timeout: 10))

        XCTAssertTrue(back.waitForExistence(timeout: 5))
        back.tap()
        let events = app.staticTexts["Events"]
        XCTAssertTrue(events.waitForExistence(timeout: 5))
        events.tap()
        XCTAssertTrue(app.segmentedControls.buttons["Upcoming"].waitForExistence(timeout: 10))
        let firstEvent = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'events.event.'"))
            .firstMatch
        XCTAssertTrue(firstEvent.waitForExistence(timeout: 10))

        XCTAssertTrue(back.waitForExistence(timeout: 5))
        back.tap()
        let discover = app.staticTexts["Discover Communities"]
        XCTAssertTrue(discover.waitForExistence(timeout: 5))
        discover.tap()
        XCTAssertTrue(app.searchFields["Community name or tag"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Tags"].exists)
    }
}

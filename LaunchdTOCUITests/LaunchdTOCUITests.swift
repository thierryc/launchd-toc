import XCTest

@MainActor
final class LaunchdTOCUITests: XCTestCase {
    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-UITesting"]
        app.launchEnvironment["LAUNCHD_TOC_UI_TESTING"] = "1"
        app.launch()
        addTeardownBlock {
            app.terminate()
        }
        return app
    }

    func testThreeColumnInventoryAndAccessibilityNames() {
        let app = launchApp()
        XCTAssertTrue(app.descendants(matching: .any)["sidebar.all"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["sidebar.userAgents"].firstMatch.exists)
        XCTAssertTrue(app.descendants(matching: .any)["sidebar.globalAgents"].firstMatch.exists)
        XCTAssertTrue(app.descendants(matching: .any)["sidebar.daemons"].firstMatch.exists)
        XCTAssertTrue(app.descendants(matching: .any)["sidebar.attention"].firstMatch.exists)
        XCTAssertTrue(app.descendants(matching: .any)["jobs.table"].firstMatch.exists)
        XCTAssertTrue(
            app.descendants(matching: .any)["job.com.litsquare.sample.running"]
                .firstMatch
                .waitForExistence(timeout: 2)
        )
        XCTAssertTrue(app.staticTexts["Running"].firstMatch.exists)
    }

    func testSmartFilterAndSearch() {
        let app = launchApp()
        let attention = app.descendants(matching: .any)["sidebar.attention"].firstMatch
        XCTAssertTrue(attention.waitForExistence(timeout: 5))
        attention.click()
        XCTAssertTrue(
            app.descendants(matching: .any)["job.com.litsquare.sample.attention"]
                .firstMatch
                .waitForExistence(timeout: 2)
        )

        let all = app.descendants(matching: .any)["sidebar.all"].firstMatch
        all.click()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 2))
        search.click()
        search.typeText("running")
        XCTAssertTrue(app.descendants(matching: .any)["job.com.litsquare.sample.running"].firstMatch.exists)
        XCTAssertFalse(app.descendants(matching: .any)["job.com.litsquare.sample.attention"].firstMatch.exists)
    }

    func testKeyboardNewAgentAndEditorValidation() {
        let app = launchApp()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 5))
        app.typeKey("n", modifierFlags: .command)
        let label = app.textFields["editor.label"].firstMatch
        XCTAssertTrue(label.waitForExistence(timeout: 4))
        let saveReload = app.buttons["editor.saveReload"].firstMatch
        XCTAssertTrue(saveReload.exists)
        XCTAssertFalse(saveReload.isEnabled)
        label.click()
        label.typeText("com.litsquare.ui")
        XCTAssertFalse(saveReload.isEnabled)
    }
}

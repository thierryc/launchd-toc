import Foundation
import XCTest

@MainActor
final class LaunchdTOCUITests: XCTestCase {
    private func launchApp(readmeCapture: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-UITesting",
            "-ApplePersistenceIgnoreState",
            "YES"
        ]
        app.launchEnvironment["LAUNCHD_TOC_UI_TESTING"] = "1"
        if readmeCapture {
            app.launchArguments.append("-READMECapture")
            app.launchEnvironment["LAUNCHD_TOC_README_CAPTURE"] = "1"
        }
        app.launch()
        app.activate()
        if !app.windows.firstMatch.waitForExistence(timeout: 2) {
            let newWindow = app.menuItems["New Window"].firstMatch
            if newWindow.waitForExistence(timeout: 2) {
                newWindow.click()
            }
        }
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
            app.descendants(matching: .any)["job.com.example.backup.photos"]
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
            app.descendants(matching: .any)["job.com.example.cache.maintenance"]
                .firstMatch
                .waitForExistence(timeout: 2)
        )

        let all = app.descendants(matching: .any)["sidebar.all"].firstMatch
        all.click()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 2))
        search.click()
        search.typeText("photos")
        XCTAssertTrue(app.descendants(matching: .any)["job.com.example.backup.photos"].firstMatch.exists)
        XCTAssertFalse(app.descendants(matching: .any)["job.com.example.cache.maintenance"].firstMatch.exists)
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

    func testDetailExplainsContinuousJobAndEditorPreservesExecutableSource() {
        let app = launchApp()
        let runningJob = app.descendants(matching: .any)["job.com.example.backup.photos"].firstMatch
        XCTAssertTrue(runningJob.waitForExistence(timeout: 5))
        runningJob.click()

        XCTAssertTrue(
            app.descendants(matching: .any)["detail.behaviorSummary"]
                .firstMatch
                .waitForExistence(timeout: 3)
        )
        XCTAssertTrue(
            app.staticTexts["No repeating launchd interval or calendar schedule is configured."]
                .firstMatch
                .exists
        )
        XCTAssertTrue(app.staticTexts["10 seconds"].firstMatch.exists)
        XCTAssertTrue(app.staticTexts["Background"].firstMatch.exists)

        let edit = app.descendants(matching: .any)["toolbar.edit"].firstMatch
        XCTAssertTrue(edit.exists)
        edit.click()

        let executable = app.textFields["editor.executable"].firstMatch
        XCTAssertTrue(executable.waitForExistence(timeout: 3))
        XCTAssertEqual(executable.value as? String, "/usr/bin/python3")
        XCTAssertTrue(app.staticTexts["ProgramArguments[0]"].firstMatch.exists)

        let launchTab = app.descendants(matching: .any)["editor.tab.launch"].firstMatch
        XCTAssertTrue(launchTab.waitForExistence(timeout: 2))
        launchTab.click()
        XCTAssertTrue(
            app.descendants(matching: .any)["editor.throttleEnabled"]
                .firstMatch
                .waitForExistence(timeout: 2)
        )

        let throttleAmount = app.textFields["editor.throttleAmount"].firstMatch
        let throttleUnit = app.staticTexts["editor.throttleUnit"].firstMatch
        XCTAssertTrue(throttleAmount.exists)
        XCTAssertTrue(throttleUnit.exists)
        XCTAssertLessThan(abs(throttleAmount.frame.midY - throttleUnit.frame.midY), 4)
        XCTAssertFalse(app.staticTexts["Seconds"].exists)
    }

    func testCaptureReadmeScreenshots() throws {
        let marker = URL(filePath: "/private/tmp/launchd-toc-readme-capture.enabled")
        guard FileManager.default.fileExists(atPath: marker.path) else {
            throw XCTSkip("Opt-in README screenshot capture")
        }

        let app = launchApp(readmeCapture: true)
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 5))

        let dailyReport = app.descendants(matching: .any)["job.com.example.reports.daily"]
            .firstMatch
        XCTAssertTrue(dailyReport.waitForExistence(timeout: 3))
        dailyReport.click()
        XCTAssertTrue(
            app.descendants(matching: .any)["detail.behaviorSummary"]
                .firstMatch
                .waitForExistence(timeout: 3)
        )
        capture(window, named: "launchd-toc-overview.png")

        let photoBackup = app.descendants(matching: .any)["job.com.example.backup.photos"]
            .firstMatch
        XCTAssertTrue(photoBackup.exists)
        photoBackup.click()
        XCTAssertTrue(
            app.staticTexts["No repeating launchd interval or calendar schedule is configured."]
                .firstMatch
                .waitForExistence(timeout: 3)
        )
        capture(window, named: "launchd-toc-detail.png")

        let edit = app.descendants(matching: .any)["toolbar.edit"].firstMatch
        XCTAssertTrue(edit.exists)
        edit.click()
        let launchTab = app.descendants(matching: .any)["editor.tab.launch"].firstMatch
        XCTAssertTrue(launchTab.waitForExistence(timeout: 3))
        launchTab.click()
        XCTAssertTrue(
            app.descendants(matching: .any)["editor.throttleAmount"]
                .firstMatch
                .waitForExistence(timeout: 3)
        )
        capture(window, named: "launchd-toc-editor.png")
    }

    private func capture(_ element: XCUIElement, named filename: String) {
        let attachment = XCTAttachment(screenshot: element.screenshot())
        attachment.name = filename
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

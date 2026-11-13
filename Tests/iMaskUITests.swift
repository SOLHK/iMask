import XCTest

final class iMaskUITests: XCTestCase {
    @MainActor
    func testControlsPreferencesAndDiagnosticExport() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["toggleMode"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["悬浮窗高刷"].exists)

        let mode = app.segmentedControls["windowMode"]
        mode.buttons["显示"].tap()
        app.terminate()
        app.launch()
        XCTAssertTrue(mode.buttons["显示"].waitForExistence(timeout: 10))
        XCTAssertTrue(mode.buttons["显示"].isSelected)
        mode.buttons["最小化"].tap()

        let diagnostics = app.buttons["openDiagnostics"]
        if !diagnostics.isHittable { app.swipeUp() }
        diagnostics.tap()
        XCTAssertTrue(app.buttons["exportDiagnostics"].waitForExistence(timeout: 10))
        let logging = app.switches["enableLogging"]
        if logging.value as? String == "0" { logging.tap() }
        app.buttons["exportDiagnostics"].tap()
        let file = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "iMask-diagnostics"))
            .firstMatch
        XCTAssertTrue(file.waitForExistence(timeout: 10))
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "高刷诊断导出"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

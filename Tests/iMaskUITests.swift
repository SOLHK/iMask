import XCTest

final class iMaskUITests: XCTestCase {
    @MainActor
    func testStartRestoreAndStopLiveActivity() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()

        // A previously interrupted test may have left an actual Live Activity behind.
        let stop = app.buttons["stopMask"]
        if stop.exists {
            stop.tap()
        }

        let start = app.buttons["startMask"]
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        XCTAssertTrue(start.isEnabled, "The simulator must allow Live Activities.")

        XCUIDevice.shared.press(.home)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        XCTAssertTrue(springboard.wait(for: .runningForeground, timeout: 10))
        attachScreenshot("桌面 · 活动未开启")
        app.activate()

        start.tap()
        assertStatus("运行中", in: app)
        attachScreenshot("iMask · 运行中")

        XCUIDevice.shared.press(.home)
        XCTAssertTrue(springboard.wait(for: .runningForeground, timeout: 10))
        attachScreenshot("桌面 · 活动运行中")
        app.terminate()
        app.launch()
        assertStatus("运行中", in: app)

        XCTAssertTrue(stop.exists)
        stop.tap()
        assertStatus("已关闭", in: app)

        app.terminate()
        app.launch()
        assertStatus("已关闭", in: app)
        XCTAssertTrue(app.buttons["startMask"].isEnabled)
    }

    @MainActor
    private func assertStatus(_ value: String, in app: XCUIApplication, line: UInt = #line) {
        let status = app.descendants(matching: .any)
            .matching(identifier: "maskStatus")
            .matching(NSPredicate(format: "value == %@", value))
            .firstMatch
        XCTAssertTrue(status.waitForExistence(timeout: 15), "Expected mask status \(value).", line: line)
    }

    @MainActor
    private func attachScreenshot(_ name: String) {
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}

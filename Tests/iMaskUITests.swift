import UIKit
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
        waitForHomeIcons(in: springboard)
        attachScreenshot("桌面 · 活动未开启")
        app.activate()

        start.tap()
        assertStatus("运行中", in: app)
        attachScreenshot("iMask · 运行中")

        XCUIDevice.shared.press(.home)
        XCTAssertTrue(springboard.wait(for: .runningForeground, timeout: 10))
        waitForHomeIcons(in: springboard)
        assertSystemIsland("桌面 · 活动运行中")

        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        settings.launch()
        assertSystemIsland("系统设置 · 活动运行中")

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
    private func waitForHomeIcons(in springboard: XCUIApplication) {
        let icon = springboard.icons["iMask"]
        let visible = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: icon)
        XCTAssertEqual(XCTWaiter.wait(for: [visible], timeout: 10), .completed)
    }

    @MainActor
    private func assertSystemIsland(_ name: String, line: UInt = #line) {
        let deadline = Date().addingTimeInterval(12)
        repeat {
            let screenshot = XCUIScreen.main.screenshot()
            if let image = screenshot.image.cgImage, hasBlackIsland(in: image) {
                attachScreenshot(name, screenshot: screenshot)
                return
            }
            Thread.sleep(forTimeInterval: 0.35)
        } while Date() < deadline

        attachScreenshot(name)
        XCTFail("No black system Island observed in \(name).", line: line)
    }

    private func hasBlackIsland(in image: CGImage) -> Bool {
        // The simulator captures the screen without drawing the physical camera cutout.
        // Check a centered 40×34pt band in the status bar, clear of the clock and battery.
        let scale = CGFloat(image.width) / UIScreen.main.bounds.width
        let width = Int(40 * scale)
        let height = Int(34 * scale)
        let region = CGRect(x: (image.width - width) / 2, y: Int(18 * scale), width: width, height: height)
        guard let strip = image.cropping(to: region) else { return false }
        var luminance = [UInt8](repeating: 255, count: width * height)
        return luminance.withUnsafeMutableBytes { bytes in
            guard let context = CGContext(
                data: bytes.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return false }
            context.draw(strip, in: CGRect(x: 0, y: 0, width: width, height: height))
            return bytes.lazy.filter { $0 <= 5 }.count > width * height / 3
        }
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
    private func attachScreenshot(_ name: String, screenshot: XCUIScreenshot? = nil) {
        let attachment = XCTAttachment(screenshot: screenshot ?? XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

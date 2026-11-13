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
        app.segmentedControls["maskWidth"].buttons["标准"].tap()

        XCUIDevice.shared.press(.home)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        XCTAssertTrue(springboard.wait(for: .runningForeground, timeout: 10))
        waitForHomeIcons(in: springboard)
        attachScreenshot("桌面 · 活动未开启")
        showNotificationCenter(in: springboard)
        let notificationsBefore = XCUIScreen.main.screenshot()
        attachScreenshot("通知中心 · 未开启", screenshot: notificationsBefore)
        XCUIDevice.shared.press(.home)
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
        // The system can change the outer width across contexts and transitions.
        // Compare all three presets in the same foreground app.
        let standardWidth = assertSystemIsland("系统设置 · 活动运行中")

        showNotificationCenter(in: settings)
        let allowActivity = springboard.buttons
            .matching(NSPredicate(format: "label IN %@", ["Allow", "允许"]))
            .firstMatch
        if allowActivity.waitForExistence(timeout: 5) {
            allowActivity.tap()
            let promptDismissed = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "exists == false"), object: allowActivity
            )
            XCTAssertEqual(XCTWaiter.wait(for: [promptDismissed], timeout: 10), .completed)
        }
        let notificationsActive = XCUIScreen.main.screenshot()
        attachScreenshot("通知中心 · 活动运行中", screenshot: notificationsActive)
        if let before = notificationsBefore.image.cgImage, let active = notificationsActive.image.cgImage {
            XCTAssertLessThanOrEqual(blackBarRows(in: active), blackBarRows(in: before) + 1,
                                     "The Live Activity must not add a black bar across Notification Center.")
        } else {
            XCTFail("Notification Center screenshots are unavailable.")
        }
        XCUIDevice.shared.press(.home)

        app.activate()
        app.segmentedControls["maskWidth"].buttons["加宽"].tap()
        settings.activate()
        let wideWidth = assertSystemIsland("系统设置 · 加宽", expectedWidth: standardWidth + 12)
        XCTAssertGreaterThan(wideWidth, standardWidth + 6)

        app.activate()
        app.segmentedControls["maskWidth"].buttons["较窄"].tap()
        settings.activate()
        let narrowWidth = assertSystemIsland("系统设置 · 较窄", expectedWidth: standardWidth - 12)
        XCTAssertLessThan(narrowWidth, standardWidth - 6)

        app.activate()
        app.segmentedControls["maskWidth"].buttons["标准"].tap()
        settings.activate()
        assertSystemIsland("系统设置 · 恢复标准", expectedWidth: standardWidth)

        app.terminate()
        app.launch()
        assertStatus("运行中", in: app)
        XCTAssertTrue(app.segmentedControls["maskWidth"].buttons["标准"].isSelected)

        XCTAssertTrue(stop.exists)
        stop.tap()
        assertStatus("已关闭", in: app)

        app.terminate()
        app.launch()
        assertStatus("已关闭", in: app)
        XCTAssertTrue(app.buttons["startMask"].isEnabled)

        let diagnostics = app.buttons["openDiagnostics"]
        if !diagnostics.isHittable { app.swipeUp() }
        XCTAssertTrue(diagnostics.waitForExistence(timeout: 10))
        diagnostics.tap()
        XCTAssertTrue(app.buttons["exportDiagnostics"].waitForExistence(timeout: 10))
        attachScreenshot("诊断页面")
        app.buttons["exportDiagnostics"].tap()
        let file = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "iMask-diagnostics"))
            .firstMatch
        XCTAssertTrue(file.waitForExistence(timeout: 10), "The share sheet must contain the exported diagnostic file.")
        attachScreenshot("诊断日志分享")
    }

    @MainActor
    private func showNotificationCenter(in app: XCUIApplication) {
        let top = app.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.005))
        let bottom = app.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.8))
        top.press(forDuration: 0.1, thenDragTo: bottom)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let homeCovered = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "hittable == false"), object: springboard.icons["iMask"]
        )
        XCTAssertEqual(XCTWaiter.wait(for: [homeCovered], timeout: 15), .completed)
    }

    private func blackBarRows(in image: CGImage) -> Int {
        let region = CGRect(x: Double(image.width) * 0.12, y: Double(image.height) * 0.45,
                            width: Double(image.width) * 0.76, height: Double(image.height) * 0.45)
        guard let crop = image.cropping(to: region) else { return 0 }
        let size = 64
        var pixels = [UInt8](repeating: 255, count: size * size)
        return pixels.withUnsafeMutableBytes { bytes in
            guard let context = CGContext(data: bytes.baseAddress, width: size, height: size,
                                          bitsPerComponent: 8, bytesPerRow: size,
                                          space: CGColorSpaceCreateDeviceGray(),
                                          bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return 0 }
            context.draw(crop, in: CGRect(x: 0, y: 0, width: size, height: size))
            return (0..<size).filter { row in
                bytes[(row * size)..<((row + 1) * size)].filter { $0 <= 8 }.count > size * 9 / 10
            }.count
        }
    }

    @MainActor
    private func waitForHomeIcons(in springboard: XCUIApplication) {
        let icon = springboard.icons["iMask"]
        let visible = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: icon)
        XCTAssertEqual(XCTWaiter.wait(for: [visible], timeout: 10), .completed)
    }

    @MainActor
    @discardableResult
    private func assertSystemIsland(_ name: String, expectedWidth: Double? = nil, line: UInt = #line) -> Double {
        let deadline = Date().addingTimeInterval(30)
        var lastWidth = 0.0
        var stableSamples = 0
        repeat {
            let screenshot = XCUIScreen.main.screenshot()
            if let image = screenshot.image.cgImage {
                let width = blackIslandWidth(in: image)
                let matchesExpected = expectedWidth.map { abs(width - $0) < 3 } ?? (width > 120)
                if matchesExpected {
                    stableSamples = abs(width - lastWidth) < 0.5 ? stableSamples + 1 : 1
                } else {
                    stableSamples = 0
                }
                lastWidth = width
                if stableSamples >= 2 {
                    attachScreenshot(name, screenshot: screenshot)
                    let measurement = XCTAttachment(string: "\(name) width=\(width)pt")
                    measurement.lifetime = .keepAlways
                    add(measurement)
                    return width
                }
            }
            Thread.sleep(forTimeInterval: 0.35)
        } while Date() < deadline

        attachScreenshot(name)
        XCTFail("No stable Island width in \(name). Last=\(lastWidth)pt, expected=\(String(describing: expectedWidth))pt.", line: line)
        return lastWidth
    }

    @MainActor
    private func blackIslandWidth(in image: CGImage) -> Double {
        // Sample through the pill's center, apart from the clock and battery.
        let scale = CGFloat(image.width) / UIScreen.main.bounds.width
        let width = image.width
        let region = CGRect(x: 0, y: Int(32 * scale), width: width, height: 1)
        guard let strip = image.cropping(to: region) else { return 0 }
        var luminance = [UInt8](repeating: 255, count: width)
        return luminance.withUnsafeMutableBytes { bytes in
            guard let context = CGContext(
                data: bytes.baseAddress, width: width, height: 1,
                bitsPerComponent: 8, bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return 0 }
            context.draw(strip, in: CGRect(x: 0, y: 0, width: width, height: 1))
            var left = width / 2
            var right = left
            while left > 0 && bytes[left - 1] <= 8 { left -= 1 }
            while right < width && bytes[right] <= 8 { right += 1 }
            return Double(right - left) / scale
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

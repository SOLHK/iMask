import Foundation
import XCTest

final class MaskDataTests: XCTestCase {
    func testRestoresVersionOneContentAndAllWidths() throws {
        let oldState = try JSONDecoder().decode(MaskAttributes.ContentState.self, from: Data("{}".utf8))
        XCTAssertEqual(oldState.effectiveWidth, .standard)
        for width in MaskWidth.allCases {
            let encoded = try JSONEncoder().encode(MaskAttributes.ContentState(width: width))
            let decoded = try JSONDecoder().decode(MaskAttributes.ContentState.self, from: encoded)
            XCTAssertEqual(decoded.effectiveWidth, width)
        }
    }

    @MainActor
    func testKeepsBoundedLogsAcrossRelaunchAndExportsText() throws {
        let directory = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let log = DiagnosticsLog(directory: directory)
        for index in 0..<260 { log.record("event.\(index)", "test") }
        XCTAssertNil(log.storageIssue)
        let restored = DiagnosticsLog(directory: directory)
        XCTAssertEqual(restored.entries.count, DiagnosticsLog.maximumEntries)
        XCTAssertEqual(restored.entries.first?.event, "event.4")
        XCTAssertEqual(restored.entries.last?.event, "event.259")
        let url = try restored.export(snapshot: "selectedWidth=wide")
        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(text.contains("selectedWidth=wide"))
        XCTAssertTrue(text.contains("export.prepared"))
        XCTAssertTrue(text.contains("event.259"))
    }

    @MainActor
    func testReportsLogStorageFailure() throws {
        let file = URL.temporaryDirectory.appending(path: UUID().uuidString)
        try Data("occupied".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let log = DiagnosticsLog(directory: file)
        log.record("activity.started")
        XCTAssertNotNil(log.storageIssue)
        XCTAssertEqual(log.entries.last?.event, "activity.started")
        XCTAssertTrue(log.report(snapshot: "").contains("保存诊断日志失败"))
    }
}

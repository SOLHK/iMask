import Foundation
import OSLog

@MainActor
final class DiagnosticsLog {
    struct Entry: Codable {
        let timestamp: Date
        let event: String
        let detail: String
    }

    static let maximumEntries = 256
    private(set) var entries: [Entry] = []
    private(set) var storageIssue: String?
    private let directory: URL
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "iMask", category: "Diagnostics")

    init(directory: URL = .applicationSupportDirectory.appending(path: "iMaskDiagnostics")) {
        self.directory = directory
        let file = directory.appending(path: "events.json")
        if FileManager.default.fileExists(atPath: file.path) {
            do {
                let saved = try JSONDecoder().decode([Entry].self, from: Data(contentsOf: file))
                entries = Array(saved.suffix(Self.maximumEntries))
            } catch {
                storageIssue = "读取历史日志失败。\(error.localizedDescription)"
                logger.error("Reading diagnostics failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func record(_ event: String, _ detail: String = "") {
        entries.append(Entry(timestamp: .now, event: event, detail: detail))
        if entries.count > Self.maximumEntries {
            entries.removeFirst(entries.count - Self.maximumEntries)
        }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try JSONEncoder().encode(entries).write(to: directory.appending(path: "events.json"), options: .atomic)
        } catch {
            storageIssue = "保存诊断日志失败。\(error.localizedDescription)"
            logger.error("Saving diagnostics failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func recordError(_ event: String, _ error: Error) {
        let nsError = error as NSError
        record(event, "\(String(describing: error)); domain=\(nsError.domain); code=\(nsError.code); \(nsError.localizedDescription)")
    }

    func report(snapshot: String) -> String {
        let events = entries.map {
            "[\($0.timestamp.ISO8601Format())] \($0.event) \($0.detail)"
        }.joined(separator: "\n")
        return """
        iMask 诊断报告
        schemaVersion=1
        generatedAt=\(Date.now.ISO8601Format())

        \(snapshot)

        诊断范围
        活动状态来自 ActivityKit，运行中代表系统会话有效。
        当前可见性、系统最终宽高和结束原因均未由公开 API 提供。
        日志仅包含本 App 的事件、设备类型和运行环境，保存在本机。
        appStorage=\(storageIssue ?? "正常")

        最近事件（最多 \(Self.maximumEntries) 条）
        \(events)
        """
    }

    func export(snapshot: String) throws -> URL {
        record("export.prepared", "用户请求导出诊断")
        // A single export file bounds disk use. The share sheet owns access until dismissal.
        let destination = URL.cachesDirectory.appending(path: "iMaskExports", directoryHint: .isDirectory)
        let file = destination.appending(path: "iMask-diagnostics.txt")
        do {
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            try report(snapshot: snapshot).write(to: file, atomically: true, encoding: .utf8)
            return file
        } catch {
            recordError("export.failed", error)
            throw error
        }
    }
}

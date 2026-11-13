import Foundation
import Combine

/// One opt-in switch shared by the app and the imported diagnostic modules.
/// Functional preferences and ActivityKit/PiP state remain independent of this gate.
enum DiagnosticRecording {
    private static let lock = NSLock()
    private static var enabled = UserDefaults.standard.bool(forKey: "imask.diagnostics.enabled")
    static var isEnabled: Bool {
        get { lock.lock(); defer { lock.unlock() }; return enabled }
        set {
            lock.lock(); enabled = newValue; lock.unlock()
            UserDefaults.standard.set(newValue, forKey: "imask.diagnostics.enabled")
        }
    }
}

@MainActor
final class DiagnosticsLog: ObservableObject {
    struct Entry: Codable {
        let timestamp: Date
        let event: String
        let detail: String
    }
    static let maximumEntries = 256
    @Published private(set) var isEnabled = DiagnosticRecording.isEnabled
    private(set) var entries: [Entry] = []
    private(set) var storageIssue: String?
    private let directory: URL
    private var dirty = false

    init(directory: URL = .applicationSupportDirectory.appending(path: "iMaskDiagnostics")) {
        self.directory = directory
        let file = directory.appending(path: "events.json")
        if FileManager.default.fileExists(atPath: file.path) {
            do {
                let saved = try JSONDecoder().decode([Entry].self, from: Data(contentsOf: file))
                entries = Array(saved.suffix(Self.maximumEntries))
            } catch { storageIssue = "读取历史日志失败。\(error.localizedDescription)" }
        }
    }

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        if enabled {
            DiagnosticRecording.isEnabled = true
            isEnabled = true
            record("recording.started")
            flush()
        } else {
            record("recording.stopped")
            flush()
            DiagnosticRecording.isEnabled = false
            isEnabled = false
        }
    }

    func record(_ event: String, _ detail: @autoclosure () -> String = "") {
        guard DiagnosticRecording.isEnabled else { return }
        entries.append(Entry(timestamp: .now, event: event, detail: detail()))
        if entries.count > Self.maximumEntries { entries.removeFirst(entries.count - Self.maximumEntries) }
        dirty = true
    }

    func flush() {
        guard DiagnosticRecording.isEnabled, dirty else { return }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try JSONEncoder().encode(entries).write(to: directory.appending(path: "events.json"), options: .atomic)
            dirty = false
            storageIssue = nil
        } catch { storageIssue = "保存诊断日志失败。\(error.localizedDescription)" }
    }

    func recordError(_ event: String, _ error: Error) {
        guard DiagnosticRecording.isEnabled else { return }
        let nsError = error as NSError
        record(event, "\(String(describing: error)); domain=\(nsError.domain); code=\(nsError.code); \(nsError.localizedDescription)")
    }

    func report(snapshot: String) -> String {
        let events = entries.map { "[\($0.timestamp.ISO8601Format())] \($0.event) \($0.detail)" }.joined(separator: "\n")
        return """
        iMask 诊断报告
        schemaVersion=4
        generatedAt=\(Date.now.ISO8601Format())
        loggingEnabled=\(isEnabled)

        \(snapshot)

        诊断范围
        仅开启日志期间记录事件、回调采样和电量变化，关闭后停止累计。
        帧率采样来自本进程的 CADisplayLink 回调，不代表屏幕物理刷新率或其他 App 的帧率。
        电量变化是整机观测值，不能归因于 iMask；充电、采样中断和系统调度会影响统计。
        ActivityKit active 不代表灵动岛当前一定可见。数据只保存在本机。
        appStorage=\(storageIssue ?? "正常")

        最近事件（最多 \(Self.maximumEntries) 条）
        \(events)
        """
    }

    func export(snapshot: String) throws -> URL {
        record("export.prepared", "用户请求导出诊断")
        flush()
        let destination = URL.cachesDirectory.appending(path: "iMaskExports", directoryHint: .isDirectory)
        let file = destination.appending(path: "iMask-diagnostics.txt")
        do {
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            try report(snapshot: snapshot).write(to: file, atomically: true, encoding: .utf8)
            return file
        } catch { recordError("export.failed", error); throw error }
    }
}

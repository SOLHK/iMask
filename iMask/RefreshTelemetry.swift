import SwiftUI
import UIKit

/// Uses the existing render callbacks; never creates a display link to measure FPS.
@MainActor
final class RefreshTelemetry {
    static let shared = RefreshTelemetry()
    private struct Frames {
        var intervals = 0
        var seconds = 0.0
        var minimumMS: Double?
        var maximumMS: Double?
        var longIntervals = 0
        var gaps = 0
        var requestedFPS = 0.0
        var schedulerFPS = 0.0
        var previous: Double?
        mutating func add(_ link: CADisplayLink) {
            let timestamp = link.timestamp
            let scheduled = link.targetTimestamp - timestamp
            schedulerFPS = scheduled > 0 ? 1 / scheduled : 0
            requestedFPS = Double(link.preferredFrameRateRange.preferred > 0
                ? link.preferredFrameRateRange.preferred : Float(link.preferredFramesPerSecond))
            defer { previous = timestamp }
            guard let previous else { return }
            let delta = timestamp - previous
            guard delta > 0, delta < 0.5 else { gaps += 1; return }
            intervals += 1
            seconds += delta
            minimumMS = min(minimumMS ?? delta * 1_000, delta * 1_000)
            maximumMS = max(maximumMS ?? delta * 1_000, delta * 1_000)
            if scheduled > 0, delta > scheduled * 1.5 { longIntervals += 1 }
        }
        var summary: String {
            "callbacks=\(intervals); sampledSeconds=\(String(format: "%.2f", seconds)); averageCallbackFPS=\(seconds > 0 ? String(format: "%.2f", Double(intervals) / seconds) : "unavailable"); minIntervalMS=\(minimumMS.map { String(format: "%.3f", $0) } ?? "unavailable"); maxIntervalMS=\(maximumMS.map { String(format: "%.3f", $0) } ?? "unavailable"); longIntervals=\(longIntervals); gaps=\(gaps); requestedFPS=\(requestedFPS); schedulerEstimateFPS=\(String(format: "%.2f", schedulerFPS))"
        }
    }

    private var frames: [String: Frames] = [:]
    private var startedAt: Date?
    private var stoppedAt: Date?
    private var lastAccountedAt: Date?
    private var runtime: [String: TimeInterval] = [:]
    private var mode = "floatingWindow"
    private var foreground = true
    private var pip = false
    private var island = false
    private var audio = false
    private var timer: Timer?
    private var observerTokens: [NSObjectProtocol] = []
    private var batteryStart: Float?
    private var batteryLast: Float?
    private var batterySamples = 0
    private var observedDrop: Double = 0
    private var observedDischargeSeconds: TimeInterval = 0
    private var previousBattery: (level: Float, state: UIDevice.BatteryState, date: Date)?
    private var chargingObserved = false
    private var frozenReport = "尚未开启日志，未采样刷新与耗电数据。"
    private weak var log: DiagnosticsLog?
    private let file = URL.applicationSupportDirectory.appending(path: "iMaskDiagnostics/refresh-power.txt")

    init() {
        if let saved = try? String(contentsOf: file, encoding: .utf8) { frozenReport = saved }
    }

    func start(log: DiagnosticsLog) {
        guard DiagnosticRecording.isEnabled, startedAt == nil || stoppedAt != nil else { return }
        self.log = log
        frames = [:]
        runtime = [:]
        startedAt = .now
        stoppedAt = nil
        lastAccountedAt = .now
        batteryStart = nil
        batteryLast = nil
        previousBattery = nil
        batterySamples = 0
        observedDrop = 0
        observedDischargeSeconds = 0
        chargingObserved = false
        UIDevice.current.isBatteryMonitoringEnabled = true
        let center = NotificationCenter.default
        for name in [UIDevice.batteryLevelDidChangeNotification, UIDevice.batteryStateDidChangeNotification,
                     ProcessInfo.thermalStateDidChangeNotification, Notification.Name.NSProcessInfoPowerStateDidChange] {
            observerTokens.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.checkpoint(persist: false) }
            })
        }
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkpoint(persist: true) }
        }
        timer.tolerance = 10
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        checkpoint(persist: true)
    }

    func stop() {
        guard startedAt != nil, stoppedAt == nil else { return }
        checkpoint(persist: false)
        stoppedAt = .now
        account(until: stoppedAt!)
        frozenReport = makeReport()
        persist()
        timer?.invalidate()
        timer = nil
        observerTokens.forEach(NotificationCenter.default.removeObserver)
        observerTokens.removeAll()
        UIDevice.current.isBatteryMonitoringEnabled = false
        lastAccountedAt = nil
    }

    func record(_ link: CADisplayLink, source: String) {
        guard DiagnosticRecording.isEnabled, startedAt != nil, stoppedAt == nil else { return }
        frames[source, default: Frames()].add(link)
    }

    func update(mode: String? = nil, foreground: Bool? = nil, pip: Bool? = nil, island: Bool? = nil, audio: Bool? = nil) {
        if DiagnosticRecording.isEnabled, startedAt != nil, stoppedAt == nil { account(until: .now) }
        if let mode { self.mode = mode }
        if let foreground {
            self.foreground = foreground
            // A foreground/background gap is not a dropped frame.
            for key in Array(frames.keys) { frames[key]?.previous = nil }
        }
        if let pip { self.pip = pip }
        if let island { self.island = island }
        if let audio { self.audio = audio }
    }

    func checkpoint(persist shouldPersist: Bool) {
        guard DiagnosticRecording.isEnabled, startedAt != nil, stoppedAt == nil else { return }
        account(until: .now)
        sampleBattery()
        let process = PerformanceDiagnosticsLogger.lightweightProcessSnapshot()
        log?.record("telemetry.sample", "mode=\(mode); battery=\(batteryLast.map { String(format: "%.0f", $0 * 100) } ?? "unavailable"); thermal=\(ProcessInfo.processInfo.thermalState.rawValue); lowPower=\(ProcessInfo.processInfo.isLowPowerModeEnabled); footprintMB=\(process.physicalFootprintMB); threads=\(process.threadCount)")
        frozenReport = makeReport()
        if shouldPersist { persist(); log?.flush() }
    }

    var report: String {
        if DiagnosticRecording.isEnabled, startedAt != nil, stoppedAt == nil {
            account(until: .now)
            return makeReport()
        }
        return frozenReport
    }

    private func account(until date: Date) {
        guard let lastAccountedAt else { self.lastAccountedAt = date; return }
        let seconds = max(0, date.timeIntervalSince(lastAccountedAt))
        runtime[foreground ? "foreground" : "background", default: 0] += seconds
        if pip { runtime["pip", default: 0] += seconds }
        if island { runtime["island", default: 0] += seconds }
        if audio { runtime["audio", default: 0] += seconds }
        runtime["mode.\(mode)", default: 0] += seconds
        self.lastAccountedAt = date
    }

    private func sampleBattery() {
        let device = UIDevice.current
        let now = Date.now
        let level = device.batteryLevel
        guard level >= 0 else { return }
        batterySamples += 1
        if batteryStart == nil { batteryStart = level }
        batteryLast = level
        let state = device.batteryState
        if state == .charging || state == .full { chargingObserved = true }
        if let previousBattery, previousBattery.state == .unplugged, state == .unplugged {
            observedDrop += Double(max(0, previousBattery.level - level)) * 100
            observedDischargeSeconds += max(0, now.timeIntervalSince(previousBattery.date))
        }
        previousBattery = (level, state, now)
    }

    private func makeReport() -> String {
        let rate = observedDischargeSeconds >= 300
            ? String(format: "%.3f", observedDrop / observedDischargeSeconds * 3_600) : "unavailable (less than 5 minutes)"
        let frameLines = frames.keys.sorted().map { "\($0): \(frames[$0]!.summary)" }.joined(separator: "\n")
        let runtimeLines = runtime.keys.sorted().map { "\($0)Seconds=\(String(format: "%.1f", runtime[$0]!))" }.joined(separator: "\n")
        return """
        刷新与电量统计（仅日志开启期间）
        recordingStartedAt=\(startedAt?.ISO8601Format() ?? "none")
        recordingStoppedAt=\(stoppedAt?.ISO8601Format() ?? "recording")
        screenMaximumFPS=\(UIScreen.main.maximumFramesPerSecond)
        lowPowerMode=\(ProcessInfo.processInfo.isLowPowerModeEnabled)
        thermalState=\(ProcessInfo.processInfo.thermalState.rawValue)
        reduceMotion=\(UIAccessibility.isReduceMotionEnabled)
        globalDisplayRefreshRate=unavailable
        otherAppFPS=unavailable
        \(frameLines.isEmpty ? "尚无回调采样" : frameLines)
        \(runtimeLines)
        batteryStartPercent=\(batteryStart.map { String(format: "%.1f", $0 * 100) } ?? "unavailable")
        batteryLastPercent=\(batteryLast.map { String(format: "%.1f", $0 * 100) } ?? "unavailable")
        batterySamples=\(batterySamples)
        chargingObserved=\(chargingObserved)
        observedUnpluggedDropPercentagePoints=\(String(format: "%.3f", observedDrop))
        observedUnpluggedSeconds=\(String(format: "%.1f", observedDischargeSeconds))
        wholeDevicePercentagePointsPerHour=\(rate)
        appExclusiveEnergy=unavailable
        实际回调频率不等于物理屏幕刷新率。电量变化来自整机，短时统计受电量读数精度影响；后台暂停期间可能漏过充电变化。
        """
    }

    private func persist() {
        guard DiagnosticRecording.isEnabled else { return }
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try frozenReport.write(to: file, atomically: true, encoding: .utf8)
        } catch { log?.recordError("telemetry.saveFailed", error) }
    }
}

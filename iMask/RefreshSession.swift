import Darwin
import SwiftUI
import UIKit

struct RefreshEngineState {
    var active = false
    var transitioning = false
    var suspended = false
    var title = "准备就绪"
    var route: PiPEngineRoute = .videoCall
    var policy: KeepAlivePolicy = .pipOnly
    var height: Double = 44
    var minimumHeight: Double = 0.1
    var maximumHeight: Double = 220
    var scrolling = true
    var clock = false
    var clockAvailable = false
    var rememberHeight = true
    var closeConfirmation = false
    var stoppedNotification = false
    var extremeSilent = false
    var contentExtreme = false
    var runtime = "—"
}

struct FloatingWindowProfile: Codable {
    var route: String
    var policy: String
    var height: Double
    var scrolling: Bool
    var clock: Bool
    var extremeSilent: Bool
    var contentExtreme: Bool
}

/// UI adapter only. PiP creation, recovery, audio and hiding stay in the upstream engine.
@MainActor
final class RefreshSession: NSObject, ObservableObject {
    @Published private(set) var engine = RefreshEngineState()
    @Published private(set) var foregroundFPS: Double?
    @Published private(set) var isMinimized = false
    @Published private(set) var loggingEnabled = DiagnosticRecording.isEnabled
    @Published private(set) var shortcutsEnabled = PiPShortcutFeatureAccess.isEnabled

    let diagnostics = DiagnosticsLog()
    let controller = ViewController()
    let screenMaximum = UIScreen.main.maximumFramesPerSecond
    var onShortcutRequested: (() -> Void)?
    var onEngineStateChanged: (() -> Void)?
    private let profileKey = "imask.floatingProfile.beforeIsland"
    private var foregroundLink: CADisplayLink?
    private lazy var displayTarget = ForegroundDisplayTarget(owner: self)
    private var isForeground = false
    private var sampleStart: CFTimeInterval = 0
    private var sampledFrames = 0

    override init() {
        super.init()
        CacheCleanupManager.cleanOnLaunch()
        KeepAliveModeText.migrateDefaultToLowPowerPiPIfNeeded()
        DemoFrameRatePreference.migrateLegacySettingIfNeeded()
        GeneratedPiPVideoCache.prepareForLaunch()
        PiPShortcutRuntimeRegistration.warmUpProviderIfAvailable()
        DebugDiagnosticsMonitor.setEnabled(false)
        MetricKitLogger.shared.stop()
        AppDebugLogger.isDebugModeEnabled = loggingEnabled
        if loggingEnabled { beginRecording() }
        controller.imaskDidChange = { [weak self] in
            DispatchQueue.main.async { self?.synchronize() }
        }
        controller.imaskDidAppear = { [weak self] in self?.performPendingShortcut() }
        NotificationCenter.default.addObserver(self, selector: #selector(shortcutRequested),
            name: PiPShortcutActionCenter.didRequestActionNotification, object: nil)
        diagnostics.record("app.launched", "version=2.3; engine=GlobalRefresh-PiP; upstream=1b62341")
    }

    deinit {
        foregroundLink?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }

    var isRunning: Bool { engine.active }
    var canStop: Bool { engine.active }
    var isTransitioning: Bool { engine.transitioning }
    var hasIslandDriverProfile: Bool { UserDefaults.standard.data(forKey: profileKey) != nil }

    func start() {
        diagnostics.record("pip.startRequested", "route=\(engine.route.rawValue); policy=\(engine.policy.rawValue); hidden=\(isMinimized)")
        controller.imaskStart(hidden: isMinimized)
        synchronize()
    }

    func stop() {
        diagnostics.record("pip.stopRequested")
        controller.imaskToggle()
        synchronize()
    }

    func startAndHide() {
        controller.imaskStartAndHide()
        synchronize()
    }

    func setMinimized(_ value: Bool) {
        controller.imaskSetHeight(value ? engine.minimumHeight : 44)
        synchronize()
    }

    func setHeight(_ value: Double) {
        controller.imaskPreviewHeight(value)
        synchronize()
    }

    func commitHeight() { controller.imaskSetHeight(engine.height) }

    func setRoute(_ route: PiPEngineRoute) {
        controller.imaskSetRoute(route)
        synchronize()
    }

    func setPolicy(_ policy: KeepAlivePolicy) {
        KeepAlivePolicy.current = policy
        NotificationCenter.default.post(name: ViewController.iOS26KeepAliveModeDidChangeNotification, object: nil)
        synchronize()
    }

    func setOption(_ option: String, _ enabled: Bool) {
        controller.imaskSetOption(option, enabled)
        synchronize()
    }

    func setLogging(_ enabled: Bool) {
        guard enabled != loggingEnabled else { return }
        if enabled {
            diagnostics.setEnabled(true)
            AppDebugLogger.isDebugModeEnabled = true
            beginRecording()
        } else {
            RefreshTelemetry.shared.stop()
            PowerUsageLogger.stopRecording()
            LightweightRuntimeDiagnostics.stop()
            AppDebugLogger.flushSynchronously()
            DiagnosticsRuntimeState.stopAppStateTracking()
            DebugDiagnosticsMonitor.setEnabled(false)
            MetricKitLogger.shared.stop()
            diagnostics.setEnabled(false)
            AppDebugLogger.isDebugModeEnabled = false
            UIDevice.current.isBatteryMonitoringEnabled = false
            foregroundFPS = nil
            sampleStart = 0
            sampledFrames = 0
        }
        loggingEnabled = enabled
    }

    private func beginRecording() {
        AppDebugLogger.trimOnLaunch()
        AppDebugLogger.registerBackgroundFlush()
        LightweightRuntimeDiagnostics.start()
        PowerUsageLogger.startFreshStatistics()
        PowerUsageLogger.markLaunch()
        if engine.active { PowerUsageLogger.markPiPStart() }
        if BackgroundTaskManager.shared.isPlaying { PowerUsageLogger.markKeepAliveStart() }
        KeepAliveLogger.resetLogs()
        if engine.active { KeepAliveLogger.markPiPStarted(mode: KeepAlivePolicy.current.diagnosticsName) }
        RefreshTelemetry.shared.start(log: diagnostics)
    }

    func prepareIslandDriver() {
        let defaults = UserDefaults.standard
        if defaults.data(forKey: profileKey) == nil {
            let state = controller.imaskState
            let profile = FloatingWindowProfile(route: state.route.rawValue, policy: state.policy.rawValue,
                height: state.height, scrolling: state.scrolling, clock: state.clock,
                extremeSilent: state.extremeSilent, contentExtreme: state.contentExtreme)
            do { defaults.set(try JSONEncoder().encode(profile), forKey: profileKey) }
            catch { diagnostics.recordError("islandDriver.profileSaveFailed", error) }
        }
        controller.imaskApplyProfile(FloatingWindowProfile(route: "videoCall", policy: "pipOnly", height: 0.1,
            scrolling: true, clock: false, extremeSilent: false, contentExtreme: false))
        synchronize()
    }

    func restoreFloatingProfile() {
        guard let data = UserDefaults.standard.data(forKey: profileKey) else { return }
        do {
            controller.imaskApplyProfile(try JSONDecoder().decode(FloatingWindowProfile.self, from: data))
            UserDefaults.standard.removeObject(forKey: profileKey)
            synchronize()
        } catch { diagnostics.recordError("islandDriver.profileRestoreFailed", error) }
    }

    func waitForIslandDriver() async -> Bool {
        for _ in 0..<150 {
            refresh()
            if controller.imaskIslandDriverReady { return true }
            do { try await Task.sleep(for: .milliseconds(100)) } catch { return false }
        }
        diagnostics.record("islandDriver.startTimeout", "active=\(engine.active); height=\(engine.height)")
        return false
    }

    func setShortcuts(_ enabled: Bool) {
        PiPShortcutFeatureAccess.setEnabled(enabled)
        shortcutsEnabled = enabled
    }

    func sceneChanged(_ phase: ScenePhase) {
        isForeground = phase == .active
        RefreshTelemetry.shared.update(foreground: isForeground)
        if phase == .background {
            RefreshTelemetry.shared.checkpoint(persist: true)
            diagnostics.flush()
        }
        diagnostics.record("scene.changed", String(describing: phase))
        updateForegroundProbe()
        if isForeground {
            refresh()
            shortcutRequested()
        }
    }

    @objc nonisolated private func shortcutRequested() {
        Task { @MainActor [weak self] in self?.performPendingShortcut() }
    }

    private func performPendingShortcut() {
        onShortcutRequested?()
    }

    func runPendingShortcut() {
        guard controller.isViewLoaded, controller.view.window != nil else { return }
        _ = controller.performPendingShortcutActionIfNeeded(reason: "iMask")
        synchronize()
    }

    func waitForSourceView() async -> Bool {
        for _ in 0..<40 {
            if controller.isViewLoaded, controller.view.window != nil, !controller.view.bounds.isEmpty { return true }
            do { try await Task.sleep(for: .milliseconds(50)) } catch { return false }
        }
        return false
    }

    func stopAndReleaseForModeChange() async -> Bool {
        // Let any already-submitted AVKit start finish before requesting its matching stop.
        for _ in 0..<150 {
            refresh()
            if !engine.transitioning { break }
            do { try await Task.sleep(for: .milliseconds(100)) } catch { return false }
        }
        guard !engine.transitioning else {
            diagnostics.record("mode.pipTransitionTimeout")
            return false
        }
        controller.imaskRequestModeStop()
        for _ in 0..<150 {
            refresh()
            if controller.imaskFinishModeStop() {
                synchronize()
                diagnostics.record("mode.pipReleased", "pip=false; audio=\(BackgroundTaskManager.shared.isPlaying)")
                return true
            }
            do { try await Task.sleep(for: .milliseconds(100)) } catch { break }
        }
        controller.imaskCancelModeStop()
        diagnostics.record("mode.pipStopTimeout", "active=\(engine.active); transitioning=\(engine.transitioning)")
        return false
    }

    func open(_ url: URL) {
        _ = PiPShortcutActionCenter.request(from: url)
        shortcutRequested()
    }

    func refresh() {
        controller.imaskRefresh()
        synchronize()
    }

    private func synchronize() {
        let actual = controller.imaskState
        if actual.active != engine.active || actual.transitioning != engine.transitioning {
            diagnostics.record("pip.stateChanged", "active=\(actual.active); transitioning=\(actual.transitioning)")
        }
        engine = actual
        RefreshTelemetry.shared.update(pip: actual.active, audio: BackgroundTaskManager.shared.isPlaying)
        isMinimized = engine.height <= engine.minimumHeight + 0.01
        updateForegroundProbe()
        onEngineStateChanged?()
    }

    private func updateForegroundProbe() {
        guard isForeground, engine.active else {
            foregroundLink?.invalidate()
            foregroundLink = nil
            foregroundFPS = nil
            return
        }
        guard foregroundLink == nil else { return }
        sampleStart = 0
        sampledFrames = 0
        let link = CADisplayLink(target: displayTarget, selector: #selector(ForegroundDisplayTarget.sample(_:)))
        DemoFrameRatePreference.configureForegroundRequest(link)
        link.add(to: .main, forMode: .common)
        foregroundLink = link
    }

    fileprivate func sample(_ link: CADisplayLink) {
        guard DiagnosticRecording.isEnabled else { return }
        RefreshTelemetry.shared.record(link, source: "foreground")
        guard sampleStart != 0 else { sampleStart = link.timestamp; return }
        sampledFrames += 1
        let elapsed = link.timestamp - sampleStart
        if elapsed >= 1 {
            foregroundFPS = Double(sampledFrames) / elapsed
            sampledFrames = 0
            sampleStart = link.timestamp
        }
    }

    var diagnosticSnapshot: String {
        var machine = utsname()
        uname(&machine)
        let model = withUnsafeBytes(of: &machine.machine) { String(decoding: $0.prefix(while: { $0 != 0 }), as: UTF8.self) }
        return """
        appVersion=\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] ?? "?")
        appBuild=\(Bundle.main.infoDictionary?["CFBundleVersion"] ?? "?")
        bundleIdentifier=\(Bundle.main.bundleIdentifier ?? "?")
        deviceModel=\(ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? model)
        systemVersion=\(ProcessInfo.processInfo.operatingSystemVersionString)
        engine=GlobalRefresh-PiP
        upstreamCommit=1b62341c1d62308962fb3656192d6783631aa00c
        route=\(engine.route.rawValue)
        keepAlivePolicy=\(engine.policy.rawValue)
        pipActive=\(engine.active)
        pipHeight=\(engine.height)
        audioPlayback=\(BackgroundTaskManager.shared.isPlaying)
        foregroundCallbackFPS=\(foregroundFPS.map { String(format: "%.1f", $0) } ?? "unavailable")
        globalDisplayRefreshRate=unavailable

        \(controller.imaskDiagnostics)

        原项目运行日志
        \(AppDebugLogger.exportText())

        \(RefreshTelemetry.shared.report)
        """
    }
}

@MainActor
private final class ForegroundDisplayTarget: NSObject {
    weak var owner: RefreshSession?
    init(owner: RefreshSession) { self.owner = owner }
    @objc func sample(_ link: CADisplayLink) { owner?.sample(link) }
}

struct RefreshPreview: UIViewControllerRepresentable {
    let session: RefreshSession
    func makeUIViewController(context: Context) -> ViewController { session.controller }
    func updateUIViewController(_ controller: ViewController, context: Context) {}
}

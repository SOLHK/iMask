import ActivityKit
import AVKit
import Darwin
import SwiftUI
import UIKit

/// Public VideoCall PiP path, using GlobalRefresh-PiP's content-only profile.
@MainActor
final class RefreshSession: NSObject, ObservableObject, AVPictureInPictureControllerDelegate {
    enum Phase: String {
        case idle, preparing, starting, running, stopping, stopped, failed

        var title: String {
            switch self {
            case .idle: return "准备就绪"
            case .preparing: return "准备画中画"
            case .starting: return "正在开启"
            case .running: return "运行中"
            case .stopping: return "正在停止"
            case .stopped: return "已停止"
            case .failed: return "开启失败"
            }
        }
    }

    static let upstreamCommit = "1b62341c1d62308962fb3656192d6783631aa00c"
    static let contentFramesPerSecond = 60
    static let contentWidth: CGFloat = 300
    static let hiddenHeight: CGFloat = 0.1
    static let visibleHeight: CGFloat = 44

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var isMinimized: Bool
    @Published private(set) var foregroundFPS: Double?
    @Published private(set) var screenMaximum = UIScreen.main.maximumFramesPerSecond
    @Published private(set) var isSuspended = false
    @Published private(set) var message: String?

    let diagnostics = DiagnosticsLog()
    private weak var sourceView: RefreshSurfaceView?
    private var contentController: AVPictureInPictureVideoCallViewController?
    private var renderView: RefreshSurfaceView?
    private var controller: AVPictureInPictureController?
    private var possibilityObservation: NSKeyValueObservation?
    private var suspensionObservation: NSKeyValueObservation?
    private var transitionTask: Task<Void, Never>?
    private var renderLink: CADisplayLink?
    private var foregroundLink: CADisplayLink?
    private lazy var displayTarget = DisplayTarget(owner: self)
    private var wantsRunning = false
    private var hasRequestedStart = false
    private var isForeground = false
    private var migratedLegacyActivities = false
    private var startedAt: Date?
    private var sampleStart: CFTimeInterval = 0
    private var sampledFrames = 0
    private var renderTicks = 0
    private var lastRenderedAt: Date?
    private var lastRenderLog: CFTimeInterval = 0

    var isRunning: Bool { phase == .running }
    var canStop: Bool { wantsRunning || phase == .running || phase == .starting || phase == .preparing }
    var isTransitioning: Bool { phase == .preparing || phase == .starting || phase == .stopping }
    var requestedSize: CGSize {
        CGSize(width: Self.contentWidth, height: isMinimized ? Self.hiddenHeight : Self.visibleHeight)
    }

    override init() {
        isMinimized = UserDefaults.standard.object(forKey: "refresh.minimized") as? Bool ?? true
        super.init()
        diagnostics.record("app.launched", "version=2.0; engine=videoCall; profile=contentOnly60")
    }

    deinit {
        renderLink?.invalidate()
        foregroundLink?.invalidate()
        transitionTask?.cancel()
    }

    func attach(_ view: RefreshSurfaceView) {
        sourceView = view
        let maximum = view.window?.screen.maximumFramesPerSecond ?? UIScreen.main.maximumFramesPerSecond
        if screenMaximum != maximum { screenMaximum = maximum }
    }

    func start() {
        guard !canStop, phase != .stopping else { return }
        guard AVPictureInPictureController.isPictureInPictureSupported() else {
            fail("设备当前不支持画中画。", event: "pip.unsupported")
            return
        }
        guard let sourceView, sourceView.window != nil, !sourceView.bounds.isEmpty else {
            fail("画面尚未就绪，请返回首页重试。", event: "pip.sourceUnavailable")
            return
        }

        releaseController()
        message = nil
        wantsRunning = true
        hasRequestedStart = false
        phase = .preparing
        renderTicks = 0
        lastRenderedAt = nil
        lastRenderLog = 0

        let content = AVPictureInPictureVideoCallViewController()
        content.preferredContentSize = requestedSize
        content.view.frame = CGRect(origin: .zero, size: requestedSize)
        content.view.backgroundColor = .clear
        content.view.isOpaque = false
        content.view.clipsToBounds = true
        let surface = RefreshSurfaceView(frame: CGRect(origin: .zero, size: requestedSize))
        surface.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        content.view.addSubview(surface)
        contentController = content
        renderView = surface

        let source = AVPictureInPictureController.ContentSource(
            activeVideoCallSourceView: sourceView,
            contentViewController: content
        )
        let pip = AVPictureInPictureController(contentSource: source)
        pip.delegate = self
        pip.requiresLinearPlayback = true
        pip.canStartPictureInPictureAutomaticallyFromInline = false
        controller = pip

        possibilityObservation = pip.observe(\.isPictureInPicturePossible, options: [.initial, .new]) { [weak self] pip, _ in
            Task { @MainActor in
                guard let self, self.controller === pip else { return }
                self.diagnostics.record("pip.possibilityChanged", "possible=\(pip.isPictureInPicturePossible)")
                self.startWhenPossible()
            }
        }
        suspensionObservation = pip.observe(\.isPictureInPictureSuspended, options: [.new]) { [weak self] pip, _ in
            Task { @MainActor in
                guard let self, self.controller === pip else { return }
                self.isSuspended = pip.isPictureInPictureSuspended
                self.diagnostics.record("pip.suspensionChanged", "suspended=\(self.isSuspended)")
            }
        }

        startRenderLink()
        updateForegroundProbe()
        diagnostics.record("pip.startRequested", "size=\(requestedSize); contentFPS=60; source=publicVideoCall")
        armTransitionTimeout()
        startWhenPossible()
    }

    private func startWhenPossible() {
        guard wantsRunning, !hasRequestedStart, let controller,
              controller.isPictureInPicturePossible else { return }
        hasRequestedStart = true
        phase = .starting
        controller.startPictureInPicture()
    }

    func stop() {
        guard canStop else { return }
        wantsRunning = false
        diagnostics.record("pip.stopRequested")
        if hasRequestedStart {
            phase = .stopping
            armTransitionTimeout()
            controller?.stopPictureInPicture()
        } else {
            finishStop()
        }
    }

    func setMinimized(_ value: Bool) {
        guard isMinimized != value else { return }
        isMinimized = value
        UserDefaults.standard.set(value, forKey: "refresh.minimized")
        contentController?.preferredContentSize = requestedSize
        diagnostics.record("pip.sizeChanged", "requested=\(requestedSize)")
    }

    private func armTransitionTimeout() {
        transitionTask?.cancel()
        transitionTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(12)) } catch { return }
            guard let self, self.isTransitioning else { return }
            if self.phase == .stopping {
                self.diagnostics.record("pip.stopTimedOut", "active=\(self.controller?.isPictureInPictureActive ?? false)")
                self.finishStop()
            } else {
                self.fail("画中画未能启动，请检查系统画中画设置后重试。", event: "pip.startTimedOut")
            }
        }
    }

    private func fail(_ text: String, event: String) {
        wantsRunning = false
        releaseController()
        phase = .failed
        message = text
        diagnostics.record(event, text)
    }

    private func finishStop() {
        wantsRunning = false
        releaseController()
        phase = .stopped
        diagnostics.record("pip.stopped")
    }

    private func releaseController() {
        transitionTask?.cancel()
        transitionTask = nil
        possibilityObservation = nil
        suspensionObservation = nil
        renderLink?.invalidate()
        renderLink = nil
        foregroundLink?.invalidate()
        foregroundLink = nil
        foregroundFPS = nil
        controller?.delegate = nil
        controller?.stopPictureInPicture()
        controller?.contentSource = nil
        controller = nil
        contentController = nil
        renderView = nil
        startedAt = nil
        isSuspended = false
        hasRequestedStart = false
    }

    func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        guard controller === pictureInPictureController else { return }
        guard wantsRunning else { pictureInPictureController.stopPictureInPicture(); return }
        transitionTask?.cancel()
        phase = .running
        startedAt = .now
        diagnostics.record("pip.started", "active=\(pictureInPictureController.isPictureInPictureActive); size=\(requestedSize)")
    }

    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        guard controller === pictureInPictureController else { return }
        diagnostics.record("pip.didStop", "userRequested=\(!wantsRunning)")
        finishStop()
    }

    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {
        guard controller === pictureInPictureController else { return }
        diagnostics.recordError("pip.startFailed", error)
        fail("画中画开启失败，可在诊断中查看系统原因。", event: "pip.failure")
    }

    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController,
                                   restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
        completionHandler(sourceView?.window != nil)
    }

    func sceneChanged(_ phase: ScenePhase) {
        isForeground = phase == .active
        diagnostics.record("scene.changed", String(describing: phase))
        updateForegroundProbe()
        if isForeground {
            screenMaximum = sourceView?.window?.screen.maximumFramesPerSecond ?? UIScreen.main.maximumFramesPerSecond
            refresh()
            if !migratedLegacyActivities {
                migratedLegacyActivities = true
                Task {
                    let activities = Activity<MaskAttributes>.activities
                    for activity in activities { await activity.end(nil, dismissalPolicy: .immediate) }
                    diagnostics.record("legacyActivities.ended", "count=\(activities.count)")
                }
            }
        }
    }

    func refresh() {
        if phase == .running, controller?.isPictureInPictureActive != true { finishStop() }
        diagnostics.record("pip.checked", "phase=\(phase.rawValue); active=\(controller?.isPictureInPictureActive ?? false)")
    }

    private func startRenderLink() {
        let link = CADisplayLink(target: displayTarget, selector: #selector(DisplayTarget.render(_:)))
        link.preferredFramesPerSecond = min(Self.contentFramesPerSecond, screenMaximum)
        link.add(to: .main, forMode: .common)
        renderLink = link
    }

    private func updateForegroundProbe() {
        foregroundLink?.invalidate()
        foregroundLink = nil
        foregroundFPS = nil
        guard isForeground, wantsRunning else { return }
        sampleStart = 0
        sampledFrames = 0
        let link = CADisplayLink(target: displayTarget, selector: #selector(DisplayTarget.sample(_:)))
        let target = Float(min(120, screenMaximum))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: target, maximum: target, preferred: target)
        link.add(to: .main, forMode: .common)
        foregroundLink = link
    }

    fileprivate func render(_ link: CADisplayLink) {
        renderView?.advance(to: link.targetTimestamp)
        if isForeground { sourceView?.advance(to: link.targetTimestamp) }
        renderTicks += 1
        lastRenderedAt = .now
        if lastRenderLog == 0 || link.timestamp - lastRenderLog >= 10 {
            lastRenderLog = link.timestamp
            diagnostics.record("pip.contentTick", "ticks=\(renderTicks); host=\(renderView?.bounds.size ?? .zero); foreground=\(isForeground)")
        }
    }

    fileprivate func sample(_ link: CADisplayLink) {
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
        let info = Bundle.main.infoDictionary ?? [:]
        let screen = sourceView?.window?.screen ?? UIScreen.main
        return """
        appVersion=\(info["CFBundleShortVersionString"] ?? "?")
        appBuild=\(info["CFBundleVersion"] ?? "?")
        bundleIdentifier=\(Bundle.main.bundleIdentifier ?? "?")
        deviceModel=\(ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? model)
        systemVersion=\(ProcessInfo.processInfo.operatingSystemVersionString)
        screenPoints=\(screen.bounds.size)
        nativePixels=\(screen.nativeBounds.size)
        maximumFramesPerSecond=\(screen.maximumFramesPerSecond)
        lowPowerMode=\(ProcessInfo.processInfo.isLowPowerModeEnabled)
        thermalState=\(ProcessInfo.processInfo.thermalState.rawValue)
        engine=publicVideoCall
        upstreamCommit=\(Self.upstreamCommit)
        phase=\(phase.rawValue)
        pipSupported=\(AVPictureInPictureController.isPictureInPictureSupported())
        pipPossible=\(controller?.isPictureInPicturePossible ?? false)
        pipActive=\(controller?.isPictureInPictureActive ?? false)
        pipSuspended=\(isSuspended)
        pipRequestedSize=\(requestedSize)
        pipActualContentSize=\(contentController?.view.bounds.size ?? .zero)
        startedAt=\(startedAt?.ISO8601Format() ?? "none")
        contentPreferredFPS=\(Self.contentFramesPerSecond)
        contentTicks=\(renderTicks)
        lastContentTick=\(lastRenderedAt?.ISO8601Format() ?? "none")
        foregroundCallbackFPS=\(foregroundFPS.map { String(format: "%.1f", $0) } ?? "unavailable")
        globalDisplayRefreshRate=unavailable
        audioPlayback=false
        """
    }
}

@MainActor
private final class DisplayTarget: NSObject {
    weak var owner: RefreshSession?
    init(owner: RefreshSession) { self.owner = owner }
    @objc func render(_ link: CADisplayLink) { owner?.render(link) }
    @objc func sample(_ link: CADisplayLink) { owner?.sample(link) }
}

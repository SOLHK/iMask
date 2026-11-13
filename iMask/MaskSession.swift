import ActivityKit
import Foundation
import OSLog
import SwiftUI
import UIKit
import Darwin

@MainActor
final class MaskSession: ObservableObject {
    enum Status: Equatable {
        case off
        case running(startedAt: Date)
        case stopped
        case ended

        var isRunning: Bool {
            if case .running = self { return true }
            return false
        }
    }

    private enum LastState: String {
        case running, stopped, ended
    }

    @Published private(set) var status: Status = .off
    @Published private(set) var isEnabled = false
    @Published private(set) var isStopping = false
    @Published private(set) var isUpdating = false
    @Published private(set) var selectedWidth: MaskWidth
    @Published private(set) var errorMessage: String?

    let diagnostics = DiagnosticsLog()
    private let authorization = ActivityAuthorizationInfo()
    private let defaults = UserDefaults.standard
    private let historyKey = "mask.lastActivityState"
    private let widthKey = "mask.width"
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "iMask", category: "ActivityKit")
    private var observedID: String?
    private var stateTask: Task<Void, Never>?
    private var authorizationTask: Task<Void, Never>?

    var isBusy: Bool { isStopping || isUpdating }

    init() {
        selectedWidth = UserDefaults.standard.string(forKey: "mask.width")
            .flatMap(MaskWidth.init(rawValue:)) ?? .standard
        isEnabled = authorization.areActivitiesEnabled
        diagnostics.record("app.launched", "version=\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] ?? "?"); width=\(selectedWidth.rawValue)")
        let updates = authorization.activityEnablementUpdates
        authorizationTask = Task { [weak self] in
            for await enabled in updates {
                guard !Task.isCancelled else { return }
                if self?.isEnabled != enabled {
                    self?.diagnostics.record("authorization.changed", "enabled=\(enabled)")
                    self?.isEnabled = enabled
                    self?.refresh(reason: "authorization")
                }
            }
        }
    }

    deinit {
        stateTask?.cancel()
        authorizationTask?.cancel()
    }

    func refresh(reason: String = "manual") {
        isEnabled = authorization.areActivitiesEnabled
        guard !isBusy else { return }
        diagnostics.record("session.checked", "reason=\(reason); enabled=\(isEnabled); activities=\(Activity<MaskAttributes>.activities.count)")

        if let activity = Activity<MaskAttributes>.activities.first(where: {
            $0.activityState == .active || $0.activityState == .stale
        }) {
            show(activity)
            return
        }

        stateTask?.cancel()
        stateTask = nil
        observedID = nil

        switch defaults.string(forKey: historyKey).flatMap(LastState.init(rawValue:)) {
        case .running, .ended:
            if defaults.string(forKey: historyKey) == LastState.running.rawValue {
                diagnostics.record("activity.noLongerActive", "结束原因未由系统提供")
            }
            status = .ended
            defaults.set(LastState.ended.rawValue, forKey: historyKey)
        case .stopped:
            status = .stopped
        case nil:
            status = .off
        }
    }

    func start() {
        guard !isBusy else { return }
        errorMessage = nil
        refresh(reason: "start")
        guard isEnabled, !status.isRunning else {
            diagnostics.record("activity.startSkipped", "enabled=\(isEnabled); running=\(status.isRunning)")
            return
        }

        do {
            diagnostics.record("activity.startRequested", "width=\(selectedWidth.rawValue); sideWidth=\(selectedWidth.sideWidth)")
            let activity = try Activity.request(
                attributes: MaskAttributes(startedAt: .now),
                content: ActivityContent(state: MaskAttributes.ContentState(width: selectedWidth), staleDate: nil),
                pushType: nil
            )
            diagnostics.record("activity.started", "id=\(activity.id); state=\(activity.activityState)")
            show(activity)
        } catch {
            logger.error("Live Activity request failed: \(error.localizedDescription, privacy: .public)")
            diagnostics.recordError("activity.startFailed", error)
            refresh(reason: "startFailed")
            if !status.isRunning {
                errorMessage = "iOS 未能开启实时活动。请打开“诊断与日志”查看系统原因。"
            }
        }
    }

    func setWidth(_ width: MaskWidth) async {
        guard !isBusy, width != selectedWidth else { return }
        isUpdating = true
        let previous = selectedWidth
        selectedWidth = width
        defaults.set(width.rawValue, forKey: widthKey)
        diagnostics.record("width.selected", "from=\(previous.rawValue); to=\(width.rawValue); sideWidth=\(width.sideWidth)")

        for activity in Activity<MaskAttributes>.activities where activity.activityState == .active || activity.activityState == .stale {
            await activity.update(ActivityContent(state: .init(width: width), staleDate: nil))
            diagnostics.record("activity.widthUpdated", "id=\(activity.id); requested=\(width.rawValue); reported=\(activity.content.state.effectiveWidth.rawValue); state=\(activity.activityState)")
        }
        isUpdating = false
        refresh(reason: "widthUpdated")
    }

    func stop() async {
        guard !isBusy else { return }
        refresh(reason: "stop")
        guard status.isRunning else { return }

        isStopping = true
        errorMessage = nil
        defaults.set(LastState.stopped.rawValue, forKey: historyKey)
        diagnostics.record("activity.stopRequested")

        for activity in Activity<MaskAttributes>.activities where activity.activityState != .dismissed {
            await activity.end(nil, dismissalPolicy: .immediate)
            diagnostics.record("activity.stopped", "id=\(activity.id); state=\(activity.activityState)")
        }

        isStopping = false
        refresh(reason: "stopped")
    }

    private func show(_ activity: Activity<MaskAttributes>) {
        status = .running(startedAt: activity.attributes.startedAt)
        selectedWidth = activity.content.state.effectiveWidth
        defaults.set(selectedWidth.rawValue, forKey: widthKey)
        defaults.set(LastState.running.rawValue, forKey: historyKey)
        guard observedID != activity.id else { return }

        stateTask?.cancel()
        observedID = activity.id
        diagnostics.record("activity.observed", "id=\(activity.id); state=\(activity.activityState); width=\(selectedWidth.rawValue)")
        let updates = activity.activityStateUpdates
        stateTask = Task { [weak self] in
            // Check the snapshot as well in case the activity ended before observation began.
            if activity.activityState != .active && activity.activityState != .stale {
                self?.refresh(reason: "observationStarted")
                return
            }

            for await state in updates {
                guard !Task.isCancelled else { return }
                self?.diagnostics.record("activity.stateChanged", "id=\(activity.id); state=\(state)")
                if state != .active && state != .stale {
                    self?.refresh(reason: "stateChanged")
                    return
                }
            }
        }
    }

    func sceneChanged(_ phase: ScenePhase) {
        diagnostics.record("scene.changed", String(describing: phase))
        if phase == .active { refresh(reason: "foreground") }
    }

    var diagnosticSnapshot: String {
        var machine = utsname()
        uname(&machine)
        let model = withUnsafeBytes(of: &machine.machine) { bytes in
            String(decoding: bytes.prefix(while: { $0 != 0 }), as: UTF8.self)
        }
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        let screen = scene?.screen ?? UIScreen.main
        let window = scene?.windows.first(where: \.isKeyWindow)
        let extensionBundle = Bundle.main.builtInPlugInsURL
            .map { $0.appending(path: "iMaskWidget.appex") }
            .flatMap { Bundle(url: $0) }
        let info = Bundle.main.infoDictionary ?? [:]
        let activityLines = Activity<MaskAttributes>.activities.map { activity in
            """
            id=\(activity.id)
            state=\(activity.activityState)
            startedAt=\(activity.attributes.startedAt.ISO8601Format())
            maximumEndAt=\(activity.attributes.startedAt.addingTimeInterval(8 * 60 * 60).ISO8601Format())
            reportedWidth=\(activity.content.state.effectiveWidth.rawValue)
            legacyContent=\(activity.content.state.width == nil)
            """
        }.joined(separator: "\n\n")

        return """
        应用与设备
        appVersion=\(info["CFBundleShortVersionString"] ?? "?")
        appBuild=\(info["CFBundleVersion"] ?? "?")
        bundleIdentifier=\(Bundle.main.bundleIdentifier ?? "?")
        deviceModel=\(ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? model)
        systemVersion=\(ProcessInfo.processInfo.operatingSystemVersionString)
        screenPoints=\(screen.bounds.size)
        nativePixels=\(screen.nativeBounds.size)
        scale=\(screen.scale)
        nativeScale=\(screen.nativeScale)
        safeArea=\(String(describing: window?.safeAreaInsets))
        orientation=\(scene?.interfaceOrientation.rawValue ?? 0)
        appearance=\(window?.traitCollection.userInterfaceStyle.rawValue ?? 0)
        lowPowerMode=\(ProcessInfo.processInfo.isLowPowerModeEnabled)
        thermalState=\(ProcessInfo.processInfo.thermalState.rawValue)
        protectedDataAvailable=\(UIApplication.shared.isProtectedDataAvailable)

        实时活动
        liveActivitiesEnabled=\(authorization.areActivitiesEnabled)
        sessionStatus=\(status)
        selectedWidth=\(selectedWidth.rawValue)
        compactSideWidthPoints=\(selectedWidth.sideWidth)
        compactContentHeightPoints=16
        actualIslandGeometry=unavailable
        actualIslandVisibility=unavailable
        widgetBundlePresent=\(extensionBundle != nil)
        widgetBundleIdentifier=\(extensionBundle?.bundleIdentifier ?? "missing")
        widgetVersion=\(extensionBundle?.infoDictionary?["CFBundleShortVersionString"] ?? "missing")
        activityCount=\(Activity<MaskAttributes>.activities.count)
        \(activityLines)
        """
    }
}

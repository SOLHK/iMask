import SwiftUI
import UIKit

enum DisplayMode: String, CaseIterable, Identifiable {
    case floatingWindow, island
    var id: String { rawValue }
    var title: String { self == .floatingWindow ? "悬浮窗" : "灵动岛" }
}

/// Serializes the handoff between AVKit and ActivityKit. Only one mode owns a session.
@MainActor
final class DisplayModeSession: ObservableObject {
    @Published private(set) var selected: DisplayMode
    @Published private(set) var isSwitching = false
    @Published private(set) var errorMessage: String?
    private let refresh: RefreshSession
    private let mask: MaskSession
    private static let preferenceKey = "imask.displayMode"
    private var reconciledLaunch = false

    init(refresh: RefreshSession, mask: MaskSession) {
        self.refresh = refresh
        self.mask = mask
        selected = UserDefaults.standard.string(forKey: Self.preferenceKey)
            .flatMap(DisplayMode.init(rawValue:)) ?? .floatingWindow
        refresh.onShortcutRequested = { [weak self] in
            guard let self, !self.isSwitching, PiPShortcutActionCenter.hasPendingAction else { return }
            self.request(.floatingWindow, start: true, shortcut: true)
        }
    }

    func select(_ mode: DisplayMode) {
        guard mode != selected else { return }
        request(mode, start: refresh.isRunning || mask.status.isRunning)
    }

    func toggle() {
        guard !isSwitching else { return }
        errorMessage = nil
        let running = selected == .island ? mask.status.isRunning : refresh.isRunning
        if selected == .floatingWindow, running {
            refresh.stop()
            return
        }
        request(selected, start: !running)
    }

    func startHiddenWindow() { request(.floatingWindow, start: true, hidden: true) }

    func reconcileOnForeground() {
        guard !isSwitching else { return }
        if !reconciledLaunch {
            reconciledLaunch = true
            // Preserve a previously requested island when upgrading from the two-toggle UI.
            if UserDefaults.standard.string(forKey: Self.preferenceKey) == nil, mask.status.isRunning {
                selected = .island
            }
        }
        let conflict = selected == .island ? refresh.isRunning : mask.status.isRunning
        if conflict { request(selected, start: true) }
    }

    private func request(_ mode: DisplayMode, start: Bool, hidden: Bool = false, shortcut: Bool = false) {
        guard !isSwitching, !mask.isBusy else { return }
        isSwitching = true
        errorMessage = nil
        refresh.diagnostics.record("mode.handoffRequested", "from=\(selected.rawValue); to=\(mode.rawValue); start=\(start)")
        Task {
            defer { isSwitching = false }
            if mode == .island {
                guard await refresh.stopAndReleaseForModeChange() else {
                    errorMessage = "悬浮窗尚未完全停止，请稍后重试。"
                    return
                }
                // Recreate an activity that was started while PiP still owned its system surface.
                await mask.stop()
            } else {
                await mask.stop()
                guard !mask.status.isRunning else {
                    errorMessage = "灵动岛活动尚未停止，请稍后重试。"
                    return
                }
                if !start {
                    guard await refresh.stopAndReleaseForModeChange() else {
                        errorMessage = "悬浮窗尚未完全停止，请稍后重试。"
                        return
                    }
                }
            }

            selected = mode
            UserDefaults.standard.set(mode.rawValue, forKey: Self.preferenceKey)
            if start {
                guard UIApplication.shared.applicationState == .active else {
                    errorMessage = "模式已切换，请返回 iMask 后点击开启。"
                    return
                }
                if mode == .island {
                    mask.start()
                    if !mask.status.isRunning {
                        errorMessage = mask.errorMessage ?? "请在系统设置中允许 iMask 实时活动。"
                    }
                } else {
                    guard await refresh.waitForSourceView() else {
                        errorMessage = "悬浮窗画面尚未就绪，请点击开启重试。"
                        return
                    }
                    guard UIApplication.shared.applicationState == .active else {
                        errorMessage = "请先完成系统弹窗，再点击开启悬浮窗。"
                        return
                    }
                    if shortcut {
                        refresh.runPendingShortcut()
                    } else if hidden {
                        refresh.startAndHide()
                    } else if !refresh.isRunning {
                        refresh.start()
                    }
                }
            }
            refresh.diagnostics.record("mode.handoffCompleted", "mode=\(mode.rawValue); pip=\(refresh.isRunning); island=\(mask.status.isRunning)")
        }
    }
}

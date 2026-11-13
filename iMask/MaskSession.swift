import ActivityKit
import Foundation
import OSLog
import SwiftUI

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
    @Published private(set) var errorMessage: String?

    private let authorization = ActivityAuthorizationInfo()
    private let defaults = UserDefaults.standard
    private let historyKey = "mask.lastActivityState"
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "iMask", category: "ActivityKit")
    private var observedID: String?
    private var stateTask: Task<Void, Never>?

    deinit {
        stateTask?.cancel()
    }

    func refresh() {
        isEnabled = authorization.areActivitiesEnabled
        guard !isStopping else { return }

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
            status = .ended
            defaults.set(LastState.ended.rawValue, forKey: historyKey)
        case .stopped:
            status = .stopped
        case nil:
            status = .off
        }
    }

    func start() {
        guard !isStopping else { return }
        errorMessage = nil
        refresh()
        guard isEnabled, !status.isRunning else { return }

        do {
            let activity = try Activity.request(
                attributes: MaskAttributes(startedAt: .now),
                content: ActivityContent(state: MaskAttributes.ContentState(), staleDate: nil),
                pushType: nil
            )
            show(activity)
        } catch {
            logger.error("Live Activity request failed: \(error.localizedDescription, privacy: .public)")
            refresh()
            if !status.isRunning {
                errorMessage = "iOS 未能开启实时活动。请检查系统设置，或结束其他实时活动后重试。"
            }
        }
    }

    func stop() async {
        guard !isStopping else { return }
        refresh()
        guard status.isRunning else { return }

        isStopping = true
        errorMessage = nil
        defaults.set(LastState.stopped.rawValue, forKey: historyKey)

        for activity in Activity<MaskAttributes>.activities where activity.activityState != .dismissed {
            await activity.end(nil, dismissalPolicy: .immediate)
        }

        isStopping = false
        refresh()
    }

    private func show(_ activity: Activity<MaskAttributes>) {
        status = .running(startedAt: activity.attributes.startedAt)
        defaults.set(LastState.running.rawValue, forKey: historyKey)
        guard observedID != activity.id else { return }

        stateTask?.cancel()
        observedID = activity.id
        let updates = activity.activityStateUpdates
        stateTask = Task { [weak self] in
            // Check the snapshot as well in case the activity ended before observation began.
            if activity.activityState != .active && activity.activityState != .stale {
                self?.refresh()
                return
            }

            for await state in updates {
                guard !Task.isCancelled else { return }
                if state != .active && state != .stale {
                    self?.refresh()
                    return
                }
            }
        }
    }
}

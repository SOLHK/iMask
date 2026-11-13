import SwiftUI

@main
@MainActor
struct IMaskApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var session: RefreshSession
    @StateObject private var mask: MaskSession
    @StateObject private var modes: DisplayModeSession

    init() {
        let refresh = RefreshSession()
        let island = MaskSession(diagnostics: refresh.diagnostics)
        _session = StateObject(wrappedValue: refresh)
        _mask = StateObject(wrappedValue: island)
        _modes = StateObject(wrappedValue: DisplayModeSession(refresh: refresh, mask: island))
    }

    var body: some Scene {
        WindowGroup {
            ContentView(session: session, mask: mask, modes: modes)
                .onChange(of: scenePhase, initial: true) { _, phase in
                    session.sceneChanged(phase)
                    mask.sceneChanged(phase)
                    if phase == .active { modes.reconcileOnForeground() }
                }
                .onOpenURL { session.open($0) }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataWillBecomeUnavailableNotification)) { _ in
                    session.diagnostics.record("device.protectedDataUnavailable")
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataDidBecomeAvailableNotification)) { _ in
                    session.diagnostics.record("device.protectedDataAvailable")
                }
        }
    }
}

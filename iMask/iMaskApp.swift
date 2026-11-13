import SwiftUI

@main
@MainActor
struct IMaskApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var session: RefreshSession
    @StateObject private var mask: MaskSession

    init() {
        let refresh = RefreshSession()
        _session = StateObject(wrappedValue: refresh)
        _mask = StateObject(wrappedValue: MaskSession(diagnostics: refresh.diagnostics))
    }

    var body: some Scene {
        WindowGroup {
            ContentView(session: session, mask: mask)
                .onChange(of: scenePhase, initial: true) { _, phase in
                    session.sceneChanged(phase)
                    mask.sceneChanged(phase)
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

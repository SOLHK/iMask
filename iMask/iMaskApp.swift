import SwiftUI

@main
@MainActor
struct IMaskApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var session = MaskSession()

    var body: some Scene {
        WindowGroup {
            ContentView(session: session)
                .onChange(of: scenePhase, initial: true) { _, phase in
                    session.sceneChanged(phase)
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataWillBecomeUnavailableNotification)) { _ in
                    session.diagnostics.record("device.protectedDataUnavailable")
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataDidBecomeAvailableNotification)) { _ in
                    session.diagnostics.record("device.protectedDataAvailable")
                }
        }
    }
}

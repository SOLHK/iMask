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
                    if phase == .active {
                        session.refresh()
                    }
                }
        }
    }
}

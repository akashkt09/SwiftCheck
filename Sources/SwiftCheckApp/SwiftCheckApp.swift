import SwiftUI

@main
struct SwiftCheckApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        // Why: an explicit title, not the default — as a plain `swift run` executable (no app bundle /
        // Info.plist) the window title would otherwise fall back to the raw process name.
        WindowGroup("SwiftCheck") {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 1000, minHeight: 650)
        }
    }
}

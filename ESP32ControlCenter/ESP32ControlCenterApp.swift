import SwiftUI

@main
struct ESP32ControlCenterApp: App {
    @StateObject private var app = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(app)
                .preferredColorScheme(.dark)
        }
    }
}

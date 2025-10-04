import SwiftUI

@main
struct KeyboardRegistersApp: App {
    // Use an AppDelegate so we can set up AppKit things on launch
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // No visible windows; menubar only
        Settings {
            EmptyView()
        }
    }
}

// NxLauncher: a GUI for the nxnative pipeline (build a game from its NSPs, run it, export it).
import AppKit
import SwiftUI

@main
struct NxLauncherApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var state = LauncherState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(state)
                .frame(minWidth: 760, minHeight: 640)
        }
        .defaultSize(width: 860, height: 720)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}

/// Sets the window title (SwiftUI has no scene modifier for it that works in a SwiftPM executable).
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.main.async {
            for w in NSApp.windows where w.title.isEmpty {
                w.title = "NxLauncher"
                w.setContentSize(NSSize(width: 860, height: 720))
            }
        }
    }
}

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
                .frame(minWidth: 780, minHeight: 700)
        }
        .defaultSize(width: 880, height: 720)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}

/// Sets the window title (SwiftUI has no scene modifier for it that works in a SwiftPM executable).
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // --opmode handheld|console: put the operation mode into effect, without a window
        if CommandLine.arguments.contains("--opmode") {
            LauncherState.runOpModeFromCommandLine()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { NSApp.terminate(nil) }
            return
        }
        // --launch: start the game from the command line, without a window
        if CommandLine.arguments.contains("--launch") {
            LauncherState.runLaunchFromCommandLine()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { NSApp.terminate(nil) }
            return
        }
        DispatchQueue.main.async {
            for w in NSApp.windows {
                if w.title.isEmpty { w.title = "NxLauncher" }
                w.setContentSize(NSSize(width: 880, height: 720))
            }
        }
    }
}

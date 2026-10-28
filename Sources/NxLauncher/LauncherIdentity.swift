import Foundation

enum LauncherIdentity {
    static let name = "NxLauncher"
    // SwiftPM executables have no app Info.plist; release bundles use VERSION
    // through make-app.sh. Keep the development fallback at the same patch release.
    static let version = Bundle.main.object(
        forInfoDictionaryKey: "CFBundleShortVersionString"
    ) as? String ?? "0.1.4"
}

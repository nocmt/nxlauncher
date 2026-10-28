import AppKit
import Foundation

/// The launcher's own icon style, chosen in the settings.
///
/// Only the running application's icon can change: the Dock, the app switcher and About use
/// `NSApplication.applicationIconImage`, while Finder and Launchpad keep reading the signed
/// bundle's `AppIcon.icns`. Rewriting the bundle at runtime would break its signature, so the
/// setting deliberately stops at the runtime icon.
enum AppIconStyle: String, CaseIterable, Identifiable {
    case solid
    case outline
    case retro

    var id: String { rawValue }

    var label: String {
        switch self {
        case .solid: return "实心"
        case .outline: return "描边"
        case .retro: return "复古"
        }
    }

    /// The file name inside the app bundle's Resources directory.
    var fileName: String { "IconVariants/\(rawValue).png" }

    static let defaultsKey = "appIconStyle"

    /// The stored choice, or `.solid` for a first run and for an unknown stored value.
    static func saved(_ defaults: UserDefaults = .standard) -> AppIconStyle {
        guard let raw = defaults.string(forKey: defaultsKey) else { return .solid }
        return AppIconStyle(rawValue: raw) ?? .solid
    }

    /// The bundled preview image, or nil when the resource is missing. A development build has no
    /// app bundle resources, so a repository directory can be given as a fallback.
    func image(in bundle: Bundle = .main, fallbackDirectory: URL? = nil) -> NSImage? {
        if let url = bundle.url(forResource: fileName, withExtension: nil),
           let image = NSImage(contentsOf: url) {
            return image
        }
        guard let directory = fallbackDirectory else { return nil }
        return NSImage(contentsOf: directory.appendingPathComponent(fileName))
    }

    /// Applies the choice to the running application. A missing resource leaves the current
    /// icon alone instead of clearing it.
    @MainActor
    func apply(in bundle: Bundle = .main, fallbackDirectory: URL? = nil) {
        guard let image = image(in: bundle, fallbackDirectory: fallbackDirectory) else { return }
        NSApplication.shared.applicationIconImage = image
    }
}

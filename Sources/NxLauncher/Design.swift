// The look: the palette, the card, the buttons, the progress bar.
//
// Everything is built from the semantic colors, so the window follows the system's light / dark
// appearance without a second set of values.
import SwiftUI

enum DS {
    /// The corner radius of a card.
    static let radius: CGFloat = 14
    /// The small radius of a control.
    static let small: CGFloat = 8

    static var accent: Color { Color.accentColor }

    /// A soft accent tint for the icon chips (the section headers, the status dot).
    static func tint(_ color: Color) -> Color { color.opacity(0.16) }

    static var ok: Color { Color(nsColor: .systemGreen) }
    static var idle: Color { Color(nsColor: .tertiaryLabelColor) }
    static var warn: Color { Color(nsColor: .systemOrange) }
    static var bad: Color { Color(nsColor: .systemRed) }
}

// MARK: - the card

struct Card<Content: View>: View {
    var title: String
    var systemImage: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: title, systemImage: systemImage)
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DS.radius, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.radius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.10), radius: 10, x: 0, y: 3)
    }
}

/// A section title: the icon in a tinted rounded square, then the name.
struct SectionHeader: View {
    var title: String
    var systemImage: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(DS.accent)
                .frame(width: 22, height: 22)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(DS.tint(DS.accent)))
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
        }
    }
}

// MARK: - the buttons

/// The main action: a filled, rounded button with a gradient and a soft shadow.
struct PrimaryButtonStyle: ButtonStyle {
    var enabled: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(LinearGradient(colors: [DS.accent, DS.accent.opacity(0.78)],
                                         startPoint: .top, endPoint: .bottom))
                    .shadow(color: DS.accent.opacity(0.28), radius: 8, x: 0, y: 3)
            )
            .opacity(enabled ? (configuration.isPressed ? 0.82 : 1) : 0.45)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// The secondary actions: a tinted, bordered button.
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(DS.accent)
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(DS.tint(DS.accent).opacity(configuration.isPressed ? 0.9 : 1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(DS.accent.opacity(0.28), lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

/// A small quiet button (the "选择…" ones).
struct QuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.primary)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.14 : 0.07))
            )
    }
}

// MARK: - the progress bar

/// A rounded progress bar: empty when idle, a moving stripe when the count is unknown, filled when
/// the count is known.
struct Bar: View {
    /// nil = idle (empty), a negative number = the count is unknown (a moving stripe), 0...1 = the count.
    var fraction: Double?
    var height: CGFloat = 8

    /// Whether the moving stripe has reached the right end of its travel.
    @State private var stripeAtEnd = false

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                if let f = fraction, f >= 0 {
                    Capsule()
                        .fill(LinearGradient(colors: [DS.accent, DS.accent.opacity(0.75)],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(0, min(1, f)) * geo.size.width)
                } else if fraction != nil {
                    Capsule()
                        .fill(LinearGradient(colors: [DS.accent.opacity(0.30), DS.accent],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width * 0.35)
                        .offset(x: stripeAtEnd ? geo.size.width * 0.65 : 0)
                        .onAppear {
                            withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) {
                                stripeAtEnd = true
                            }
                        }
                        .onDisappear { stripeAtEnd = false }
                }
            }
        }
        .frame(height: height)
        .animation(.easeOut(duration: 0.25), value: fraction)
    }
}

// MARK: - small pieces

/// A row of the game folder list: a state dot, the name, and the detail on the right.
struct DataRow: View {
    var title: String
    var detail: String
    var state: State

    enum State { case ok, idle, warn }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: state == .ok ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 13))
                .foregroundStyle(state == .ok ? DS.ok : (state == .warn ? DS.warn : DS.idle))
            Text(title)
                .font(.system(size: 13))
            Spacer(minLength: 12)
            Text(detail.isEmpty ? "—" : detail)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

/// The status dot + text under the title.
struct StatusDot: View {
    var text: String
    var color: Color

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text).font(.system(size: 12)).foregroundStyle(.secondary)
        }
    }
}

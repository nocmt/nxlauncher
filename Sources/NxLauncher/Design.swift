// The look: the palette, the card, the buttons, the progress bar.
//
// Everything is built from the semantic colors, so the window follows the system's light / dark
// appearance without a second set of values.
import AppKit
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

    // MARK: - the colours of the window

    /// A colour that follows the appearance: the same colour, another value in the light and in the
    /// dark. The system is asked for the value when it draws, so no view has to know which
    /// appearance is on -- and the window's own appearance setting (light / dark / follow the
    /// system) works exactly like the system's.
    static func dynamic(_ light: NSColor, _ dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        })
    }

    /// The ground of the window. In the light mode it is almost white with a cold hint of grey, so
    /// the white cards on it read clean instead of grey on grey.
    static let windowTop = dynamic(NSColor(srgbRed: 0.988, green: 0.990, blue: 0.996, alpha: 1),
                                   NSColor(srgbRed: 0.125, green: 0.125, blue: 0.140, alpha: 1))
    static let windowBottom = dynamic(NSColor(srgbRed: 0.949, green: 0.953, blue: 0.969, alpha: 1),
                                      NSColor(srgbRed: 0.086, green: 0.086, blue: 0.098, alpha: 1))

    /// The cards: white on the light ground, a little lighter than the ground in the dark (a card
    /// that is darker than its ground looks hollow).
    static let card = dynamic(.white, NSColor(srgbRed: 0.153, green: 0.153, blue: 0.173, alpha: 1))
    static let cardStroke = dynamic(NSColor.black.withAlphaComponent(0.07),
                                    NSColor.white.withAlphaComponent(0.09))
    static let cardShadow = dynamic(NSColor.black.withAlphaComponent(0.05),
                                    NSColor.black.withAlphaComponent(0.42))
    /// The shadow of something that floats over the window (the toast): it needs more than the
    /// cards' shadow to read as a separate layer on the light ground.
    static let floatShadow = dynamic(NSColor.black.withAlphaComponent(0.16),
                                     NSColor.black.withAlphaComponent(0.55))

    /// A group of rows inside a card. In the light mode there is no block at all: the rows are
    /// separated by a hairline, and that is what makes the light mode clean. In the dark mode the
    /// block is a little lighter than the card, so the rows read as one group.
    static let row = dynamic(NSColor.white.withAlphaComponent(0),
                              NSColor(srgbRed: 0.204, green: 0.204, blue: 0.227, alpha: 1))
    /// The hairline between the rows.
    static let hairline = dynamic(NSColor.black.withAlphaComponent(0.08),
                                   NSColor.white.withAlphaComponent(0.09))
    /// The small quiet buttons and the empty track of the progress bar.
    static let quiet = dynamic(NSColor(srgbRed: 0.925, green: 0.929, blue: 0.945, alpha: 1),
                               NSColor(srgbRed: 0.259, green: 0.259, blue: 0.286, alpha: 1))
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
                .fill(DS.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.radius, style: .continuous)
                .strokeBorder(DS.cardStroke, lineWidth: 1)
        )
        .shadow(color: DS.cardShadow, radius: 10, x: 0, y: 3)
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
                    .fill(DS.accent.opacity(configuration.isPressed ? 0.20 : 0.11))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(DS.accent.opacity(0.22), lineWidth: 1)
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
                    .fill(configuration.isPressed ? DS.hairline : DS.quiet)
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
                Capsule().fill(DS.quiet)
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

// MARK: - the toast

/// A short message that floats over the window and disappears by itself.
struct Toast: View {
    var text: String
    var systemImage: String = "info.circle.fill"
    var color: Color = DS.accent

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(color)
            Text(text)
                .font(.system(size: 12.5))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(maxWidth: 480, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(DS.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(DS.cardStroke, lineWidth: 1)
        )
        .shadow(color: DS.floatShadow, radius: 16, x: 0, y: 6)
    }
}

// MARK: - the small pieces

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

// MARK: - the files in the game folder

/// A group of files in the game folder: the base game, the updates, the DLC.
///
/// A folder can hold several updates and several DLC, and one row cannot hold all their names, so:
/// one file shows its name in place; several files show how many there are, and opening the row
/// lists them one by one -- the title ID first, because it always fits.
struct FileGroupRow: View {
    var title: String
    var files: [GameFile]
    var state: DataRow.State
    var open: Bool = false

    @State private var opened: Bool

    init(title: String, files: [GameFile], state: DataRow.State, open: Bool = false) {
        self.title = title
        self.files = files
        self.state = state
        self.open = open
        _opened = State(initialValue: open)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if opened {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(files.prefix(10)) { f in
                        fileLine(f)
                    }
                    if files.count > 10 {
                        Text("…还有 \(files.count - 10) 个")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.leading, 33)
                .padding(.trailing, 12)
                .padding(.bottom, 9)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: state == .ok ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 13))
                .foregroundStyle(state == .ok ? DS.ok : (state == .warn ? DS.warn : DS.idle))
            Text(title)
                .font(.system(size: 13))
            Spacer(minLength: 12)
            if files.count > 1 {
                Text("\(files.count) 个")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Button { toggle() } label: {
                    Image(systemName: opened ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 16, height: 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(opened ? "收起" : "看看这 \(files.count) 个文件")
            } else {
                Text(files.first?.name ?? "—")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            guard files.count > 1 else { return }
            toggle()
        }
    }

    private func toggle() {
        withAnimation(.easeOut(duration: 0.18)) { opened.toggle() }
    }

    /// One file: the title ID (it always fits) and then the name without it.
    private func fileLine(_ f: GameFile) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(f.titleID)
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(DS.accent)
                .fixedSize()
            Text(f.label)
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .help(f.path)
        .textSelection(.enabled)
    }
}

import AppKit
import SwiftUI

struct BuildLogView: NSViewRepresentable {
    var lines: [String]

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .controlBackgroundColor

        let textView = Coordinator.makeTextView(initialWidth: max(scrollView.contentSize.width, 1))
        textView.frame = NSRect(x: 0, y: 0, width: max(scrollView.contentSize.width, 1), height: 1)
        scrollView.documentView = textView
        context.coordinator.update(lines: lines, in: scrollView, forceInitialScroll: true)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.update(lines: lines, in: scrollView)
    }

    final class Coordinator {
        private(set) var renderedLines: [String]?

        func update(lines: [String], in scrollView: NSScrollView, forceInitialScroll: Bool = false) {
            guard let textView = scrollView.documentView as? NSTextView else { return }
            let boundedLines = Array(lines.suffix(Self.maximumLines))
            guard boundedLines != renderedLines else { return }

            let previousLines = renderedLines ?? []
            let overlap = boundedLines.starts(with: previousLines)
                ? previousLines.count : Self.suffixPrefixOverlap(previousLines, boundedLines)
            let isAppendOrRollover = renderedLines != nil && overlap > 0
            let droppedLines = isAppendOrRollover ? previousLines.count - overlap : 0
            let isRollover = droppedLines > 0
            let replaced = renderedLines != nil && !isAppendOrRollover
            let wasAtBottom = forceInitialScroll || Self.isAtBottom(scrollView)
            let oldSelections = textView.selectedRanges.map(\.rangeValue)
            let oldOriginY = scrollView.contentView.bounds.origin.y
            let droppedHeight = isRollover ? Self.height(ofFirstLines: droppedLines, in: textView) : 0

            textView.textStorage?.setAttributedString(Self.attributedLog(boundedLines))
            renderedLines = boundedLines
            textView.layoutManager?.ensureLayout(for: textView.textContainer!)

            if isAppendOrRollover {
                let newRanges = oldSelections.map { Self.translatedRange($0, dropping: droppedLines, from: previousLines) }
                textView.setSelectedRanges(newRanges.map(NSValue.init(range:)), affinity: .downstream,
                                           stillSelecting: false)
            } else if replaced {
                textView.setSelectedRange(NSRange(location: 0, length: 0))
            }

            let hadSelection = oldSelections.contains { $0.length > 0 }
            let hasSelection = textView.selectedRanges.contains { $0.rangeValue.length > 0 }
            let nextOrigin = Self.originAfterDropping(oldOriginY, droppedHeight: droppedHeight)
            if wasAtBottom && !hasSelection && !(isRollover && hadSelection) {
                textView.scrollRangeToVisible(NSRange(location: textView.string.utf16.count, length: 0))
            } else if isRollover {
                Self.setVerticalOrigin(nextOrigin, in: scrollView)
            }
        }

        static let maximumLines = 500

        static func suffixPrefixOverlap(_ old: [String], _ new: [String]) -> Int {
            for count in stride(from: min(old.count, new.count), through: 1, by: -1) {
                if old.suffix(count).elementsEqual(new.prefix(count)) { return count }
            }
            return 0
        }

        static func translatedRange(_ range: NSRange, dropping lineCount: Int, from lines: [String]) -> NSRange {
            guard lineCount > 0 else { return range }
            let droppedLength = lines.prefix(lineCount).reduce(0) { $0 + $1.utf16.count } + lineCount
            let end = NSMaxRange(range)
            guard end > droppedLength else { return NSRange(location: 0, length: 0) }
            let newStart = max(range.location, droppedLength) - droppedLength
            return NSRange(location: newStart, length: end - max(range.location, droppedLength))
        }

        static func height(ofFirstLines count: Int, in textView: NSTextView) -> CGFloat {
            guard count > 0, let layoutManager = textView.layoutManager else { return 0 }
            let text = textView.string as NSString
            var boundary = 0
            for line in textView.string.components(separatedBy: "\n").prefix(count) {
                boundary += (line as NSString).length + 1
            }
            guard boundary > 0, text.length > 0 else { return 0 }
            let characterIndex = min(boundary, text.length) - 1
            let glyphIndex = layoutManager.glyphIndexForCharacter(at: characterIndex)
            let lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
            return max(0, lineRect.maxY)
        }

        static func originAfterDropping(_ origin: CGFloat, droppedHeight: CGFloat) -> CGFloat {
            max(0, origin - max(0, droppedHeight))
        }

        static func setVerticalOrigin(_ y: CGFloat, in scrollView: NSScrollView) {
            var origin = scrollView.contentView.bounds.origin
            origin.y = y
            scrollView.contentView.setBoundsOrigin(origin)
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }

        static func makeTextView(initialWidth: CGFloat = 1) -> NSTextView {
            let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: max(initialWidth, 1), height: 1))
            textView.isEditable = false
            textView.isSelectable = true
            textView.isRichText = false
            textView.importsGraphics = false
            textView.usesFindBar = true
            textView.font = .monospacedSystemFont(ofSize: 10.5, weight: .regular)
            textView.textContainerInset = NSSize(width: 8, height: 8)
            textView.minSize = NSSize(width: 0, height: 0)
            textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                      height: CGFloat.greatestFiniteMagnitude)
            textView.isVerticallyResizable = true
            textView.isHorizontallyResizable = false
            textView.autoresizingMask = [.width]
            textView.textContainer?.widthTracksTextView = true
            textView.setAccessibilityLabel("构建日志")
            return textView
        }

        static func isAtBottom(_ scrollView: NSScrollView) -> Bool {
            guard let documentView = scrollView.documentView else { return true }
            let visible = scrollView.contentView.bounds
            let documentHeight = documentView.bounds.height
            return documentHeight <= visible.height || visible.maxY >= documentHeight - 2
        }

        static func attributedLog(_ lines: [String]) -> NSAttributedString {
            let result = NSMutableAttributedString()
            let font = NSFont.monospacedSystemFont(ofSize: 10.5, weight: .regular)
            for (index, line) in lines.enumerated() {
                if index > 0 { result.append(NSAttributedString(string: "\n")) }
                let color: NSColor = line.hasPrefix("✗") ? .systemRed : .secondaryLabelColor
                result.append(NSAttributedString(string: line, attributes: [.font: font, .foregroundColor: color]))
            }
            return result
        }
    }
}

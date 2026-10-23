// Standalone macOS harness. Run from the repository root with:
// swiftc Sources/NxLauncher/BuildLogView.swift Tests/BuildLogViewTests.swift -o /tmp/BuildLogViewTests && /tmp/BuildLogViewTests
import AppKit
import SwiftUI

@main
struct BuildLogViewTests {
    @MainActor
    static func main() throws {
        _ = NSApplication.shared
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 360, height: 100))
        scrollView.hasVerticalScroller = true
        let textView = BuildLogView.Coordinator.makeTextView(initialWidth: 340)
        precondition(textView.frame.width > 0 && (textView.textContainer?.containerSize.width ?? 0) > 0,
                     "The initial document view must not have zero width")
        textView.frame = NSRect(x: 0, y: 0, width: 340, height: 100)
        scrollView.documentView = textView
        let coordinator = BuildLogView.Coordinator()

        coordinator.update(lines: ["first line", "✗ failed compile"], in: scrollView, forceInitialScroll: true)
        precondition(textView.string == "first line\n✗ failed compile")
        precondition(textView.isSelectable && !textView.isEditable)
        precondition(textView.accessibilityLabel() == "构建日志")
        let errorColor = textView.textStorage!.attribute(.foregroundColor, at: 11, effectiveRange: nil) as? NSColor
        precondition(errorColor?.isEqual(NSColor.systemRed) == true)

        let selection = NSRange(location: 0, length: "first line\n✗".utf16.count)
        textView.setSelectedRange(selection)
        let selectedText = (textView.string as NSString).substring(with: textView.selectedRange())
        precondition(selectedText == "first line\n✗", "Selection spans multiple lines")
        let copyWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 360, height: 140),
                                  styleMask: [.titled], backing: .buffered, defer: false)
        copyWindow.contentView = scrollView
        copyWindow.makeKeyAndOrderFront(nil)
        _ = copyWindow.makeFirstResponder(textView)
        NSApp.activate(ignoringOtherApps: true)
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        textView.setSelectedRange(selection)
        textView.layoutManager?.ensureLayout(for: textView.textContainer!)
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("BuildLogViewTests-\(UUID().uuidString)"))
        let didWriteSelection = textView.writeSelection(to: pasteboard, types: textView.writablePasteboardTypes)
        precondition(didWriteSelection, "Native selection copy writes to isolated pasteboard")
        precondition(pasteboard.string(forType: .string) == "first line\n✗")

        coordinator.update(lines: ["first line", "✗ failed compile"], in: scrollView)
        precondition(textView.selectedRange() == selection, "Unchanged input must not reset selection")
        coordinator.update(lines: ["first line", "✗ failed compile", "third line"], in: scrollView)
        precondition(textView.selectedRange() == selection, "Appending must preserve selection")
        precondition(textView.string == "first line\n✗ failed compile\nthird line")

        textView.setSelectedRange(NSRange(location: 1, length: 4))
        coordinator.update(lines: ["replacement"], in: scrollView)
        precondition(textView.string == "replacement")
        precondition(textView.selectedRange().length == 0, "Replacement must clear old selection")

        let capped = (0..<BuildLogView.Coordinator.maximumLines + 1).map(String.init)
        coordinator.update(lines: capped, in: scrollView)
        precondition(coordinator.renderedLines?.count == 500)
        precondition(coordinator.renderedLines?.first == "1", "The cap retains the newest lines")

        let oldLines = (0..<500).map { "line-\($0)" }
        let rolloverView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 300, height: 100))
        rolloverView.hasVerticalScroller = true
        let rolloverText = BuildLogView.Coordinator.makeTextView()
        rolloverText.frame = NSRect(x: 0, y: 0, width: 280, height: 100)
        rolloverView.documentView = rolloverText
        let rollover = BuildLogView.Coordinator()
        rollover.update(lines: oldLines, in: rolloverView, forceInitialScroll: true)
        rolloverText.layoutManager?.ensureLayout(for: rolloverText.textContainer!)
        let retainedSelectionText = "line-100\nline-101"
        let selectionStart = (rolloverText.string as NSString).range(of: retainedSelectionText).location
        let retainedSelection = NSRange(location: selectionStart, length: (retainedSelectionText as NSString).length)
        rolloverText.setSelectedRange(retainedSelection)
        let oldSelectionString = (rolloverText.string as NSString).substring(with: retainedSelection)

        let lineHeight = rolloverText.layoutManager!.defaultLineHeight(for: rolloverText.font!)
        let oldOrigin = lineHeight * 150
        rolloverView.contentView.scroll(to: NSPoint(x: 0, y: oldOrigin))
        let oldVisibleOrigin = rolloverView.contentView.bounds.origin.y
        let nextLines = Array(oldLines.suffix(499)) + ["line-500"]
        rollover.update(lines: nextLines, in: rolloverView)
        precondition(rolloverText.selectedRange().location == retainedSelection.location - ("line-0" as NSString).length - 1)
        precondition((rolloverText.string as NSString).substring(with: rolloverText.selectedRange()) == oldSelectionString)
        precondition(abs(BuildLogView.Coordinator.originAfterDropping(oldVisibleOrigin, droppedHeight: lineHeight) -
                         max(0, oldVisibleOrigin - lineHeight)) < 0.01,
                     "Rollover origin must preserve the same retained content")

        let evictedLocation = (rolloverText.string as NSString).range(of: "line-1").location
        rolloverText.setSelectedRange(NSRange(location: evictedLocation, length: 3))
        rolloverView.contentView.scroll(to: NSPoint(x: 0, y: oldOrigin))
        rollover.update(lines: Array(nextLines.suffix(499)) + ["line-501"], in: rolloverView)
        precondition(rolloverText.selectedRange().length == 0, "An evicted selection must be cleared")
        precondition(BuildLogView.Coordinator.originAfterDropping(oldOrigin, droppedHeight: lineHeight) < oldOrigin,
                     "Clearing an evicted selection must not force a jump to the bottom")

        let smallScroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 200, height: 40))
        let tallDocument = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 400))
        smallScroll.documentView = tallDocument
        smallScroll.contentView.scroll(to: NSPoint(x: 0, y: 100))
        precondition(!BuildLogView.Coordinator.isAtBottom(smallScroll), "A scrolled-up viewport must not follow")
        smallScroll.contentView.scroll(to: NSPoint(x: 0, y: 360))
        precondition(BuildLogView.Coordinator.isAtBottom(smallScroll), "A bottom viewport must follow")

        print("PASS: selectable multiline text, error color, unchanged updates, append selection, reset, 500-line cap, and bottom detection")
    }
}

import AppKit
import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("CodeViewerPaneView")
struct CodeViewerPaneViewTests {
    @Test("renders file contents in a read-only text view")
    func rendersFileContentsInReadOnlyTextView() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appending(path: "code-viewer-pane-\(UUID().uuidString).swift")
        try "struct Demo {}\n".write(to: fileURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let view = CodeViewerPaneView(
            paneId: UUID(),
            state: CodeViewerState(filePath: fileURL, scrollToLine: 1)
        )

        let scrollView = view.subviews.compactMap { $0 as? NSScrollView }.first
        let textView = scrollView?.documentView as? NSTextView

        #expect(scrollView != nil)
        #expect(scrollView?.hasVerticalScroller == true)
        #expect(textView != nil)
        #expect(textView?.string == "struct Demo {}\n")
        #expect(textView?.isEditable == false)
        #expect(textView?.isSelectable == true)
    }

    @Test("shows an explicit load error in text view when file cannot be read")
    func showsLoadErrorWhenFileCannotBeRead() {
        let fileURL = FileManager.default.temporaryDirectory
            .appending(path: "missing-file-\(UUID().uuidString).swift")

        let view = CodeViewerPaneView(
            paneId: UUID(),
            state: CodeViewerState(filePath: fileURL, scrollToLine: nil)
        )

        let scrollView = view.subviews.compactMap { $0 as? NSScrollView }.first
        let textView = scrollView?.documentView as? NSTextView

        #expect(textView != nil)
        #expect(textView?.isEditable == false)
        #expect(textView?.string.contains("Unable to load file") == true)
    }
}

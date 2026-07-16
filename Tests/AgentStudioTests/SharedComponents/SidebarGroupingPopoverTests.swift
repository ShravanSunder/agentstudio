import AppKit
import SwiftUI
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct SidebarGroupingPopoverTests {
    @Test("mounted grouping popover routes keyboard selection and dismissal")
    func mountedPopoverRoutesKeyboardSelectionAndDismissal() async throws {
        var selectedItem: String?
        var dismissCount = 0
        let hostingView = NSHostingView(
            rootView: SidebarGroupingPopover(
                items: ["Repo", "Pane", "Tab"],
                selectedItem: "Repo",
                icon: { _ in .system(.folder) },
                label: { $0 },
                onSelect: { selectedItem = $0 },
                onDismiss: { dismissCount += 1 }
            )
            .frame(width: 180, height: 140)
        )
        hostingView.frame = NSRect(x: 0, y: 0, width: 180, height: 140)
        hostingView.layoutSubtreeIfNeeded()
        await Task.yield()

        let focusView: SelectablePopoverFocusCapturingView<String> = try #require(
            firstGroupingPopoverDescendant(in: hostingView)
        )
        #expect(focusView.selectedItemId == "Repo")

        #expect(focusView.performKeyEquivalent(with: try #require(makeKeyEvent(keyCode: 125))))
        #expect(await waitForGroupingPopoverState { focusView.selectedItemId == "Pane" })
        #expect(focusView.performKeyEquivalent(with: try #require(makeKeyEvent(keyCode: 36))))
        #expect(selectedItem == "Pane")

        #expect(
            focusView.performKeyEquivalent(
                with: try #require(
                    makeKeyEvent(
                        characters: "\u{1b}",
                        charactersIgnoringModifiers: "\u{1b}",
                        keyCode: 53
                    )
                )
            )
        )
        #expect(dismissCount == 1)
        await Task.yield()
    }

    private func firstGroupingPopoverDescendant<Item: Hashable>(
        in view: NSView
    ) -> SelectablePopoverFocusCapturingView<Item>? {
        if let focusView = view as? SelectablePopoverFocusCapturingView<Item> {
            return focusView
        }

        for subview in view.subviews {
            if let focusView: SelectablePopoverFocusCapturingView<Item> =
                firstGroupingPopoverDescendant(in: subview)
            {
                return focusView
            }
        }

        return nil
    }

    private func waitForGroupingPopoverState(
        maxTurns: Int = 1000,
        _ condition: @MainActor () -> Bool
    ) async -> Bool {
        for _ in 0..<maxTurns {
            if condition() {
                return true
            }
            await Task.yield()
        }
        return condition()
    }
}

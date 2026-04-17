import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
@MainActor
struct PaneRefocusRequestFocusDeciderTests {
    @Test("refocus request for unmounted pane falls back to pane host focus")
    func refocusUnmountedPane_fallsBackToPaneHost() {
        let paneId = UUID()

        let decision = PaneRefocusRequestFocusDecider.decide(
            trigger: PaneRefocusRequestTrigger(reason: .explicit),
            context: PaneFocusContext(
                activeTabId: UUID(),
                activePaneId: paneId,
                activeDrawer: nil,
                targetPaneId: paneId,
                targetTabId: UUID(),
                targetPaneKind: .webview,
                targetPaneIsAlreadyActive: true,
                targetMountedContent: .unmounted,
                managementLayer: .inactive,
                windowState: .key
            )
        )

        #expect(decision.responder == .focusPaneHost(paneId: paneId))
    }

    @Test("refocus request for terminal syncs runtime and focuses host")
    func refocusTerminalPane_focusesHostAndSyncsRuntime() {
        let paneId = UUID()

        let decision = PaneRefocusRequestFocusDecider.decide(
            trigger: PaneRefocusRequestTrigger(reason: .explicit),
            context: PaneFocusContext(
                activeTabId: UUID(),
                activePaneId: paneId,
                activeDrawer: nil,
                targetPaneId: paneId,
                targetTabId: UUID(),
                targetPaneKind: .terminal,
                targetPaneIsAlreadyActive: true,
                targetMountedContent: .terminal(surfaceId: UUID()),
                managementLayer: .inactive,
                windowState: .key
            )
        )

        #expect(decision.responder == .focusPaneHost(paneId: paneId))
        #expect(decision.runtime == .syncTerminalSurface(paneId: paneId))
    }

    @Test("refocus request for mounted non-terminal content prefers mounted content")
    func refocusMountedNonTerminalContent_prefersMountedContent() {
        let paneId = UUID()

        let decision = PaneRefocusRequestFocusDecider.decide(
            trigger: PaneRefocusRequestTrigger(reason: .explicit),
            context: PaneFocusContext(
                activeTabId: UUID(),
                activePaneId: paneId,
                activeDrawer: nil,
                targetPaneId: paneId,
                targetTabId: UUID(),
                targetPaneKind: .webview,
                targetPaneIsAlreadyActive: true,
                targetMountedContent: .nonTerminal(acceptsFirstResponder: true),
                managementLayer: .inactive,
                windowState: .key
            )
        )

        #expect(decision.responder == .focusMountedContent(paneId: paneId))
    }
}

import Foundation
import Testing

@testable import AgentStudioCore
@testable import AgentStudioInfrastructure

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

    @Test("restore settlement preserves a responder chosen after restore began")
    func restoreSettlementWithUserResponder_preservesResponder() {
        let paneId = UUIDv7.generate()

        let decision = PaneRefocusRequestFocusDecider.decide(
            trigger: PaneRefocusRequestTrigger(reason: .restoreTail),
            context: terminalContext(
                paneId: paneId,
                currentResponderOwnership: .userOwned
            )
        )

        #expect(decision.responder == .preserveCurrentResponder)
        #expect(decision.runtime == .syncTerminalSurface(paneId: paneId))
    }

    @Test("restore settlement preserves user focus for mounted non-terminal content")
    func restoreSettlementPreservesUserFocusForMountedNonTerminalContent() {
        let paneId = UUIDv7.generate()

        let decision = PaneRefocusRequestFocusDecider.decide(
            trigger: PaneRefocusRequestTrigger(reason: .restoreTail),
            context: PaneFocusContext(
                activeTabId: UUIDv7.generate(),
                activePaneId: paneId,
                activeDrawer: nil,
                targetPaneId: paneId,
                targetTabId: UUIDv7.generate(),
                targetPaneKind: .bridge,
                targetPaneIsAlreadyActive: true,
                targetMountedContent: .nonTerminal(acceptsFirstResponder: true),
                managementLayer: .inactive,
                windowState: .key,
                currentResponderOwnership: .userOwned
            )
        )

        #expect(decision.responder == .preserveCurrentResponder)
        #expect(decision.runtime == .preserveRuntimeFocus)
    }

    @Test("parked restore replay preserves a responder chosen after restore began")
    func parkedRestoreReplayWithUserResponder_preservesResponder() {
        let paneId = UUIDv7.generate()

        let decision = PaneRefocusRequestFocusDecider.decide(
            trigger: PaneRefocusRequestTrigger(reason: .parkedRestoreReplay),
            context: terminalContext(
                paneId: paneId,
                currentResponderOwnership: .userOwned
            )
        )

        #expect(decision.responder == .preserveCurrentResponder)
        #expect(decision.runtime == .syncTerminalSurface(paneId: paneId))
    }

    @Test("restore settlement focuses the restored pane while the window still owns default focus")
    func restoreSettlementWithDefaultResponder_focusesRestoredPane() {
        let paneId = UUIDv7.generate()

        let decision = PaneRefocusRequestFocusDecider.decide(
            trigger: PaneRefocusRequestTrigger(reason: .restoreTail),
            context: terminalContext(
                paneId: paneId,
                currentResponderOwnership: .windowContentDefault
            )
        )

        #expect(decision.responder == .focusPaneHost(paneId: paneId))
        #expect(decision.runtime == .syncTerminalSurface(paneId: paneId))
    }

    private func terminalContext(
        paneId: UUID,
        currentResponderOwnership: PaneFocusContext.CurrentResponderOwnership
    ) -> PaneFocusContext {
        PaneFocusContext(
            activeTabId: UUIDv7.generate(),
            activePaneId: paneId,
            activeDrawer: nil,
            targetPaneId: paneId,
            targetTabId: UUIDv7.generate(),
            targetPaneKind: .terminal,
            targetPaneIsAlreadyActive: true,
            targetMountedContent: .terminal(surfaceId: UUIDv7.generate()),
            managementLayer: .inactive,
            windowState: .key,
            currentResponderOwnership: currentResponderOwnership
        )
    }
}

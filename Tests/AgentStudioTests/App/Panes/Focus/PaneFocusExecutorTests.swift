import AppKit
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct PaneFocusExecutorTests {
    init() {
        installTestAtomRegistryIfNeeded()
    }

    @Test("executor applies host responder focus without direct helper bypass")
    func executorAppliesHostResponderFocus() throws {
        let window = try makeWindow()
        let paneHost = PaneHostView(paneId: UUID())
        try attach(paneHost, to: window)

        let executor = makeExecutor()
        executor.registerHostView(paneHost)

        executor.apply(
            PaneFocusDecision.contentClick(
                PaneContentClickFocusDecision(
                    selection: .keep,
                    responder: .focusPaneHost(paneId: paneHost.paneId),
                    runtime: .preserveRuntimeFocus,
                    content: .preserve,
                    reason: .explicitRefocus
                )
            )
        )

        #expect(window.firstResponder === paneHost)
    }

    @Test("executor focuses mounted content for explicit non-terminal refocus")
    func executorFocusesMountedContentForNonTerminalRefocus() throws {
        let window = try makeWindow()
        let paneHost = PaneHostView(paneId: UUID())
        let mountedContent = FocusableMountedContentView()
        paneHost.mountContentView(mountedContent)
        try attach(paneHost, to: window)

        let executor = makeExecutor()
        executor.registerHostView(paneHost)

        executor.apply(
            PaneFocusDecision.refocusRequest(
                PaneRefocusRequestDecision(
                    responder: .focusMountedContent(paneId: paneHost.paneId),
                    runtime: .preserveRuntimeFocus,
                    reason: .explicitRefocus
                )
            )
        )

        #expect(window.firstResponder === mountedContent)
    }

    @Test("active webview content click preserves the mounted responder")
    func activeWebviewContentClickPreservesMountedResponder() throws {
        let window = try makeWindow()
        let paneHost = PaneHostView(paneId: UUID())
        let mountedContent = FocusableMountedContentView()
        paneHost.mountContentView(mountedContent)
        try attach(paneHost, to: window)
        window.makeFirstResponder(mountedContent)

        let executor = makeExecutor()
        executor.registerHostView(paneHost)

        let decision = PaneFocusOrchestrator.decide(
            trigger: .contentClick(
                PaneContentClickFocusTrigger(
                    targetPaneId: paneHost.paneId,
                    location: .content,
                    clickPhase: .completed
                )
            ),
            context: PaneFocusContext(
                activeTabId: UUID(),
                activePaneId: paneHost.paneId,
                activeDrawerParentPaneId: nil,
                activeDrawerPaneId: nil,
                targetPaneId: paneHost.paneId,
                targetTabId: UUID(),
                targetPaneKind: .webview,
                targetPaneIsAlreadyActive: true,
                targetMountedContent: .nonTerminal(acceptsFirstResponder: true),
                managementMode: .inactive,
                windowState: .key,
                triggerSource: .contentClick
            )
        )

        executor.apply(decision)

        #expect(window.firstResponder === mountedContent)
        #expect(window.firstResponder !== paneHost)
    }

    private func makeExecutor() -> PaneFocusExecutor {
        PaneFocusExecutor(
            hostViewProvider: { _ in nil },
            hostViewsProvider: { [] },
            selectTab: { _ in },
            selectPane: { _, _ in },
            selectDrawerPane: { _, _ in },
            syncRuntimeFocus: { _ in }
        )
    }

    private func makeWindow() throws -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        _ = try #require(window.contentView)
        return window
    }

    private func attach(_ view: NSView, to window: NSWindow) throws {
        let contentView = try #require(window.contentView)
        view.frame = contentView.bounds
        contentView.addSubview(view)
        view.layoutSubtreeIfNeeded()
    }
}

@MainActor
private final class FocusableMountedContentView: NSView, PaneMountedContent {
    override var acceptsFirstResponder: Bool { true }

    func setContentInteractionEnabled(_: Bool) {}
}

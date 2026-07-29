import AppKit
import SwiftUI
import Testing

@testable import AgentStudio
@testable import AgentStudioCore
@testable import AgentStudioEditorChooser
@testable import AgentStudioInfrastructure
@testable import AgentStudioSharedComponents
@testable import AgentStudioTestSupport

@MainActor
@Suite(.serialized)
struct ZoomPresentationContainerExitTests {
    init() {
        installTestAtomRegistryIfNeeded()
    }

    @Test("Zoom toolbar contracts before cancelling and ignores repeated presses")
    func zoomToolbarContractsBeforeCancelling() async throws {
        try await expectSequencedZoomExit(
            accessibilityIdentifier: "paneSurfaceToolbar.zoom",
            managementActive: false
        )
    }

    @Test("Zoom management control contracts before cancelling and ignores repeated presses")
    func zoomManagementControlContractsBeforeCancelling() async throws {
        try await expectSequencedZoomExit(
            accessibilityIdentifier: "paneManagement.zoom",
            managementActive: true
        )
    }

    private func expectSequencedZoomExit(
        accessibilityIdentifier: String,
        managementActive: Bool
    ) async throws {
        let sourcePaneId = UUID()
        let store = WorkspaceStore()
        let viewRegistry = ViewRegistry()
        let recorder = ZoomExitRecorder()
        let (cancellationEvents, cancellationContinuation) = AsyncStream.makeStream(
            of: Void.self,
            bufferingPolicy: .bufferingNewest(1)
        )
        defer { cancellationContinuation.finish() }
        if managementActive {
            atom(\.managementLayer).activate()
        }
        defer {
            if managementActive {
                atom(\.managementLayer).deactivate()
            }
        }
        let hostingView = NSHostingView(
            rootView: ZoomPresentationContainer(
                sourcePaneId: sourcePaneId,
                sourceOrdinal: 1,
                sourceContent: AnyView(Color.clear),
                companionContent: nil,
                parentToolbarPresentation: .zoom(
                    ZoomToolbarModel(
                        viewerAction: toolbarAction(
                            label: "Worktree Viewer",
                            accessibilityIdentifier: "paneSurfaceToolbar.viewer",
                            visibleLabel: nil,
                            perform: {}
                        ),
                        zoomAction: toolbarAction(
                            label: "Pane Zoom",
                            accessibilityIdentifier: "paneSurfaceToolbar.zoom",
                            visibleLabel: "Zoomed",
                            perform: {
                                recorder.cancelledSourcePaneIds.append(sourcePaneId)
                                cancellationContinuation.yield()
                            }
                        )
                    )
                ),
                splitRatio: 0.35,
                store: store,
                octiconLoader: makeTestOcticonLoader(),
                editorChooser: makeTestAtomRegistry().editorChooser,
                actionDispatcher: makeNoOpPaneActionDispatcher(),
                onPaneFocusTrigger: { _ in },
                viewRegistry: viewRegistry,
                surfaceId: "zoom-toolbar-exit-test",
                renderedPaneIds: [sourcePaneId]
            )
            .frame(width: 640, height: 360)
        )
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 640, height: 360),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = hostingView
        window.makeKeyAndOrderFront(nil)
        defer {
            window.orderOut(nil)
            window.close()
        }
        hostingView.layoutSubtreeIfNeeded()

        let zoomView = try #require(
            accessibilityPressBridgeView(
                in: hostingView,
                identifier: accessibilityIdentifier
            )
        )
        #expect(zoomView.accessibilityPerformPress())
        #expect(zoomView.accessibilityPerformPress())
        #expect(recorder.cancelledSourcePaneIds.isEmpty)

        #expect(await waitForCancellationEvent(cancellationEvents))

        #expect(recorder.cancelledSourcePaneIds == [sourcePaneId])
    }

    private func waitForCancellationEvent(
        _ cancellationEvents: AsyncStream<Void>,
        timeout: Duration = .seconds(1)
    ) async -> Bool {
        let clock = ContinuousClock()
        return await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                for await _ in cancellationEvents {
                    return true
                }
                return false
            }
            group.addTask {
                do {
                    try await clock.sleep(for: timeout)
                } catch {
                    return false
                }
                return false
            }

            let didCancel = await group.next() ?? false
            group.cancelAll()
            return didCancel
        }
    }

    private func toolbarAction(
        label: String,
        accessibilityIdentifier: String,
        visibleLabel: String?,
        perform: @escaping @MainActor @Sendable () -> Void
    ) -> PaneSurfaceToolbarAction {
        PaneSurfaceToolbarAction(
            state: PaneSurfaceToolbarAction.State(
                label: label,
                accessibilityIdentifier: accessibilityIdentifier,
                icon: .system(.rectangleSplit2x1),
                tooltip: ControlTooltipRenderValue(text: label, shortcutDisplayText: nil),
                isEnabled: true,
                isSelected: true,
                visibleLabel: visibleLabel
            ),
            perform: perform
        )
    }

    private func makeNoOpPaneActionDispatcher() -> PaneTabActionDispatcher {
        PaneTabActionDispatcher(
            dispatch: { _ in },
            shouldHandleSplitDragPayload: { _ in false },
            shouldAcceptDrop: { _, _, _, _ in false },
            handleDrop: { _, _, _, _ in }
        )
    }
}

@MainActor
private final class ZoomExitRecorder {
    var cancelledSourcePaneIds: [UUID] = []
}

@MainActor
private func accessibilityPressBridgeView(
    in root: NSView,
    identifier: String
) -> AccessibilityPressBridgeView? {
    if let bridgeView = root as? AccessibilityPressBridgeView,
        bridgeView.accessibilityIdentifier() == identifier
    {
        return bridgeView
    }
    for subview in root.subviews {
        if let bridgeView = accessibilityPressBridgeView(
            in: subview,
            identifier: identifier
        ) {
            return bridgeView
        }
    }
    return nil
}

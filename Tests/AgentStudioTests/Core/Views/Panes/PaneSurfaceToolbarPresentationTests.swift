import AgentStudioInfrastructure
import AgentStudioTestSupport
import AppKit
import Foundation
import SwiftUI
import Testing

@testable import AgentStudioCore

@MainActor
@Suite(.serialized)
struct PaneSurfaceToolbarPresentationTests {
    @Test("normal pane content maps exhaustively to its semantic toolbar role")
    func normalPaneContentMapsToSemanticToolbarRole() {
        let cases: [(content: PaneContent, expectedRole: ExpectedPaneToolbarRole)] = [
            (
                .terminal(
                    TerminalState(
                        provider: .ghostty,
                        lifetime: .temporary,
                        zmxSessionID: .generateUUIDv7()
                    )
                ),
                .terminal
            ),
            (
                .webview(
                    WebviewState(url: URL(string: "https://example.com")!)
                ),
                .webview
            ),
            (
                .codeViewer(
                    CodeViewerState(
                        filePath: URL(filePath: "/tmp/example.swift"),
                        scrollToLine: 12
                    )
                ),
                .codeViewer
            ),
            (
                .unsupported(
                    UnsupportedContent(
                        type: "future-pane",
                        version: 4,
                        rawState: nil
                    )
                ),
                .unsupported
            ),
            (
                .bridgePanel(
                    BridgePaneState(panelKind: .fileViewer, source: nil)
                ),
                .viewer
            ),
            (
                .bridgePanel(
                    BridgePaneState(panelKind: .diffViewer, source: nil)
                ),
                .viewer
            ),
        ]

        for testCase in cases {
            let presentation = PaneSurfaceToolbarResolver.resolve(
                content: testCase.content,
                placement: .normalMainPane
            )

            #expect(presentation.expectedRoleForTesting == testCase.expectedRole)
        }
    }

    @Test("Zoom child panes omit toolbar layout, interaction, and accessibility")
    func zoomChildPanesResolveToHiddenToolbar() {
        for content in paneContentFixtures {
            let presentation = PaneSurfaceToolbarResolver.resolve(
                content: content,
                placement: .zoomChild
            )

            #expect(presentation.expectedRoleForTesting == .hidden)
            #expect(!presentation.reservesToolbarLayout)
        }
    }

    @Test("normal terminal exposes Zoom then Viewer as trailing context actions")
    func normalPaneActionsRespectSemanticRoleAndPlacement() {
        let recorder = ToolbarActionRecorder()
        let viewerAction = makeAction(label: "Viewer", sourcePaneId: recorder.sourcePaneId) {
            recorder.recordViewer(sourcePaneId: $0)
        }
        let zoomAction = makeAction(label: "Pane Zoom", sourcePaneId: recorder.sourcePaneId) {
            recorder.recordZoom(sourcePaneId: $0)
        }

        let terminalPresentation = PaneSurfaceToolbarResolver.resolve(
            content: paneContentFixtures[0],
            placement: .normalMainPane,
            terminalModeActions: TerminalModeToolbarActions(
                zoomAction: zoomAction,
                viewerAction: viewerAction
            )
        )
        #expect(terminalPresentation.actionStatesForTesting.viewer?.label == viewerAction.state.label)
        #expect(terminalPresentation.actionStatesForTesting.viewer?.isSelected == false)
        #expect(terminalPresentation.actionStatesForTesting.zoom?.label == zoomAction.state.label)
        #expect(terminalPresentation.actionStatesForTesting.zoom?.visibleLabel == nil)
        #expect(terminalPresentation.actionStatesForTesting.zoom?.isSelected == false)
        #expect(terminalPresentation.leadingActions.isEmpty)
        #expect(terminalPresentation.contextActions.map(\.state.label) == ["Pane Zoom", "Viewer"])
        #expect(terminalPresentation.actions.map(\.state.label) == ["Pane Zoom", "Viewer"])

        let webviewPresentation = PaneSurfaceToolbarResolver.resolve(
            content: paneContentFixtures[1],
            placement: .normalMainPane,
            terminalModeActions: TerminalModeToolbarActions(
                zoomAction: zoomAction,
                viewerAction: viewerAction
            )
        )
        #expect(webviewPresentation.actionStatesForTesting.viewer == nil)
        #expect(webviewPresentation.actionStatesForTesting.zoom == nil)
        #expect(webviewPresentation.actions.isEmpty)

        let viewerPresentation = PaneSurfaceToolbarResolver.resolve(
            content: paneContentFixtures[4],
            placement: .normalMainPane,
            terminalModeActions: TerminalModeToolbarActions(
                zoomAction: zoomAction,
                viewerAction: viewerAction
            )
        )
        #expect(viewerPresentation.actionStatesForTesting.viewer == nil)
        #expect(viewerPresentation.actionStatesForTesting.zoom == nil)
        #expect(viewerPresentation.actions.isEmpty)

        for content in paneContentFixtures.dropFirst() {
            let presentation = PaneSurfaceToolbarResolver.resolve(
                content: content,
                placement: .normalMainPane,
                terminalModeActions: TerminalModeToolbarActions(
                    zoomAction: zoomAction,
                    viewerAction: viewerAction
                )
            )

            #expect(presentation.actions.isEmpty)
        }

        for content in paneContentFixtures {
            let drawerPresentation = PaneSurfaceToolbarResolver.resolve(
                content: content,
                placement: .drawerChild,
                terminalModeActions: TerminalModeToolbarActions(
                    zoomAction: zoomAction,
                    viewerAction: viewerAction
                )
            )

            #expect(
                drawerPresentation.expectedRoleForTesting
                    == PaneSurfaceToolbarResolver.resolve(
                        content: content,
                        placement: .normalMainPane
                    ).expectedRoleForTesting
            )
            #expect(drawerPresentation.actionStatesForTesting.viewer == nil)
            #expect(drawerPresentation.actionStatesForTesting.zoom == nil)
            #expect(drawerPresentation.actions.isEmpty)
        }
    }

    @Test("normal pane and terminal Zoom omit denied actions independently")
    func paneAndTerminalZoomActionsAreIndependentlyOptional() {
        let recorder = ToolbarActionRecorder()
        let viewerAction = makeAction(label: "Viewer", sourcePaneId: recorder.sourcePaneId) {
            recorder.recordViewer(sourcePaneId: $0)
        }
        let zoomAction = makeAction(label: "Pane Zoom", sourcePaneId: recorder.sourcePaneId) {
            recorder.recordZoom(sourcePaneId: $0)
        }

        let normalPanePresentation = PaneSurfaceToolbarResolver.resolve(
            content: paneContentFixtures[0],
            placement: .normalMainPane,
            terminalModeActions: TerminalModeToolbarActions(
                zoomAction: nil,
                viewerAction: viewerAction
            )
        )
        let terminalZoomPresentation = PaneSurfaceToolbarResolver.resolveZoom(
            viewerPresentation: .retryable,
            viewerAction: nil,
            zoomAction: zoomAction
        )

        #expect(normalPanePresentation.actions.map(\.state.label) == ["Viewer"])
        #expect(terminalZoomPresentation.actions.map(\.state.label) == ["Pane Zoom"])
    }

    @Test(
        "Zoom parent owns the only toolbar and derives Viewer selection from presentation state",
        arguments: [
            ZoomParentToolbarTestCase(
                presentation: ZoomViewerPresentation.unavailable,
                viewerEnabled: true,
                viewerSelected: false
            ),
            ZoomParentToolbarTestCase(
                presentation: ZoomViewerPresentation.unavailableVisible,
                viewerEnabled: true,
                viewerSelected: true
            ),
            ZoomParentToolbarTestCase(
                presentation: ZoomViewerPresentation.retryable,
                viewerEnabled: true,
                viewerSelected: false
            ),
            ZoomParentToolbarTestCase(
                presentation: ZoomViewerPresentation.retainedHidden(
                    companionPaneId: UUID(uuidString: "00000000-0000-0000-0000-000000000011")!
                ),
                viewerEnabled: true,
                viewerSelected: false
            ),
            ZoomParentToolbarTestCase(
                presentation: ZoomViewerPresentation.retainedVisible(
                    companionPaneId: UUID(uuidString: "00000000-0000-0000-0000-000000000012")!
                ),
                viewerEnabled: true,
                viewerSelected: true
            ),
        ]
    )
    func zoomParentToolbarState(testCase: ZoomParentToolbarTestCase) {
        let recorder = ToolbarActionRecorder()
        let viewerAction = makeAction(label: "Viewer", sourcePaneId: recorder.sourcePaneId) {
            recorder.recordViewer(sourcePaneId: $0)
        }
        let zoomAction = makeAction(label: "Pane Zoom", sourcePaneId: recorder.sourcePaneId) {
            recorder.recordZoom(sourcePaneId: $0)
        }

        let presentation = PaneSurfaceToolbarResolver.resolveZoom(
            viewerPresentation: testCase.presentation,
            viewerAction: viewerAction,
            zoomAction: zoomAction
        )

        #expect(presentation.expectedRoleForTesting == .zoom)
        #expect(presentation.actions.map(\.state.label) == ["Pane Zoom", "Viewer"])
        #expect(presentation.actionStatesForTesting.viewer?.isEnabled == testCase.viewerEnabled)
        #expect(presentation.actionStatesForTesting.viewer?.isSelected == testCase.viewerSelected)
        #expect(presentation.actionStatesForTesting.zoom?.isEnabled == true)
        #expect(presentation.actionStatesForTesting.zoom?.isSelected == true)
        #expect(presentation.actionStatesForTesting.zoom?.selectionEmphasis == .accent)
        #expect(presentation.actionStatesForTesting.zoom?.visibleLabel == "Zoomed")
        #expect(presentation.leadingActions.isEmpty)
        #expect(presentation.contextActions.map(\.state.label) == ["Pane Zoom", "Viewer"])
    }

    @Test("Zoom parent preserves dispatcher-disabled Viewer and Zoom actions")
    func zoomParentPreservesDispatcherDisabledActions() {
        let recorder = ToolbarActionRecorder()
        let viewerAction = makeAction(
            label: "Viewer",
            sourcePaneId: recorder.sourcePaneId,
            isEnabled: false
        ) {
            recorder.recordViewer(sourcePaneId: $0)
        }
        let zoomAction = makeAction(
            label: "Pane Zoom",
            sourcePaneId: recorder.sourcePaneId,
            isEnabled: false
        ) {
            recorder.recordZoom(sourcePaneId: $0)
        }

        let presentation = PaneSurfaceToolbarResolver.resolveZoom(
            viewerPresentation: .retainedVisible(
                companionPaneId: UUID(uuidString: "00000000-0000-0000-0000-000000000013")!
            ),
            viewerAction: viewerAction,
            zoomAction: zoomAction
        )

        #expect(presentation.actionStatesForTesting.viewer?.isEnabled == false)
        #expect(presentation.actionStatesForTesting.viewer?.isSelected == true)
        #expect(presentation.actionStatesForTesting.zoom?.isEnabled == false)
        #expect(presentation.actionStatesForTesting.zoom?.isSelected == true)
        #expect(presentation.actionStatesForTesting.zoom?.selectionEmphasis == .accent)
        #expect(presentation.actionStatesForTesting.zoom?.visibleLabel == "Zoomed")
    }

    @Test("toolbar resolution preserves callbacks anchored to the original source pane")
    func resolutionPreservesSourceAnchoredCallbacks() {
        let recorder = ToolbarActionRecorder()
        let viewerAction = makeAction(label: "Viewer", sourcePaneId: recorder.sourcePaneId) {
            recorder.recordViewer(sourcePaneId: $0)
        }
        let zoomAction = makeAction(label: "Pane Zoom", sourcePaneId: recorder.sourcePaneId) {
            recorder.recordZoom(sourcePaneId: $0)
        }

        let presentation = PaneSurfaceToolbarResolver.resolveZoom(
            viewerPresentation: .retryable,
            viewerAction: viewerAction,
            zoomAction: zoomAction
        )

        #expect(recorder.viewerSourcePaneIds.isEmpty)
        #expect(recorder.zoomSourcePaneIds.isEmpty)

        presentation.actionsForTesting.viewer?.perform()
        presentation.actionsForTesting.zoom?.perform()

        #expect(recorder.viewerSourcePaneIds == [recorder.sourcePaneId])
        #expect(recorder.zoomSourcePaneIds == [recorder.sourcePaneId])
    }

    @Test("drawer icon bar renders and invokes resolved pane surface actions")
    func drawerIconBarRendersResolvedPaneSurfaceActions() async throws {
        let recorder = ToolbarActionRecorder()
        let viewerAction = makeAction(label: "Viewer", sourcePaneId: recorder.sourcePaneId) {
            recorder.recordViewer(sourcePaneId: $0)
        }
        let zoomAction = makeAction(label: "Pane Zoom", sourcePaneId: recorder.sourcePaneId) {
            recorder.recordZoom(sourcePaneId: $0)
        }
        let hostingView = NSHostingView(
            rootView: DrawerIconBar(
                octiconLoader: makeCoreTestOcticonLoader(),
                leadingControls: .hidden,
                trailingActions: nil,
                paneSurfaceActions: [zoomAction, viewerAction]
            )
            .frame(width: 360, height: 40)
        )
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 360, height: 40),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }

        hostingView.layoutSubtreeIfNeeded()

        let viewerElement = try #require(
            findPaneToolbarAccessibleElement(in: hostingView, label: "Viewer")
        )
        let zoomElement = try #require(
            findPaneToolbarAccessibleElement(in: hostingView, label: "Pane Zoom")
        )

        pressPaneToolbarAccessibleElement(zoomElement)
        pressPaneToolbarAccessibleElement(viewerElement)

        await assertEventuallyMain("resolved pane toolbar actions should remain source anchored") {
            recorder.viewerSourcePaneIds == [recorder.sourcePaneId]
                && recorder.zoomSourcePaneIds == [recorder.sourcePaneId]
        }
    }

    private func makeAction(
        label: String,
        sourcePaneId: UUID,
        isEnabled: Bool = true,
        perform: @MainActor @Sendable @escaping (UUID) -> Void
    ) -> PaneSurfaceToolbarAction {
        PaneSurfaceToolbarAction(
            state: PaneSurfaceToolbarAction.State(
                label: label,
                accessibilityIdentifier: "paneSurfaceToolbar.\(label == "Pane Zoom" ? "zoom" : label.lowercased())",
                icon: .system(label == "Viewer" ? .rectangleSplit2x1 : .plusMagnifyingglass),
                tooltip: ControlTooltipRenderValue(
                    text: label,
                    shortcutDisplayText: nil
                ),
                isEnabled: isEnabled,
                isSelected: false
            ),
            perform: {
                perform(sourcePaneId)
            }
        )
    }

    private var paneContentFixtures: [PaneContent] {
        [
            .terminal(
                TerminalState(
                    provider: .ghostty,
                    lifetime: .temporary,
                    zmxSessionID: .generateUUIDv7()
                )
            ),
            .webview(WebviewState(url: URL(string: "https://example.com")!)),
            .codeViewer(
                CodeViewerState(
                    filePath: URL(filePath: "/tmp/example.swift"),
                    scrollToLine: nil
                )
            ),
            .unsupported(
                UnsupportedContent(
                    type: "future-pane",
                    version: 4,
                    rawState: nil
                )
            ),
            .bridgePanel(BridgePaneState(panelKind: .fileViewer, source: nil)),
            .bridgePanel(BridgePaneState(panelKind: .diffViewer, source: nil)),
        ]
    }
}

struct ZoomParentToolbarTestCase: Sendable {
    let presentation: ZoomViewerPresentation
    let viewerEnabled: Bool
    let viewerSelected: Bool
}

private enum ExpectedPaneToolbarRole: Equatable {
    case terminal
    case webview
    case codeViewer
    case unsupported
    case viewer
    case zoom
    case hidden
}

extension PaneSurfaceToolbarPresentation {
    fileprivate var expectedRoleForTesting: ExpectedPaneToolbarRole {
        switch self {
        case .terminal:
            .terminal
        case .webview:
            .webview
        case .codeViewer:
            .codeViewer
        case .unsupported:
            .unsupported
        case .viewer:
            .viewer
        case .zoom:
            .zoom
        case .hidden:
            .hidden
        }
    }

    fileprivate var actionStatesForTesting:
        (
            viewer: PaneSurfaceToolbarAction.State?,
            zoom: PaneSurfaceToolbarAction.State?
        )
    {
        let actions = actionsForTesting
        return (actions.viewer?.state, actions.zoom?.state)
    }

    fileprivate var actionsForTesting:
        (
            viewer: PaneSurfaceToolbarAction?,
            zoom: PaneSurfaceToolbarAction?
        )
    {
        switch self {
        case .terminal(let model):
            (model.modeActions?.viewerAction, model.modeActions?.zoomAction)
        case .webview, .codeViewer, .unsupported, .viewer:
            (nil, nil)
        case .zoom(let model):
            (model.viewerAction, model.zoomAction)
        case .hidden:
            (nil, nil)
        }
    }
}

@MainActor
private final class ToolbarActionRecorder {
    let sourcePaneId = UUID(uuidString: "00000000-0000-0000-0000-000000000010")!
    private(set) var viewerSourcePaneIds: [UUID] = []
    private(set) var zoomSourcePaneIds: [UUID] = []

    func recordViewer(sourcePaneId: UUID) {
        viewerSourcePaneIds.append(sourcePaneId)
    }

    func recordZoom(sourcePaneId: UUID) {
        zoomSourcePaneIds.append(sourcePaneId)
    }
}

@MainActor
private func findPaneToolbarAccessibleElement(in root: AnyObject, label: String) -> AnyObject? {
    var visited: Set<ObjectIdentifier> = []
    return findPaneToolbarAccessibleElement(
        in: root,
        label: label,
        visited: &visited
    )
}

@MainActor
private func findPaneToolbarAccessibleElement(
    in element: AnyObject,
    label: String,
    visited: inout Set<ObjectIdentifier>
) -> AnyObject? {
    let objectIdentifier = ObjectIdentifier(element)
    guard visited.insert(objectIdentifier).inserted else { return nil }

    if paneToolbarAccessibilityLabel(of: element) == label {
        return element
    }

    for child in paneToolbarAccessibilityChildren(of: element) {
        if let match = findPaneToolbarAccessibleElement(
            in: child,
            label: label,
            visited: &visited
        ) {
            return match
        }
    }

    for subview in (element as? NSView)?.subviews ?? [] {
        if let match = findPaneToolbarAccessibleElement(
            in: subview,
            label: label,
            visited: &visited
        ) {
            return match
        }
    }

    return nil
}

private func paneToolbarAccessibilityLabel(of element: AnyObject) -> String? {
    let selector = NSSelectorFromString("accessibilityLabel")
    guard element.responds(to: selector) else { return nil }
    return element.perform(selector)?.takeUnretainedValue() as? String
}

private func paneToolbarAccessibilityChildren(of element: AnyObject) -> [AnyObject] {
    let selector = NSSelectorFromString("accessibilityChildren")
    guard element.responds(to: selector) else { return [] }
    return element.perform(selector)?.takeUnretainedValue() as? [AnyObject] ?? []
}

private func pressPaneToolbarAccessibleElement(_ element: AnyObject) {
    let selector = NSSelectorFromString("accessibilityPerformPress")
    guard element.responds(to: selector) else { return }
    _ = element.perform(selector)
}

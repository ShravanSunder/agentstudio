import AgentStudioTestSupport
import AppKit
import SwiftUI
import Testing

@testable import AgentStudioCore

@MainActor
@Suite("ArrangementPanel mounted behavior", .serialized)
struct ArrangementPanelMountTests {
    @Test("normal terminal rows expose a targeted canonical Zoom action")
    func normalTerminalRowsExposeTargetedZoomAction() throws {
        try withTestCoreAtoms { _ in
            let paneId = UUID()
            let actionResolver = RecordingArrangementPanelActionResolver()
            let hostingView = NSHostingView(
                rootView: ArrangementPanel(
                    tabId: UUID(),
                    workspaceWindowId: nil,
                    octiconLoader: makeCoreTestOcticonLoader(),
                    panes: [
                        PaneVisibilityInfo(
                            id: paneId,
                            title: "repo | feature/pane-zoom | worktree",
                            isMinimized: false,
                            supportsZoom: true
                        )
                    ],
                    zoomMode: nil,
                    arrangements: [
                        ArrangementInfo(
                            id: UUID(),
                            name: "Default",
                            role: .defaultArrangement,
                            isActive: true
                        )
                    ],
                    inlineRenameState: ArrangementInlineRenameState(),
                    commandActionResolver: actionResolver.resolve,
                    onPaneAction: { _ in },
                    onDismiss: {}
                )
            )
            hostingView.frame = CGRect(origin: .zero, size: hostingView.fittingSize)
            hostingView.layoutSubtreeIfNeeded()

            let zoomView = try #require(
                findArrangementPanelView(
                    in: hostingView,
                    identifier: "arrangement-panel-pane-\(paneId.uuidString)-zoom"
                )
            )
            #expect(zoomView.isAccessibilityElement())
            #expect(zoomView.accessibilityLabel() == "Pane Zoom")
            #expect(zoomView.accessibilityPerformPress())
            #expect(
                actionResolver.performedRequests == [
                    ArrangementPanelActionRequest(
                        command: .zoomPane,
                        surface: .inlineControl,
                        target: paneId,
                        targetType: .pane
                    )
                ]
            )
        }
    }

    @Test("unsupported pane rows omit Zoom")
    func unsupportedRowsOmitZoom() {
        withTestCoreAtoms { _ in
            let paneId = UUID()
            let hostingView = makeArrangementPanelHostingView(
                panes: [
                    PaneVisibilityInfo(
                        id: paneId,
                        title: "Unsupported",
                        isMinimized: false,
                        supportsZoom: false
                    )
                ],
                zoomMode: nil
            )

            #expect(
                findArrangementPanelView(
                    in: hostingView,
                    identifier: "arrangement-panel-pane-\(paneId.uuidString)-zoom"
                ) == nil
            )
        }
    }

    @Test("active Pane Zoom exposes a status block with explicit Cancel Zoom")
    func activePaneZoomExposesStatusBlockWithExplicitCancelZoom() throws {
        try withTestCoreAtoms { _ in
            let sourcePaneId = UUID()
            let actionResolver = RecordingArrangementPanelActionResolver()
            let hostingView = makeArrangementPanelHostingView(
                panes: [
                    PaneVisibilityInfo(
                        id: UUID(),
                        title: "repo | feature/pane-zoom | worktree",
                        isMinimized: false,
                        supportsZoom: true
                    )
                ],
                zoomMode: ArrangementPanelZoomMode(
                    label: "Cancel Zoom",
                    sourcePaneId: sourcePaneId,
                    sourceIdentity: ArrangementPanelZoomSourceIdentity(
                        title: "repo | feature/pane-zoom | worktree",
                        detail: "/Users/example/project/worktree",
                        fullPath: "/Users/example/project/worktree"
                    )
                ),
                commandActionResolver: actionResolver.resolve
            )

            let zoomView = try #require(
                findArrangementPanelView(
                    in: hostingView,
                    identifier: "arrangement-panel-zoom-pane"
                )
            )
            let statusBlock = try #require(
                findArrangementPanelView(
                    in: hostingView,
                    identifier: "arrangement-panel-zoom-status"
                )
            )
            #expect(statusBlock.isAccessibilityElement())
            #expect(zoomView.accessibilityLabel() == "Cancel Zoom")
            #expect(zoomView.accessibilityValue() == nil)
            #expect(zoomView.accessibilityPerformPress())
            #expect(
                actionResolver.performedRequests == [
                    ArrangementPanelActionRequest(
                        command: .zoomPane,
                        surface: .inlineControl,
                        target: sourcePaneId,
                        targetType: .pane
                    )
                ]
            )
        }
    }

    @Test("pane visibility controls use targeted inline commands")
    func paneVisibilityControlsUseTargetedInlineCommands() throws {
        try withTestCoreAtoms { _ in
            let paneId = UUID()
            let actionResolver = RecordingArrangementPanelActionResolver()
            var legacyActions: [WorkspaceActionCommand] = []
            let hostingView = makeArrangementPanelHostingView(
                panes: [
                    PaneVisibilityInfo(
                        id: paneId,
                        title: "Terminal",
                        isMinimized: false
                    )
                ],
                zoomMode: nil,
                commandActionResolver: actionResolver.resolve,
                onPaneAction: { legacyActions.append($0) }
            )

            let visibilityView = try #require(
                findArrangementPanelView(
                    in: hostingView,
                    identifier: "arrangement-panel-pane-\(paneId.uuidString)-visibility"
                )
            )
            #expect(visibilityView.accessibilityPerformPress())
            #expect(
                actionResolver.performedRequests == [
                    ArrangementPanelActionRequest(
                        command: .minimizePane,
                        surface: .inlineControl,
                        target: paneId,
                        targetType: .pane
                    )
                ]
            )
            #expect(legacyActions.isEmpty)
        }
    }

    @Test("pane visibility controls use typed command tooltips")
    func paneVisibilityControlsUseTypedCommandTooltips() throws {
        let source = try String(
            contentsOfFile: "Sources/AgentStudio/Core/Views/Panes/ArrangementPanel.swift",
            encoding: .utf8
        )

        #expect(
            source.contains(
                ".controlHelp(visibilityAction.commandSpec.controlTooltipRenderValue())"
            )
        )
        #expect(!source.contains("visibilityAction.commandSpec.helpText"))
    }

    @Test("arrangement rename survives transient AppKit focus churn")
    func arrangementRenameSurvivesTransientFocusChurn() async throws {
        try await withAsyncTestCoreAtoms { _ in
            let arrangementId = UUID()
            let renameState = ArrangementInlineRenameState()
            renameState.beginEditing(
                arrangementId: arrangementId,
                currentName: "Layout 1",
                isDefault: false
            )
            let hostingView = NSHostingView(
                rootView: ArrangementPanel(
                    tabId: UUID(),
                    workspaceWindowId: nil,
                    octiconLoader: makeCoreTestOcticonLoader(),
                    panes: [],
                    zoomMode: nil,
                    arrangements: [
                        ArrangementInfo(
                            id: arrangementId,
                            name: "Layout 1",
                            role: .userLayout,
                            isActive: true
                        )
                    ],
                    inlineRenameState: renameState,
                    commandActionResolver: makePresentedCommandAction,
                    onPaneAction: { _ in },
                    onDismiss: {}
                )
            )
            let window = NSWindow(contentViewController: NSViewController())
            window.contentView = hostingView
            window.makeKeyAndOrderFront(nil)
            defer { window.close() }
            hostingView.frame = CGRect(origin: .zero, size: hostingView.fittingSize)
            hostingView.layoutSubtreeIfNeeded()

            var mountedRenameField: ArrangementRenameNSTextField?
            await assertEventuallyMain("arrangement rename field should mount") {
                mountedRenameField = findArrangementRenameField(in: hostingView)
                return mountedRenameField != nil
            }
            let renameField = try #require(mountedRenameField)
            renameField.focusAndSelectAll()
            await assertEventuallyMain("arrangement rename field should become first responder") {
                window.firstResponder === renameField.currentEditor()
            }
            let fieldEditor = try #require(renameField.currentEditor())

            window.makeFirstResponder(nil)
            await assertEventuallyMain("arrangement rename field should report editing ended") {
                renameField.currentEditor() == nil && window.firstResponder !== fieldEditor
            }

            #expect(renameState.editingArrangementId == arrangementId)
        }
    }
}

@MainActor
private func makeArrangementPanelHostingView(
    panes: [PaneVisibilityInfo],
    zoomMode: ArrangementPanelZoomMode?,
    commandActionResolver: @escaping TargetedCommandControlActionResolver =
        makePresentedCommandAction,
    onPaneAction: @escaping (WorkspaceActionCommand) -> Void = { _ in }
) -> NSHostingView<ArrangementPanel> {
    let hostingView = NSHostingView(
        rootView: ArrangementPanel(
            tabId: UUID(),
            workspaceWindowId: nil,
            octiconLoader: makeCoreTestOcticonLoader(),
            panes: panes,
            zoomMode: zoomMode,
            arrangements: [
                ArrangementInfo(
                    id: UUID(),
                    name: "Default",
                    role: .defaultArrangement,
                    isActive: true
                )
            ],
            inlineRenameState: ArrangementInlineRenameState(),
            commandActionResolver: commandActionResolver,
            onPaneAction: onPaneAction,
            onDismiss: {}
        )
    )
    hostingView.frame = CGRect(origin: .zero, size: hostingView.fittingSize)
    hostingView.layoutSubtreeIfNeeded()
    return hostingView
}

private struct ArrangementPanelActionRequest: Equatable {
    let command: AppCommand
    let surface: AppCommandSurface
    let target: UUID
    let targetType: SearchItemType
}

@MainActor
private final class RecordingArrangementPanelActionResolver {
    private(set) var requests: [ArrangementPanelActionRequest] = []
    private(set) var performedRequests: [ArrangementPanelActionRequest] = []

    func resolve(
        command: AppCommand,
        surface: AppCommandSurface,
        target: UUID,
        targetType: SearchItemType
    ) -> TargetedCommandControlAction? {
        let request = ArrangementPanelActionRequest(
            command: command,
            surface: surface,
            target: target,
            targetType: targetType
        )
        requests.append(request)
        let commandSpec = command.definition
        guard
            commandSpec.shouldPresent(
                AppCommandPresentationQuery(
                    surface: surface,
                    subject: .targeted(targetType)
                )
            )
        else {
            return nil
        }
        return TargetedCommandControlAction(
            commandSpec: commandSpec,
            isEnabled: true,
            perform: { [weak self] in
                self?.performedRequests.append(request)
            }
        )
    }
}

@MainActor
private func makePresentedCommandAction(
    command: AppCommand,
    surface: AppCommandSurface,
    target _: UUID,
    targetType: SearchItemType
) -> TargetedCommandControlAction? {
    let commandSpec = command.definition
    guard
        commandSpec.shouldPresent(
            AppCommandPresentationQuery(
                surface: surface,
                subject: .targeted(targetType)
            )
        )
    else {
        return nil
    }
    return TargetedCommandControlAction(
        commandSpec: commandSpec,
        isEnabled: true,
        perform: {}
    )
}

@MainActor
private func findArrangementPanelView(
    in root: NSView,
    identifier: String
) -> NSView? {
    if root.identifier?.rawValue == identifier {
        return root
    }

    for subview in root.subviews {
        if let match = findArrangementPanelView(in: subview, identifier: identifier) {
            return match
        }
    }
    return nil
}

@MainActor
private func findArrangementRenameField(in root: NSView) -> ArrangementRenameNSTextField? {
    if let field = root as? ArrangementRenameNSTextField {
        return field
    }
    for subview in root.subviews {
        if let field = findArrangementRenameField(in: subview) {
            return field
        }
    }
    return nil
}

import AppKit
import SwiftUI
import Testing

@testable import AgentStudio

@MainActor
@Suite("ArrangementPanel mounted behavior", .serialized)
struct ArrangementPanelMountTests {
    @Test("normal terminal rows expose a targeted canonical Zoom action")
    func normalTerminalRowsExposeTargetedZoomAction() throws {
        try AtomScope.$override.withValue(makeInstalledTestAtomRegistry()) {
            let paneId = UUID()
            var zoomTargets: [UUID?] = []
            let hostingView = NSHostingView(
                rootView: ArrangementPanel(
                    tabId: UUID(),
                    workspaceWindowId: nil,
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
                    onPaneAction: { _ in },
                    onToggleZoom: { zoomTargets.append($0) },
                    onSaveArrangement: {},
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
            #expect(zoomTargets == [paneId])
        }
    }

    @Test("unsupported pane rows omit Zoom")
    func unsupportedRowsOmitZoom() {
        AtomScope.$override.withValue(makeInstalledTestAtomRegistry()) {
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
                zoomMode: nil,
                onToggleZoom: { _ in }
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
        try AtomScope.$override.withValue(makeInstalledTestAtomRegistry()) {
            var zoomTargets: [UUID?] = []
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
                    sourceIdentity: ArrangementPanelZoomSourceIdentity(
                        title: "repo | feature/pane-zoom | worktree",
                        detail: "/Users/example/project/worktree",
                        fullPath: "/Users/example/project/worktree"
                    )
                ),
                onToggleZoom: { zoomTargets.append($0) }
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
            #expect(zoomTargets == [nil])
        }
    }

    @Test("arrangement rename survives transient AppKit focus churn")
    func arrangementRenameSurvivesTransientFocusChurn() async throws {
        try await AtomScope.$override.withValue(makeInstalledTestAtomRegistry()) {
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
                    onPaneAction: { _ in },
                    onToggleZoom: { _ in },
                    onSaveArrangement: {},
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
    onToggleZoom: @escaping (UUID?) -> Void
) -> NSHostingView<ArrangementPanel> {
    let hostingView = NSHostingView(
        rootView: ArrangementPanel(
            tabId: UUID(),
            workspaceWindowId: nil,
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
            onPaneAction: { _ in },
            onToggleZoom: onToggleZoom,
            onSaveArrangement: {},
            onDismiss: {}
        )
    )
    hostingView.frame = CGRect(origin: .zero, size: hostingView.fittingSize)
    hostingView.layoutSubtreeIfNeeded()
    return hostingView
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

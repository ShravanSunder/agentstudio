import AgentStudioInfrastructure
import Foundation
import Testing

@testable import AgentStudioCore

@Suite
struct DrawerChildContentPolicyTests {
    @Test(
        "Drawer children admit terminals and browsers only",
        arguments: [
            (DrawerChildContentKind.terminal, true),
            (.browser, true),
            (.bridge, false),
            (.codeViewer, false),
            (.unsupported, false),
        ]
    )
    func drawerChildAdmissionByKind(kind: DrawerChildContentKind, admitted: Bool) {
        #expect(DrawerChildContentPolicy.admits(kind) == admitted)
    }

    @Test("Every PaneContent variant maps to its drawer admission")
    func drawerChildAdmissionByPaneContent() throws {
        let contents: [(PaneContent, Bool)] = [
            (
                .terminal(
                    TerminalState(provider: .zmx, lifetime: .persistent, zmxSessionID: .generateUUIDv7())
                ),
                true
            ),
            (.webview(WebviewState(url: try #require(URL(string: "https://example.com")))), true),
            (.bridgePanel(BridgePaneState(panelKind: .diffViewer, source: nil)), false),
            (.codeViewer(CodeViewerState(filePath: URL(filePath: "/tmp/file.swift"), scrollToLine: nil)), false),
            (.unsupported(UnsupportedContent(type: "future", version: 1, rawState: nil)), false),
        ]

        for (content, admitted) in contents {
            #expect(DrawerChildContentPolicy.admits(content) == admitted)
        }
    }

    @Test("Drawer-child creation actions declare admitted content and pass validation")
    func drawerChildCreationActionsDeclareAdmittedContent() throws {
        let tabId = UUID()
        let parentPaneId = UUIDv7.generate()
        let drawerChildId = UUIDv7.generate()
        let snapshot = ActionStateSnapshot(
            tabs: [
                TabSnapshot(
                    id: tabId,
                    visiblePaneIds: [parentPaneId],
                    ownedPaneIds: [parentPaneId],
                    activePaneId: parentPaneId
                )
            ],
            activeTabId: tabId,
            isManagementLayerActive: false
        )
        let webviewState = WebviewState(url: try #require(URL(string: "https://example.com/drawer")))
        let creations: [(WorkspaceActionCommand, DrawerChildContentKind)] = [
            (.addDrawerPane(parentPaneId: parentPaneId), .terminal),
            (.addWebviewDrawerPane(parentPaneId: parentPaneId, state: webviewState), .browser),
            (
                .insertDrawerPane(
                    parentPaneId: parentPaneId,
                    targetDrawerPaneId: drawerChildId,
                    direction: .right,
                    sizingMode: .halveTarget
                ),
                .terminal
            ),
        ]

        for (action, kind) in creations {
            #expect(WorkspaceCommandValidator.createdDrawerChildContent(of: action) == kind)
            #expect(DrawerChildContentPolicy.admits(kind))
        }
        for action in creations.prefix(2).map(\.0) {
            #expect((try? WorkspaceCommandValidator.validate(action, state: snapshot).get())?.action == action)
        }
        #expect(WorkspaceCommandValidator.createdDrawerChildContent(of: .toggleDrawer(paneId: parentPaneId)) == nil)
    }
}

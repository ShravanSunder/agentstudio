import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("PaneTargetResolver")
struct PaneTargetResolverTests {
    private func makeStore() -> WorkspaceStore {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "agentstudio-pane-target-resolver-\(UUID().uuidString)")
        let persistor = WorkspacePersistor(workspacesDir: tempDir)
        let store = WorkspaceStore(persistor: persistor)
        store.restore()
        return store
    }

    @Test("resolves active pane target from active tab")
    func resolveActivePane() {
        let store = makeStore()
        let pane = store.createPane(
            content: .webview(WebviewState(url: URL(string: "https://example.com")!)),
            metadata: PaneMetadata(source: .floating(workingDirectory: nil, title: "A"), title: "A")
        )
        let tab = Tab(paneId: pane.id)
        store.appendTab(tab)
        store.setActiveTab(tab.id)

        let resolver = PaneTargetResolver(workspaceStore: store)
        let result = resolver.resolve(.activePane)
        #expect(result == pane.id)
    }

    @Test("returns nil when explicit pane target does not exist")
    func resolveMissingPane() {
        let store = makeStore()
        let resolver = PaneTargetResolver(workspaceStore: store)
        #expect(resolver.resolve(.pane(UUID())) == nil)
    }
}

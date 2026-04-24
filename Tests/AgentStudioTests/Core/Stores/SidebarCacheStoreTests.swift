import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct SidebarCacheStoreTests {
    private let tempDir: URL
    private let persistor: WorkspacePersistor

    init() {
        tempDir = FileManager.default.temporaryDirectory
            .appending(path: "sidebar-cache-store-tests-\(UUID().uuidString)")
        persistor = WorkspacePersistor(workspacesDir: tempDir)
        persistor.ensureDirectory()
    }

    @Test
    func flushAndRestore_roundTripsSidebarCache() throws {
        let workspaceId = UUID()
        let atom = SidebarCacheAtom()
        let store = SidebarCacheStore(atom: atom, persistor: persistor)

        atom.setGroupExpanded("repo:agent-studio", isExpanded: true)
        atom.setCheckoutColor("#ff6600", for: SidebarCheckoutColorKey("repo:agent-studio"))
        atom.setInboxGroupCollapsed(InboxNotificationGroupKey("kind:terminal"), isCollapsed: true)

        try store.flush(for: workspaceId)

        let restoredAtom = SidebarCacheAtom()
        SidebarCacheStore(atom: restoredAtom, persistor: persistor).restore(for: workspaceId)

        #expect(restoredAtom.expandedGroups == [SidebarGroupKey("repo:agent-studio")])
        #expect(restoredAtom.checkoutColors == [SidebarCheckoutColorKey("repo:agent-studio"): "#ff6600"])
        #expect(restoredAtom.collapsedInboxGroups == [InboxNotificationGroupKey("kind:terminal")])
    }

    @Test
    func restore_corruptSidebarCacheFile_fallsBackToDefaultsAndQuarantines() throws {
        let workspaceId = UUID()
        let cacheURL = tempDir.appending(path: "\(workspaceId.uuidString).workspace.sidebar-cache.json")
        try Data("not-json".utf8).write(to: cacheURL, options: .atomic)

        let atom = SidebarCacheAtom()
        SidebarCacheStore(atom: atom, persistor: persistor).restore(for: workspaceId)

        #expect(atom.expandedGroups.isEmpty)
        #expect(atom.checkoutColors.isEmpty)
        #expect(atom.collapsedInboxGroups.isEmpty)

        let quarantinedFiles = try FileManager.default.contentsOfDirectory(
            at: tempDir,
            includingPropertiesForKeys: nil
        ).filter {
            $0.lastPathComponent.hasPrefix("\(workspaceId.uuidString).workspace.sidebar-cache.corrupt-")
        }
        #expect(quarantinedFiles.count == 1)
    }
}

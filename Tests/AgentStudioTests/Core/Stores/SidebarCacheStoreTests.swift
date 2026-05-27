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

        try store.flush(for: workspaceId)

        let restoredAtom = SidebarCacheAtom()
        SidebarCacheStore(atom: restoredAtom, persistor: persistor).restore(for: workspaceId)

        #expect(restoredAtom.expandedGroups == [SidebarGroupKey("repo:agent-studio")])
        #expect(restoredAtom.checkoutColors == [SidebarCheckoutColorKey("repo:agent-studio"): "#ff6600"])
    }

    @Test
    func observedExpansionChange_autosavesSidebarCache() async throws {
        let workspaceId = UUID()
        let atom = SidebarCacheAtom()
        let store = SidebarCacheStore(
            atom: atom,
            persistor: persistor,
            persistDebounceDuration: .zero
        )
        store.restore(for: workspaceId)

        atom.setGroupExpanded(SidebarGroupKey("repo:agent-studio"), isExpanded: true)

        await assertEventuallyMain("expanded repo group should autosave") {
            switch persistor.loadSidebarCache(for: workspaceId) {
            case .loaded(let cache):
                return cache.expandedGroups == [SidebarGroupKey("repo:agent-studio")]
            case .missing, .corrupt:
                return false
            }
        }
    }

    @Test
    func restore_cancelsPendingDebouncedSaveForPreviousWorkspace() async throws {
        let workspaceAId = UUID()
        let workspaceBId = UUID()
        try persistor.saveSidebarCache(
            .init(
                workspaceId: workspaceBId,
                expandedGroups: [SidebarGroupKey("repo:workspace-b")],
                checkoutColors: [:]
            )
        )
        let atom = SidebarCacheAtom()
        let clock = TestPushClock()
        let store = SidebarCacheStore(
            atom: atom,
            persistor: persistor,
            persistDebounceDuration: .milliseconds(10),
            clock: clock
        )

        store.restore(for: workspaceAId)
        atom.setGroupExpanded(SidebarGroupKey("repo:workspace-a"), isExpanded: true)
        await clock.waitForPendingSleepCount()
        store.restore(for: workspaceBId)
        clock.advance(by: .milliseconds(10))
        await Task.yield()

        guard case .missing = persistor.loadSidebarCache(for: workspaceAId) else {
            Issue.record("Expected stale workspace A debounce to be cancelled")
            return
        }
    }

    @Test
    func restore_corruptSidebarCacheFile_fallsBackToDefaultsAndQuarantines() throws {
        let workspaceId = UUID()
        let cacheURL = tempDir.appending(path: "\(workspaceId.uuidString).workspace.sidebar-cache.json")
        try Data("not-json".utf8).write(to: cacheURL, options: .atomic)
        var reportedRecovery: PersistenceRecoveryEvent?

        let atom = SidebarCacheAtom()
        SidebarCacheStore(
            atom: atom,
            persistor: persistor,
            recoveryReporter: { reportedRecovery = $0 }
        ).restore(for: workspaceId)

        #expect(atom.expandedGroups.isEmpty)
        #expect(atom.checkoutColors.isEmpty)
        #expect(reportedRecovery?.store == .sidebarCache)
        #expect(reportedRecovery?.workspaceId == workspaceId)
        #expect(reportedRecovery?.recovery == .quarantinedAndReset)

        let quarantinedFiles = try FileManager.default.contentsOfDirectory(
            at: tempDir,
            includingPropertiesForKeys: nil
        ).filter {
            $0.lastPathComponent.hasPrefix("\(workspaceId.uuidString).workspace.sidebar-cache.corrupt-")
        }
        #expect(quarantinedFiles.count == 1)
    }

    @Test
    func restore_missingSidebarCacheFile_keepsDefaults() {
        let workspaceId = UUID()
        let atom = SidebarCacheAtom()

        SidebarCacheStore(atom: atom, persistor: persistor).restore(for: workspaceId)

        #expect(atom.expandedGroups.isEmpty)
        #expect(atom.checkoutColors.isEmpty)
    }

    @Test
    func flushFailure_reportsSaveFailedRecovery() {
        let workspaceId = UUID()
        let blockedDirectoryURL = FileManager.default.temporaryDirectory
            .appending(path: "sidebar-cache-blocked-\(UUID().uuidString)")
        try? Data("not-a-directory".utf8).write(to: blockedDirectoryURL, options: .atomic)
        let atom = SidebarCacheAtom()
        var reportedRecovery: PersistenceRecoveryEvent?
        let store = SidebarCacheStore(
            atom: atom,
            persistor: WorkspacePersistor(workspacesDir: blockedDirectoryURL),
            recoveryReporter: { reportedRecovery = $0 }
        )

        #expect(throws: Error.self) {
            try store.flush(for: workspaceId)
        }

        #expect(reportedRecovery?.store == .sidebarCache)
        #expect(reportedRecovery?.workspaceId == workspaceId)
        #expect(reportedRecovery?.recovery == .saveFailed)
    }

    @Test
    func restore_partialSidebarCachePayload_defaultsMissingSlices() throws {
        let workspaceId = UUID()
        let cacheURL = tempDir.appending(path: "\(workspaceId.uuidString).workspace.sidebar-cache.json")
        let json = """
            {
                "schemaVersion": 1,
                "workspaceId": "\(workspaceId.uuidString)",
                "checkoutColors": {"repo:agent-studio": "#ff6600"}
            }
            """
        try Data(json.utf8).write(to: cacheURL, options: .atomic)

        let atom = SidebarCacheAtom()
        SidebarCacheStore(atom: atom, persistor: persistor).restore(for: workspaceId)

        #expect(atom.expandedGroups.isEmpty)
        #expect(atom.checkoutColors == [SidebarCheckoutColorKey("repo:agent-studio"): "#ff6600"])
    }
}

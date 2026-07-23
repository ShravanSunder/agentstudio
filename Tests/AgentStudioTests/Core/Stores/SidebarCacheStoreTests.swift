import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct SidebarCacheStoreTests {
    @Test
    func flushAndRestoreRoundTripsMainWindowExpandedGroups() async throws {
        let workspaceId = UUID()
        let fixture = try makeWorkspaceLocalSQLiteStoreFixture(workspaceId: workspaceId)
        let datastore = try workspaceSQLiteDatastore(from: fixture.sqliteBackend)
        let atom = SidebarCacheState()
        let expandedGroup = SidebarGroupKey("repo:agent-studio")
        atom.setGroupExpanded(expandedGroup, isExpanded: true)

        try await SidebarCacheStore(atom: atom, sqliteDatastore: datastore).flushAsync(for: workspaceId)
        let restoredAtom = SidebarCacheState()
        await SidebarCacheStore(atom: restoredAtom, sqliteDatastore: datastore).restoreAsync(for: workspaceId)

        #expect(restoredAtom.expandedGroups == [expandedGroup])
    }

    @Test
    func missingSQLiteRowsResetExistingStateToTypedDefaults() async throws {
        let workspaceId = UUID()
        let fixture = try makeWorkspaceLocalSQLiteStoreFixture(workspaceId: workspaceId)
        let atom = SidebarCacheState()
        atom.setGroupExpanded(SidebarGroupKey("repo:stale"), isExpanded: true)

        await SidebarCacheStore(
            atom: atom,
            sqliteDatastore: try workspaceSQLiteDatastore(from: fixture.sqliteBackend)
        ).restoreAsync(for: workspaceId)

        #expect(atom.expandedGroups.isEmpty)
    }

    @Test
    func unavailableSQLiteResetsDefaultsAndReportsRecovery() async throws {
        let workspaceId = UUID()
        let atom = SidebarCacheState()
        atom.setGroupExpanded(SidebarGroupKey("repo:stale"), isExpanded: true)
        var reportedRecoveries: [PersistenceRecoveryEvent] = []

        await SidebarCacheStore(
            atom: atom,
            sqliteDatastore: try workspaceSQLiteDatastore(from: failingWorkspaceLocalSQLiteBackend()),
            recoveryReporter: { reportedRecoveries.append($0) }
        ).restoreAsync(for: workspaceId)

        #expect(atom.expandedGroups.isEmpty)
        #expect(
            reportedRecoveries.contains { recovery in
                recovery.store == .sidebarCache
                    && recovery.workspaceId == workspaceId
                    && recovery.recovery == .resetToDefaults
            })
    }

    @Test
    func observedExpansionChangeAutosavesSQLite() async throws {
        let workspaceId = UUID()
        let fixture = try makeWorkspaceLocalSQLiteStoreFixture(workspaceId: workspaceId)
        let atom = SidebarCacheState()
        let clock = TestPushClock()
        let expandedGroup = SidebarGroupKey("repo:agent-studio")
        let store = SidebarCacheStore(
            atom: atom,
            sqliteDatastore: try workspaceSQLiteDatastore(from: fixture.sqliteBackend),
            persistDebounceDuration: .milliseconds(10),
            clock: clock
        )
        await store.restoreAsync(for: workspaceId)
        store.startObserving()

        atom.setGroupExpanded(expandedGroup, isExpanded: true)
        await clock.waitForPendingSleepCount()
        clock.advance(by: .milliseconds(10))

        await assertEventuallyMain("expanded group should autosave") {
            (try? fixture.repository.fetchExpandedGroups()) == [expandedGroup]
        }
    }

    @Test
    func directWriteOwnerMutationAutosavesThroughComposedState() async throws {
        let workspaceId = UUID()
        let fixture = try makeWorkspaceLocalSQLiteStoreFixture(workspaceId: workspaceId)
        let expandedGroupAtom = SidebarExpandedGroupAtom()
        let atom = SidebarCacheState(expandedGroupAtom: expandedGroupAtom)
        let clock = TestPushClock()
        let expandedGroup = SidebarGroupKey("repo:agent-studio")
        let store = SidebarCacheStore(
            atom: atom,
            sqliteDatastore: try workspaceSQLiteDatastore(from: fixture.sqliteBackend),
            persistDebounceDuration: .milliseconds(10),
            clock: clock
        )
        await store.restoreAsync(for: workspaceId)
        store.startObserving()

        expandedGroupAtom.setGroupExpanded(expandedGroup, isExpanded: true)
        await clock.waitForPendingSleepCount()
        clock.advance(by: .milliseconds(10))

        await assertEventuallyMain("write-owner mutation should autosave") {
            (try? fixture.repository.fetchExpandedGroups()) == [expandedGroup]
        }
    }

    @Test
    func restoreCancelsPendingSaveFromPreviousWorkspaceContext() async throws {
        let workspaceAId = UUID()
        let workspaceBId = UUID()
        let fixture = try makeWorkspaceLocalSQLiteStoreFixture(workspaceId: workspaceAId)
        let atom = SidebarCacheState()
        let clock = TestPushClock()
        let store = SidebarCacheStore(
            atom: atom,
            sqliteDatastore: try workspaceSQLiteDatastore(from: fixture.sqliteBackend),
            persistDebounceDuration: .milliseconds(10),
            clock: clock
        )
        await store.restoreAsync(for: workspaceAId)
        store.startObserving()
        atom.setGroupExpanded(SidebarGroupKey("repo:stale-workspace"), isExpanded: true)
        await clock.waitForPendingSleepCount()

        await store.restoreAsync(for: workspaceBId)
        clock.advance(by: .milliseconds(10))
        await Task.yield()

        #expect(try fixture.repository.hasExpandedGroupsState() == false)
    }

    @Test
    func observationIsExplicitlyArmed() async throws {
        let workspaceId = UUID()
        let fixture = try makeWorkspaceLocalSQLiteStoreFixture(workspaceId: workspaceId)
        let store = SidebarCacheStore(
            atom: SidebarCacheState(),
            sqliteDatastore: try workspaceSQLiteDatastore(from: fixture.sqliteBackend)
        )

        #expect(store.isAutosaveObservationActive == false)
        await store.restoreAsync(for: workspaceId)
        #expect(store.isAutosaveObservationActive == false)
        store.startObserving()
        #expect(store.isAutosaveObservationActive)
    }
}

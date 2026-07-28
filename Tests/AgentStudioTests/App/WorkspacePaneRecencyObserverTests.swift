import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("PaneRecency Observer", .serialized)
struct WorkspacePaneRecencyObserverTests {
    private enum IneligiblePaneScenario: CaseIterable {
        case drawerChild
        case backgrounded
        case pendingUndo
        case orphaned
        case unreachable
        case nonActiveWorkspace
    }

    init() {
        installTestAtomRegistryIfNeeded()
    }

    @Test("retains pane identity across nil and records only a different pane")
    func nilRoundTrip_recordsOnlyDifferentPane() async throws {
        try await withAsyncTestAtomRegistry { atoms in
            let store = WorkspaceStore(
                identityAtom: atoms.workspaceIdentity,
                windowMemoryAtom: atoms.workspaceWindowMemory,
                repositoryTopologyAtom: atoms.workspaceRepositoryTopology,
                paneAtom: atoms.workspacePane,
                tabLayoutAtom: atoms.workspaceTabLayout,
                mutationCoordinator: atoms.workspaceMutationCoordinator
            )
            let paneA = store.createPane(title: "A")
            let paneB = store.createPane(title: "B")
            let tab = Tab(paneId: paneA.id)
            store.appendTab(tab)
            #expect(
                store.insertPane(
                    paneB.id,
                    inTab: tab.id,
                    at: paneA.id,
                    direction: .horizontal,
                    position: .after,
                    sizingMode: .halveTarget
                )
            )
            store.setActivePane(paneA.id, inTab: tab.id)
            atoms.workspaceEntityRecency.hydrate(
                workspaceID: store.workspaceId,
                recentEntities: []
            )
            let windowID = UUID()
            atoms.windowLifecycle.recordWindowRegistered(windowID)
            atoms.windowLifecycle.recordWindowBecameKey(windowID)
            let observer = WorkspacePaneRecencyObserver(
                store: store,
                attendedPane: atoms.attendedPane,
                recencyAtom: atoms.workspaceEntityRecency,
                now: { Date(timeIntervalSince1970: 900) }
            )
            defer { observer.stop() }

            atoms.windowLifecycle.recordWindowResignedKey(windowID)
            await Task.yield()
            atoms.windowLifecycle.recordWindowBecameKey(windowID)
            await Task.yield()

            #expect(atoms.workspaceEntityRecency.recentEntities.isEmpty)

            store.setActivePane(paneB.id, inTab: tab.id)
            await eventually("different attended pane should be recorded") {
                atoms.workspaceEntityRecency.recentEntities.count == 1
            }

            let recency = try #require(atoms.workspaceEntityRecency.recentEntities.first)
            #expect(recency.workspaceID == store.workspaceId)
            #expect(recency.entity == .pane(paneID: paneB.id))
            #expect(recency.interaction == .focused)
            #expect(recency.lastInteractedAt == Date(timeIntervalSince1970: 900))

            store.setActivePane(paneB.id, inTab: tab.id)
            for _ in 0..<10 {
                await Task.yield()
            }
            #expect(atoms.workspaceEntityRecency.recentEntities.count == 1)
        }
    }

    @Test("records every attended pane when transitions occur in one MainActor turn")
    func rapidTransitions_recordEveryAttendedPane() async throws {
        await withAsyncTestAtomRegistry { atoms in
            let store = WorkspaceStore(
                identityAtom: atoms.workspaceIdentity,
                windowMemoryAtom: atoms.workspaceWindowMemory,
                repositoryTopologyAtom: atoms.workspaceRepositoryTopology,
                paneAtom: atoms.workspacePane,
                tabLayoutAtom: atoms.workspaceTabLayout,
                mutationCoordinator: atoms.workspaceMutationCoordinator
            )
            let paneA = store.createPane(title: "A")
            let paneB = store.createPane(title: "B")
            let paneC = store.createPane(title: "C")
            let tab = Tab(paneId: paneA.id)
            store.appendTab(tab)
            #expect(
                store.insertPane(
                    paneB.id,
                    inTab: tab.id,
                    at: paneA.id,
                    direction: .horizontal,
                    position: .after,
                    sizingMode: .halveTarget
                )
            )
            #expect(
                store.insertPane(
                    paneC.id,
                    inTab: tab.id,
                    at: paneB.id,
                    direction: .horizontal,
                    position: .after,
                    sizingMode: .halveTarget
                )
            )
            store.setActivePane(paneA.id, inTab: tab.id)
            atoms.workspaceEntityRecency.hydrate(
                workspaceID: store.workspaceId,
                recentEntities: []
            )
            let windowID = UUID()
            atoms.windowLifecycle.recordWindowRegistered(windowID)
            atoms.windowLifecycle.recordWindowBecameKey(windowID)
            var timestamp = Date(timeIntervalSince1970: 900)
            let observer = WorkspacePaneRecencyObserver(
                store: store,
                attendedPane: atoms.attendedPane,
                recencyAtom: atoms.workspaceEntityRecency,
                now: {
                    timestamp.addTimeInterval(1)
                    return timestamp
                }
            )
            defer { observer.stop() }

            store.setActivePane(paneB.id, inTab: tab.id)
            store.setActivePane(paneC.id, inTab: tab.id)
            await eventually("both rapid attended-pane transitions should be recorded") {
                atoms.workspaceEntityRecency.recentEntities.count == 2
            }

            #expect(
                Set(atoms.workspaceEntityRecency.recentEntities.map(\.entity))
                    == Set([
                        .pane(paneID: paneB.id),
                        .pane(paneID: paneC.id),
                    ])
            )
        }
    }

    @Test("stop records the pending attended-pane transition before cancelling delivery")
    func stop_recordsPendingAttendedPaneTransition() async {
        await withAsyncTestAtomRegistry { atoms in
            let store = WorkspaceStore(
                identityAtom: atoms.workspaceIdentity,
                windowMemoryAtom: atoms.workspaceWindowMemory,
                repositoryTopologyAtom: atoms.workspaceRepositoryTopology,
                paneAtom: atoms.workspacePane,
                tabLayoutAtom: atoms.workspaceTabLayout,
                mutationCoordinator: atoms.workspaceMutationCoordinator
            )
            let paneA = store.createPane(title: "A")
            let paneB = store.createPane(title: "B")
            let tab = Tab(paneId: paneA.id)
            store.appendTab(tab)
            #expect(
                store.insertPane(
                    paneB.id,
                    inTab: tab.id,
                    at: paneA.id,
                    direction: .horizontal,
                    position: .after,
                    sizingMode: .halveTarget
                )
            )
            store.setActivePane(paneA.id, inTab: tab.id)
            atoms.workspaceEntityRecency.hydrate(
                workspaceID: store.workspaceId,
                recentEntities: []
            )
            let windowID = UUID()
            atoms.windowLifecycle.recordWindowRegistered(windowID)
            atoms.windowLifecycle.recordWindowBecameKey(windowID)
            let observer = WorkspacePaneRecencyObserver(
                store: store,
                attendedPane: atoms.attendedPane,
                recencyAtom: atoms.workspaceEntityRecency,
                now: { Date(timeIntervalSince1970: 900) }
            )

            store.setActivePane(paneB.id, inTab: tab.id)
            observer.stop()

            #expect(
                atoms.workspaceEntityRecency.recentEntities.map(\.entity)
                    == [.pane(paneID: paneB.id)]
            )
        }
    }

    @Test("records an attended pane after its eligibility settles")
    func provisionalIneligibleTransition_recordsAfterEligibilitySettles() async {
        await withAsyncTestAtomRegistry { atoms in
            let store = WorkspaceStore(
                identityAtom: atoms.workspaceIdentity,
                windowMemoryAtom: atoms.workspaceWindowMemory,
                repositoryTopologyAtom: atoms.workspaceRepositoryTopology,
                paneAtom: atoms.workspacePane,
                tabLayoutAtom: atoms.workspaceTabLayout,
                mutationCoordinator: atoms.workspaceMutationCoordinator
            )
            let paneA = store.createPane(title: "A")
            let paneB = store.createPane(title: "B")
            let tab = Tab(paneId: paneA.id)
            store.appendTab(tab)
            _ = store.insertPane(
                paneB.id,
                inTab: tab.id,
                at: paneA.id,
                direction: .horizontal,
                position: .after,
                sizingMode: .halveTarget
            )
            store.setActivePane(paneA.id, inTab: tab.id)
            store.setResidency(.backgrounded, for: paneB.id)
            atoms.workspaceEntityRecency.hydrate(
                workspaceID: store.workspaceId,
                recentEntities: []
            )
            let windowID = UUID()
            atoms.windowLifecycle.recordWindowRegistered(windowID)
            atoms.windowLifecycle.recordWindowBecameKey(windowID)
            let observer = WorkspacePaneRecencyObserver(
                store: store,
                attendedPane: atoms.attendedPane,
                recencyAtom: atoms.workspaceEntityRecency
            )
            defer { observer.stop() }

            store.setActivePane(paneB.id, inTab: tab.id)
            atoms.windowLifecycle.recordWindowResignedKey(windowID)
            store.setResidency(.active, for: paneB.id)
            atoms.windowLifecycle.recordWindowBecameKey(windowID)

            await eventually("settled eligible pane should be recorded") {
                atoms.workspaceEntityRecency.recentEntities.map(\.entity)
                    == [.pane(paneID: paneB.id)]
            }
        }
    }

    @Test("rejects every pane that is not a live canonical focus target")
    func ineligiblePanes_areNotRecorded() async {
        for scenario in IneligiblePaneScenario.allCases {
            await assertScenarioDoesNotRecord(scenario)
        }
    }

    @Test("rejects malformed duplicate and non-targetable canonical snapshots")
    func malformedCanonicalSnapshots_areRejected() {
        let pane = Pane(
            content: .terminal(
                TerminalState(
                    provider: .zmx,
                    lifetime: .persistent,
                    zmxSessionID: .generateUUIDv7()
                )
            ),
            metadata: PaneMetadata(title: "Target")
        )
        let firstTab = Tab(paneId: pane.id)
        let duplicateTab = Tab(paneId: pane.id)
        let unrelatedTab = Tab(paneId: UUID())

        #expect(
            !WorkspacePaneRecencyObserver.isEligibleForRecording(
                pane: pane,
                workspaceMatches: true,
                tabs: [firstTab, duplicateTab],
                targetableTabID: firstTab.id
            )
        )
        #expect(
            !WorkspacePaneRecencyObserver.isEligibleForRecording(
                pane: pane,
                workspaceMatches: true,
                tabs: [unrelatedTab],
                targetableTabID: unrelatedTab.id
            )
        )
        #expect(
            !WorkspacePaneRecencyObserver.isEligibleForRecording(
                pane: pane,
                workspaceMatches: true,
                tabs: [firstTab],
                targetableTabID: nil
            )
        )
    }

    @Test("AppDelegate composition starts and stops pane recency observation")
    func appDelegateComposition_startsAndStopsObservation() async {
        await withAsyncTestAtomRegistry { atoms in
            let store = WorkspaceStore(
                identityAtom: atoms.workspaceIdentity,
                windowMemoryAtom: atoms.workspaceWindowMemory,
                repositoryTopologyAtom: atoms.workspaceRepositoryTopology,
                paneAtom: atoms.workspacePane,
                tabLayoutAtom: atoms.workspaceTabLayout,
                mutationCoordinator: atoms.workspaceMutationCoordinator
            )
            let paneA = store.createPane(title: "A")
            let paneB = store.createPane(title: "B")
            let tab = Tab(paneId: paneA.id)
            store.appendTab(tab)
            _ = store.insertPane(
                paneB.id,
                inTab: tab.id,
                at: paneA.id,
                direction: .horizontal,
                position: .after,
                sizingMode: .halveTarget
            )
            store.setActivePane(paneA.id, inTab: tab.id)
            atoms.workspaceEntityRecency.hydrate(
                workspaceID: store.workspaceId,
                recentEntities: []
            )
            let windowID = UUID()
            atoms.windowLifecycle.recordWindowRegistered(windowID)
            atoms.windowLifecycle.recordWindowBecameKey(windowID)
            let delegate = AppDelegate()
            delegate.atomStore = atoms
            delegate.store = store

            delegate.startWorkspacePaneRecencyObservation()
            store.setActivePane(paneB.id, inTab: tab.id)
            await eventually("AppDelegate observer should record") {
                atoms.workspaceEntityRecency.recentEntities.count == 1
            }

            delegate.stopWorkspacePaneRecencyObservation()
            store.setActivePane(paneA.id, inTab: tab.id)
            for _ in 0..<20 {
                await Task.yield()
            }

            #expect(atoms.workspaceEntityRecency.recentEntities.count == 1)
            #expect(delegate.workspacePaneRecencyObserver == nil)
        }
    }

    private func assertScenarioDoesNotRecord(
        _ scenario: IneligiblePaneScenario
    ) async {
        await withAsyncTestAtomRegistry { atoms in
            let store = WorkspaceStore(
                identityAtom: atoms.workspaceIdentity,
                windowMemoryAtom: atoms.workspaceWindowMemory,
                repositoryTopologyAtom: atoms.workspaceRepositoryTopology,
                paneAtom: atoms.workspacePane,
                tabLayoutAtom: atoms.workspaceTabLayout,
                mutationCoordinator: atoms.workspaceMutationCoordinator
            )
            let paneA = store.createPane(title: "A")
            let paneB = store.createPane(title: "B")
            let tab = Tab(paneId: paneA.id)
            store.appendTab(tab)
            _ = store.insertPane(
                paneB.id,
                inTab: tab.id,
                at: paneA.id,
                direction: .horizontal,
                position: .after,
                sizingMode: .halveTarget
            )
            store.setActivePane(paneA.id, inTab: tab.id)
            atoms.workspaceEntityRecency.hydrate(
                workspaceID: store.workspaceId,
                recentEntities: []
            )
            let windowID = UUID()
            atoms.windowLifecycle.recordWindowRegistered(windowID)
            atoms.windowLifecycle.recordWindowBecameKey(windowID)
            let observer = WorkspacePaneRecencyObserver(
                store: store,
                attendedPane: atoms.attendedPane,
                recencyAtom: atoms.workspaceEntityRecency
            )
            defer { observer.stop() }

            switch scenario {
            case .drawerChild:
                if var state = atoms.workspacePaneGraph.paneState(paneB.id) {
                    state.kind = .drawerChild(parentPaneId: paneA.id)
                    atoms.workspacePaneGraph.setCanonicalPaneState(state)
                }
            case .backgrounded:
                store.setResidency(.backgrounded, for: paneB.id)
            case .pendingUndo:
                store.setResidency(
                    .pendingUndo(expiresAt: Date(timeIntervalSince1970: 1000)),
                    for: paneB.id
                )
            case .orphaned:
                store.setResidency(
                    .orphaned(reason: .worktreeNotFound(path: "/missing")),
                    for: paneB.id
                )
            case .unreachable:
                _ = atoms.workspacePaneGraph.removeCanonicalPaneState(for: paneB.id)
            case .nonActiveWorkspace:
                atoms.workspaceEntityRecency.hydrate(
                    workspaceID: UUID(),
                    recentEntities: []
                )
            }

            store.setActivePane(paneB.id, inTab: tab.id)
            for _ in 0..<20 {
                await Task.yield()
            }

            #expect(
                atoms.workspaceEntityRecency.recentEntities.isEmpty,
                "Unexpected recency for \(String(describing: scenario))"
            )
        }
    }
}

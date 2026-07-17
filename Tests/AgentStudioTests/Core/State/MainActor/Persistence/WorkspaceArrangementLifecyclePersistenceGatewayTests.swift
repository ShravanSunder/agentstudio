import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("Workspace arrangement lifecycle persistence gateway")
struct ArrangementLifecyclePersistenceTests {
    @Test("preinstall rejects without revision")
    func preinstallRejectsWithoutRevision() {
        // Arrange
        let runtime = WorkspacePersistenceRuntime(atomRegistry: AtomRegistry())
        let request = WorkspaceRemoveArrangementRequest(tabID: UUIDv7.generate(), arrangementID: UUIDv7.generate())

        // Act
        let result = runtime.mutationCoordinator.removeArrangement(request)

        // Assert
        #expect(result == .rejected(.compositionDomainNotInstalled(phase: .preinstall)))
        #expect(runtime.revisionOwner.committedRevision == .zero)
    }

    @Test("installed create commits one revision, retains target preimage, and excludes new cursor from base")
    func installedCreateHasOneRevisionAndExactBase() throws {
        // Arrange
        let fixture = makeArrangementLifecycleFixture()
        let unrelated = (0..<256).map { _ in makeArrangementLifecycleFixture().tab }
        let registry = makeArrangementLifecycleRegistry(fixture: fixture, unrelated: unrelated)
        let runtime = WorkspacePersistenceRuntime(atomRegistry: registry)
        let installed = try installArrangementLifecycleParticipants(runtime)
        let newID = WorkspaceNewArrangementID.generate()

        // Act
        let result = runtime.mutationCoordinator.createArrangement(
            .init(tabID: fixture.tab.tabId, arrangementID: newID, name: "Created")
        )

        // Assert
        guard case .changed(let revision) = result else {
            Issue.record("expected installed create")
            return
        }
        #expect(revision.rawValue == 1)
        #expect(runtime.revisionOwner.committedRevision == revision)
        #expect(registry.workspaceTabGraph.tabID(containingArrangement: newID.rawValue) == fixture.tab.tabId)
        #expect(Array(registry.workspaceTabGraph.tabStates.prefix(256)) == unrelated)
        #expect(
            try baseItems(installed, participantID: .tabGraphs).contains(
                .tabGraph(fixture.tab)
            )
        )
        #expect(
            try baseItems(installed, participantID: .activePanes).contains { item in
                item.snapshotItemID == .activePane(arrangementID: newID.rawValue)
            } == false
        )
        #expect(
            try baseItems(installed, participantID: .activeDrawerChildren).contains { item in
                item.snapshotItemID
                    == .activeDrawerChild(
                        .init(arrangementId: newID.rawValue, drawerId: fixture.drawerID)
                    )
            } == false
        )
        closeArrangementLifecycleParticipants(installed)
    }

    @Test("installed active removal retains removed graph and cursor base items")
    func installedRemovalRetainsRemovedBaseItems() throws {
        // Arrange
        let fixture = makeArrangementLifecycleFixture()
        let registry = makeArrangementLifecycleRegistry(fixture: fixture)
        let runtime = WorkspacePersistenceRuntime(atomRegistry: registry)
        let installed = try installArrangementLifecycleParticipants(runtime)

        // Act
        let result = runtime.mutationCoordinator.removeArrangement(
            .init(tabID: fixture.tab.tabId, arrangementID: fixture.activeArrangement.id)
        )

        // Assert
        guard case .changed(let revision) = result else {
            Issue.record("expected installed removal")
            return
        }
        #expect(revision.rawValue == 1)
        #expect(registry.workspaceTabGraph.tabID(containingArrangement: fixture.activeArrangement.id) == nil)
        #expect(registry.workspaceArrangementCursor.hasPaneCursor(arrangementID: fixture.activeArrangement.id) == false)
        #expect(try baseItems(installed, participantID: .tabGraphs).contains(.tabGraph(fixture.tab)))
        #expect(
            try baseItems(installed, participantID: .activePanes).contains(
                .activePane(
                    arrangementID: fixture.activeArrangement.id,
                    paneID: fixture.mainPaneIDs[1]
                )
            )
        )
        #expect(
            try baseItems(installed, participantID: .activeArrangements).contains(
                .activeArrangement(
                    tabID: fixture.tab.tabId,
                    arrangementID: fixture.activeArrangement.id
                )
            )
        )
        #expect(
            try baseItems(installed, participantID: .activeDrawerChildren).contains(
                .activeDrawerChild(
                    key: .init(
                        arrangementId: fixture.activeArrangement.id,
                        drawerId: fixture.drawerID
                    ),
                    childPaneID: fixture.drawerPaneIDs[0]
                )
            )
        )
        closeArrangementLifecycleParticipants(installed)
    }

    @Test("installed inactive removal preserves active selection and removed cursor base items")
    func installedInactiveRemovalPreservesSelectionAndBaseItems() throws {
        // Arrange
        let fixture = makeArrangementLifecycleFixture()
        let registry = makeArrangementLifecycleRegistry(fixture: fixture)
        registry.workspaceArrangementCursor.setActiveArrangementId(
            fixture.defaultArrangement.id,
            forTab: fixture.tab.tabId
        )
        let runtime = WorkspacePersistenceRuntime(atomRegistry: registry)
        let installed = try installArrangementLifecycleParticipants(runtime)

        // Act
        let result = runtime.mutationCoordinator.removeArrangement(
            .init(tabID: fixture.tab.tabId, arrangementID: fixture.activeArrangement.id)
        )

        // Assert
        guard case .changed(let revision) = result else {
            Issue.record("expected installed inactive removal")
            return
        }
        #expect(revision.rawValue == 1)
        #expect(
            registry.workspaceArrangementCursor.activeArrangementId(forTab: fixture.tab.tabId)
                == fixture.defaultArrangement.id
        )
        #expect(
            try baseItems(installed, participantID: .activePanes).contains(
                .activePane(
                    arrangementID: fixture.activeArrangement.id,
                    paneID: fixture.mainPaneIDs[1]
                )
            )
        )
        #expect(
            try baseItems(installed, participantID: .activeDrawerChildren).contains(
                .activeDrawerChild(
                    key: .init(
                        arrangementId: fixture.activeArrangement.id,
                        drawerId: fixture.drawerID
                    ),
                    childPaneID: fixture.drawerPaneIDs[0]
                )
            )
        )
        closeArrangementLifecycleParticipants(installed)
    }

    @Test("present no-selection cursor removal commits without false cursor capture")
    func nilCursorRemovalCommits() throws {
        // Arrange
        var fixture = makeArrangementLifecycleFixture()
        let mainPaneIDs = fixture.mainPaneIDs
        let drawerPaneIDs = fixture.drawerPaneIDs
        let drawerID = fixture.drawerID
        fixture.tab.arrangements[1].minimizedPaneIds = Set(mainPaneIDs)
        var drawer = fixture.tab.arrangements[1].drawerViews[drawerID]!
        drawer.minimizedPaneIds = Set(drawerPaneIDs)
        fixture.tab.arrangements[1].drawerViews[drawerID] = drawer
        let registry = makeArrangementLifecycleRegistry(fixture: fixture)
        registry.workspaceArrangementCursor.setPaneCursor(
            .init(activePaneId: nil),
            forArrangement: fixture.activeArrangement.id
        )
        registry.workspaceArrangementCursor.setDrawerCursor(
            .init(activeChildId: nil),
            for: .init(arrangementId: fixture.activeArrangement.id, drawerId: fixture.drawerID)
        )
        let runtime = WorkspacePersistenceRuntime(atomRegistry: registry)
        let installed = try installArrangementLifecycleParticipants(runtime)

        // Act
        let result = runtime.mutationCoordinator.removeArrangement(
            .init(tabID: fixture.tab.tabId, arrangementID: fixture.activeArrangement.id)
        )

        // Assert
        guard case .changed(let revision) = result else {
            Issue.record("expected no-selection removal")
            return
        }
        #expect(revision.rawValue == 1)
        #expect(registry.workspaceArrangementCursor.hasPaneCursor(arrangementID: fixture.activeArrangement.id) == false)
        #expect(
            try baseItems(installed, participantID: .activePanes).contains { item in
                item.snapshotItemID == .activePane(arrangementID: fixture.activeArrangement.id)
            } == false
        )
        #expect(
            try baseItems(installed, participantID: .activeDrawerChildren).contains { item in
                item.snapshotItemID
                    == .activeDrawerChild(
                        .init(
                            arrangementId: fixture.activeArrangement.id,
                            drawerId: fixture.drawerID
                        )
                    )
            } == false
        )
        closeArrangementLifecycleParticipants(installed)
    }

    @Test("gateway is target-keyed and dormant outside its coordinator")
    func gatewayIsTargetKeyedAndDormant() throws {
        // Arrange
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let gateway = try String(
            contentsOf: projectRoot.appending(
                path:
                    "Sources/AgentStudio/Core/State/MainActor/Persistence/"
                    + "WorkspaceArrangementLifecyclePersistenceGateway.swift"
            ),
            encoding: .utf8
        )
        let productionRoots = ["Sources/AgentStudio/App", "Sources/AgentStudio/Features"]

        // Act
        let callers = try productionRoots.flatMap { relativeRoot -> [String] in
            let root = projectRoot.appending(path: relativeRoot)
            return try FileManager.default.subpathsOfDirectory(atPath: root.path).compactMap { relativePath in
                guard relativePath.hasSuffix(".swift") else { return nil }
                let source = try String(contentsOf: root.appending(path: relativePath), encoding: .utf8)
                return source.contains("mutationCoordinator.createArrangement")
                    || source.contains("mutationCoordinator.removeArrangement")
                    ? "\(relativeRoot)/\(relativePath)" : nil
            }
        }

        // Assert
        #expect(gateway.contains("workspaceTabGraphAtom.tabState(request.tabID)"))
        #expect(gateway.contains("activeArrangementId(forTab: request.tabID)"))
        #expect(!gateway.contains("workspaceTabGraphAtom.tabStates"))
        #expect(!gateway.contains("activeArrangementIdsByTabId"))
        #expect(!gateway.contains("paneCursorsByArrangementId"))
        #expect(!gateway.contains("drawerCursorsByKey"))
        #expect(callers.isEmpty)
    }
}

@MainActor
private func makeArrangementLifecycleRegistry(
    fixture: ArrangementLifecycleFixture,
    unrelated: [TabGraphState] = []
) -> AtomRegistry {
    let registry = AtomRegistry()
    registry.workspaceTabGraph.replaceTabStates(unrelated + [fixture.tab])
    var activeArrangements = [fixture.tab.tabId: fixture.activeArrangement.id]
    var paneCursors: [UUID: ArrangementPaneCursorState] = [:]
    var drawerCursors: [ArrangementDrawerCursorKey: ArrangementDrawerCursorState] = [:]
    for tab in unrelated {
        let arrangement = tab.arrangements[0]
        activeArrangements[tab.tabId] = arrangement.id
        paneCursors[arrangement.id] = .init(activePaneId: arrangement.layout.paneIds.first)
        for (drawerID, drawer) in arrangement.drawerViews {
            drawerCursors[.init(arrangementId: arrangement.id, drawerId: drawerID)] = .init(
                activeChildId: drawer.layout.paneIds.first
            )
        }
    }
    for arrangement in fixture.tab.arrangements {
        paneCursors[arrangement.id] = .init(activePaneId: fixture.mainPaneIDs[1])
        drawerCursors[.init(arrangementId: arrangement.id, drawerId: fixture.drawerID)] = .init(
            activeChildId: fixture.drawerPaneIDs[0]
        )
    }
    registry.workspaceArrangementCursor.replaceCursors(
        activeArrangementIdsByTabId: activeArrangements,
        paneCursorsByArrangementId: paneCursors,
        drawerCursorsByKey: drawerCursors
    )
    return registry
}

private struct InstalledArrangementLifecycleParticipants {
    let participantSet: WorkspacePersistenceSnapshotParticipantSet
    let lease: WorkspaceStateSnapshotLease
    let baseMembershipCounts: [WorkspacePersistenceSnapshotParticipantID: Int]
}

@MainActor
private func installArrangementLifecycleParticipants(
    _ runtime: WorkspacePersistenceRuntime
) throws -> InstalledArrangementLifecycleParticipants {
    guard
        case .constructed(let participantSet) = runtime.snapshotParticipantFactory
            .constructCompositionParticipantSet()
    else {
        throw ArrangementLifecyclePersistenceTestError.installationFailed
    }
    let lease = WorkspaceStateSnapshotLease.open(
        pagerIdentity: .make(),
        revisionOwner: runtime.revisionOwner
    )
    var baseMembershipCounts: [WorkspacePersistenceSnapshotParticipantID: Int] = [:]
    for participant in participantSet.participants {
        guard case .opened(let count) = participant.open(lease: lease) else {
            throw ArrangementLifecyclePersistenceTestError.leaseOpenFailed
        }
        baseMembershipCounts[participant.participantID] = count
    }
    return .init(
        participantSet: participantSet,
        lease: lease,
        baseMembershipCounts: baseMembershipCounts
    )
}

@MainActor
private func baseItems(
    _ installed: InstalledArrangementLifecycleParticipants,
    participantID: WorkspacePersistenceSnapshotParticipantID
) throws -> [WorkspacePersistenceSnapshotItem] {
    guard
        let participant = installed.participantSet.participants.first(where: {
            $0.participantID == participantID
        }),
        let membershipCount = installed.baseMembershipCounts[participantID]
    else {
        throw ArrangementLifecyclePersistenceTestError.participantMissing
    }
    return (0..<membershipCount).compactMap { slot in
        guard
            case .item(let item, _, _, _) = participant.inspectBaseSlot(
                lease: installed.lease,
                slotCursor: slot
            )
        else { return nil }
        return item.item
    }
}

@MainActor
private func closeArrangementLifecycleParticipants(_ installed: InstalledArrangementLifecycleParticipants) {
    for participant in installed.participantSet.participants {
        _ = participant.close(lease: installed.lease)
    }
}

private enum ArrangementLifecyclePersistenceTestError: Error {
    case installationFailed
    case leaseOpenFailed
    case participantMissing
}

import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("Cross-tab pane move persistence gateway")
struct WorkspaceCrossTabPaneMovePersistenceGatewayTests {
    @Test("preinstall rejects without revision or state change")
    func preinstallRejects() {
        // Arrange
        let fixture = makeCrossTabPersistenceFixture()
        let before = fixture.snapshot

        // Act
        let result = fixture.runtime.mutationCoordinator.movePaneAcrossTabs(fixture.request)

        // Assert
        #expect(result == .rejected(.compositionDomainNotInstalled(phase: .preinstall)))
        #expect(fixture.runtime.revisionOwner.committedRevision == .zero)
        #expect(fixture.snapshot == before)
    }

    @Test("installed move commits revision one and exact canonical values")
    func installedMoveCommitsExactValues() throws {
        // Arrange
        let fixture = makeCrossTabPersistenceFixture(unrelatedCount: 256)
        _ = try installCrossTabParticipants(fixture.runtime, openLease: false)
        let unrelatedBefore = fixture.unrelatedTabs

        // Act
        let result = fixture.runtime.mutationCoordinator.movePaneAcrossTabs(fixture.request)

        // Assert
        #expect(try requireMovedRevision(result).rawValue == 1)
        #expect(fixture.runtime.revisionOwner.committedRevision.rawValue == 1)
        #expect(
            fixture.registry.workspaceTabGraph.tabID(containingPane: fixture.movedPaneID) == fixture.destination.tabId)
        #expect(
            fixture.registry.workspaceTabGraph.tabState(fixture.source.tabId)?.allPaneIds == [fixture.fallbackPaneID])
        #expect(
            fixture.registry.workspaceArrangementCursor.activeArrangementId(forTab: fixture.source.tabId)
                == fixture.sourceDefaultArrangementID
        )
        #expect(
            fixture.registry.workspaceArrangementCursor.activePaneId(
                forArrangement: fixture.sourceActiveArrangementID
            ) == nil
        )
        #expect(
            fixture.registry.workspaceArrangementCursor.activePaneId(
                forArrangement: fixture.destinationArrangementID
            ) == fixture.movedPaneID
        )
        #expect(fixture.registry.workspaceTabCursor.activeTabId == fixture.destination.tabId)
        #expect(Array(fixture.registry.workspaceTabGraph.tabStates.suffix(256)) == unrelatedBefore)
    }

    @Test("fixed base retains changed values and excludes post-base insertions")
    func fixedBaseRetainsExactPreimages() throws {
        // Arrange
        let fixture = makeCrossTabPersistenceFixture(
            destinationCursor: fixtureSelectedDestinationSentinel
        )
        let installed = try installCrossTabParticipants(fixture.runtime)
        let sourceBefore = fixture.source
        let destinationBefore = fixture.destination

        // Act
        let result = fixture.runtime.mutationCoordinator.movePaneAcrossTabs(fixture.request)

        // Assert
        #expect(try requireMovedRevision(result).rawValue == 1)
        #expect(try installed.items(.tabGraphs).contains(.tabGraph(sourceBefore)))
        #expect(try installed.items(.tabGraphs).contains(.tabGraph(destinationBefore)))
        #expect(
            try installed.items(.activeArrangements).contains(
                .activeArrangement(
                    tabID: fixture.source.tabId,
                    arrangementID: fixture.sourceActiveArrangementID
                )
            )
        )
        #expect(
            try installed.items(.activePanes).contains(
                .activePane(
                    arrangementID: fixture.sourceActiveArrangementID,
                    paneID: fixture.movedPaneID
                )
            )
        )
        #expect(
            try installed.items(.activePanes).contains(
                .activePane(
                    arrangementID: fixture.destinationArrangementID,
                    paneID: fixture.targetPaneID
                )
            )
        )
        #expect(try installed.items(.activeTab).contains(.activeTab(fixture.source.tabId)))
        #expect(
            try installed.items(.activePanes).contains {
                $0.snapshotItemID == .activePane(arrangementID: fixture.destinationArrangementID)
            }
        )
        closeCrossTabParticipants(installed)

        let insertionFixture = makeCrossTabPersistenceFixture(activeTabID: nil, destinationCursor: nil)
        let insertionBase = try installCrossTabParticipants(insertionFixture.runtime)
        let insertionResult = insertionFixture.runtime.mutationCoordinator.movePaneAcrossTabs(
            insertionFixture.request
        )
        #expect(try requireMovedRevision(insertionResult).rawValue == 1)
        #expect(
            try insertionBase.items(.activePanes).contains {
                $0.snapshotItemID
                    == .activePane(arrangementID: insertionFixture.destinationArrangementID)
            } == false
        )
        #expect(try insertionBase.items(.activeTab).isEmpty)
        closeCrossTabParticipants(insertionBase)
    }

    @Test("planning rejection rejects without revision or mutation")
    func planningRejectionIsAtomic() throws {
        // Arrange
        let planningFixture = makeCrossTabPersistenceFixture()
        _ = try installCrossTabParticipants(planningFixture.runtime, openLease: false)
        let planningBefore = planningFixture.snapshot
        // Act
        let planningResult = planningFixture.runtime.mutationCoordinator.movePaneAcrossTabs(
            .init(
                paneId: planningFixture.movedPaneID,
                sourceTabId: planningFixture.source.tabId,
                destTabId: planningFixture.source.tabId,
                targetPaneId: planningFixture.targetPaneID,
                direction: .vertical,
                position: .after
            )
        )
        // Assert
        #expect(planningResult == .rejected(.planning(.sameTab(planningFixture.source.tabId))))
        #expect(planningFixture.runtime.revisionOwner.committedRevision == .zero)
        #expect(planningFixture.snapshot == planningBefore)
    }

    @Test("gateway uses keyed reads and remains production dormant")
    func keyedReadAndDormancySourceProof() throws {
        // Arrange
        let root = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let sources = root.appending(path: "Sources/AgentStudio")
        let gateway = try String(
            contentsOf: sources.appending(
                path: "Core/State/MainActor/Persistence/WorkspaceCrossTabPaneMovePersistenceGateway.swift"
            ),
            encoding: .utf8
        )
        let coordinator = try String(
            contentsOf: sources.appending(
                path: "Core/State/MainActor/Persistence/WorkspacePersistenceMutationCoordinator.swift"
            ),
            encoding: .utf8
        )

        // Act
        let sourcePaths = try FileManager.default.subpathsOfDirectory(atPath: sources.path)
        let productionCallers = try sourcePaths.compactMap { relativePath -> String? in
            guard relativePath.hasSuffix(".swift") else { return nil }
            let source = try String(contentsOf: sources.appending(path: relativePath), encoding: .utf8)
            return source.contains("mutationCoordinator.movePaneAcrossTabs") ? relativePath : nil
        }

        // Assert
        #expect(productionCallers.isEmpty)
        #expect(gateway.contains("paneState(request.paneId)"))
        #expect(gateway.contains("tabID(containingPane: request.paneId)"))
        #expect(gateway.contains("tabState(request.sourceTabId)"))
        #expect(gateway.contains("tabState(request.destTabId)"))
        #expect(!gateway.contains(".tabStates"))
        #expect(!gateway.contains("activeArrangementIdsByTabId"))
        #expect(!gateway.contains("paneCursorsByArrangementId"))
        #expect(!gateway.contains("zoomedPaneIdsByTabId"))
        #expect(!gateway.contains("workspacePaneGraph.capturePersistencePreimages"))
        #expect(!gateway.contains("workspaceTabShell"))
        #expect(!gateway.contains("workspaceDrawerCursor"))
        #expect(coordinator.components(separatedBy: "WorkspaceCrossTabPaneMovePersistenceGateway").count == 3)
        #expect(coordinator.components(separatedBy: "crossTabPaneMoveGateway.move(request)").count == 2)
    }
}

private let fixtureSelectedDestinationSentinel = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

@MainActor
private final class CrossTabPersistenceFixture {
    let registry: AtomRegistry
    let runtime: WorkspacePersistenceRuntime
    let movedPaneID: UUID
    let fallbackPaneID: UUID
    let targetPaneID: UUID
    let sourceActiveArrangementID: UUID
    let sourceDefaultArrangementID: UUID
    let destinationArrangementID: UUID
    let source: TabGraphState
    let destination: TabGraphState
    let unrelatedTabs: [TabGraphState]

    init(activeTabID: UUID?, destinationCursor: UUID?, unrelatedCount: Int) {
        movedPaneID = UUIDv7.generate()
        fallbackPaneID = UUIDv7.generate()
        targetPaneID = UUIDv7.generate()
        sourceActiveArrangementID = UUIDv7.generate()
        sourceDefaultArrangementID = UUIDv7.generate()
        destinationArrangementID = UUIDv7.generate()
        source = .init(
            tabId: UUIDv7.generate(),
            allPaneIds: [movedPaneID, fallbackPaneID],
            arrangements: [
                makeCrossTabArrangement(id: sourceActiveArrangementID, isDefault: false, panes: [movedPaneID]),
                makeCrossTabArrangement(
                    id: sourceDefaultArrangementID,
                    isDefault: true,
                    panes: [movedPaneID, fallbackPaneID]
                ),
            ]
        )
        destination = .init(
            tabId: UUIDv7.generate(),
            allPaneIds: [targetPaneID],
            arrangements: [
                makeCrossTabArrangement(
                    id: destinationArrangementID,
                    isDefault: true,
                    panes: [targetPaneID],
                    minimizedPaneIDs: destinationCursor == nil ? [targetPaneID] : []
                )
            ]
        )
        unrelatedTabs = (0..<unrelatedCount).map { index in
            let paneID = UUIDv7.generate()
            return .init(
                tabId: UUIDv7.generate(),
                allPaneIds: [paneID],
                arrangements: [
                    makeCrossTabArrangement(id: UUIDv7.generate(), isDefault: true, panes: [paneID], name: "U\(index)")
                ]
            )
        }
        registry = AtomRegistry()
        registry.workspacePaneGraph.setCanonicalPaneState(
            .init(
                pane: Pane(
                    id: movedPaneID,
                    content: .terminal(
                        .init(provider: .ghostty, lifetime: .temporary, zmxSessionID: .generateUUIDv7())
                    ),
                    metadata: .init(title: "Moved"),
                    residency: .active,
                    kind: .layout(drawer: .init(drawerId: UUIDv7.generate(), parentPaneId: movedPaneID))
                )
            )
        )
        registry.workspaceTabGraph.replaceTabStates([source, destination] + unrelatedTabs)
        registry.workspaceArrangementCursor.replaceCursors(
            activeArrangementIdsByTabId: [
                source.tabId: sourceActiveArrangementID,
                destination.tabId: destinationArrangementID,
            ],
            paneCursorsByArrangementId: [
                sourceActiveArrangementID: .init(activePaneId: movedPaneID),
                sourceDefaultArrangementID: .init(activePaneId: fallbackPaneID),
                destinationArrangementID: .init(
                    activePaneId: destinationCursor == fixtureSelectedDestinationSentinel
                        ? targetPaneID : destinationCursor
                ),
            ],
            drawerCursorsByKey: [:]
        )
        registry.workspaceTabCursor.replaceActiveTab(activeTabID)
        runtime = WorkspacePersistenceRuntime(atomRegistry: registry)
    }

    var request: CrossTabPaneMoveRequest {
        .init(
            paneId: movedPaneID,
            sourceTabId: source.tabId,
            destTabId: destination.tabId,
            targetPaneId: targetPaneID,
            direction: .vertical,
            position: .after
        )
    }

    var snapshot: CrossTabPersistenceSnapshot {
        .init(
            source: registry.workspaceTabGraph.tabState(source.tabId),
            destination: registry.workspaceTabGraph.tabState(destination.tabId),
            sourceArrangement: registry.workspaceArrangementCursor.activeArrangementId(forTab: source.tabId),
            sourcePane: registry.workspaceArrangementCursor.activePaneId(forArrangement: sourceActiveArrangementID),
            destinationPane: registry.workspaceArrangementCursor.activePaneId(forArrangement: destinationArrangementID),
            activeTab: registry.workspaceTabCursor.activeTabId
        )
    }
}

private struct CrossTabPersistenceSnapshot: Equatable {
    let source: TabGraphState?
    let destination: TabGraphState?
    let sourceArrangement: UUID?
    let sourcePane: UUID?
    let destinationPane: UUID?
    let activeTab: UUID?
}

@MainActor
private struct InstalledCrossTabParticipants {
    let participantSet: WorkspacePersistenceSnapshotParticipantSet
    let lease: WorkspaceStateSnapshotLease?
    let membership: [WorkspacePersistenceSnapshotParticipantID: Int]

    func items(_ participantID: WorkspacePersistenceSnapshotParticipantID) throws
        -> [WorkspacePersistenceSnapshotItem]
    {
        guard
            let lease,
            let participant = participantSet.participants.first(where: { $0.participantID == participantID }),
            let count = membership[participantID]
        else { throw CrossTabPersistenceTestError.participantMissing }
        return (0..<count).compactMap { slot in
            guard case .item(let item, _, _, _) = participant.inspectBaseSlot(lease: lease, slotCursor: slot)
            else { return nil }
            return item.item
        }
    }
}

@MainActor
private func makeCrossTabPersistenceFixture(
    activeTabID: UUID? = fixtureSelectedDestinationSentinel,
    destinationCursor: UUID? = fixtureSelectedDestinationSentinel,
    unrelatedCount: Int = 0
) -> CrossTabPersistenceFixture {
    let fixture = CrossTabPersistenceFixture(
        activeTabID: nil, destinationCursor: destinationCursor, unrelatedCount: unrelatedCount)
    fixture.registry.workspaceTabCursor.replaceActiveTab(
        activeTabID == fixtureSelectedDestinationSentinel ? fixture.source.tabId : activeTabID
    )
    return fixture
}

private func makeCrossTabArrangement(
    id: UUID,
    isDefault: Bool,
    panes: [UUID],
    minimizedPaneIDs: [UUID] = [],
    name: String = "Arrangement"
) -> PaneArrangementGraphState {
    .init(
        id: id,
        name: name,
        isDefault: isDefault,
        layout: .autoTiled(panes),
        minimizedPaneIds: Set(minimizedPaneIDs),
        showsMinimizedPanes: false,
        drawerViews: [:]
    )
}

@MainActor
private func installCrossTabParticipants(
    _ runtime: WorkspacePersistenceRuntime,
    openLease: Bool = true
) throws -> InstalledCrossTabParticipants {
    guard
        case .constructed(let participantSet) = runtime.snapshotParticipantFactory.constructCompositionParticipantSet()
    else { throw CrossTabPersistenceTestError.installationFailed }
    guard openLease else { return .init(participantSet: participantSet, lease: nil, membership: [:]) }
    let lease = WorkspaceStateSnapshotLease.open(pagerIdentity: .make(), revisionOwner: runtime.revisionOwner)
    var membership: [WorkspacePersistenceSnapshotParticipantID: Int] = [:]
    for participant in participantSet.participants {
        guard case .opened(let count) = participant.open(lease: lease) else {
            throw CrossTabPersistenceTestError.leaseOpenFailed
        }
        membership[participant.participantID] = count
    }
    return .init(participantSet: participantSet, lease: lease, membership: membership)
}

@MainActor
private func closeCrossTabParticipants(_ installed: InstalledCrossTabParticipants) {
    guard let lease = installed.lease else { return }
    for participant in installed.participantSet.participants { _ = participant.close(lease: lease) }
}

private enum CrossTabPersistenceTestError: Error {
    case expectedMoved
    case installationFailed
    case leaseOpenFailed
    case participantMissing
}

private func requireMovedRevision(
    _ result: WorkspaceCrossTabPaneMovePersistenceResult
) throws -> WorkspacePersistenceRevision {
    guard case .moved(let revision) = result else { throw CrossTabPersistenceTestError.expectedMoved }
    return revision
}

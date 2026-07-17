import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("Workspace persistence tab graph leaf mutations")
struct WorkspacePersistenceTabGraphLeafMutationTests {
    @Test("preinstall graph leaf mutation rejects without state or revision")
    func preinstallMutationRejects() {
        // Arrange
        let fixture = makeTabGraphLeafPersistenceFixture()

        // Act
        let result = fixture.runtime.mutationCoordinator.equalizePanes(
            .init(tabID: fixture.graphFixture.tabState.tabId)
        )

        // Assert
        #expect(result == .rejected(.compositionDomainNotInstalled(phase: .preinstall)))
        #expect(fixture.runtime.revisionOwner.committedRevision == .zero)
        #expect(fixture.atomRegistry.workspaceTabGraph.tabStates == [fixture.graphFixture.tabState])
    }

    @Test("installed equalize retains one exact tab graph preimage")
    func installedEqualizeRetainsGraphPreimage() throws {
        // Arrange
        let fixture = makeTabGraphLeafPersistenceFixture()
        let installed = try installTabGraphLeafParticipant(fixture.runtime)

        // Act
        let result = fixture.runtime.mutationCoordinator.equalizePanes(
            .init(tabID: fixture.graphFixture.tabState.tabId)
        )

        // Assert
        #expect(try requireGraphLeafChangedRevision(result).rawValue == 1)
        #expect(
            fixture.atomRegistry.workspaceTabGraph.tabStates[0].arrangements[1].layout.panes.map(\.ratio) == [0.5, 0.5])
        try expectTabGraphLeafBaseItem(
            .tabGraph(fixture.graphFixture.tabState),
            installed: installed
        )
    }

    @Test("installed rename retains one exact tab graph preimage")
    func installedRenameRetainsGraphPreimage() throws {
        // Arrange
        let fixture = makeTabGraphLeafPersistenceFixture()
        let installed = try installTabGraphLeafParticipant(fixture.runtime)

        // Act
        let result = fixture.runtime.mutationCoordinator.renameArrangement(
            .init(
                tabID: fixture.graphFixture.tabState.tabId,
                arrangementID: fixture.graphFixture.customArrangementID,
                name: "  Focus  "
            )
        )

        // Assert
        #expect(try requireGraphLeafChangedRevision(result).rawValue == 1)
        #expect(fixture.atomRegistry.workspaceTabGraph.tabStates[0].arrangements[1].name == "Focus")
        try expectTabGraphLeafBaseItem(
            .tabGraph(fixture.graphFixture.tabState),
            installed: installed
        )
    }

    @Test("installed drawer equalize retains one exact tab graph preimage")
    func installedDrawerEqualizeRetainsGraphPreimage() throws {
        // Arrange
        let fixture = makeTabGraphLeafPersistenceFixture()
        let installed = try installTabGraphLeafParticipant(fixture.runtime)

        // Act
        let result = fixture.runtime.mutationCoordinator.equalizeDrawerPanes(
            .init(
                tabID: fixture.graphFixture.tabState.tabId,
                drawerID: fixture.graphFixture.drawerID
            )
        )

        // Assert
        #expect(try requireGraphLeafChangedRevision(result).rawValue == 1)
        #expect(
            fixture.atomRegistry.workspaceTabGraph.tabStates[0].arrangements[1]
                .drawerViews[fixture.graphFixture.drawerID]?.layout.topRow.panes.map(\.ratio) == [0.5, 0.5]
        )
        try expectTabGraphLeafBaseItem(
            .tabGraph(fixture.graphFixture.tabState),
            installed: installed
        )
    }

    @Test("installed semantic no-ops do not advance the revision")
    func installedNoOpsDoNotAdvanceRevision() throws {
        // Arrange
        let fixture = makeTabGraphLeafPersistenceFixture(equalized: true, drawerEqualized: true)
        _ = try installTabGraphLeafParticipant(fixture.runtime, openLease: false)

        // Act
        let equalizeResult = fixture.runtime.mutationCoordinator.equalizePanes(
            .init(tabID: fixture.graphFixture.tabState.tabId)
        )
        let renameResult = fixture.runtime.mutationCoordinator.renameArrangement(
            .init(
                tabID: fixture.graphFixture.tabState.tabId,
                arrangementID: fixture.graphFixture.customArrangementID,
                name: " Custom "
            )
        )
        let drawerResult = fixture.runtime.mutationCoordinator.equalizeDrawerPanes(
            .init(
                tabID: fixture.graphFixture.tabState.tabId,
                drawerID: fixture.graphFixture.drawerID
            )
        )

        // Assert
        #expect(equalizeResult == .unchanged(revision: .zero))
        #expect(renameResult == .unchanged(revision: .zero))
        #expect(drawerResult == .unchanged(revision: .zero))
        #expect(fixture.runtime.revisionOwner.committedRevision == .zero)
    }

    @Test("leaf family is target-keyed and remains production dormant")
    func leafFamilyIsTargetKeyedAndDormant() throws {
        // Arrange
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let transitionSource = try String(
            contentsOf: projectRoot.appending(
                path: "Sources/AgentStudio/Core/State/Transitions/WorkspaceTabGraphLeafTransition.swift"
            ),
            encoding: .utf8
        )
        let applierSource = try String(
            contentsOf: projectRoot.appending(
                path:
                    "Sources/AgentStudio/Core/State/MainActor/Coordination/"
                    + "WorkspaceTabGraphLeafTransitionApplier.swift"
            ),
            encoding: .utf8
        )
        let coordinatorSource = try String(
            contentsOf: projectRoot.appending(
                path:
                    "Sources/AgentStudio/Core/State/MainActor/Persistence/"
                    + "WorkspacePersistenceMutationCoordinator.swift"
            ),
            encoding: .utf8
        )
        let equalizeCoordinator = try #require(
            sourceSlice(
                coordinatorSource,
                from: "    func equalizePanes(",
                through: "    func renameArrangement("
            )
        )
        let renameCoordinator = try #require(
            sourceSlice(
                coordinatorSource,
                from: "    func renameArrangement(",
                through: "    func setActivePane("
            )
        )
        let productionRoot = "Sources/AgentStudio"

        // Act
        let root = projectRoot.appending(path: productionRoot)
        let productionSourcePaths = try FileManager.default.subpathsOfDirectory(atPath: root.path)
        let callers: [String] = try productionSourcePaths.compactMap { relativePath -> String? in
            guard relativePath.hasSuffix(".swift") else { return nil }
            let source = try String(contentsOf: root.appending(path: relativePath), encoding: .utf8)
            let hasCaller =
                source.contains("mutationCoordinator.equalizePanes")
                || source.contains("mutationCoordinator.equalizeDrawerPanes")
                || source.contains("mutationCoordinator.renameArrangement")
            return hasCaller ? "\(productionRoot)/\(relativePath)" : nil
        }

        // Assert
        #expect(!transitionSource.contains("replacementTabStates"))
        #expect(!transitionSource.contains("tabStates:"))
        #expect(!applierSource.contains("replaceTabStates"))
        #expect(!applierSource.contains("workspaceTabGraphAtom.tabStates"))
        #expect(equalizeCoordinator.contains("tabGraphLeafPlanningContext(tabID: request.tabID)"))
        #expect(renameCoordinator.contains("tabGraphLeafPlanningContext(tabID: request.tabID)"))
        #expect(!equalizeCoordinator.contains("workspaceTabGraphAtom.tabStates"))
        #expect(!renameCoordinator.contains("workspaceTabGraphAtom.tabStates"))
        #expect(callers.isEmpty)
    }
}

private struct TabGraphLeafPersistenceFixture {
    let atomRegistry: AtomRegistry
    let runtime: WorkspacePersistenceRuntime
    let graphFixture: TabGraphLeafFixture
}

private struct InstalledTabGraphLeafParticipant {
    let participant: WorkspacePersistenceSnapshotParticipantSet.Participant
    let lease: WorkspaceStateSnapshotLease
}

@MainActor
private func makeTabGraphLeafPersistenceFixture(
    equalized: Bool = false,
    drawerEqualized: Bool = false
) -> TabGraphLeafPersistenceFixture {
    let atomRegistry = AtomRegistry()
    var graphFixture = makeTabGraphLeafFixture()
    if equalized {
        graphFixture = TabGraphLeafFixture(
            tabState: equalizedTabState(graphFixture.tabState),
            defaultArrangementID: graphFixture.defaultArrangementID,
            customArrangementID: graphFixture.customArrangementID,
            paneIDs: graphFixture.paneIDs,
            drawerID: graphFixture.drawerID,
            drawerPaneIDs: graphFixture.drawerPaneIDs
        )
    }
    if drawerEqualized {
        var tabState = graphFixture.tabState
        var drawer = tabState.arrangements[1].drawerViews[graphFixture.drawerID]!
        drawer.layout = drawer.layout.equalized()
        tabState.arrangements[1].drawerViews[graphFixture.drawerID] = drawer
        graphFixture = TabGraphLeafFixture(
            tabState: tabState,
            defaultArrangementID: graphFixture.defaultArrangementID,
            customArrangementID: graphFixture.customArrangementID,
            paneIDs: graphFixture.paneIDs,
            drawerID: graphFixture.drawerID,
            drawerPaneIDs: graphFixture.drawerPaneIDs
        )
    }
    atomRegistry.workspaceTabGraph.replaceTabStates([graphFixture.tabState])
    atomRegistry.workspaceArrangementCursor.replaceCursors(
        activeArrangementIdsByTabId: [graphFixture.tabState.tabId: graphFixture.customArrangementID],
        paneCursorsByArrangementId: [:],
        drawerCursorsByKey: [:]
    )
    return TabGraphLeafPersistenceFixture(
        atomRegistry: atomRegistry,
        runtime: WorkspacePersistenceRuntime(atomRegistry: atomRegistry),
        graphFixture: graphFixture
    )
}

private func sourceSlice(
    _ source: String,
    from startMarker: String,
    through endMarker: String
) -> String? {
    guard let start = source.range(of: startMarker),
        let end = source.range(of: endMarker, range: start.upperBound..<source.endIndex)
    else { return nil }
    return String(source[start.lowerBound..<end.lowerBound])
}

private func equalizedTabState(_ state: TabGraphState) -> TabGraphState {
    var replacement = state
    replacement.arrangements[1].layout = replacement.arrangements[1].layout.equalized()
    return replacement
}

@MainActor
private func installTabGraphLeafParticipant(
    _ runtime: WorkspacePersistenceRuntime,
    openLease: Bool = true
) throws -> InstalledTabGraphLeafParticipant {
    guard
        case .constructed(let participantSet) = runtime.snapshotParticipantFactory
            .constructCompositionParticipantSet(),
        let participant = participantSet.participants.first(where: { $0.participantID == .tabGraphs })
    else {
        throw WorkspacePersistenceTabGraphLeafMutationTestError.installationFailed
    }
    let lease = WorkspaceStateSnapshotLease.open(
        pagerIdentity: .make(),
        revisionOwner: runtime.revisionOwner
    )
    if openLease {
        guard participant.open(lease: lease) == .opened(baseMembershipCount: 1) else {
            throw WorkspacePersistenceTabGraphLeafMutationTestError.leaseOpenFailed
        }
    }
    return InstalledTabGraphLeafParticipant(participant: participant, lease: lease)
}

@MainActor
private func expectTabGraphLeafBaseItem(
    _ expectedItem: WorkspacePersistenceSnapshotItem,
    installed: InstalledTabGraphLeafParticipant
) throws {
    guard
        case .item(let projectedItem, _, _, _) = installed.participant.inspectBaseSlot(
            lease: installed.lease,
            slotCursor: 0
        )
    else {
        throw WorkspacePersistenceTabGraphLeafMutationTestError.baseItemMissing
    }
    #expect(projectedItem.item == expectedItem)
    _ = installed.participant.close(lease: installed.lease)
}

private func requireGraphLeafChangedRevision(
    _ result: WorkspacePersistenceMutationResult
) throws -> WorkspacePersistenceRevision {
    guard case .changed(let revision) = result else {
        throw WorkspacePersistenceTabGraphLeafMutationTestError.expectedChangedResult
    }
    return revision
}

private enum WorkspacePersistenceTabGraphLeafMutationTestError: Error {
    case baseItemMissing
    case expectedChangedResult
    case installationFailed
    case leaseOpenFailed
}

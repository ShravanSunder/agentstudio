import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("Create pane in existing tab persistence gateway")
struct ExistingTabPaneCreationPersistenceTests {
    @Test("preinstall rejects without state or revision")
    func preinstallRejects() throws {
        // Arrange
        let fixture = try makeCreatePaneFixture()
        let registry = makeCreatePanePersistenceRegistry(fixture)
        let runtime = WorkspacePersistenceRuntime(atomRegistry: registry)

        // Act
        let result = runtime.mutationCoordinator.createPaneInExistingTab(fixture.request())

        // Assert
        #expect(result == .rejected(.compositionDomainNotInstalled(phase: .preinstall)))
        #expect(runtime.revisionOwner.committedRevision == .zero)
        #expect(registry.workspacePaneGraph.paneState(fixture.identities.paneID.uuid) == nil)
        #expect(registry.workspaceTabGraph.tabState(fixture.tab.tabId) == fixture.tab)
    }

    @Test("installed creation commits one revision and retains the exact fixed base")
    func installedCreationHasOneRevisionAndExactBase() throws {
        // Arrange
        let fixture = try makeCreatePaneFixture()
        let registry = makeCreatePanePersistenceRegistry(fixture)
        let runtime = WorkspacePersistenceRuntime(atomRegistry: registry)
        let fixedBase = try installCreatePaneParticipants(runtime)

        // Act
        let result = runtime.mutationCoordinator.createPaneInExistingTab(fixture.request())
        let repeated = runtime.mutationCoordinator.createPaneInExistingTab(fixture.request())

        // Assert
        guard case .created(let committed) = result else {
            Issue.record("expected installed pane creation")
            return
        }
        #expect(committed.revision.rawValue == 1)
        #expect(committed.pane.id == fixture.identities.paneID.uuid)
        #expect(committed.tabID == fixture.tab.tabId)
        #expect(runtime.revisionOwner.committedRevision.rawValue == 1)
        #expect(
            repeated
                == .rejected(
                    .planning(
                        .paneIdentityAlreadyExistsAndOwned(
                            paneID: fixture.identities.paneID.uuid,
                            tabID: fixture.tab.tabId
                        ))
                )
        )
        #expect(runtime.revisionOwner.committedRevision.rawValue == 1)
        #expect(registry.workspaceTabGraph.tabID(containingPane: committed.pane.id) == fixture.tab.tabId)
        #expect(
            registry.workspaceArrangementCursor.activePaneId(forArrangement: fixture.activeArrangementID)
                == committed.pane.id
        )
        let paneBase = try createPaneBaseItems(fixedBase, participantID: .paneGraphs)
        #expect(paneBase.contains { $0.snapshotItemID == .paneGraph(committed.pane.id) } == false)
        #expect(
            try createPaneBaseItems(fixedBase, participantID: .tabGraphs)
                .contains(.tabGraph(fixture.tab))
        )
        #expect(
            try createPaneBaseItems(fixedBase, participantID: .activePanes)
                .contains(
                    .activePane(
                        arrangementID: fixture.activeArrangementID,
                        paneID: fixture.targetPaneID
                    )
                )
        )
        closeCreatePaneParticipants(fixedBase)
    }

    @Test("gateway is target-keyed and remains production dormant")
    func gatewayIsTargetKeyedAndDormant() throws {
        // Arrange
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let sourcesRoot = projectRoot.appending(path: "Sources/AgentStudio")
        let sourcePaths = try FileManager.default.subpathsOfDirectory(atPath: sourcesRoot.path)

        // Act
        let callers: [String] = try sourcePaths.compactMap { relativePath -> String? in
            guard relativePath.hasSuffix(".swift") else { return nil }
            let source = try String(contentsOf: sourcesRoot.appending(path: relativePath), encoding: .utf8)
            return source.contains("mutationCoordinator.createPaneInExistingTab") ? relativePath : nil
        }
        let applierSource = try String(
            contentsOf: sourcesRoot.appending(
                path:
                    "Core/State/MainActor/Coordination/"
                    + "WorkspaceCreatePaneInExistingTabTransitionApplier.swift"
            ),
            encoding: .utf8
        )
        let gatewaySource = try String(
            contentsOf: sourcesRoot.appending(
                path:
                    "Core/State/MainActor/Persistence/"
                    + "WorkspaceCreatePaneInExistingTabPersistenceGateway.swift"
            ),
            encoding: .utf8
        )

        // Assert
        #expect(callers.isEmpty)
        #expect(applierSource.contains("replaceTabStateAndOwnership"))
        #expect(!applierSource.contains("replaceTabStates"))
        #expect(!applierSource.contains("replaceTabStatePreservingIdentity"))
        #expect(!gatewaySource.contains("workspaceTabGraphAtom.tabStates"))
        #expect(!gatewaySource.contains("WorkspaceTabShell"))
        #expect(!gatewaySource.contains("WorkspaceTabCursor"))
    }
}

private struct InstalledCreatePaneParticipants {
    let participantSet: WorkspacePersistenceSnapshotParticipantSet
    let lease: WorkspaceStateSnapshotLease
    let membershipCounts: [WorkspacePersistenceSnapshotParticipantID: Int]
}

@MainActor
private func makeCreatePanePersistenceRegistry(
    _ fixture: CreatePaneInExistingTabFixture
) -> AtomRegistry {
    let registry = AtomRegistry()
    for paneID in fixture.tab.allPaneIds {
        let pane = Pane(
            id: paneID,
            content: .webview(WebviewState(url: URL(string: "https://example.com/\(paneID)")!)),
            metadata: PaneMetadata(title: "Existing"),
            kind: .layout(
                drawer: Drawer(
                    drawerId: UUIDv7.generate(),
                    parentPaneId: paneID
                )
            )
        )
        registry.workspacePaneGraph.setCanonicalPaneState(.init(pane: pane))
    }
    registry.workspaceTabGraph.replaceTabStates([fixture.tab])
    registry.workspaceArrangementCursor.replaceCursors(
        activeArrangementIdsByTabId: [fixture.tab.tabId: fixture.activeArrangementID],
        paneCursorsByArrangementId: [
            fixture.activeArrangementID: .init(activePaneId: fixture.targetPaneID),
            fixture.inactiveArrangementID: .init(activePaneId: fixture.otherPaneID),
        ],
        drawerCursorsByKey: [:]
    )
    return registry
}

@MainActor
private func installCreatePaneParticipants(
    _ runtime: WorkspacePersistenceRuntime
) throws -> InstalledCreatePaneParticipants {
    guard
        case .constructed(let participantSet) = runtime.snapshotParticipantFactory
            .constructCompositionParticipantSet()
    else {
        throw CreatePanePersistenceTestError.installationFailed
    }
    let lease = WorkspaceStateSnapshotLease.open(
        pagerIdentity: .make(),
        revisionOwner: runtime.revisionOwner
    )
    var membershipCounts: [WorkspacePersistenceSnapshotParticipantID: Int] = [:]
    for participant in participantSet.participants {
        guard case .opened(let count) = participant.open(lease: lease) else {
            throw CreatePanePersistenceTestError.leaseOpenFailed
        }
        membershipCounts[participant.participantID] = count
    }
    return .init(
        participantSet: participantSet,
        lease: lease,
        membershipCounts: membershipCounts
    )
}

@MainActor
private func createPaneBaseItems(
    _ installed: InstalledCreatePaneParticipants,
    participantID: WorkspacePersistenceSnapshotParticipantID
) throws -> [WorkspacePersistenceSnapshotItem] {
    guard
        let participant = installed.participantSet.participants.first(where: {
            $0.participantID == participantID
        }),
        let membershipCount = installed.membershipCounts[participantID]
    else {
        throw CreatePanePersistenceTestError.participantMissing
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
private func closeCreatePaneParticipants(_ installed: InstalledCreatePaneParticipants) {
    for participant in installed.participantSet.participants {
        _ = participant.close(lease: installed.lease)
    }
}

private enum CreatePanePersistenceTestError: Error {
    case installationFailed
    case leaseOpenFailed
    case participantMissing
}

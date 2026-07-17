import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("Close final pane and remove tab persistence gateway")
struct FinalPaneTabRemovalPersistenceTests {
    @Test("preinstall rejects without revision or owner mutation")
    func preinstallRejects() {
        // Arrange
        let fixture = makeFinalPaneRemovalPersistenceFixture()
        let before = fixture.snapshot

        // Act
        let result = fixture.runtime.mutationCoordinator.closeFinalPaneAndRemoveTab(fixture.fixture.request)

        // Assert
        #expect(result == .rejected(.compositionDomainNotInstalled(phase: .preinstall)))
        #expect(fixture.runtime.revisionOwner.committedRevision == .zero)
        #expect(fixture.snapshot == before)
    }

    @Test("installed close captures literal fixed-base pane tab shell suffix and cursors")
    func installedCloseCapturesExactPreimages() throws {
        // Arrange
        let fixture = makeFinalPaneRemovalPersistenceFixture()
        let installed = try installFinalPaneRemovalParticipants(fixture.runtime)
        defer { closeFinalPaneRemovalParticipants(installed) }
        let expectedTabs = fixture.registry.workspaceTabGraph.tabStates
        let expectedMembership: [WorkspacePersistenceSnapshotParticipantID: Int] = [
            .workspaceIdentity: 1,
            .workspaceWindowMemory: 1,
            .paneGraphs: 1,
            .expandedDrawer: 0,
            .tabShells: 3,
            .activeTab: 1,
            .tabGraphs: 3,
            .activeArrangements: 1,
            .activePanes: 1,
            .activeDrawerChildren: 0,
        ]

        // Act
        let result = fixture.runtime.mutationCoordinator.closeFinalPaneAndRemoveTab(fixture.fixture.request)

        // Assert
        #expect(try requireFinalPaneRemovalRevision(result).rawValue == 1)
        #expect(fixture.runtime.revisionOwner.committedRevision.rawValue == 1)
        #expect(fixture.registry.workspacePaneGraph.paneState(fixture.fixture.pane.id) == nil)
        #expect(fixture.registry.workspaceTabGraph.tabState(fixture.fixture.tab.tabId) == nil)
        #expect(fixture.registry.workspaceTabShell.tabShell(fixture.fixture.tab.tabId) == nil)
        #expect(fixture.registry.workspaceTabCursor.activeTabId == fixture.fixture.shells[2].id)
        #expect(fixture.registry.workspaceTabShell.tabIndex(for: fixture.fixture.shells[2].id) == 1)
        #expect(
            installed.participantSet.participantIDs
                == WorkspacePersistenceSnapshotParticipantID.allCases.filter {
                    ![.repositories, .worktrees, .watchedPaths, .unavailableRepositories].contains($0)
                }
        )
        #expect(installed.membership == expectedMembership)
        #expect(
            try finalPaneRemovalBaseItems(installed, participantID: .tabGraphs)
                == expectedTabs.map(WorkspacePersistenceSnapshotItem.tabGraph)
        )
        #expect(
            try finalPaneRemovalBaseItems(installed, participantID: .paneGraphs)
                == [.paneGraph(fixture.fixture.pane)]
        )
        #expect(
            try finalPaneRemovalBaseItems(installed, participantID: .tabShells)
                == fixture.fixture.shells.enumerated().map {
                    .tabShell(.init(shell: $0.element, sortIndex: $0.offset))
                }
        )
        #expect(
            try finalPaneRemovalBaseItems(installed, participantID: .activeTab)
                == [.activeTab(fixture.fixture.tab.tabId)]
        )
        #expect(
            try finalPaneRemovalBaseItems(installed, participantID: .activeArrangements)
                == [
                    .activeArrangement(
                        tabID: fixture.fixture.tab.tabId,
                        arrangementID: fixture.fixture.arrangementIDs[0]
                    )
                ]
        )
        #expect(
            try finalPaneRemovalBaseItems(installed, participantID: .activePanes)
                == [
                    .activePane(
                        arrangementID: fixture.fixture.arrangementIDs[0],
                        paneID: fixture.fixture.pane.id
                    )
                ]
        )
        #expect(try finalPaneRemovalBaseItems(installed, participantID: .activeDrawerChildren).isEmpty)
    }

    @Test("background tab close leaves active-tab participant untouched")
    func backgroundTabDoesNotCaptureActiveTab() throws {
        // Arrange
        let fixture = makeFinalPaneRemovalPersistenceFixture(scenario: .backgroundTab)
        let installed = try installFinalPaneRemovalParticipants(fixture.runtime)
        defer { closeFinalPaneRemovalParticipants(installed) }
        let activeTabBefore = try #require(fixture.registry.workspaceTabCursor.activeTabId)

        // Act
        let result = fixture.runtime.mutationCoordinator.closeFinalPaneAndRemoveTab(fixture.fixture.request)

        // Assert
        #expect(try requireFinalPaneRemovalRevision(result).rawValue == 1)
        #expect(fixture.registry.workspaceTabCursor.activeTabId == activeTabBefore)
        #expect(
            try finalPaneRemovalBaseItems(installed, participantID: .activeTab)
                == [.activeTab(activeTabBefore)]
        )
        #expect(
            try finalPaneRemovalParticipantCloseReceipt(installed, participantID: .activeTab)
                .releasedBaseValueCount == 0
        )
    }

    @Test("only-tab close captures active-tab removal preimage")
    func onlyTabCapturesActiveTabRemoval() throws {
        // Arrange
        let fixture = makeFinalPaneRemovalPersistenceFixture(scenario: .onlyTab)
        let installed = try installFinalPaneRemovalParticipants(fixture.runtime)
        defer { closeFinalPaneRemovalParticipants(installed) }

        // Act
        let result = fixture.runtime.mutationCoordinator.closeFinalPaneAndRemoveTab(fixture.fixture.request)

        // Assert
        #expect(try requireFinalPaneRemovalRevision(result).rawValue == 1)
        #expect(fixture.registry.workspaceTabCursor.activeTabId == nil)
        #expect(fixture.registry.workspaceTabShell.tabShells.isEmpty)
        #expect(fixture.registry.workspaceTabGraph.tabStates.isEmpty)
        #expect(
            try finalPaneRemovalBaseItems(installed, participantID: .activeTab)
                == [.activeTab(fixture.fixture.tab.tabId)]
        )
        #expect(
            try finalPaneRemovalParticipantCloseReceipt(installed, participantID: .activeTab)
                .releasedBaseValueCount == 1
        )
    }

    @Test("expanded empty drawer rejection commits zero revision")
    func expandedDrawerRejectionIsAtomic() throws {
        // Arrange
        let fixture = makeFinalPaneRemovalPersistenceFixture()
        _ = try installFinalPaneRemovalParticipants(fixture.runtime, openLease: false)
        let drawerID = fixture.fixture.pane.drawer!.drawerId
        fixture.registry.workspaceDrawerCursor.expandDrawer(drawerId: drawerID)
        let before = fixture.snapshot

        // Act
        let result = fixture.runtime.mutationCoordinator.closeFinalPaneAndRemoveTab(fixture.fixture.request)

        // Assert
        #expect(result == .rejected(.planning(.paneDrawerExpanded(drawerID: drawerID))))
        #expect(fixture.runtime.revisionOwner.committedRevision == .zero)
        #expect(fixture.snapshot == before)
    }

    @Test("foreign drawer cursor under removed arrangement rejects without revision")
    func foreignDrawerCursorRejectionIsAtomic() throws {
        // Arrange
        let fixture = makeFinalPaneRemovalPersistenceFixture()
        _ = try installFinalPaneRemovalParticipants(fixture.runtime, openLease: false)
        let foreignKey = ArrangementDrawerCursorKey(
            arrangementId: fixture.fixture.arrangementIDs[0],
            drawerId: UUIDv7.generate()
        )
        fixture.registry.workspaceArrangementCursor.insertDrawerCursor(
            .init(activeChildId: nil),
            for: foreignKey
        )
        let before = fixture.snapshot

        // Act
        let result = fixture.runtime.mutationCoordinator.closeFinalPaneAndRemoveTab(fixture.fixture.request)

        // Assert
        #expect(result == .rejected(.planning(.arrangementDrawerCursorPresent(foreignKey))))
        #expect(fixture.runtime.revisionOwner.committedRevision == .zero)
        #expect(fixture.snapshot == before)
    }

    @Test("gateway remains production dormant and zoom is not captured")
    func gatewayIsDormantAndZoomIsRuntimeOnly() throws {
        // Arrange
        let root = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let sources = root.appending(path: "Sources/AgentStudio")
        let paths = try FileManager.default.subpathsOfDirectory(atPath: sources.path)
        let gatewayURL = sources.appending(
            path: "Core/State/MainActor/Persistence/WorkspaceCloseFinalPaneAndRemoveTabPersistenceGateway.swift"
        )
        let gateway = try String(contentsOf: gatewayURL, encoding: .utf8)

        // Act
        let callers = try paths.compactMap { relativePath -> String? in
            guard relativePath.hasSuffix(".swift") else { return nil }
            let source = try String(contentsOf: sources.appending(path: relativePath), encoding: .utf8)
            return source.contains("mutationCoordinator.closeFinalPaneAndRemoveTab") ? relativePath : nil
        }

        // Assert
        #expect(callers.isEmpty)
        #expect(!gateway.contains("workspacePanePresentation.capturePersistence"))
        #expect(gateway.contains("shiftedShellSuffix.map"))
        #expect(gateway.contains("WorkspaceActivePanePersistenceCapture.removal"))
    }
}

@MainActor
private final class FinalPaneRemovalPersistenceFixture {
    let fixture = makeFinalPaneRemovalFixture()
    let registry = AtomRegistry()
    let runtime: WorkspacePersistenceRuntime

    init(scenario: FinalPaneRemovalPersistenceScenario = .activeMiddleTab) {
        registry.workspacePaneGraph.setCanonicalPaneState(fixture.pane)
        let alignedTabs = makeFinalPaneRemovalPersistenceAlignedTabs(fixture)
        switch scenario {
        case .activeMiddleTab:
            registry.workspaceTabGraph.replaceTabStates(alignedTabs)
            registry.workspaceTabShell.replaceTabShells(fixture.shells)
            registry.workspaceTabCursor.replaceActiveTab(fixture.tab.tabId)
        case .backgroundTab:
            registry.workspaceTabGraph.replaceTabStates(alignedTabs)
            registry.workspaceTabShell.replaceTabShells(fixture.shells)
            registry.workspaceTabCursor.replaceActiveTab(fixture.shells[0].id)
        case .onlyTab:
            registry.workspaceTabGraph.replaceTabStates([fixture.tab])
            registry.workspaceTabShell.replaceTabShells([fixture.shells[1]])
            registry.workspaceTabCursor.replaceActiveTab(fixture.tab.tabId)
        }
        registry.workspaceArrangementCursor.replaceCursors(
            activeArrangementIdsByTabId: [fixture.tab.tabId: fixture.arrangementIDs[0]],
            paneCursorsByArrangementId: [
                fixture.arrangementIDs[0]: .init(activePaneId: fixture.pane.id),
                fixture.arrangementIDs[1]: .init(activePaneId: nil),
            ],
            drawerCursorsByKey: [:]
        )
        registry.workspacePanePresentation.setZoomedPaneId(fixture.pane.id, forTab: fixture.tab.tabId)
        runtime = WorkspacePersistenceRuntime(atomRegistry: registry)
    }

    var snapshot: FinalPaneRemovalPersistenceSnapshot {
        .init(
            pane: registry.workspacePaneGraph.paneState(fixture.pane.id),
            shells: registry.workspaceTabShell.tabShells,
            activeTab: registry.workspaceTabCursor.activeTabId,
            tabs: registry.workspaceTabGraph.tabStates,
            activeArrangement: registry.workspaceArrangementCursor.activeArrangementId(forTab: fixture.tab.tabId),
            paneCursors: registry.workspaceArrangementCursor.paneCursorsByArrangementId,
            arrangementDrawerCursors: registry.workspaceArrangementCursor.drawerCursorsByKey,
            drawerCursor: registry.workspaceDrawerCursor.expandedDrawerId,
            zoom: registry.workspacePanePresentation.zoomedPaneId(forTab: fixture.tab.tabId)
        )
    }
}

private struct FinalPaneRemovalPersistenceSnapshot: Equatable {
    let pane: PaneGraphState?
    let shells: [TabShell]
    let activeTab: UUID?
    let tabs: [TabGraphState]
    let activeArrangement: UUID?
    let paneCursors: [UUID: ArrangementPaneCursorState]
    let arrangementDrawerCursors: [ArrangementDrawerCursorKey: ArrangementDrawerCursorState]
    let drawerCursor: UUID?
    let zoom: UUID?
}

private struct InstalledFinalPaneRemovalParticipants {
    let participantSet: WorkspacePersistenceSnapshotParticipantSet
    let lease: WorkspaceStateSnapshotLease?
    let membership: [WorkspacePersistenceSnapshotParticipantID: Int]
}

@MainActor
private func makeFinalPaneRemovalPersistenceFixture() -> FinalPaneRemovalPersistenceFixture {
    .init()
}

@MainActor
private func makeFinalPaneRemovalPersistenceFixture(
    scenario: FinalPaneRemovalPersistenceScenario
) -> FinalPaneRemovalPersistenceFixture {
    .init(scenario: scenario)
}

@MainActor
private func installFinalPaneRemovalParticipants(
    _ runtime: WorkspacePersistenceRuntime,
    openLease: Bool = true
) throws -> InstalledFinalPaneRemovalParticipants {
    guard
        case .constructed(let participantSet) = runtime.snapshotParticipantFactory
            .constructCompositionParticipantSet()
    else { throw FinalPaneRemovalPersistenceTestError.installationFailed }
    guard openLease else {
        return .init(participantSet: participantSet, lease: nil, membership: [:])
    }
    let lease = WorkspaceStateSnapshotLease.open(
        pagerIdentity: .make(),
        revisionOwner: runtime.revisionOwner
    )
    var membership: [WorkspacePersistenceSnapshotParticipantID: Int] = [:]
    for participant in participantSet.participants {
        guard case .opened(let count) = participant.open(lease: lease) else {
            throw FinalPaneRemovalPersistenceTestError.leaseOpenFailed
        }
        membership[participant.participantID] = count
    }
    return .init(participantSet: participantSet, lease: lease, membership: membership)
}

@MainActor
private func finalPaneRemovalBaseItems(
    _ installed: InstalledFinalPaneRemovalParticipants,
    participantID: WorkspacePersistenceSnapshotParticipantID
) throws -> [WorkspacePersistenceSnapshotItem] {
    guard
        let lease = installed.lease,
        let participant = installed.participantSet.participants.first(where: {
            $0.participantID == participantID
        }),
        let count = installed.membership[participantID]
    else { throw FinalPaneRemovalPersistenceTestError.participantMissing }
    var items: [WorkspacePersistenceSnapshotItem] = []
    items.reserveCapacity(count)
    for slot in 0..<count {
        guard case .item(let item, _, _, _) = participant.inspectBaseSlot(lease: lease, slotCursor: slot)
        else { throw FinalPaneRemovalPersistenceTestError.unexpectedBaseSlot }
        items.append(item.item)
    }
    return items
}

@MainActor
private func finalPaneRemovalParticipantCloseReceipt(
    _ installed: InstalledFinalPaneRemovalParticipants,
    participantID: WorkspacePersistenceSnapshotParticipantID
) throws -> WorkspaceStateSnapshotParticipantCloseReceipt {
    guard
        let lease = installed.lease,
        let participant = installed.participantSet.participants.first(where: {
            $0.participantID == participantID
        })
    else { throw FinalPaneRemovalPersistenceTestError.participantMissing }
    guard case .closed(let receipt) = participant.close(lease: lease) else {
        throw FinalPaneRemovalPersistenceTestError.participantCloseFailed
    }
    return receipt
}

@MainActor
private func closeFinalPaneRemovalParticipants(_ installed: InstalledFinalPaneRemovalParticipants) {
    guard let lease = installed.lease else { return }
    for participant in installed.participantSet.participants {
        _ = participant.close(lease: lease)
        _ = participant.drainCleanup(maximumValues: Int.max)
    }
}

private func requireFinalPaneRemovalRevision(
    _ result: WorkspaceFinalPaneTabRemovalResult
) throws -> WorkspacePersistenceRevision {
    guard case .closed(let revision) = result else {
        throw FinalPaneRemovalPersistenceTestError.expectedClosed
    }
    return revision
}

private func makeFinalPaneRemovalPersistenceAlignedTabs(
    _ fixture: FinalPaneRemovalFixture
) -> [TabGraphState] {
    let prefix = makeFinalPaneRemovalUnrelatedTab(seed: 0)
    let suffix = makeFinalPaneRemovalUnrelatedTab(seed: 1)
    return [
        .init(tabId: fixture.shells[0].id, allPaneIds: prefix.allPaneIds, arrangements: prefix.arrangements),
        fixture.tab,
        .init(tabId: fixture.shells[2].id, allPaneIds: suffix.allPaneIds, arrangements: suffix.arrangements),
    ]
}

private enum FinalPaneRemovalPersistenceTestError: Error {
    case expectedClosed
    case installationFailed
    case leaseOpenFailed
    case participantMissing
    case participantCloseFailed
    case unexpectedBaseSlot
}

private enum FinalPaneRemovalPersistenceScenario {
    case activeMiddleTab
    case backgroundTab
    case onlyTab
}

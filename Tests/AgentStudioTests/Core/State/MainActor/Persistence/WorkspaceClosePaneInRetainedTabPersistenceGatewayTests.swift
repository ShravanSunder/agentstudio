import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("Close pane in retained tab persistence gateway")
struct RetainedTabPaneClosePersistenceTests {
    @Test("preinstall rejects without revision or state change")
    func preinstallRejects() {
        // Arrange
        let fixture = makeRetainedTabClosePersistenceFixture()
        let before = fixture.snapshot

        // Act
        let result = fixture.runtime.mutationCoordinator.closePaneInRetainedTab(fixture.fixture.request)

        // Assert
        #expect(result == .rejected(.compositionDomainNotInstalled(phase: .preinstall)))
        #expect(fixture.runtime.revisionOwner.committedRevision == .zero)
        #expect(fixture.snapshot == before)
    }

    @Test("installed close commits one revision and retains exact fixed-base values")
    func installedCloseCommitsExactPreimages() throws {
        // Arrange
        let fixture = makeRetainedTabClosePersistenceFixture(unrelatedCount: 256)
        let installed = try installRetainedTabCloseParticipants(fixture.runtime)
        let previousPane = fixture.fixture.pane
        let previousTab = fixture.fixture.tab

        // Act
        let result = fixture.runtime.mutationCoordinator.closePaneInRetainedTab(fixture.fixture.request)

        // Assert
        #expect(try requireRetainedTabClosedRevision(result).rawValue == 1)
        #expect(fixture.runtime.revisionOwner.committedRevision.rawValue == 1)
        #expect(fixture.registry.workspacePaneGraph.paneState(fixture.fixture.closedPaneID) == nil)
        #expect(fixture.registry.workspaceTabGraph.tabID(containingPane: fixture.fixture.closedPaneID) == nil)
        #expect(
            fixture.registry.workspaceTabGraph.tabState(previousTab.tabId)?.allPaneIds
                == [fixture.fixture.fallbackPaneID]
        )
        #expect(
            fixture.registry.workspaceArrangementCursor.activeArrangementId(forTab: previousTab.tabId)
                == fixture.fixture.defaultArrangementID
        )
        #expect(
            fixture.registry.workspaceArrangementCursor.activePaneId(
                forArrangement: fixture.fixture.selectedArrangementID
            ) == nil
        )
        #expect(fixture.registry.workspacePanePresentation.zoomedPaneId(forTab: previousTab.tabId) == nil)
        #expect(Array(fixture.registry.workspaceTabGraph.tabStates.suffix(256)) == fixture.unrelatedTabs)
        #expect(
            try retainedTabCloseBaseItems(installed, participantID: .paneGraphs)
                .contains(.paneGraph(previousPane))
        )
        #expect(
            try retainedTabCloseBaseItems(installed, participantID: .tabGraphs)
                .contains(.tabGraph(previousTab))
        )
        #expect(
            try retainedTabCloseBaseItems(installed, participantID: .activeArrangements)
                .contains(
                    .activeArrangement(
                        tabID: previousTab.tabId,
                        arrangementID: fixture.fixture.selectedArrangementID
                    )
                )
        )
        #expect(
            try retainedTabCloseBaseItems(installed, participantID: .activePanes)
                .contains(
                    .activePane(
                        arrangementID: fixture.fixture.selectedArrangementID,
                        paneID: fixture.fixture.closedPaneID
                    )
                )
        )
        closeRetainedTabCloseParticipants(installed)
    }

    @Test("planning rejection advances zero revision and mutates no owner")
    func planningRejectionIsAtomic() throws {
        // Arrange
        let fixture = makeRetainedTabClosePersistenceFixture()
        _ = try installRetainedTabCloseParticipants(fixture.runtime, openLease: false)
        let before = fixture.snapshot
        let missingPaneID = UUIDv7.generate()

        // Act
        let result = fixture.runtime.mutationCoordinator.closePaneInRetainedTab(
            .init(paneID: missingPaneID, tabID: fixture.fixture.tab.tabId)
        )

        // Assert
        #expect(result == .rejected(.planning(.paneMissing(missingPaneID))))
        #expect(fixture.runtime.revisionOwner.committedRevision == .zero)
        #expect(fixture.snapshot == before)
    }

    @Test("expanded target drawer rejects with zero revision and exact owner preservation")
    func expandedTargetDrawerRejectsAtomically() throws {
        // Arrange
        let fixture = makeRetainedTabClosePersistenceFixture()
        _ = try installRetainedTabCloseParticipants(fixture.runtime, openLease: false)
        let drawerID = try #require(fixture.fixture.pane.drawer?.drawerId)
        fixture.registry.workspaceDrawerCursor.expandDrawer(drawerId: drawerID)
        let before = fixture.snapshot

        // Act
        let result = fixture.runtime.mutationCoordinator.closePaneInRetainedTab(
            fixture.fixture.request
        )

        // Assert
        #expect(result == .rejected(.planning(.paneDrawerExpanded(drawerID: drawerID))))
        #expect(fixture.runtime.revisionOwner.committedRevision == .zero)
        #expect(fixture.snapshot == before)
        #expect(fixture.registry.workspaceDrawerCursor.expandedDrawerId == drawerID)
    }

    @Test("gateway is keyed runtime-only for zoom and remains production dormant")
    func gatewayIsKeyedAndDormant() throws {
        // Arrange
        let root = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let sources = root.appending(path: "Sources/AgentStudio")
        let paths = try FileManager.default.subpathsOfDirectory(atPath: sources.path)
        let gateway = try String(
            contentsOf: sources.appending(
                path: "Core/State/MainActor/Persistence/WorkspaceClosePaneInRetainedTabPersistenceGateway.swift"
            ),
            encoding: .utf8
        )

        // Act
        let callers = try paths.compactMap { relativePath -> String? in
            guard relativePath.hasSuffix(".swift") else { return nil }
            let source = try String(contentsOf: sources.appending(path: relativePath), encoding: .utf8)
            return source.contains("mutationCoordinator.closePaneInRetainedTab") ? relativePath : nil
        }

        // Assert
        #expect(callers.isEmpty)
        #expect(gateway.contains("paneState(request.paneID)"))
        #expect(gateway.contains("tabID(containingPane: request.paneID)"))
        #expect(gateway.contains("tabState(request.tabID)"))
        #expect(!gateway.contains("workspacePanePresentation.capturePersistence"))
        #expect(!gateway.contains("workspaceTabShell"))
        #expect(!gateway.contains("workspaceTabCursor"))
        #expect(gateway.contains("workspaceDrawerCursorAtom.expandedDrawerId"))
        #expect(!gateway.contains("adapters.workspaceDrawerCursor"))
    }
}

@MainActor
private final class RetainedTabClosePersistenceFixture {
    let fixture: RetainedTabCloseFixture
    let registry: AtomRegistry
    let runtime: WorkspacePersistenceRuntime
    let unrelatedTabs: [TabGraphState]

    init(unrelatedCount: Int) {
        fixture = makeRetainedTabCloseFixture()
        unrelatedTabs = (0..<unrelatedCount).map { makeRetainedTabClosePersistenceUnrelatedTab(seed: $0) }
        registry = AtomRegistry()
        registry.workspacePaneGraph.setCanonicalPaneState(fixture.pane)
        registry.workspacePaneGraph.setCanonicalPaneState(
            .init(
                pane: Pane(
                    id: fixture.fallbackPaneID,
                    content: .webview(WebviewState(url: URL(string: "https://example.com/fallback")!)),
                    metadata: .init(title: "Fallback"),
                    kind: .layout(
                        drawer: Drawer(
                            drawerId: UUIDv7.generate(),
                            parentPaneId: fixture.fallbackPaneID
                        )
                    )
                )
            )
        )
        registry.workspaceTabGraph.replaceTabStates([fixture.tab] + unrelatedTabs)
        registry.workspaceArrangementCursor.replaceCursors(
            activeArrangementIdsByTabId: [fixture.tab.tabId: fixture.selectedArrangementID],
            paneCursorsByArrangementId: [
                fixture.selectedArrangementID: .init(activePaneId: fixture.closedPaneID),
                fixture.defaultArrangementID: .init(activePaneId: fixture.fallbackPaneID),
            ],
            drawerCursorsByKey: [:]
        )
        registry.workspacePanePresentation.setZoomedPaneId(fixture.closedPaneID, forTab: fixture.tab.tabId)
        runtime = WorkspacePersistenceRuntime(atomRegistry: registry)
    }

    var snapshot: RetainedTabClosePersistenceSnapshot {
        .init(
            pane: registry.workspacePaneGraph.paneState(fixture.closedPaneID),
            tab: registry.workspaceTabGraph.tabState(fixture.tab.tabId),
            activeArrangement: registry.workspaceArrangementCursor.activeArrangementId(forTab: fixture.tab.tabId),
            selectedPane: registry.workspaceArrangementCursor.activePaneId(
                forArrangement: fixture.selectedArrangementID
            ),
            zoom: registry.workspacePanePresentation.zoomedPaneId(forTab: fixture.tab.tabId)
        )
    }
}

private struct RetainedTabClosePersistenceSnapshot: Equatable {
    let pane: PaneGraphState?
    let tab: TabGraphState?
    let activeArrangement: UUID?
    let selectedPane: UUID?
    let zoom: UUID?
}

private struct InstalledRetainedTabCloseParticipants {
    let participantSet: WorkspacePersistenceSnapshotParticipantSet
    let lease: WorkspaceStateSnapshotLease?
    let membership: [WorkspacePersistenceSnapshotParticipantID: Int]
}

@MainActor
private func makeRetainedTabClosePersistenceFixture(
    unrelatedCount: Int = 0
) -> RetainedTabClosePersistenceFixture {
    .init(unrelatedCount: unrelatedCount)
}

@MainActor
private func installRetainedTabCloseParticipants(
    _ runtime: WorkspacePersistenceRuntime,
    openLease: Bool = true
) throws -> InstalledRetainedTabCloseParticipants {
    guard
        case .constructed(let participantSet) = runtime.snapshotParticipantFactory
            .constructCompositionParticipantSet()
    else { throw RetainedTabClosePersistenceTestError.installationFailed }
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
            throw RetainedTabClosePersistenceTestError.leaseOpenFailed
        }
        membership[participant.participantID] = count
    }
    return .init(participantSet: participantSet, lease: lease, membership: membership)
}

@MainActor
private func retainedTabCloseBaseItems(
    _ installed: InstalledRetainedTabCloseParticipants,
    participantID: WorkspacePersistenceSnapshotParticipantID
) throws -> [WorkspacePersistenceSnapshotItem] {
    guard
        let lease = installed.lease,
        let participant = installed.participantSet.participants.first(where: {
            $0.participantID == participantID
        }),
        let count = installed.membership[participantID]
    else { throw RetainedTabClosePersistenceTestError.participantMissing }
    return (0..<count).compactMap { slot in
        guard case .item(let item, _, _, _) = participant.inspectBaseSlot(lease: lease, slotCursor: slot)
        else { return nil }
        return item.item
    }
}

@MainActor
private func closeRetainedTabCloseParticipants(_ installed: InstalledRetainedTabCloseParticipants) {
    guard let lease = installed.lease else { return }
    for participant in installed.participantSet.participants {
        _ = participant.close(lease: lease)
    }
}

private func makeRetainedTabClosePersistenceUnrelatedTab(seed: Int) -> TabGraphState {
    let paneID = UUIDv7.generate()
    return .init(
        tabId: UUIDv7.generate(),
        allPaneIds: [paneID],
        arrangements: [
            makeRetainedTabCloseArrangement(
                id: UUIDv7.generate(),
                isDefault: true,
                paneIDs: [paneID]
            )
        ]
    )
}

private func requireRetainedTabClosedRevision(
    _ result: WorkspaceClosePaneInRetainedTabPersistenceResult
) throws -> WorkspacePersistenceRevision {
    guard case .closed(let revision) = result else {
        throw RetainedTabClosePersistenceTestError.expectedClosed
    }
    return revision
}

private enum RetainedTabClosePersistenceTestError: Error {
    case expectedClosed
    case installationFailed
    case leaseOpenFailed
    case participantMissing
}

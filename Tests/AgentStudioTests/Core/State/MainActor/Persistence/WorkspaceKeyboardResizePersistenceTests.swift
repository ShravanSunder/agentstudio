import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("Workspace keyboard resize persistence")
struct WorkspaceKeyboardResizePersistenceTests {
    @Test("preinstall and zoom reject without revision or graph mutation")
    func preinstallAndZoomRejectWithoutMutation() {
        // Arrange
        let fixture = makeTabGraphLeafFixture()
        let registry = AtomRegistry()
        registry.workspaceTabGraph.replaceTabStates([fixture.tabState])
        registry.workspaceArrangementCursor.replaceCursors(
            activeArrangementIdsByTabId: [fixture.tabState.tabId: fixture.customArrangementID],
            paneCursorsByArrangementId: [:],
            drawerCursorsByKey: [:]
        )
        let runtime = WorkspacePersistenceRuntime(atomRegistry: registry)
        let request = WorkspaceKeyboardResizeRequest(
            tabID: fixture.tabState.tabId,
            paneID: fixture.paneIDs[0],
            direction: .right,
            amount: 10
        )
        let graphBefore = registry.workspaceTabGraph.tabStates

        // Act
        let preinstall = runtime.mutationCoordinator.resizePaneByDelta(request)
        guard case .constructed = runtime.snapshotParticipantFactory.constructCompositionParticipantSet() else {
            Issue.record("expected composition installation")
            return
        }
        registry.workspacePanePresentation.setZoomedPaneId(fixture.paneIDs[0], forTab: fixture.tabState.tabId)
        let zoomed = runtime.mutationCoordinator.resizePaneByDelta(request)

        // Assert
        #expect(preinstall == .rejected(.compositionDomainNotInstalled(phase: .preinstall)))
        #expect(
            zoomed
                == .rejected(
                    .planning(.zoomed(tabID: fixture.tabState.tabId, paneID: fixture.paneIDs[0]))
                )
        )
        #expect(runtime.revisionOwner.committedRevision == .zero)
        #expect(registry.workspaceTabGraph.tabStates == graphBefore)
    }

    @Test("installed resize captures one target preimage and preserves unrelated fleet")
    func installedResizeCapturesTargetPreimageAndPreservesFleet() throws {
        // Arrange
        let fixture = makeTabGraphLeafFixture()
        let unrelated = (0..<256).map { _ in makeTabGraphLeafFixture().tabState }
        let registry = AtomRegistry()
        registry.workspaceTabGraph.replaceTabStates(unrelated + [fixture.tabState])
        registry.workspaceArrangementCursor.replaceCursors(
            activeArrangementIdsByTabId: [fixture.tabState.tabId: fixture.customArrangementID],
            paneCursorsByArrangementId: [:],
            drawerCursorsByKey: [:]
        )
        let runtime = WorkspacePersistenceRuntime(atomRegistry: registry)
        guard
            case .constructed(let participantSet) = runtime.snapshotParticipantFactory
                .constructCompositionParticipantSet(),
            let participant = participantSet.participants.first(where: { $0.participantID == .tabGraphs })
        else {
            Issue.record("expected tab graph participant")
            return
        }
        let lease = WorkspaceStateSnapshotLease.open(
            pagerIdentity: .make(),
            revisionOwner: runtime.revisionOwner
        )
        #expect(participant.open(lease: lease) == .opened(baseMembershipCount: 257))

        // Act
        let result = runtime.mutationCoordinator.resizePaneByDelta(
            .init(
                tabID: fixture.tabState.tabId,
                paneID: fixture.paneIDs[0],
                direction: .right,
                amount: 10
            )
        )

        // Assert
        guard case .changed(let revision) = result else {
            Issue.record("expected installed keyboard resize to change")
            return
        }
        #expect(revision.rawValue == 1)
        #expect(Array(registry.workspaceTabGraph.tabStates.prefix(256)) == unrelated)
        #expect(runtime.revisionOwner.committedRevision.rawValue == 1)
        let retainedTarget = (0..<257).compactMap { index -> TabGraphState? in
            guard
                case .item(let item, _, _, _) = participant.inspectBaseSlot(
                    lease: lease,
                    slotCursor: index
                ),
                case .tabGraph(let tab) = item.item,
                tab.tabId == fixture.tabState.tabId
            else { return nil }
            return tab
        }
        #expect(retainedTarget == [fixture.tabState])
        _ = participant.close(lease: lease)
    }

    @Test("coordinator captures only keyed resize planning state")
    func coordinatorUsesOnlyKeyedPlanningReads() throws {
        // Arrange
        let source = try workspacePersistenceMutationCoordinatorSource()

        // Act
        let methodStart = try #require(source.range(of: "func resizePaneByDelta("))
        let suffix = source[methodStart.lowerBound...]
        let methodEnd = try #require(
            suffix.range(
                of: "\n    func ", options: [], range: suffix.index(after: methodStart.lowerBound)..<suffix.endIndex))
        let method = String(suffix[..<methodEnd.lowerBound])

        // Assert
        #expect(method.contains("workspaceTabGraphAtom.tabState(request.tabID)"))
        #expect(method.contains("workspaceArrangementCursorAtom.activeArrangementId(forTab: request.tabID)"))
        #expect(method.contains("workspacePanePresentationAtom.zoomedPaneId(forTab: request.tabID)"))
        #expect(!method.contains(".tabStates"))
        #expect(!method.contains("activeArrangementIdsByTabId"))
        #expect(!method.contains("zoomedPaneIdsByTabId"))
    }

    @Test("keyboard resize remains dormant outside the persistence coordinator")
    func keyboardResizeHasNoAppOrFeatureCallers() throws {
        // Arrange
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let sourceRoots = ["Sources/AgentStudio/App", "Sources/AgentStudio/Features"]

        // Act
        let callers = try sourceRoots.flatMap { relativeRoot -> [String] in
            let root = projectRoot.appending(path: relativeRoot)
            return try FileManager.default.subpathsOfDirectory(atPath: root.path).compactMap { relativePath in
                guard relativePath.hasSuffix(".swift") else { return nil }
                let source = try String(contentsOf: root.appending(path: relativePath), encoding: .utf8)
                return source.contains("mutationCoordinator.resizePaneByDelta")
                    ? "\(relativeRoot)/\(relativePath)"
                    : nil
            }
        }

        // Assert
        #expect(callers.isEmpty)
    }
}

private func workspacePersistenceMutationCoordinatorSource() throws -> String {
    let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
    let sourceURL = projectRoot.appending(
        path:
            "Sources/AgentStudio/Core/State/MainActor/Persistence/"
            + "WorkspacePersistenceMutationCoordinator.swift"
    )
    return try String(contentsOf: sourceURL, encoding: .utf8)
}

import AgentStudioInfrastructure
import Foundation
import Observation
import Testing

@testable import AgentStudioCore

private final class WorkspacePaneObservationCounter: @unchecked Sendable {
    private(set) var invalidationCount = 0

    func record() {
        invalidationCount += 1
    }
}

@MainActor
@Suite("Workspace pane boundary split")
struct WorkspacePaneBoundaryTests {
    @Test("Pane graph isolates canonical structural membership and accepted revision observation")
    func paneGraphObservationIsolatesDependencyClasses() throws {
        let graphAtom = WorkspacePaneGraphAtom()
        let paneA = graphAtom.createPane(
            launchDirectory: URL(filePath: "/tmp/pane-a", directoryHint: .isDirectory),
            zmxSessionID: .generateUUIDv7()
        )
        let paneB = graphAtom.createPane(
            launchDirectory: URL(filePath: "/tmp/pane-b", directoryHint: .isDirectory),
            zmxSessionID: .generateUUIDv7()
        )
        let revisionAfterInsertion = graphAtom.paneAcceptedCommitRevision
        let canonicalA = observe { _ = graphAtom.paneState(paneA.id) }
        let canonicalB = observe { _ = graphAtom.paneState(paneB.id) }
        let structuralA = observe { _ = graphAtom.paneStructuralFacts(paneA.id) }
        let structuralB = observe { _ = graphAtom.paneStructuralFacts(paneB.id) }
        let membership = observe { _ = graphAtom.paneIDs }
        let acceptedRevision = observe { _ = graphAtom.paneAcceptedCommitRevision }

        graphAtom.updatePaneTitle(paneA.id, title: "Renamed")

        #expect(canonicalA.invalidationCount == 1)
        #expect(canonicalB.invalidationCount == 0)
        #expect(structuralA.invalidationCount == 0)
        #expect(structuralB.invalidationCount == 0)
        #expect(membership.invalidationCount == 0)
        #expect(acceptedRevision.invalidationCount == 1)
        #expect(graphAtom.paneAcceptedCommitRevision == revisionAfterInsertion + 1)

        let equalCanonicalA = observe { _ = graphAtom.paneState(paneA.id) }
        let equalStructuralA = observe { _ = graphAtom.paneStructuralFacts(paneA.id) }
        let equalRevision = observe { _ = graphAtom.paneAcceptedCommitRevision }

        graphAtom.updatePaneTitle(paneA.id, title: "Renamed")

        #expect(equalCanonicalA.invalidationCount == 0)
        #expect(equalStructuralA.invalidationCount == 0)
        #expect(equalRevision.invalidationCount == 0)
        #expect(graphAtom.paneAcceptedCommitRevision == revisionAfterInsertion + 1)

        let cwdCanonicalA = observe { _ = graphAtom.paneState(paneA.id) }
        let cwdCanonicalB = observe { _ = graphAtom.paneState(paneB.id) }
        let cwdStructuralA = observe { _ = graphAtom.paneStructuralFacts(paneA.id) }
        let cwdStructuralB = observe { _ = graphAtom.paneStructuralFacts(paneB.id) }
        let cwdMembership = observe { _ = graphAtom.paneIDs }
        let cwdRevision = observe { _ = graphAtom.paneAcceptedCommitRevision }
        let updatedCWD = URL(filePath: "/tmp/pane-a/Sources", directoryHint: .isDirectory)

        graphAtom.updatePaneCWD(paneA.id, cwd: updatedCWD)

        #expect(cwdCanonicalA.invalidationCount == 1)
        #expect(cwdCanonicalB.invalidationCount == 0)
        #expect(cwdStructuralA.invalidationCount == 1)
        #expect(cwdStructuralB.invalidationCount == 0)
        #expect(cwdMembership.invalidationCount == 0)
        #expect(cwdRevision.invalidationCount == 1)
        #expect(graphAtom.paneStructuralFacts(paneA.id)?.cwd == updatedCWD)
        #expect(graphAtom.paneStructuralFacts(paneA.id)?.paneID == paneA.id)
    }

    @Test("Pane graph reconciles insertion removal replacement restore and retained missing slots atomically")
    func paneGraphReconcilesLifecycleAndRetainedMissingSlotsAtomically() throws {
        let graphAtom = WorkspacePaneGraphAtom()
        let paneA = graphAtom.createPane(
            launchDirectory: URL(filePath: "/tmp/pane-lifecycle-a", directoryHint: .isDirectory),
            zmxSessionID: .generateUUIDv7()
        )
        let restoredPaneID = UUIDv7.generate()
        let restoredPane = Pane(
            id: restoredPaneID,
            content: .terminal(
                TerminalState(provider: .zmx, lifetime: .persistent, zmxSessionID: .generateUUIDv7())
            ),
            metadata: PaneMetadata(
                launchDirectory: URL(filePath: "/tmp/pane-restored", directoryHint: .isDirectory),
                title: "Restored"
            )
        )
        let missingCanonical = observe { _ = graphAtom.paneState(restoredPaneID) }
        let missingStructural = observe { _ = graphAtom.paneStructuralFacts(restoredPaneID) }
        let insertionMembership = observe { _ = graphAtom.paneIDs }
        let insertionRevision = observe { _ = graphAtom.paneAcceptedCommitRevision }

        #expect(graphAtom.insertRestoredPane(restoredPane))

        #expect(missingCanonical.invalidationCount == 1)
        #expect(missingStructural.invalidationCount == 1)
        #expect(insertionMembership.invalidationCount == 1)
        #expect(insertionRevision.invalidationCount == 1)
        #expect(graphAtom.paneStateSnapshot()[restoredPaneID] == graphAtom.paneState(restoredPaneID))

        let unaffectedCanonical = observe { _ = graphAtom.paneState(paneA.id) }
        let removedCanonical = observe { _ = graphAtom.paneState(restoredPaneID) }
        let removedStructural = observe { _ = graphAtom.paneStructuralFacts(restoredPaneID) }
        let removalMembership = observe { _ = graphAtom.paneIDs }
        let removalRevision = observe { _ = graphAtom.paneAcceptedCommitRevision }

        #expect(graphAtom.deletePaneAndOwnedDrawerChildren(restoredPaneID))

        #expect(unaffectedCanonical.invalidationCount == 0)
        #expect(removedCanonical.invalidationCount == 1)
        #expect(removedStructural.invalidationCount == 1)
        #expect(removalMembership.invalidationCount == 1)
        #expect(removalRevision.invalidationCount == 1)
        #expect(graphAtom.paneState(restoredPaneID) == nil)

        var replacementStates = graphAtom.paneStateSnapshot()
        replacementStates[paneA.id]?.metadata.title = "Replacement title"
        replacementStates[restoredPaneID] = PaneGraphState(pane: restoredPane)
        let replacementCanonicalA = observe { _ = graphAtom.paneState(paneA.id) }
        let replacementStructuralA = observe { _ = graphAtom.paneStructuralFacts(paneA.id) }
        let replacementCanonicalB = observe { _ = graphAtom.paneState(restoredPaneID) }
        let replacementStructuralB = observe { _ = graphAtom.paneStructuralFacts(restoredPaneID) }
        let replacementMembership = observe { _ = graphAtom.paneIDs }
        let replacementRevision = observe { _ = graphAtom.paneAcceptedCommitRevision }

        graphAtom.replacePaneStates(try requirePaneGraphReplacement(replacementStates))

        #expect(replacementCanonicalA.invalidationCount == 1)
        #expect(replacementStructuralA.invalidationCount == 0)
        #expect(replacementCanonicalB.invalidationCount == 1)
        #expect(replacementStructuralB.invalidationCount == 1)
        #expect(replacementMembership.invalidationCount == 1)
        #expect(replacementRevision.invalidationCount == 1)
        #expect(graphAtom.paneIDs == Set([paneA.id, restoredPaneID]))

        let retainedMissingID = UUIDv7.generate()
        let retainedCanonical = observe { _ = graphAtom.paneState(retainedMissingID) }
        let retainedStructural = observe { _ = graphAtom.paneStructuralFacts(retainedMissingID) }
        let unchangedRevision = observe { _ = graphAtom.paneAcceptedCommitRevision }
        let revisionBeforeReplacement = graphAtom.paneAcceptedCommitRevision

        graphAtom.replacePaneStates(
            try requirePaneGraphReplacement(graphAtom.paneStateSnapshot())
        )

        #expect(retainedCanonical.invalidationCount == 0)
        #expect(retainedStructural.invalidationCount == 0)
        #expect(unchangedRevision.invalidationCount == 0)
        #expect(graphAtom.paneAcceptedCommitRevision == revisionBeforeReplacement)
    }

    @Test("Pane graph state preserves durable association and strips drawer expansion and display facets")
    func paneGraphStatePreservesDurableAssociationAndStripsCursorAndDisplayFields() throws {
        let repoId = UUID()
        let worktreeId = UUID()
        let paneId = UUIDv7.generate()
        let pane = Pane(
            id: paneId,
            content: .terminal(
                TerminalState(
                    provider: .zmx,
                    lifetime: .persistent,
                    zmxSessionID: .generateUUIDv7()
                )
            ),
            metadata: PaneMetadata(
                launchDirectory: URL(filePath: "/tmp/agent-studio", directoryHint: .isDirectory),
                title: "Terminal",
                facets: PaneContextFacets(
                    repoId: repoId,
                    repoName: "stale repo",
                    worktreeId: worktreeId,
                    worktreeName: "stale worktree",
                    cwd: URL(filePath: "/tmp/agent-studio/Sources", directoryHint: .isDirectory),
                    parentFolder: "stale parent",
                    organizationName: "stale org",
                    origin: "stale origin",
                    upstream: "stale upstream"
                ),
                note: "ship it"
            ),
            kind: .layout(
                drawer: Drawer(
                    parentPaneId: paneId,
                    paneIds: [],
                    isExpanded: true
                )
            )
        )
        let graphAtom = WorkspacePaneGraphAtom()

        graphAtom.replacePaneStates(
            try requirePaneGraphReplacement([pane.id: PaneGraphState(pane: pane)])
        )

        let state = try #require(graphAtom.paneState(pane.id))
        #expect(state.metadata.facets.paneContextFacets.repoId == repoId)
        #expect(state.metadata.facets.paneContextFacets.worktreeId == worktreeId)
        #expect(
            state.metadata.facets.cwd
                == URL(filePath: "/tmp/agent-studio/Sources", directoryHint: .isDirectory)
        )
        #expect(state.metadata.facets.paneContextFacets.repoName == nil)
        #expect(state.metadata.facets.paneContextFacets.worktreeName == nil)
        #expect(state.metadata.facets.paneContextFacets.parentFolder == nil)
        #expect(state.metadata.facets.paneContextFacets.organizationName == nil)
        #expect(state.metadata.facets.paneContextFacets.origin == nil)
        #expect(state.metadata.facets.paneContextFacets.upstream == nil)
        #expect(state.drawer?.paneIds.isEmpty == true)
    }

    @Test("Pane graph normalizes a partial durable association to unassociated")
    func paneGraphNormalizesPartialDurableAssociationToUnassociated() throws {
        let graphAtom = WorkspacePaneGraphAtom()

        let pane = graphAtom.createPane(
            launchDirectory: URL(filePath: "/tmp/partial-association", directoryHint: .isDirectory),
            zmxSessionID: .generateUUIDv7(),
            facets: PaneContextFacets(
                repoId: UUIDv7.generate(),
                cwd: URL(filePath: "/tmp/partial-association", directoryHint: .isDirectory)
            )
        )

        let facets = try #require(graphAtom.paneState(pane.id)?.durableContextFacets)
        #expect(facets.repoId == nil)
        #expect(facets.worktreeId == nil)
    }

    @Test("Pane association revisions reject stale and equal completions without publication")
    func paneAssociationRevisionsRejectStaleAndEqualCompletions() throws {
        let graphAtom = WorkspacePaneGraphAtom()
        let originalRepoID = UUIDv7.generate()
        let originalWorktreeID = UUIDv7.generate()
        let pane = graphAtom.createPane(
            launchDirectory: URL(filePath: "/tmp/revision-original", directoryHint: .isDirectory),
            zmxSessionID: .generateUUIDv7(),
            facets: PaneContextFacets(
                repoId: originalRepoID,
                worktreeId: originalWorktreeID,
                cwd: URL(filePath: "/tmp/revision-original", directoryHint: .isDirectory)
            )
        )
        let staleRevision = try #require(graphAtom.reservePaneAssociationRevision(pane.id))
        let currentRevision = try #require(graphAtom.reservePaneAssociationRevision(pane.id))
        let currentRepoID = UUIDv7.generate()
        let currentWorktreeID = UUIDv7.generate()
        let currentCWD = URL(filePath: "/tmp/revision-current", directoryHint: .isDirectory)

        #expect(
            graphAtom.applyPaneAssociationUpdate(
                pane.id,
                cwd: currentCWD,
                resolution: .matched(repoId: currentRepoID, worktreeId: currentWorktreeID),
                revision: currentRevision
            ) == .applied
        )
        let canonicalObservation = observe { _ = graphAtom.paneState(pane.id) }
        let structuralObservation = observe { _ = graphAtom.paneStructuralFacts(pane.id) }

        #expect(
            graphAtom.applyPaneAssociationUpdate(
                pane.id,
                cwd: URL(filePath: "/tmp/revision-stale", directoryHint: .isDirectory),
                resolution: .confidentNoMatch,
                revision: staleRevision
            ) == .staleRevision
        )
        #expect(
            graphAtom.applyPaneAssociationUpdate(
                pane.id,
                cwd: currentCWD,
                resolution: .matched(repoId: currentRepoID, worktreeId: currentWorktreeID),
                revision: currentRevision
            ) == .staleRevision
        )

        let facets = try #require(graphAtom.paneState(pane.id)?.durableContextFacets)
        #expect(facets.repoId == currentRepoID)
        #expect(facets.worktreeId == currentWorktreeID)
        #expect(facets.cwd == currentCWD)
        #expect(canonicalObservation.invalidationCount == 0)
        #expect(structuralObservation.invalidationCount == 0)
    }

    @Test("Uncertain association resolution retains the known pair while accepting CWD")
    func uncertainAssociationResolutionRetainsKnownPair() throws {
        let graphAtom = WorkspacePaneGraphAtom()
        let repoID = UUIDv7.generate()
        let worktreeID = UUIDv7.generate()
        let pane = graphAtom.createPane(
            launchDirectory: URL(filePath: "/tmp/uncertain-original", directoryHint: .isDirectory),
            zmxSessionID: .generateUUIDv7(),
            facets: PaneContextFacets(repoId: repoID, worktreeId: worktreeID)
        )
        let revision = try #require(graphAtom.reservePaneAssociationRevision(pane.id))
        let updatedCWD = URL(filePath: "/tmp/uncertain-updated", directoryHint: .isDirectory)

        #expect(
            graphAtom.applyPaneAssociationUpdate(
                pane.id,
                cwd: updatedCWD,
                resolution: .uncertain,
                revision: revision
            ) == .deferredUncertain
        )

        let facets = try #require(graphAtom.paneState(pane.id)?.durableContextFacets)
        #expect(facets.repoId == repoID)
        #expect(facets.worktreeId == worktreeID)
        #expect(facets.cwd == updatedCWD)
    }

    @Test("Pane graph projection preserves explicitly cleared live worktree facets")
    func paneGraphProjectionPreservesClearedLiveWorktreeFacets() throws {
        let repoId = UUID()
        let worktreeId = UUID()
        let graphAtom = WorkspacePaneGraphAtom()
        let paneAtom = WorkspacePaneAtom(graphAtom: graphAtom)
        let pane = paneAtom.createPane(
            launchDirectory: URL(filePath: "/tmp/project", directoryHint: .isDirectory),
            zmxSessionID: .generateUUIDv7(),
            facets: PaneContextFacets(
                repoId: repoId,
                worktreeId: worktreeId,
                cwd: URL(filePath: "/tmp/project", directoryHint: .isDirectory)
            )
        )

        let result = paneAtom.updatePaneCWDAndResolvedContext(
            pane.id,
            cwd: URL(filePath: "/tmp/outside-project", directoryHint: .isDirectory),
            resolvedContext: nil
        )
        let projectedPane = try #require(paneAtom.pane(pane.id))

        #expect(result == .applied)
        #expect(
            projectedPane.metadata.cwd
                == URL(filePath: "/tmp/outside-project", directoryHint: .isDirectory)
        )
        #expect(projectedPane.repoId == nil)
        #expect(projectedPane.worktreeId == nil)
    }

    @Test("Required pane rejects an invalid CWD update and preserves its last accepted CWD")
    func requiredPaneRejectsInvalidCWDUpdate() throws {
        let paneAtom = WorkspacePaneAtom(graphAtom: WorkspacePaneGraphAtom())
        let acceptedCWD = URL(filePath: "/tmp/required-terminal", directoryHint: .isDirectory)
        let pane = paneAtom.createPane(
            launchDirectory: acceptedCWD,
            zmxSessionID: .generateUUIDv7(),
            facets: PaneContextFacets(cwd: acceptedCWD)
        )

        let result = paneAtom.updatePaneCWDAndResolvedContext(
            pane.id,
            cwd: nil,
            resolvedContext: nil
        )

        #expect(result == .unchanged)
        #expect(try #require(paneAtom.pane(pane.id)).metadata.cwd == acceptedCWD)
    }

    @Test("Generic pane creation rejects required content without a trustworthy location")
    func genericPaneCreationRejectsUnlocatedRequiredContent() {
        let graphAtom = WorkspacePaneGraphAtom()

        _ = graphAtom.createPane(
            content: .bridgePanel(BridgePaneState(panelKind: .diffViewer, source: .commit(sha: "abc123"))),
            metadata: PaneMetadata(title: "Unlocated review")
        )

        #expect(graphAtom.paneIDs.isEmpty)
    }

    @Test("Generic pane creation derives required locations from content-owned sources")
    func genericPaneCreationDerivesRequiredLocations() throws {
        let graphAtom = WorkspacePaneGraphAtom()
        let bridgeRoot = URL(filePath: "/tmp/location-policy-bridge", directoryHint: .isDirectory)
        let codeFile = URL(filePath: "/tmp/location-policy-code/Sources/App.swift")

        let bridgePane = try #require(
            graphAtom.createPane(
                content: .bridgePanel(
                    BridgePaneState(
                        panelKind: .fileViewer,
                        source: .workspace(
                            rootPath: bridgeRoot.path,
                            baseline: .ref(name: "HEAD~1")
                        )
                    )
                ),
                metadata: PaneMetadata(title: "Files")
            )
        )
        let codePane = try #require(
            graphAtom.createPane(
                content: .codeViewer(CodeViewerState(filePath: codeFile, scrollToLine: nil)),
                metadata: PaneMetadata(title: "Code")
            )
        )

        #expect(bridgePane.metadata.facets.cwd == bridgeRoot)
        #expect(
            codePane.metadata.facets.cwd
                == URL(filePath: codeFile.deletingLastPathComponent().path, directoryHint: .isDirectory)
        )
    }

    @Test("Terminal creation normalizes CWD and ignores an invalid higher-precedence sample")
    func terminalCreationAdmitsFirstValidNormalizedLocation() throws {
        let graphAtom = WorkspacePaneGraphAtom()
        let normalizedPane = graphAtom.createPane(
            launchDirectory: URL(
                filePath: "/tmp/terminal-normalization-fallback",
                directoryHint: .isDirectory
            ),
            zmxSessionID: .generateUUIDv7(),
            facets: PaneContextFacets(
                cwd: URL(
                    filePath: "/tmp/terminal-normalization/../accepted",
                    directoryHint: .isDirectory
                )
            )
        )
        let fallbackPane = graphAtom.createPane(
            launchDirectory: URL(filePath: "/tmp/terminal-valid-launch", directoryHint: .isDirectory),
            zmxSessionID: .generateUUIDv7(),
            facets: PaneContextFacets(cwd: try #require(URL(string: "https://example.com/not-a-cwd")))
        )

        let expectedNormalizedCWD = URL(filePath: "/tmp/accepted", directoryHint: .isDirectory)
        let expectedFallbackCWD = URL(filePath: "/tmp/terminal-valid-launch", directoryHint: .isDirectory)
        #expect(normalizedPane.metadata.facets.cwd == expectedNormalizedCWD)
        #expect(normalizedPane.metadata.launchDirectory == expectedNormalizedCWD)
        #expect(fallbackPane.metadata.facets.cwd == expectedFallbackCWD)
        #expect(fallbackPane.metadata.launchDirectory == expectedFallbackCWD)
    }

    @Test("Generic drawer admission rejects or repairs required content before insertion")
    func genericDrawerAdmissionEnforcesRequiredLocationPolicy() throws {
        let graphAtom = WorkspacePaneGraphAtom()
        let parent = graphAtom.createPane(
            launchDirectory: URL(filePath: "/tmp/drawer-admission-parent", directoryHint: .isDirectory),
            zmxSessionID: .generateUUIDv7()
        )
        let rejected = graphAtom.addDrawerPane(
            to: parent.id,
            content: .bridgePanel(BridgePaneState(panelKind: .diffViewer, source: .commit(sha: "abc123"))),
            metadata: PaneMetadata(title: "Unlocated review")
        )
        let codeFile = URL(filePath: "/tmp/drawer-admission-code/Sources/App.swift")
        let repaired = try #require(
            graphAtom.addDrawerPane(
                to: parent.id,
                content: .codeViewer(CodeViewerState(filePath: codeFile, scrollToLine: 10)),
                metadata: PaneMetadata(title: "Code")
            )
        )
        let membershipBeforeRejectedInsert = graphAtom.paneState(parent.id)?.drawer?.paneIds
        let rejectedInsert = graphAtom.insertDrawerPane(
            in: parent.id,
            at: repaired.id,
            content: .bridgePanel(BridgePaneState(panelKind: .fileViewer, source: nil)),
            metadata: PaneMetadata(title: "Unlocated files")
        )

        #expect(rejected == nil)
        #expect(
            repaired.metadata.facets.cwd
                == URL(filePath: "/tmp/drawer-admission-code/Sources", directoryHint: .isDirectory)
        )
        #expect(rejectedInsert == nil)
        #expect(graphAtom.paneState(parent.id)?.drawer?.paneIds == membershipBeforeRejectedInsert)
    }

    @Test("Pane creation preserves the caller-supplied zmx identity")
    func paneCreationPreservesCallerSuppliedZmxIdentity() throws {
        let graphAtom = WorkspacePaneGraphAtom()
        let paneAtom = WorkspacePaneAtom(graphAtom: graphAtom)
        let suppliedSessionID = try #require(ZmxSessionID(restoring: "existing-session"))
        let pane = paneAtom.createPane(zmxSessionID: suppliedSessionID)

        guard case .terminal(let terminalState) = graphAtom.paneState(pane.id)?.content else {
            Issue.record("Expected pane content to remain terminal")
            return
        }
        #expect(terminalState.zmxSessionID == suppliedSessionID)
    }

    @Test("Drawer cursor owns expansion and derived panes reflect it atomically")
    func drawerCursorOwnsExpansionAndDerivedPaneReflectsIt() throws {
        let graphAtom = WorkspacePaneGraphAtom()
        let drawerCursorAtom = WorkspaceDrawerCursorAtom()
        let paneAtom = WorkspacePaneAtom(graphAtom: graphAtom, drawerCursorAtom: drawerCursorAtom)
        let derived = WorkspacePaneDerived(graphAtom: graphAtom, drawerCursorAtom: drawerCursorAtom)
        let firstPane = paneAtom.createPane(zmxSessionID: .generateUUIDv7())
        let secondPane = paneAtom.createPane(zmxSessionID: .generateUUIDv7())
        let firstDrawerId = try #require(graphAtom.paneState(firstPane.id)?.drawer?.drawerId)
        let secondDrawerId = try #require(graphAtom.paneState(secondPane.id)?.drawer?.drawerId)

        paneAtom.toggleDrawer(for: firstPane.id)
        paneAtom.toggleDrawer(for: secondPane.id)

        #expect(drawerCursorAtom.isExpanded(drawerId: firstDrawerId) == false)
        #expect(drawerCursorAtom.isExpanded(drawerId: secondDrawerId) == true)
        #expect(derived.pane(firstPane.id)?.drawer?.isExpanded == false)
        #expect(derived.pane(secondPane.id)?.drawer?.isExpanded == true)
    }

    @Test("Pane derived model composes display facets from topology and cache")
    func paneDerivedComposesDisplayFacetsFromTopologyAndCache() throws {
        let repoId = UUID()
        let worktreeId = UUID()
        let repoPath = URL(filePath: "/tmp/project-dev/agent-studio")
        let worktreePath = repoPath.appending(path: "sqlite")
        let repo = Repo(id: repoId, name: "agent-studio", repoPath: repoPath)
        let worktree = Worktree(
            id: worktreeId,
            repoId: repoId,
            name: "sqlite",
            path: worktreePath,
            isMainWorktree: false
        )
        let mainWorktree = Worktree(
            repoId: repoId,
            name: "agent-studio",
            path: repoPath,
            isMainWorktree: true
        )
        let topologyAtom = RepositoryTopologyAtom()
        try replaceTopology(
            topologyAtom,
            repositories: [
                Repo(id: repo.id, name: repo.name, repoPath: repo.repoPath, worktrees: [mainWorktree, worktree])
            ]
        )
        let cacheAtom = RepoEnrichmentCacheAtom()
        cacheAtom.setRepoEnrichment(
            .resolvedRemote(
                repoId: repoId,
                raw: RawRepoOrigin(origin: "git@github.com:ShravanSunder/agentstudio.git", upstream: "origin/main"),
                identity: RepoIdentity(
                    groupKey: "ShravanSunder",
                    remoteSlug: "ShravanSunder/agentstudio",
                    organizationName: "ShravanSunder",
                    displayName: "agentstudio"
                ),
                updatedAt: Date(timeIntervalSince1970: 1)
            )
        )
        let graphAtom = WorkspacePaneGraphAtom()
        let drawerCursorAtom = WorkspaceDrawerCursorAtom()
        let paneAtom = WorkspacePaneAtom(
            graphAtom: graphAtom,
            drawerCursorAtom: drawerCursorAtom,
            repositoryTopologyAtom: topologyAtom
        )
        let derived = WorkspacePaneDerived(
            graphAtom: graphAtom,
            drawerCursorAtom: drawerCursorAtom,
            repositoryTopologyAtom: topologyAtom,
            repoEnrichmentCacheAtom: cacheAtom
        )
        let pane = paneAtom.createPane(
            launchDirectory: worktreePath,
            zmxSessionID: .generateUUIDv7(),
            facets: PaneContextFacets(
                repoId: repoId,
                repoName: "stale repo",
                worktreeId: worktreeId,
                worktreeName: "stale worktree",
                cwd: worktreePath.appending(path: "Sources"),
                parentFolder: "stale parent",
                organizationName: "stale org",
                origin: "stale origin",
                upstream: "stale upstream"
            )
        )

        let derivedPane = try #require(derived.pane(pane.id))

        #expect(derivedPane.metadata.facets.repoName == "agent-studio")
        #expect(derivedPane.metadata.facets.worktreeName == "sqlite")
        #expect(derivedPane.metadata.facets.parentFolder == "project-dev")
        #expect(derivedPane.metadata.facets.organizationName == "ShravanSunder")
        #expect(derivedPane.metadata.facets.origin == "git@github.com:ShravanSunder/agentstudio.git")
        #expect(derivedPane.metadata.facets.upstream == "origin/main")
    }

    @Test("Pane derived worktree lookup uses composed topology context")
    func paneDerivedWorktreeLookupUsesComposedTopologyContext() throws {
        let repoId = UUID()
        let worktreeId = UUID()
        let repoPath = URL(filePath: "/tmp/project-dev/agent-studio")
        let worktreePath = repoPath.appending(path: "sqlite")
        let worktree = Worktree(
            id: worktreeId,
            repoId: repoId,
            name: "sqlite",
            path: worktreePath,
            isMainWorktree: false
        )
        let mainWorktree = Worktree(
            repoId: repoId,
            name: "agent-studio",
            path: repoPath,
            isMainWorktree: true
        )
        let topologyAtom = RepositoryTopologyAtom()
        try replaceTopology(
            topologyAtom,
            repositories: [
                Repo(id: repoId, name: "agent-studio", repoPath: repoPath, worktrees: [mainWorktree, worktree])
            ]
        )
        let graphAtom = WorkspacePaneGraphAtom()
        let drawerCursorAtom = WorkspaceDrawerCursorAtom()
        let paneAtom = WorkspacePaneAtom(
            graphAtom: graphAtom,
            drawerCursorAtom: drawerCursorAtom,
            repositoryTopologyAtom: topologyAtom
        )
        let derived = WorkspacePaneDerived(
            graphAtom: graphAtom,
            drawerCursorAtom: drawerCursorAtom,
            repositoryTopologyAtom: topologyAtom
        )
        let pane = paneAtom.createPane(
            launchDirectory: worktreePath,
            zmxSessionID: .generateUUIDv7(),
            facets: PaneContextFacets(cwd: worktreePath.appending(path: "Sources"))
        )

        let worktreePanes = derived.panes(for: worktreeId)

        #expect(worktreePanes.map(\.id) == [pane.id])
        #expect(worktreePanes.first?.repoId == repoId)
        #expect(worktreePanes.first?.worktreeId == worktreeId)
    }

    @Test("Cold and live pane projections agree across removal and fresh worktree identity")
    func coldAndLivePaneProjectionsAgreeAcrossFreshWorktreeIdentity() throws {
        let repoId = UUIDv7.generate()
        let originalWorktreeId = UUIDv7.generate()
        let replacementWorktreeId = UUIDv7.generate()
        let repoPath = URL(filePath: "/tmp/project-dev/association-equivalence")
        let worktreePath = repoPath.appending(path: "feature")
        let paneCWD = worktreePath.appending(path: "Sources", directoryHint: .isDirectory)
        let mainWorktree = Worktree(
            id: UUIDv7.generate(),
            repoId: repoId,
            name: "association-equivalence",
            path: repoPath,
            isMainWorktree: true
        )
        let originalWorktree = Worktree(
            id: originalWorktreeId,
            repoId: repoId,
            name: "feature",
            path: worktreePath
        )
        let topologyAtom = RepositoryTopologyAtom()
        try replaceTopology(
            topologyAtom,
            repositories: [
                Repo(
                    id: repoId,
                    name: "association-equivalence",
                    repoPath: repoPath,
                    worktrees: [mainWorktree, originalWorktree]
                )
            ]
        )
        let graphAtom = WorkspacePaneGraphAtom()
        let drawerCursorAtom = WorkspaceDrawerCursorAtom()
        let paneAtom = WorkspacePaneAtom(
            graphAtom: graphAtom,
            drawerCursorAtom: drawerCursorAtom,
            repositoryTopologyAtom: topologyAtom
        )
        let pane = paneAtom.createPane(
            launchDirectory: paneCWD,
            zmxSessionID: .generateUUIDv7(),
            facets: PaneContextFacets(cwd: paneCWD)
        )
        let liveDerived = WorkspacePaneDerived(
            graphAtom: graphAtom,
            drawerCursorAtom: drawerCursorAtom,
            repositoryTopologyAtom: topologyAtom
        )

        #expect(liveDerived.pane(pane.id)?.worktreeId == originalWorktreeId)

        try replaceTopology(
            topologyAtom,
            repositories: [
                Repo(
                    id: repoId,
                    name: "association-equivalence",
                    repoPath: repoPath,
                    worktrees: [mainWorktree]
                )
            ]
        )
        #expect(liveDerived.pane(pane.id)?.repoId == nil)
        #expect(liveDerived.pane(pane.id)?.worktreeId == nil)

        let replacementWorktree = Worktree(
            id: replacementWorktreeId,
            repoId: repoId,
            name: "feature",
            path: worktreePath
        )
        let finalRepositories = [
            Repo(
                id: repoId,
                name: "association-equivalence",
                repoPath: repoPath,
                worktrees: [mainWorktree, replacementWorktree]
            )
        ]
        try replaceTopology(topologyAtom, repositories: finalRepositories)
        let adoptionRevision = try #require(graphAtom.reservePaneAssociationRevision(pane.id))
        #expect(
            graphAtom.applyPaneAssociationUpdate(
                pane.id,
                cwd: paneCWD,
                resolution: .matched(repoId: repoId, worktreeId: replacementWorktreeId),
                revision: adoptionRevision
            ) == .applied
        )
        let liveFacets = try #require(liveDerived.pane(pane.id)?.metadata.facets)

        let coldTopologyAtom = RepositoryTopologyAtom()
        try replaceTopology(coldTopologyAtom, repositories: finalRepositories)
        let coldDerived = WorkspacePaneDerived(
            graphAtom: graphAtom,
            drawerCursorAtom: drawerCursorAtom,
            repositoryTopologyAtom: coldTopologyAtom
        )
        let coldFacets = try #require(coldDerived.pane(pane.id)?.metadata.facets)

        #expect(liveFacets.worktreeId == replacementWorktreeId)
        #expect(coldFacets == liveFacets)
        expectDurablePaneAssociation(
            graphAtom, pane.id, PaneContextFacets(repoId: repoId, worktreeId: replacementWorktreeId, cwd: paneCWD)
        )
    }

    @Test("Pane count derives current worktree membership from CWD and topology")
    func paneCountDerivesCurrentWorktreeMembershipFromCWDAndTopology() throws {
        let repoId = UUID()
        let worktreeId = UUID()
        let repoPath = URL(filePath: "/tmp/project-dev/agent-studio")
        let worktreePath = repoPath.appending(path: "performance")
        let mainWorktree = Worktree(
            repoId: repoId,
            name: "agent-studio",
            path: repoPath,
            isMainWorktree: true
        )
        let topologyAtom = RepositoryTopologyAtom()
        try replaceTopology(
            topologyAtom,
            repositories: [
                Repo(
                    id: repoId,
                    name: "agent-studio",
                    repoPath: repoPath,
                    worktrees: [
                        mainWorktree,
                        Worktree(
                            id: worktreeId,
                            repoId: repoId,
                            name: "performance",
                            path: worktreePath,
                            isMainWorktree: false
                        ),
                    ]
                )
            ]
        )
        let paneAtom = WorkspacePaneAtom(
            graphAtom: WorkspacePaneGraphAtom(),
            repositoryTopologyAtom: topologyAtom
        )
        _ = paneAtom.createPane(
            launchDirectory: worktreePath,
            zmxSessionID: .generateUUIDv7(),
            facets: PaneContextFacets(cwd: worktreePath.appending(path: "Sources"))
        )

        #expect(paneAtom.paneCount(for: worktreeId) == 1)
    }

    private func replaceTopology(
        _ atom: RepositoryTopologyAtom,
        repositories: [Repo]
    ) throws {
        guard
            case .prepared(let replacement) = RepositoryTopologyReplacement.prepare(
                repositories: repositories,
                watchedPaths: [],
                unavailableRepositoryIDs: []
            )
        else {
            throw WorkspacePaneBoundaryTestError.topologyReplacementRejected
        }
        atom.replaceTopology(replacement)
    }

    private func requirePaneGraphReplacement(
        _ paneStates: [UUID: PaneGraphState]
    ) throws -> WorkspacePaneGraphReplacement {
        switch WorkspacePaneGraphReplacement.prepare(paneStates) {
        case .success(let replacement):
            return replacement
        case .failure:
            throw WorkspacePaneBoundaryTestError.paneGraphReplacementRejected
        }
    }

    private func observe(_ read: @escaping @MainActor () -> Void) -> WorkspacePaneObservationCounter {
        let counter = WorkspacePaneObservationCounter()
        withObservationTracking {
            read()
        } onChange: {
            counter.record()
        }
        return counter
    }
}

private enum WorkspacePaneBoundaryTestError: Error {
    case paneGraphReplacementRejected
    case topologyReplacementRejected
}

@MainActor
private func expectDurablePaneAssociation(
    _ graphAtom: WorkspacePaneGraphAtom,
    _ paneId: UUID,
    _ expected: PaneContextFacets
) {
    #expect(graphAtom.paneState(paneId)?.durableContextFacets == expected)
}

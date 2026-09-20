import AgentStudioCore
import AgentStudioInfrastructure
import AppKit
import Testing

@testable import AgentStudioRepoExplorer

@MainActor
@Suite("RepoExplorerListKeyboardIntegrationTests", .serialized)
struct RepoExplorerListKeyboardIntegrationTests {
    @Test("local action descriptors resolve unmodified arrows Enter Escape and digits")
    func localActionDescriptorsOwnListTriggers() {
        let actions: [RepoExplorerListKeyboardAction] =
            [
                .moveSelectionUp,
                .moveSelectionDown,
                .moveToParentOrCollapseGroup,
                .moveToFirstChildOrExpandGroup,
                .activateSelection,
                .returnFocus,
            ] + (1...9).map(RepoExplorerListKeyboardAction.activateNumberedDestination)

        for action in actions {
            #expect(RepoExplorerListKeyboardAction.resolve(action.trigger) == action)
            #expect(action.trigger.modifiers.isEmpty)
            #expect(!action.actionSpec.label.isEmpty)
            #expect(!action.actionSpec.helpText.isEmpty)
        }
        let expectedDirections: [(ShortcutInputKey, RepoExplorerListKeyboardAction)] = [
            (.arrow(.up), .moveSelectionUp),
            (.arrow(.down), .moveSelectionDown),
            (.arrow(.left), .moveToParentOrCollapseGroup),
            (.arrow(.right), .moveToFirstChildOrExpandGroup),
            (.enter, .activateSelection),
            (.escape, .returnFocus),
        ]
        for (key, expectedAction) in expectedDirections {
            #expect(RepoExplorerListKeyboardAction.resolve(ShortcutTrigger(key: key, modifiers: [])) == expectedAction)
            #expect(expectedAction.trigger.key == key)
        }
        #expect(
            RepoExplorerListKeyboardAction.resolve(
                ShortcutTrigger(key: .arrow(.down), modifiers: [.command])
            ) == nil
        )
        #expect(
            RepoExplorerListKeyboardAction.resolve(
                ShortcutTrigger(key: .character(.p), modifiers: [])
            ) == nil
        )
    }

    @Test("accepted content selects and scrolls the first destination rather than a leading group")
    func acceptedContentSelectsInitialDestination() throws {
        let fixture = RepoExplorerListKeyboardFixture()
        defer { fixture.close() }
        let paneID = UUIDv7.generate()
        let tabID = UUIDv7.generate()
        let snapshot = navigationSnapshot([
            .section(.panes),
            .group(id: "group:leading", expanded: false),
            .unassociatedPane(paneID: paneID, tabID: tabID),
        ])
        let expectedRowID = RepoExplorerRowID.unassociatedPane(paneID: paneID)

        guard case .accepted = try fixture.apply(snapshot: snapshot, generation: 1) else {
            Issue.record("Initial real-table candidate must be accepted")
            return
        }
        #expect(fixture.host.selectedRowID == expectedRowID)
        #expect(fixture.nativeSelectedRowID(in: snapshot) == expectedRowID)
        #expect(fixture.recorder.focusedPaneIDs.isEmpty)
        #expect(fixture.recorder.commandRequests.isEmpty)
    }

    @Test("background content waits for keyboard entry before creating initial selection")
    func backgroundContentWaitsForKeyboardEntry() throws {
        let fixture = RepoExplorerListKeyboardFixture(focusListInitially: false)
        defer { fixture.close() }
        let paneID = UUIDv7.generate()
        let tabID = UUIDv7.generate()
        let snapshot = navigationSnapshot([
            .unassociatedPane(paneID: paneID, tabID: tabID)
        ])
        let expectedRowID = RepoExplorerRowID.unassociatedPane(paneID: paneID)

        _ = try fixture.apply(snapshot: snapshot, generation: 1)
        #expect(fixture.host.selectedRowID == nil)
        #expect(fixture.nativeSelectedRowID(in: snapshot) == nil)
        #expect(fixture.window.makeFirstResponder(fixture.host))
        #expect(fixture.host.selectedRowID == expectedRowID)
        #expect(fixture.nativeSelectedRowID(in: snapshot) == expectedRowID)
    }

    @Test("Up and Down follow numbered destinations and stop at both edges")
    func verticalNavigationFollowsNumberedDestinations() throws {
        let fixture = RepoExplorerListKeyboardFixture()
        defer { fixture.close() }
        let paneIDs = (0..<3).map { _ in UUIDv7.generate() }
        let tabID = UUIDv7.generate()
        let numberedRowIDs = paneIDs.map { RepoExplorerRowID.unassociatedPane(paneID: $0) }
        let snapshot = navigationSnapshot([
            .section(.panes),
            .group(id: "group:first", expanded: true),
            .activity(groupID: "group:first", bucket: .active),
            .unassociatedPane(paneID: paneIDs[0], tabID: tabID),
            .loadingSection(.repositories),
            .group(id: "group:middle", expanded: false),
            .unassociatedPane(paneID: paneIDs[1], tabID: tabID),
            .topologyFault,
            .group(id: "group:last", expanded: false),
            .unassociatedPane(paneID: paneIDs[2], tabID: tabID),
        ])
        _ = try fixture.apply(snapshot: snapshot, generation: 1)

        try fixture.send(.moveSelectionUp)
        #expect(fixture.host.selectedRowID == numberedRowIDs[0])
        try fixture.send(.moveSelectionUp)
        #expect(fixture.host.selectedRowID == numberedRowIDs[0])
        try fixture.send(.moveSelectionDown)
        #expect(fixture.host.selectedRowID == numberedRowIDs[1])
        try fixture.send(.moveSelectionDown)
        #expect(fixture.host.selectedRowID == numberedRowIDs[2])
        try fixture.send(.moveSelectionDown)
        #expect(fixture.host.selectedRowID == numberedRowIDs[2])
        #expect(fixture.nativeSelectedRowID(in: snapshot) == numberedRowIDs[2])
        #expect(fixture.recorder.focusedPaneIDs.isEmpty)
        #expect(fixture.recorder.commandRequests.isEmpty)
    }

    @Test("Left and Right traverse group relationships and repeated Right requests expansion")
    func horizontalNavigationAndExpansionAreIdempotent() throws {
        let fixture = RepoExplorerListKeyboardFixture()
        defer { fixture.close() }
        let paneID = UUIDv7.generate()
        let tabID = UUIDv7.generate()
        let groupRowID = RepoExplorerRowID.group(groupID: "group:expanded")
        let paneRowID = RepoExplorerRowID.tabPane(groupID: "group:expanded", paneID: paneID)
        let expandedSnapshot = navigationSnapshot([
            .group(id: "group:expanded", expanded: true),
            .activity(groupID: "group:expanded", bucket: .justNow),
            .tabPane(groupID: "group:expanded", paneID: paneID, tabID: tabID),
        ])
        _ = try fixture.apply(snapshot: expandedSnapshot, generation: 1)

        try fixture.send(.moveToParentOrCollapseGroup)
        #expect(fixture.host.selectedRowID == groupRowID)
        try fixture.send(.moveToFirstChildOrExpandGroup)
        #expect(fixture.host.selectedRowID == paneRowID)

        let collapsedSnapshot = navigationSnapshot([
            .group(id: "group:collapsed", expanded: false)
        ])
        _ = try fixture.apply(snapshot: collapsedSnapshot, generation: 2)
        try fixture.send(.moveToFirstChildOrExpandGroup)
        try fixture.send(.moveToFirstChildOrExpandGroup)
        #expect(
            fixture.recorder.expansionRequests == [
                RepoExplorerGroupExpansionRequest(groupID: "group:collapsed", isExpanded: true),
                RepoExplorerGroupExpansionRequest(groupID: "group:collapsed", isExpanded: true),
            ]
        )
        try fixture.send(.activateSelection)
        #expect(fixture.recorder.toggledGroupIDs == ["group:collapsed"])
    }

    @Test("Enter and digits use exact accepted worktree and pane callbacks")
    func activationUsesExactAcceptedRows() throws {
        let fixture = RepoExplorerListKeyboardFixture()
        defer { fixture.close() }
        let repositoryID = UUIDv7.generate()
        let worktreeID = UUIDv7.generate()
        let paneID = UUIDv7.generate()
        let tabID = UUIDv7.generate()
        let paneRowID = RepoExplorerRowID.unassociatedPane(paneID: paneID)
        let snapshot = navigationSnapshot([
            .worktree(groupID: "group:worktree", repositoryID: repositoryID, worktreeID: worktreeID),
            .unassociatedPane(paneID: paneID, tabID: tabID),
        ])
        _ = try fixture.apply(snapshot: snapshot, generation: 1)

        try fixture.send(.activateSelection)
        #expect(fixture.recorder.commandRequests.last?.command == .openWorktree)
        #expect(fixture.recorder.commandRequests.last?.target == worktreeID)
        try fixture.send(.moveSelectionDown)
        #expect(fixture.host.selectedRowID == paneRowID)
        try fixture.send(.activateSelection)
        #expect(fixture.recorder.focusedPaneIDs.last == paneID)
        try fixture.send(.activateNumberedDestination(1))
        #expect(fixture.recorder.commandRequests.last?.target == worktreeID)
        try fixture.send(.activateNumberedDestination(2))
        #expect(fixture.recorder.focusedPaneIDs == [paneID, paneID])
        #expect(fixture.recorder.commandRequests.map(\.target) == [worktreeID, worktreeID])
        #expect(fixture.recorder.commandRequests.allSatisfy { $0.targetType == .worktree })
    }

    @Test("pane activation commits held preview before the existing focus effect")
    func activationCommitsPreviewBeforeFocusEffect() throws {
        let fixture = RepoExplorerListKeyboardFixture()
        defer { fixture.close() }
        let paneID = UUIDv7.generate()
        let tabID = UUIDv7.generate()
        let snapshot = navigationSnapshot([
            .unassociatedPane(paneID: paneID, tabID: tabID)
        ])
        fixture.interaction.configure(
            RepoExplorerKeyboardCallbacks(
                canInterpretListInput: { true },
                onPreviewCommit: { fixture.recorder.recordPreviewCommit() }
            )
        )

        _ = try fixture.apply(snapshot: snapshot, generation: 1)
        try fixture.send(.activateSelection)

        #expect(fixture.recorder.events == ["previewCommit", "focusPane"])
        #expect(fixture.recorder.focusedPaneIDs == [paneID])
    }

    @Test("passive selection synchronization is distinct from deliberate arrow preview selection")
    func paneSelectionReportsItsOrigin() throws {
        let fixture = RepoExplorerListKeyboardFixture()
        defer { fixture.close() }
        let tabID = UUIDv7.generate()
        let firstPaneID = UUIDv7.generate()
        let secondPaneID = UUIDv7.generate()
        let expectedPassiveTarget = RepoExplorerSelectedPaneTarget(
            paneID: firstPaneID, owningTabID: tabID
        )
        let expectedArrowTarget = RepoExplorerSelectedPaneTarget(
            paneID: secondPaneID, owningTabID: tabID
        )
        let snapshot = navigationSnapshot([
            .unassociatedPane(paneID: firstPaneID, tabID: tabID),
            .unassociatedPane(paneID: secondPaneID, tabID: tabID),
        ])
        var observedChanges: [(RepoExplorerSelectedPaneTarget?, RepoExplorerSelectedPaneTargetChangeOrigin)] = []
        fixture.interaction.configure(
            RepoExplorerKeyboardCallbacks(
                canInterpretListInput: { true },
                onSelectedPaneTargetChange: { target, origin in
                    observedChanges.append((target, origin))
                }
            )
        )

        _ = try fixture.apply(snapshot: snapshot, generation: 1)
        #expect(observedChanges.last?.0 == expectedPassiveTarget)
        #expect(observedChanges.last?.1 == .passiveSynchronization)

        try fixture.send(.moveSelectionDown)

        #expect(observedChanges.last?.0 == expectedArrowTarget)
        #expect(observedChanges.last?.1 == .arrowNavigation)
    }

    @Test("digit nine activates its accepted destination below the viewport")
    func ninthDestinationActivatesOffscreen() throws {
        let fixture = RepoExplorerListKeyboardFixture(windowHeight: 40)
        defer { fixture.close() }
        let tabID = UUIDv7.generate()
        let paneIDs = (0..<10).map { _ in UUIDv7.generate() }
        let snapshot = navigationSnapshot(
            paneIDs.map { .unassociatedPane(paneID: $0, tabID: tabID) }
        )
        _ = try fixture.apply(snapshot: snapshot, generation: 1)

        let tableView = try #require(firstRepoExplorerKeyboardDescendant(NSTableView.self, in: fixture.host))
        #expect(tableView.visibleRect.height > 0)
        #expect(!tableView.rect(ofRow: 8).intersects(tableView.visibleRect))
        try fixture.send(.activateNumberedDestination(9))
        #expect(fixture.recorder.focusedPaneIDs == [paneIDs[8]])
    }

    @Test("accepted updates reconcile selection across regroup removal and empty content")
    func acceptedUpdatesReconcileSelection() throws {
        let fixture = RepoExplorerListKeyboardFixture()
        defer { fixture.close() }
        let repositoryID = UUIDv7.generate()
        let worktreeID = UUIDv7.generate()
        let successorPaneID = UUIDv7.generate()
        let tabID = UUIDv7.generate()
        let sourceRowID = RepoExplorerRowID.worktree(
            groupID: "group:source",
            repoID: repositoryID,
            worktreeID: worktreeID
        )
        let regroupedRowID = RepoExplorerRowID.worktree(
            groupID: "group:regrouped",
            repoID: repositoryID,
            worktreeID: worktreeID
        )
        let successorRowID = RepoExplorerRowID.unassociatedPane(paneID: successorPaneID)
        let source = navigationSnapshot([
            .worktree(groupID: "group:source", repositoryID: repositoryID, worktreeID: worktreeID),
            .unassociatedPane(paneID: successorPaneID, tabID: tabID),
        ])
        let regrouped = navigationSnapshot([
            .worktree(groupID: "group:regrouped", repositoryID: repositoryID, worktreeID: worktreeID),
            .unassociatedPane(paneID: successorPaneID, tabID: tabID),
        ])
        let removed = navigationSnapshot([
            .unassociatedPane(paneID: successorPaneID, tabID: tabID)
        ])

        _ = try fixture.apply(snapshot: source, generation: 1)
        #expect(fixture.host.selectedRowID == sourceRowID)
        _ = try fixture.apply(snapshot: regrouped, generation: 2)
        #expect(fixture.host.selectedRowID == regroupedRowID)
        _ = try fixture.apply(snapshot: removed, generation: 3)
        #expect(fixture.host.selectedRowID == successorRowID)
        _ = try fixture.apply(rowless: .searchNoResults, generation: 4)
        #expect(fixture.host.selectedRowID == nil)
    }

    @Test("background updates retain an offscreen viewport anchor instead of revealing selection")
    func backgroundUpdatesDoNotScrollToRetainedSelection() throws {
        let fixture = RepoExplorerListKeyboardFixture(windowHeight: 40)
        defer { fixture.close() }
        let tabID = UUIDv7.generate()
        let paneIDs = (0..<11).map { _ in UUIDv7.generate() }
        let source = navigationSnapshot(
            paneIDs.prefix(10).map { .unassociatedPane(paneID: $0, tabID: tabID) }
        )
        let target = navigationSnapshot(
            paneIDs.map { .unassociatedPane(paneID: $0, tabID: tabID) }
        )
        let retainedAnchorRowID = RepoExplorerRowID.unassociatedPane(paneID: paneIDs[8])
        let selectedRowID = RepoExplorerRowID.unassociatedPane(paneID: paneIDs[0])

        _ = try fixture.apply(snapshot: source, generation: 1)
        fixture.materializer.scroll(to: retainedAnchorRowID, offset: 0)
        #expect(fixture.materializer.currentTopVisibleAnchor?.rowID == retainedAnchorRowID)
        _ = try fixture.apply(snapshot: target, generation: 2)

        #expect(fixture.host.selectedRowID == selectedRowID)
        #expect(fixture.materializer.currentTopVisibleAnchor?.rowID == retainedAnchorRowID)
    }

    @Test("rejected candidates leave host and native selection unchanged")
    func rejectedCandidatePreservesSelection() throws {
        let fixture = RepoExplorerListKeyboardFixture()
        defer { fixture.close() }
        let paneID = UUIDv7.generate()
        let replacementPaneID = UUIDv7.generate()
        let tabID = UUIDv7.generate()
        let initial = navigationSnapshot([
            .unassociatedPane(paneID: paneID, tabID: tabID)
        ])
        let replacement = navigationSnapshot([
            .unassociatedPane(paneID: replacementPaneID, tabID: tabID)
        ])
        _ = try fixture.apply(snapshot: initial, generation: 1)
        let validCandidate = try fixture.candidate(snapshot: replacement, generation: 2)
        let rejectedCandidate = RepoExplorerMaterializationCandidate(
            id: validCandidate.id,
            lifetimeID: validCandidate.lifetimeID,
            demandEpoch: validCandidate.demandEpoch,
            requestGeneration: validCandidate.requestGeneration,
            visibleGeneration: validCandidate.visibleGeneration,
            expectedRevision: 99,
            proposedRevision: validCandidate.proposedRevision,
            presentation: validCandidate.presentation,
            nativeUpdatePlan: validCandidate.nativeUpdatePlan
        )

        #expect(fixture.host.apply(rejectedCandidate) == .rejected(.revisionMismatch))
        let expectedRowID = RepoExplorerRowID.unassociatedPane(paneID: paneID)
        #expect(fixture.host.selectedRowID == expectedRowID)
        #expect(fixture.nativeSelectedRowID(in: initial) == expectedRowID)
    }

    @Test("editable non-list input keeps digits as text without sidebar action")
    func editableInputRemainsProtected() throws {
        let fixture = RepoExplorerListKeyboardFixture()
        defer { fixture.close() }
        let paneID = UUIDv7.generate()
        let tabID = UUIDv7.generate()
        let snapshot = navigationSnapshot([
            .unassociatedPane(paneID: paneID, tabID: tabID)
        ])
        _ = try fixture.apply(snapshot: snapshot, generation: 1)
        #expect(fixture.window.makeFirstResponder(fixture.textField))

        try fixture.send(.activateNumberedDestination(1), directlyToHost: false)
        #expect(fixture.textField.stringValue == "1")
        #expect(fixture.recorder.focusedPaneIDs.isEmpty)
        #expect(fixture.recorder.commandRequests.isEmpty)
        #expect(fixture.host.selectedRowID == .unassociatedPane(paneID: paneID))
    }
}

import AgentStudioInfrastructure
import AgentStudioTestSupport
import Foundation
import GRDB
import Testing

@testable import AgentStudioCore

func testCommittedMemberLinks(_ worktreeIDs: [UUID]) -> [BridgeMemberLink] {
    worktreeIDs.map { worktreeID in
        BridgeMemberLink(
            worktreeId: worktreeID,
            contributions: [
                BridgeLinkContribution(
                    addedBy: .app, addedAt: Date(timeIntervalSince1970: 1_700_000_000))
            ])
    }
}

func receiverTopologySnapshot(
    for receiver: BridgeReceiver,
    knownWorktreeRoots: [UUID: String] = [:],
    currentCWDWorktreeID: UUID? = nil
) throws -> BridgeReceiverTopologySnapshot {
    let repositoryID = UUIDv7.generate()
    let worktrees = knownWorktreeRoots.map { worktreeID, root in
        Worktree(
            id: worktreeID, repoId: repositoryID,
            name: worktreeID.uuidString, path: URL(fileURLWithPath: root))
    }
    let repository = Repo(
        id: repositoryID, name: "Receiver test repository",
        repoPath: URL(fileURLWithPath: "/tmp"), worktrees: worktrees)
    let repositories = worktrees.isEmpty ? [] : [repository]
    guard
        case .prepared(let replacement) = RepositoryTopologyReplacement.prepare(
            repositories: repositories, watchedPaths: [], unavailableRepositoryIDs: [])
    else {
        throw BridgeReceiverStorageError.malformedRow("test topology")
    }
    let content: PaneContent
    switch receiver.kind {
    case .terminalAssociated:
        content = .terminal(
            .init(
                provider: .zmx, lifetime: .persistent,
                zmxSessionID: .generateUUIDv7()))
    case .standaloneBridge:
        content = .bridgePanel(.init(panelKind: .fileViewer))
    }
    let pane = Pane(
        id: receiver.paneId, content: content,
        metadata: PaneMetadata(
            contentType: receiver.kind == .terminalAssociated ? .terminal : .diff,
            launchDirectory: URL(fileURLWithPath: "/tmp"),
            facets: PaneContextFacets(
                repoId: currentCWDWorktreeID == nil ? nil : repositoryID,
                worktreeId: currentCWDWorktreeID)))
    return BridgeReceiverTopologySnapshot(
        sourcePaneId: receiver.paneId,
        paneStatesByID: [receiver.paneId: PaneGraphState(pane: pane)],
        companionEntriesBySourceID: [:],
        repositoryTopology: RepositoryTopologyReadSnapshot(replacement: replacement))
}

@Suite("Bridge receiver keyed SQLite storage", .serialized)
struct BridgeReceiverKeyedStorageTests {
    @Test("agent show preparation validates a local file and committed membership")
    func agentShowPreparation() async throws {
        let fixture = try ReceiverKeyedStorageFixture()
        defer { fixture.remove() }
        let receiver = BridgeReceiver.standalone(UUIDv7.generate())
        let worktree = UUIDv7.generate()
        let memberRoot = fixture.root.appending(path: "member", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: memberRoot, withIntermediateDirectories: true)
        let file = memberRoot.appending(path: "show.swift")
        #expect(FileManager.default.createFile(atPath: file.path, contents: Data("show".utf8)))
        let outside = fixture.root.appending(path: "outside.swift")
        #expect(FileManager.default.createFile(atPath: outside.path, contents: Data("outside".utf8)))
        try FileManager.default.createSymbolicLink(
            at: memberRoot.appending(path: "escape.swift"), withDestinationURL: outside)
        let topology = try receiverTopologySnapshot(
            for: receiver, knownWorktreeRoots: [worktree: memberRoot.path])
        let datastore = WorkspaceSQLiteDatastoreFactory(
            coreDatabaseURL: fixture.root.appending(path: "core.sqlite"),
            localDatabaseURL: fixture.root.appending(path: "local.sqlite")
        ).makeDatastore()
        _ = await datastore.prepareDatabasesForBoot()

        let target = try BridgeAgentShowTarget(
            worktree: worktree, relativePath: "show.swift", line: 9)
        let loose = try await datastore.prepareAgentShow(
            workspaceID: fixture.repository.workspaceId, receiver: receiver,
            target: target, topologySnapshot: topology)
        guard case .prepared(let looseDocument) = loose else {
            Issue.record("Expected a validated loose document")
            return
        }
        #expect(looseDocument.provenance == nil)
        #expect(looseDocument.openedLine == 9)

        _ = try fixture.repository.commitBridgeMemberAddition(
            receiver: receiver, worktreeID: worktree, contributor: .person,
            generation: 1, addedAt: Date(timeIntervalSince1970: 100), topologySnapshot: topology)
        let linked = try await datastore.prepareAgentShow(
            workspaceID: fixture.repository.workspaceId, receiver: receiver,
            target: target, topologySnapshot: topology)
        guard case .prepared(let memberDocument) = linked else {
            Issue.record("Expected a validated member document")
            return
        }
        #expect(memberDocument.provenance?.worktreeId == worktree)
        #expect(memberDocument.location == looseDocument.location)

        let missing = try BridgeAgentShowTarget(worktree: worktree, relativePath: "missing.swift")
        let missingOutcome = try await datastore.prepareAgentShow(
            workspaceID: fixture.repository.workspaceId, receiver: receiver,
            target: missing, topologySnapshot: topology)
        guard case .notFound = missingOutcome else {
            Issue.record("Missing file was accepted")
            return
        }
        let escaped = try BridgeAgentShowTarget(worktree: worktree, relativePath: "escape.swift")
        let escapedOutcome = try await datastore.prepareAgentShow(
            workspaceID: fixture.repository.workspaceId, receiver: receiver,
            target: escaped, topologySnapshot: topology)
        guard case .notFound = escapedOutcome else {
            Issue.record("Escaped file was accepted")
            return
        }

        let retirementTime = BridgeReceiverRetirementTime(
            clock: TestPushClock(), anchorDate: Date(timeIntervalSince1970: 1000))
        try fixture.repository.retireBridgeReceiver(receiver, time: retirementTime)
        let retiredOutcome = try await datastore.prepareAgentShow(
            workspaceID: fixture.repository.workspaceId, receiver: receiver,
            target: target, topologySnapshot: topology)
        guard case .paneUnavailable = retiredOutcome else {
            Issue.record("Retired receiver was accepted")
            return
        }
    }

    @Test("off-main prepared application keeps valid UI state and clears removed-member state")
    func preparedCommitApplication() async throws {
        let fixture = try ReceiverKeyedStorageFixture()
        defer { fixture.remove() }
        let receiver = BridgeReceiver.standalone(UUIDv7.generate())
        let member = UUIDv7.generate()
        let topology = try receiverTopologySnapshot(
            for: receiver, knownWorktreeRoots: [member: "/"])
        let location = try #require(BridgeDocumentLocation(canonicalPath: "/tmp/prepared-link.swift"))
        let document = BridgeOpenedDocument(
            location: location,
            provenance: .init(
                repoId: UUIDv7.generate(), worktreeId: member,
                relativePath: "prepared-link.swift"))
        let latest = BridgeNavigationRecord(
            openedDocuments: [document], committedMemberLinks: testCommittedMemberLinks([member]),
            filesFilter: .member(worktreeId: member), selectedFilesDocument: location,
            reviewSelection: .member(worktreeId: member), surface: .review)
        let committed = BridgeNavigationRecord(surface: .review)
        let datastore = WorkspaceSQLiteDatastoreFactory(
            coreDatabaseURL: fixture.root.appending(path: "core.sqlite"),
            localDatabaseURL: fixture.root.appending(path: "local.sqlite")
        ).makeDatastore()
        let prepared = await datastore.prepareBridgeCommittedLinkApplication(
            committedRecord: committed, latestUIRecord: latest,
            topologySnapshot: topology, removedWorktreeID: member, removedRoot: nil)
        #expect(prepared.record.committedMemberWorktreeIds.isEmpty)
        #expect(prepared.record.openedDocuments.isEmpty)
        #expect(prepared.record.selectedFilesDocument == nil)
        #expect(prepared.record.filesFilter == .allMembers)
        #expect(prepared.record.reviewSelection == .unselected)
        #expect(prepared.record.surface == .review)
        #expect(prepared.reviewReplacement == .review)
        #expect(prepared.memberRoots[member] == "/")
    }

    @Test("catalog removed root keeps a newer provenance-free document out")
    func catalogRootPreventsLooseFileResurrection() async throws {
        let fixture = try ReceiverKeyedStorageFixture()
        defer { fixture.remove() }
        let receiver = BridgeReceiver.standalone(UUIDv7.generate())
        let removedMember = UUIDv7.generate()
        let topology = try receiverTopologySnapshot(for: receiver)
        let location = try #require(BridgeDocumentLocation(canonicalPath: "/private/tmp/catalog-old/late.md"))
        let latest = BridgeNavigationRecord(
            openedDocuments: [.init(location: location, provenance: nil)],
            committedMemberLinks: testCommittedMemberLinks([removedMember]), selectedFilesDocument: location,
            reviewSelection: .member(worktreeId: removedMember), surface: .review)
        let committed = BridgeNavigationRecord(surface: .review)
        let datastore = WorkspaceSQLiteDatastoreFactory(
            coreDatabaseURL: fixture.root.appending(path: "core.sqlite"),
            localDatabaseURL: fixture.root.appending(path: "local.sqlite")
        ).makeDatastore()
        let prepared = await datastore.prepareBridgeCommittedLinkApplication(
            committedRecord: committed, latestUIRecord: latest,
            topologySnapshot: topology, removedWorktreeID: removedMember,
            removedRoot: "/tmp/catalog-old")
        #expect(prepared.record.openedDocuments.isEmpty)
        #expect(prepared.record.selectedFilesDocument == nil)
        #expect(prepared.record.committedMemberWorktreeIds.isEmpty)
        #expect(prepared.memberRoots[removedMember] == "/private/tmp/catalog-old")
    }

    @Test("unknown worktree and a moved owner are rejected from the effect snapshot")
    func topologySnapshotAdmission() throws {
        let fixture = try ReceiverKeyedStorageFixture()
        defer { fixture.remove() }
        let receiver = BridgeReceiver.standalone(UUIDv7.generate())
        let member = UUIDv7.generate()
        let unknown = try receiverTopologySnapshot(for: receiver)
        let (_, unknownResult) = try fixture.repository.commitBridgeMemberAddition(
            receiver: receiver, worktreeID: member, contributor: .person,
            generation: 1, addedAt: Date(timeIntervalSince1970: 1_700_000_000), topologySnapshot: unknown)
        #expect(unknownResult == .refusedUnknownWorktree)
        let known = try receiverTopologySnapshot(for: receiver, knownWorktreeRoots: [member: "/"])
        let otherReceiver = BridgeReceiver.standalone(UUIDv7.generate())
        let otherOwner = try receiverTopologySnapshot(for: otherReceiver, knownWorktreeRoots: [member: "/"])
        let movedOwner = BridgeReceiverTopologySnapshot(
            sourcePaneId: otherReceiver.paneId,
            paneStatesByID: otherOwner.paneStatesByID,
            companionEntriesBySourceID: [:],
            repositoryTopology: known.repositoryTopology)
        let (_, staleOwner) = try fixture.repository.commitBridgeMemberAddition(
            receiver: receiver, worktreeID: member, contributor: .person,
            generation: 2, addedAt: Date(timeIntervalSince1970: 1_700_000_000), topologySnapshot: movedOwner)
        #expect(staleOwner == .staleOwner)
        let missingReceiver = BridgeReceiverTopologySnapshot(
            sourcePaneId: UUIDv7.generate(), paneStatesByID: known.paneStatesByID,
            companionEntriesBySourceID: [:],
            repositoryTopology: known.repositoryTopology)
        let (_, staleReceiver) = try fixture.repository.commitBridgeMemberAddition(
            receiver: receiver, worktreeID: member, contributor: .person,
            generation: 3, addedAt: Date(timeIntervalSince1970: 1_700_000_000), topologySnapshot: missingReceiver)
        #expect(staleReceiver == .staleReceiver)
        #expect(try fixture.repository.readBridgeReceivers().records[receiver] == nil)

        let terminalReceiver = BridgeReceiver.terminal(UUIDv7.generate())
        let companionPaneID = UUIDv7.generate()
        let staleCompanion = BridgeReceiverTopologySnapshot(
            sourcePaneId: companionPaneID, paneStatesByID: [:],
            companionEntriesBySourceID: [
                terminalReceiver.paneId: ZoomCompanionMetadata(
                    owningTabId: UUIDv7.generate(), reviewWorktreeId: nil,
                    companionPaneId: companionPaneID, lastZoomVisibility: .visible)
            ],
            repositoryTopology: known.repositoryTopology)
        let (_, staleCompanionResult) = try fixture.repository.commitBridgeMemberAddition(
            receiver: terminalReceiver, worktreeID: member, contributor: .person,
            generation: 3, addedAt: Date(timeIntervalSince1970: 1_700_000_000), topologySnapshot: staleCompanion)
        #expect(staleCompanionResult == .staleReceiver)

        // A move after capture is a later event. The captured owner still
        // authorizes this commit at its defined linearization point.
        let (_, committed) = try fixture.repository.commitBridgeMemberAddition(
            receiver: receiver, worktreeID: member, contributor: .person,
            generation: 4, addedAt: Date(timeIntervalSince1970: 1_700_000_000), topologySnapshot: known)
        #expect(committed == .added(effect: .newItem))
    }

    @Test("terminal CWD protection is derived from the effect snapshot")
    func snapshotCurrentDirectoryProtection() throws {
        let fixture = try ReceiverKeyedStorageFixture()
        defer { fixture.remove() }
        let receiver = BridgeReceiver.terminal(UUIDv7.generate())
        let member = UUIDv7.generate()
        let topologySnapshot = try receiverTopologySnapshot(
            for: receiver, knownWorktreeRoots: [member: "/"], currentCWDWorktreeID: member)
        _ = try fixture.repository.commitBridgeMemberAddition(
            receiver: receiver, worktreeID: member, contributor: .person,
            generation: 1, addedAt: Date(timeIntervalSince1970: 1_700_000_000), topologySnapshot: topologySnapshot)
        let preview = try fixture.repository.previewBridgeMemberRemoval(
            receiver: receiver, worktreeID: member, contributor: .person,
            topologySnapshot: topologySnapshot)
        #expect(preview == .refusedProtectedCurrentDirectory)
        let (record, committed) = try fixture.repository.commitBridgeMemberRemoval(
            receiver: receiver, worktreeID: member, contributor: .person,
            generation: 2, topologySnapshot: topologySnapshot)
        #expect(committed == .refusedProtectedCurrentDirectory)
        #expect(record.committedMemberWorktreeIds == [member])
    }

    @Test("derived current CWD refuses removal even without a committed row")
    func uncommittedCurrentDirectoryIsProtected() throws {
        let fixture = try ReceiverKeyedStorageFixture()
        defer { fixture.remove() }
        let receiver = BridgeReceiver.terminal(UUIDv7.generate())
        let currentCWD = UUIDv7.generate()
        let topologySnapshot = try receiverTopologySnapshot(
            for: receiver, knownWorktreeRoots: [currentCWD: "/"],
            currentCWDWorktreeID: currentCWD)
        let preview = try fixture.repository.previewBridgeMemberRemoval(
            receiver: receiver, worktreeID: currentCWD, contributor: .person,
            topologySnapshot: topologySnapshot)
        #expect(preview == .refusedProtectedCurrentDirectory)
        let (_, committed) = try fixture.repository.commitBridgeMemberRemoval(
            receiver: receiver, worktreeID: currentCWD, contributor: .person,
            generation: 1, topologySnapshot: topologySnapshot)
        #expect(committed == .refusedProtectedCurrentDirectory)
        #expect(try fixture.repository.readBridgeReceivers().records[receiver] == nil)
    }

    @Test("transient Review selection from a failed old CWD commit cannot persist after the move")
    func transientOldCurrentDirectorySelectionIsRejected() throws {
        let fixture = try ReceiverKeyedStorageFixture()
        defer { fixture.remove() }
        let receiver = BridgeReceiver.terminal(UUIDv7.generate())
        let oldCurrentDirectory = UUIDv7.generate()
        let newCurrentDirectory = UUIDv7.generate()
        let transient = BridgeNavigationRecord(
            derivedCurrentCWDWorktreeId: newCurrentDirectory,
            reviewSelection: .member(worktreeId: oldCurrentDirectory), surface: .review)
        #expect(transient.committedMemberWorktreeIds.isEmpty)
        #expect(transient.effectiveMemberWorktreeIds == [newCurrentDirectory])

        #expect(throws: BridgeReceiverStorageError.missingMemberReference) {
            try fixture.repository.saveBridgeCurrentValues(
                [receiver: transient], retainedPaneIDs: [receiver.paneId],
                generation: 1, now: Date(timeIntervalSince1970: 1_700_000_000))
        }
        #expect(try fixture.repository.readBridgeReceivers().records[receiver] == nil)
    }

    @Test("separate contributor rows survive add and agent removal")
    func contributionRowsAreIndependent() async throws {
        let fixture = try ReceiverKeyedStorageFixture()
        defer { fixture.remove() }
        let receiver = BridgeReceiver.standalone(UUIDv7.generate())
        let member = UUIDv7.generate()
        let topologySnapshot = try receiverTopologySnapshot(
            for: receiver, knownWorktreeRoots: [member: "/"])
        let agentOne = BridgeLinkContributor.agent(
            .init(
                provider: try BridgeAgentProviderName("codex"), sessionRef: try BridgeAgentSessionRef("session:one")))
        let agentTwo = BridgeLinkContributor.agent(
            .init(
                provider: try BridgeAgentProviderName("codex"), sessionRef: try BridgeAgentSessionRef("session:two")))
        let repository = fixture.repository
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                _ = try repository.commitBridgeMemberAddition(
                    receiver: receiver, worktreeID: member,
                    contributor: agentOne, generation: 1, addedAt: Date(timeIntervalSince1970: 1_700_000_000),
                    topologySnapshot: topologySnapshot)
            }
            group.addTask {
                _ = try repository.commitBridgeMemberAddition(
                    receiver: receiver, worktreeID: member,
                    contributor: agentTwo, generation: 2, addedAt: Date(timeIntervalSince1970: 1_700_000_000),
                    topologySnapshot: topologySnapshot)
            }
            try await group.waitForAll()
        }
        let afterAdds = try #require(fixture.repository.readBridgeReceivers().records[receiver])
        #expect(afterAdds.committedMemberLinks.count == 1)
        #expect(Set(afterAdds.committedMemberLinks[0].contributions.map(\.addedBy)) == [agentOne, agentTwo])
        let (afterOneRemoval, outcome) = try fixture.repository.commitBridgeMemberRemoval(
            receiver: receiver, worktreeID: member, contributor: agentOne, generation: 3,
            topologySnapshot: topologySnapshot)
        guard case .removed(_, effect: nil, let removedContributions) = outcome else {
            Issue.record("first author removal changed effective membership")
            return
        }
        #expect(removedContributions == [agentOne])
        #expect(afterOneRemoval.committedMemberWorktreeIds == [member])
        #expect(afterOneRemoval.committedMemberLinks[0].contributions.map(\.addedBy) == [agentTwo])
        let (_, notAuthor) = try fixture.repository.commitBridgeMemberRemoval(
            receiver: receiver, worktreeID: member, contributor: agentOne, generation: 4,
            topologySnapshot: topologySnapshot)
        #expect(notAuthor == .refusedNotAuthor)
        let (afterPersonRemoval, personOutcome) = try fixture.repository.commitBridgeMemberRemoval(
            receiver: receiver, worktreeID: member, contributor: .person, generation: 5,
            topologySnapshot: topologySnapshot)
        guard case .removed = personOutcome else {
            Issue.record("person removal was refused")
            return
        }
        #expect(afterPersonRemoval.committedMemberWorktreeIds.isEmpty)
    }

    @Test("a deleted selection key rejects an older save while an independent key accepts it")
    func keyedGenerationsAndTombstones() throws {
        let fixture = try ReceiverKeyedStorageFixture()
        defer { fixture.remove() }
        let receiver = BridgeReceiver.standalone(UUIDv7.generate())
        let location = try #require(BridgeDocumentLocation(canonicalPath: "/tmp/receiver-keyed.md"))
        let document = BridgeOpenedDocument(location: location, provenance: nil)
        var seeded = BridgeNavigationRecord(openedDocuments: [document], selectedFilesDocument: location)
        _ = try fixture.repository.insertBridgeReceiversIfAbsent([receiver: seeded])
        var cleared = seeded
        cleared.selectedFilesDocument = nil
        try fixture.repository.saveBridgeCurrentValues(
            [receiver: cleared], retainedPaneIDs: [receiver.paneId], generation: 11,
            now: Date(timeIntervalSince1970: 1_700_000_000))
        seeded.filesFilter = .openedDocuments
        try fixture.repository.saveBridgeCurrentValues(
            [receiver: seeded], retainedPaneIDs: [receiver.paneId], generation: 10,
            now: Date(timeIntervalSince1970: 1_700_000_000))
        let restored = try #require(fixture.repository.readBridgeReceivers().records[receiver])
        #expect(restored.selectedFilesDocument == nil)
        #expect(restored.filesFilter == .openedDocuments)
        #expect(try fixture.isSelectionTombstone(receiver: receiver, generation: 11))
    }

    @Test("late membership commit clears newer dependent state and preserves unrelated UI state")
    func lateMembershipCommitReconcilesDependentState() throws {
        let fixture = try ReceiverKeyedStorageFixture()
        defer { fixture.remove() }
        let receiver = BridgeReceiver.standalone(UUIDv7.generate())
        let member = UUIDv7.generate()
        let topologySnapshot = try receiverTopologySnapshot(
            for: receiver, knownWorktreeRoots: [member: "/"])
        let location = try #require(BridgeDocumentLocation(canonicalPath: "/tmp/late-member.swift"))
        let document = BridgeOpenedDocument(
            location: location,
            provenance: .init(repoId: UUIDv7.generate(), worktreeId: member, relativePath: "late-member.swift"))
        let initial = BridgeNavigationRecord(
            openedDocuments: [document], committedMemberLinks: testCommittedMemberLinks([member]),
            filesFilter: .member(worktreeId: member), reviewSelection: .member(worktreeId: member),
            reviewComparisonsByWorktreeId: [member: .staged])
        _ = try fixture.repository.insertBridgeReceiversIfAbsent([receiver: initial])
        var newerUI = initial
        newerUI.selectedFilesDocument = location
        newerUI.surface = .review
        try fixture.repository.saveBridgeCurrentValues(
            [receiver: newerUI],
            retainedPaneIDs: [receiver.paneId], generation: 21, now: Date(timeIntervalSince1970: 1_700_000_000))
        let (committed, outcome) = try fixture.repository.commitBridgeMemberRemoval(
            receiver: receiver, worktreeID: member, contributor: .person, generation: 20,
            topologySnapshot: topologySnapshot)
        guard case .removed = outcome else {
            Issue.record("member removal did not commit")
            return
        }
        #expect(committed.committedMemberWorktreeIds.isEmpty)
        #expect(committed.selectedFilesDocument == nil)
        #expect(committed.filesFilter == .allMembers)
        #expect(committed.reviewSelection == .unselected)
        #expect(committed.reviewComparisonsByWorktreeId.isEmpty)
        #expect(committed.surface == .review)
        #expect(try fixture.isSelectionTombstone(receiver: receiver, generation: 22))
        #expect(try fixture.repository.latestBridgeGeneration() >= 22)
    }

    @Test("a stale new selection under a removed member fails the transaction reference check")
    func staleSelectionWithoutPriorKeyIsRejected() throws {
        let fixture = try ReceiverKeyedStorageFixture()
        defer { fixture.remove() }
        let receiver = BridgeReceiver.standalone(UUIDv7.generate())
        let member = UUIDv7.generate()
        let topologySnapshot = try receiverTopologySnapshot(
            for: receiver, knownWorktreeRoots: [member: "/"])
        let location = try #require(BridgeDocumentLocation(canonicalPath: "/tmp/removed-member.swift"))
        let document = BridgeOpenedDocument(
            location: location,
            provenance: .init(repoId: UUIDv7.generate(), worktreeId: member, relativePath: "removed-member.swift"))
        let initial = BridgeNavigationRecord(
            openedDocuments: [document], committedMemberLinks: testCommittedMemberLinks([member]))
        _ = try fixture.repository.insertBridgeReceiversIfAbsent([receiver: initial])
        _ = try fixture.repository.commitBridgeMemberRemoval(
            receiver: receiver, worktreeID: member,
            contributor: .person, generation: 11, topologySnapshot: topologySnapshot)
        var staleUI = initial
        staleUI.selectedFilesDocument = location
        #expect(throws: BridgeReceiverStorageError.missingMemberReference) {
            try fixture.repository.saveBridgeCurrentValues(
                [receiver: staleUI],
                retainedPaneIDs: [receiver.paneId], generation: 10, now: Date(timeIntervalSince1970: 1_700_000_000))
        }
        #expect(try fixture.repository.readBridgeReceivers().records[receiver]?.selectedFilesDocument == nil)
    }

    @Test("catalog unregistration removes every author and its dependent receiver state")
    func catalogRemovalCommitsAllContributions() throws {
        let fixture = try ReceiverKeyedStorageFixture()
        defer { fixture.remove() }
        let receiver = BridgeReceiver.standalone(UUIDv7.generate())
        let member = UUIDv7.generate()
        let topologySnapshot = try receiverTopologySnapshot(
            for: receiver, knownWorktreeRoots: [member: "/"])
        let agent = BridgeLinkContributor.agent(
            .init(
                provider: try BridgeAgentProviderName("codex"),
                sessionRef: try BridgeAgentSessionRef("catalog-agent")))
        _ = try fixture.repository.commitBridgeMemberAddition(
            receiver: receiver,
            worktreeID: member, contributor: agent, generation: 1, addedAt: Date(timeIntervalSince1970: 1_700_000_000),
            topologySnapshot: topologySnapshot)
        _ = try fixture.repository.commitBridgeMemberAddition(
            receiver: receiver,
            worktreeID: member, contributor: .person, generation: 2,
            addedAt: Date(timeIntervalSince1970: 1_700_000_000),
            topologySnapshot: topologySnapshot)
        let preview = try fixture.repository.previewBridgeCatalogMemberRemoval(
            receiver: receiver,
            worktreeID: member, removedRoot: "/tmp/catalog-member", memberRootsByWorktreeID: [:])
        guard case .removed = preview else {
            Issue.record("catalog preview did not see effective member")
            return
        }
        let (committed, outcome, deletedContributors) = try fixture.repository.commitBridgeCatalogMemberRemoval(
            receiver: receiver, worktreeID: member, generation: 3,
            removedRoot: "/tmp/catalog-member", memberRootsByWorktreeID: [:])
        guard case .removed = outcome else {
            Issue.record("catalog removal did not commit")
            return
        }
        #expect(committed.committedMemberLinks.isEmpty)
        #expect(deletedContributors == [agent, .person])
        #expect(try fixture.repository.readBridgeReceivers().records[receiver]?.committedMemberLinks.isEmpty == true)

        let appReceiver = BridgeReceiver.standalone(UUIDv7.generate())
        let appTopology = try receiverTopologySnapshot(
            for: appReceiver, knownWorktreeRoots: [member: "/"])
        _ = try fixture.repository.commitBridgeMemberAddition(
            receiver: appReceiver, worktreeID: member, contributor: .app,
            generation: 4, addedAt: Date(timeIntervalSince1970: 1_700_000_000), topologySnapshot: appTopology)
        let (_, appOutcome, appDeletedContributors) = try fixture.repository.commitBridgeCatalogMemberRemoval(
            receiver: appReceiver, worktreeID: member, generation: 5,
            removedRoot: "/tmp/catalog-member", memberRootsByWorktreeID: [:])
        guard case .removed = appOutcome else {
            Issue.record("app-only catalog removal did not commit")
            return
        }
        #expect(appDeletedContributors == [.app])
    }

    @Test("committed membership restores after reopen without an atom publication")
    func committedMembershipRestoresAfterReopen() throws {
        let fixture = try ReceiverKeyedStorageFixture()
        defer { fixture.remove() }
        let receiver = BridgeReceiver.standalone(UUIDv7.generate())
        let member = UUIDv7.generate()
        let topologySnapshot = try receiverTopologySnapshot(
            for: receiver, knownWorktreeRoots: [member: "/"])
        _ = try fixture.repository.commitBridgeMemberAddition(
            receiver: receiver, worktreeID: member, contributor: .person,
            generation: 10, addedAt: Date(timeIntervalSince1970: 1_700_000_000), topologySnapshot: topologySnapshot)
        try fixture.withReopenedRepository { reopened in
            let restored = try reopened.readBridgeReceivers().records[receiver]
            let generationFloor = try reopened.latestBridgeGeneration()
            #expect(restored?.committedMemberWorktreeIds == [member])
            #expect(generationFloor == 10)
        }
    }

    @Test("a malformed kind-column row defaults only its receiver on SQLite read")
    func malformedStoredRowIsRejected() throws {
        let fixture = try ReceiverKeyedStorageFixture()
        defer { fixture.remove() }
        let malformed = BridgeReceiver.standalone(UUIDv7.generate())
        let healthy = BridgeReceiver.standalone(UUIDv7.generate())
        _ = try fixture.repository.insertBridgeReceiversIfAbsent([malformed: .empty, healthy: .empty])
        try fixture.pool.write { database in
            try database.execute(
                sql: """
                    UPDATE bridge_receiver_state SET worktree_id = ?
                    WHERE workspace_id = ? AND receiver_pane_id = ? AND kind = 'surface'
                    """,
                arguments: [
                    UUIDv7.generate().uuidString, fixture.repository.workspaceId.uuidString,
                    malformed.paneId.uuidString,
                ])
        }
        let readback = try fixture.repository.readBridgeReceivers()
        #expect(readback.records[malformed] == nil)
        #expect(readback.presentPaneIDs.contains(malformed.paneId))
        #expect(readback.records[healthy] == .empty)
    }

    @Test("an ordinary keyed save does not delete and reinsert another receiver")
    func ordinarySaveIsKeyed() throws {
        let fixture = try ReceiverKeyedStorageFixture()
        defer { fixture.remove() }
        let edited = BridgeReceiver.standalone(UUIDv7.generate())
        let untouched = BridgeReceiver.standalone(UUIDv7.generate())
        _ = try fixture.repository.insertBridgeReceiversIfAbsent([edited: .empty, untouched: .empty])
        try fixture.pool.write { database in
            try database.execute(
                sql: """
                    CREATE TRIGGER forbid_receiver_delete BEFORE DELETE ON bridge_receiver_state
                    BEGIN SELECT RAISE(ABORT, 'receiver state deletion is not an ordinary save'); END
                    """)
        }
        let changed = BridgeNavigationRecord(surface: .review)
        try fixture.repository.saveBridgeCurrentValues(
            [edited: changed, untouched: .empty],
            retainedPaneIDs: [edited.paneId, untouched.paneId], generation: 1,
            now: Date(timeIntervalSince1970: 1_700_000_000))
        let readback = try fixture.repository.readBridgeReceivers().records
        #expect(readback[edited]?.surface == .review)
        #expect(readback[untouched] == .empty)
    }

    @Test("retirement rejects late writes and a controlled clock purges at the deadline")
    func retirementDeadline() throws {
        let fixture = try ReceiverKeyedStorageFixture()
        defer { fixture.remove() }
        let receiver = BridgeReceiver.standalone(UUIDv7.generate())
        _ = try fixture.repository.insertBridgeReceiversIfAbsent([receiver: .empty])
        let clock = TestPushClock()
        let time = BridgeReceiverRetirementTime(clock: clock, anchorDate: Date(timeIntervalSince1970: 1000))
        try fixture.repository.retireBridgeReceiver(receiver, time: time)
        #expect(throws: BridgeReceiverStorageError.retiredReceiver) {
            try fixture.repository.commitBridgeMemberAddition(
                receiver: receiver, worktreeID: UUIDv7.generate(),
                contributor: .person, generation: 1, addedAt: time.now,
                topologySnapshot: try receiverTopologySnapshot(for: receiver))
        }
        clock.advance(by: .seconds(86_399))
        try fixture.repository.purgeRetiredBridgeReceivers(time: time)
        #expect(try fixture.rowCount(for: receiver) > 0)
        clock.advance(by: .seconds(1))
        try fixture.repository.purgeRetiredBridgeReceivers(time: time)
        #expect(try fixture.rowCount(for: receiver) == 0)
    }

    @Test("opened-document line updates in place, survives UI save and restart, then closes")
    func openedDocumentLineLifecycle() throws {
        let fixture = try ReceiverKeyedStorageFixture()
        defer { fixture.remove() }
        let receiver = BridgeReceiver.standalone(UUIDv7.generate())
        let location = try #require(
            BridgeDocumentLocation(
                canonicalPath: fixture.root.appendingPathComponent("notes.swift").path))
        var record = BridgeNavigationRecord(openedDocuments: [
            .init(location: location, provenance: nil, openedLine: 4)
        ])
        try fixture.repository.saveBridgeCurrentValues(
            [receiver: record], retainedPaneIDs: [receiver.paneId], generation: 10,
            now: Date(timeIntervalSince1970: 100))

        record = BridgeNavigationRules.openingInBackground(
            .init(location: location, provenance: nil, openedLine: 8), in: record)
        record.surface = .review
        try fixture.repository.saveBridgeCurrentValues(
            [receiver: record], retainedPaneIDs: [receiver.paneId], generation: 11,
            now: Date(timeIntervalSince1970: 101))
        #expect(record.openedDocuments.count == 1)
        #expect(record.openedDocuments.first?.openedLine == 8)
        #expect(try fixture.repository.readBridgeReceivers().records[receiver]?.openedDocuments.first?.openedLine == 8)
        try fixture.withReopenedRepository { reopened in
            let restored = try reopened.readBridgeReceivers().records[receiver]
            #expect(restored?.openedDocuments.first?.openedLine == 8)
            #expect(restored?.surface == .review)
        }

        try fixture.repository.saveBridgeCurrentValues(
            [receiver: .empty], retainedPaneIDs: [receiver.paneId], generation: 12,
            now: Date(timeIntervalSince1970: 102))
        #expect(try fixture.repository.readBridgeReceivers().records[receiver]?.openedDocuments.isEmpty == true)
        try fixture.withReopenedRepository { reopened in
            let restored = try reopened.readBridgeReceivers().records[receiver]
            #expect(restored?.openedDocuments.isEmpty == true)
        }
    }

    @Test("malformed opened line rejects only its receiver")
    func malformedOpenedLine() throws {
        let fixture = try ReceiverKeyedStorageFixture()
        defer { fixture.remove() }
        let receiver = BridgeReceiver.standalone(UUIDv7.generate())
        let healthy = BridgeReceiver.standalone(UUIDv7.generate())
        let location = try #require(
            BridgeDocumentLocation(
                canonicalPath: fixture.root.appendingPathComponent("valid.swift").path))
        let records: [BridgeReceiver: BridgeNavigationRecord] = [
            receiver: .init(openedDocuments: [.init(location: location, provenance: nil, openedLine: 4)]),
            healthy: .empty,
        ]
        try fixture.repository.saveBridgeCurrentValues(
            records, retainedPaneIDs: [receiver.paneId, healthy.paneId], generation: 10,
            now: Date(timeIntervalSince1970: 100))
        try fixture.pool.write { database in
            try database.execute(sql: "PRAGMA ignore_check_constraints = ON")
            try database.execute(
                sql: """
                    UPDATE bridge_receiver_state SET opened_line = 0
                    WHERE workspace_id = ? AND receiver_pane_id = ? AND kind = 'openedDocument'
                    """, arguments: [fixture.repository.workspaceId.uuidString, receiver.paneId.uuidString])
            try database.execute(sql: "PRAGMA ignore_check_constraints = OFF")
        }
        let readback = try fixture.repository.readBridgeReceivers()
        #expect(readback.records[receiver] == nil)
        #expect(readback.presentPaneIDs.contains(receiver.paneId))
        #expect(readback.records[healthy] == .empty)
    }

}

private struct ReceiverKeyedStorageFixture {
    let root: URL
    let pool: DatabasePool
    let repository: WorkspaceLocalRepository

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(
            path: "bridge-receiver-keyed-\(UUIDv7.generate().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        pool = try SQLiteDatabaseFactory.makeFileBackedPool(
            at: root.appending(path: "local.sqlite"), label: "AgentStudio.sqlite.bridge-receiver-keyed")
        repository = WorkspaceLocalRepository(workspaceId: UUIDv7.generate(), databaseWriter: pool)
        try repository.migrateBootRequired()
    }

    func remove() {
        try? pool.close()
        try? FileManager.default.removeItem(at: root)
    }

    func withReopenedRepository<Output>(
        _ body: (WorkspaceLocalRepository) throws -> Output
    ) throws -> Output {
        let reopenedPool = try SQLiteDatabaseFactory.makeFileBackedPool(
            at: root.appending(path: "local.sqlite"), label: "AgentStudio.sqlite.bridge-receiver-reopen")
        defer { try? reopenedPool.close() }
        return try body(
            WorkspaceLocalRepository(
                workspaceId: repository.workspaceId,
                databaseWriter: reopenedPool))
    }

    func isSelectionTombstone(receiver: BridgeReceiver, generation: Int) throws -> Bool {
        try pool.read { database in
            try Int.fetchOne(
                database,
                sql: """
                    SELECT 1 FROM bridge_receiver_state WHERE workspace_id = ? AND receiver_pane_id = ?
                    AND kind = 'selectedFilesDocument' AND item_key = 'singleton'
                    AND generation = ? AND is_deleted = 1
                    """, arguments: [repository.workspaceId.uuidString, receiver.paneId.uuidString, generation]) != nil
        }
    }

    func rowCount(for receiver: BridgeReceiver) throws -> Int {
        try pool.read { database in
            try Int.fetchOne(
                database,
                sql: """
                    SELECT (SELECT COUNT(*) FROM bridge_receiver_state WHERE workspace_id = ? AND receiver_pane_id = ?)
                    + (SELECT COUNT(*) FROM bridge_receiver_item WHERE workspace_id = ? AND receiver_pane_id = ?)
                    + (SELECT COUNT(*) FROM bridge_receiver_retirement WHERE workspace_id = ? AND receiver_pane_id = ?)
                    """,
                arguments: [
                    repository.workspaceId.uuidString, receiver.paneId.uuidString,
                    repository.workspaceId.uuidString, receiver.paneId.uuidString,
                    repository.workspaceId.uuidString, receiver.paneId.uuidString,
                ]) ?? 0
        }
    }

}

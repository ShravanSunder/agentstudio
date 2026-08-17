import AgentStudioCore
import AgentStudioInfrastructure
import Foundation
import GRDB
import Testing

@testable import AgentStudioBridge

@MainActor
@Suite("Worktree annotation Store")
struct WorktreeAnnotationStoreTests {
    @Test("located root admission publishes its exact inline placement immediately")
    func locatedRootAdmissionPublishesExactPlacement() async throws {
        let repository = try makeAnnotationRepository()
        let projection = WorktreeAnnotationProjectionAtom()
        let store = WorktreeAnnotationStore(
            projection: projection,
            repositoryAccess: RepositoryBackedWorktreeAnnotationAccess(repository: repository)
        )

        let detail = try await store.createRootDraft(
            makeLocatedRootDraftProps(),
            ownerGeneration: "worker-a",
            placementContext: .init(contextID: "pane-a", surface: .file)
        )
        let thread = try #require(detail.threads.first?.thread)
        let placement = try #require(
            projection.placement(
                contextID: "pane-a",
                surface: .file,
                sessionID: detail.session.id,
                threadID: thread.id
            )
        )

        #expect(placement.placement == .exact)
        #expect(placement.currentPath == "Sources/Feature.swift")
        #expect(placement.currentStartLine == 2)
        #expect(placement.currentEndLine == 2)
        #expect(placement.currentSourceIdentity == "source-original")
    }

    @Test("Store binds edit ownership to product generation and disconnect enables fenced reclaim")
    func productGenerationEditOwnershipAndReclaim() async throws {
        let repository = try makeAnnotationRepository()
        let store = WorktreeAnnotationStore(
            projection: WorktreeAnnotationProjectionAtom(),
            repositoryAccess: RepositoryBackedWorktreeAnnotationAccess(repository: repository)
        )
        var detail = try await store.createRootDraft(
            makeCreateRootDraftProps(),
            ownerGeneration: "worker-a"
        )
        let message = try #require(detail.threads.first?.messages.first)
        let originalDraft = try #require(message.draft)
        let acquireProps = WorktreeAnnotationEditTokenCommandProps(
            sessionID: detail.session.id,
            messageID: message.id,
            editToken: "editor-reclaimed",
            expectedSessionRevision: detail.session.semanticRevision,
            expectedDraftRevision: originalDraft.draftRevision,
            now: Date(timeIntervalSince1970: 3)
        )

        await #expect(throws: WorktreeAnnotationRepositoryError.editTokenConflict) {
            try await store.acquireEditToken(acquireProps, ownerGeneration: "worker-b")
        }

        store.invalidateEditOwnerGeneration("worker-a")
        detail = try await store.acquireEditToken(acquireProps, ownerGeneration: "worker-b")
        let reclaimedDraft = try #require(detail.threads.first?.messages.first?.draft)
        #expect(reclaimedDraft.body == originalDraft.body)
        #expect(reclaimedDraft.draftRevision == originalDraft.draftRevision + 1)

        await #expect(throws: WorktreeAnnotationRepositoryError.editTokenConflict) {
            try await store.flushDraft(
                .init(
                    sessionID: detail.session.id,
                    messageID: message.id,
                    editToken: "editor-1",
                    expectedSessionRevision: detail.session.semanticRevision,
                    expectedDraftRevision: originalDraft.draftRevision,
                    body: "delayed old writer",
                    now: Date(timeIntervalSince1970: 4)
                ),
                ownerGeneration: "worker-a"
            )
        }

        detail = try await store.releaseEditToken(
            .init(
                sessionID: detail.session.id,
                messageID: message.id,
                editToken: "editor-reclaimed",
                expectedSessionRevision: detail.session.semanticRevision,
                expectedDraftRevision: reclaimedDraft.draftRevision,
                now: Date(timeIntervalSince1970: 5)
            ),
            ownerGeneration: "worker-b"
        )
        #expect(detail.threads.first?.messages.first?.draft?.activeEditToken == nil)
    }

    @Test("committed repository detail publishes only after mutation returns")
    func committedDetailPublishesAfterMutationReturns() async throws {
        let access = ControllableWorktreeAnnotationAccess()
        let projection = WorktreeAnnotationProjectionAtom()
        let store = WorktreeAnnotationStore(projection: projection, repositoryAccess: access)
        let props = makeCreateRootDraftProps()

        let mutation = Task { try await store.createRootDraft(props) }
        await access.waitForCreateRootDraft()

        #expect(projection.detail(sessionID: nil) == nil)

        let committedDetail = try makeCommittedDetail()
        await access.completeCreateRootDraft(with: .success(committedDetail))
        let returnedDetail = try await mutation.value

        #expect(returnedDetail == committedDetail)
        #expect(projection.detail(sessionID: committedDetail.session.id)?.session == committedDetail.session)
    }

    @Test("failed repository mutation leaves projection unchanged")
    func failedMutationLeavesProjectionUnchanged() async throws {
        let existingDetail = try makeCommittedDetail()
        let access = ControllableWorktreeAnnotationAccess()
        let projection = WorktreeAnnotationProjectionAtom()
        projection.publish(detail: existingDetail)
        let store = WorktreeAnnotationStore(projection: projection, repositoryAccess: access)

        let mutation = Task { try await store.createRootDraft(makeCreateRootDraftProps()) }
        await access.waitForCreateRootDraft()
        await access.completeCreateRootDraft(with: .failure(TestAnnotationAccessError.writeFailed))

        await #expect(throws: TestAnnotationAccessError.writeFailed) {
            try await mutation.value
        }
        #expect(projection.detail(sessionID: existingDetail.session.id)?.session == existingDetail.session)
    }

    @Test("multiple demands share one detail load and zero demand evicts without persistence")
    func demandReferenceCountingEvictsWithoutPersistence() async throws {
        let detail = try makeCommittedDetail()
        let access = ImmediateWorktreeAnnotationAccess(detail: detail)
        let projection = WorktreeAnnotationProjectionAtom()
        let store = WorktreeAnnotationStore(projection: projection, repositoryAccess: access)

        _ = try await store.acquireDemand(
            worktreeID: "worktree-1",
            contextID: "pane-b",
            surface: .file,
            sessionID: detail.session.id
        )
        _ = try await store.acquireDemand(
            worktreeID: "worktree-1",
            contextID: "pane-a",
            surface: .file,
            sessionID: detail.session.id
        )

        #expect(await access.detailLoadCount == 1)
        #expect(projection.detail(sessionID: detail.session.id) != nil)

        store.releaseDemand(
            worktreeID: "worktree-1",
            contextID: "pane-b",
            surface: .file,
            sessionID: detail.session.id
        )
        #expect(projection.detail(sessionID: detail.session.id) != nil)
        store.releaseDemand(
            worktreeID: "worktree-1",
            contextID: "pane-a",
            surface: .file,
            sessionID: detail.session.id
        )

        #expect(projection.detail(sessionID: detail.session.id) == nil)
        #expect(await access.mutationCount == 0)

        _ = try await store.acquireDemand(
            worktreeID: "worktree-1",
            contextID: "pane-a",
            surface: .file,
            sessionID: detail.session.id
        )
        #expect(await access.detailLoadCount == 2)
    }

    @Test("unacknowledged recovery witness blocks mutation until durable acknowledgement")
    func recoveryWitnessBlocksMutationUntilAcknowledgement() async throws {
        let witness = WorktreeAnnotationRecoveryProvenance(
            id: .generate(),
            recoveredAt: Date(timeIntervalSince1970: 10),
            quarantinedFilenames: ["local.sqlite.corrupt-1"],
            reason: "corrupt_database",
            acknowledgedAt: nil
        )
        let access = ImmediateWorktreeAnnotationAccess(detail: try makeCommittedDetail(), witness: witness)
        let projection = WorktreeAnnotationProjectionAtom()
        let store = WorktreeAnnotationStore(projection: projection, repositoryAccess: access)

        await store.restoreRecoveryState()

        #expect(projection.recoveryState == .recoveredDegraded(witness))
        await #expect(throws: WorktreeAnnotationStoreError.recoveryAcknowledgementRequired) {
            try await store.createRootDraft(makeCreateRootDraftProps())
        }

        try await store.acknowledgeRecovery(at: Date(timeIntervalSince1970: 11))
        #expect(projection.recoveryState == .available)
        _ = try await store.createRootDraft(makeCreateRootDraftProps())
        #expect(await access.mutationCount == 1)
    }

    @Test("local quarantine writes a durable annotation witness before availability")
    func localQuarantineWritesWitnessBeforeAvailability() async throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "annotation-recovery-witness-\(UUIDv7.generate().uuidString)"
        )
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let coreURL = root.appending(path: "core.sqlite")
        let localURL = root.appending(path: "local.sqlite")
        try Data("not sqlite".utf8).write(to: localURL)
        let datastore = WorkspaceSQLiteDatastoreFactory(
            coreDatabaseURL: coreURL,
            localDatabaseURL: localURL,
            localDatabaseReplacementObserver: WorktreeAnnotationRecoveryWitnessWriter.write
        ).makeDatastore()

        guard case .prepared = await datastore.prepareDatabasesForBoot() else {
            Issue.record("Expected replacement database to become available")
            return
        }
        let adapter = WorktreeAnnotationSQLiteDatastoreAdapter(
            workspaceID: UUIDv7.generate(),
            datastore: datastore
        )
        let witness = try #require(try await adapter.fetchUnacknowledgedRecoveryProvenance())

        #expect(witness.reason == "corrupt_database")
        #expect(witness.quarantinedFilenames.count == 1)
        #expect(witness.quarantinedFilenames[0].contains("local.sqlite.corrupt-"))
        #expect(FileManager.default.fileExists(atPath: root.appending(path: witness.quarantinedFilenames[0]).path))
    }

    @Test("failed recovery witness callback keeps replacement local database unavailable")
    func failedRecoveryWitnessCallbackKeepsLocalDatabaseUnavailable() async throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "annotation-recovery-callback-failure-\(UUIDv7.generate().uuidString)"
        )
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let localURL = root.appending(path: "local.sqlite")
        try Data("not sqlite".utf8).write(to: localURL)
        let datastore = WorkspaceSQLiteDatastoreFactory(
            coreDatabaseURL: root.appending(path: "core.sqlite"),
            localDatabaseURL: localURL,
            localDatabaseReplacementObserver: { _, _ in
                throw TestAnnotationAccessError.writeFailed
            }
        ).makeDatastore()

        guard case .prepared = await datastore.prepareDatabasesForBoot() else {
            Issue.record("Core preparation should remain available after local callback failure")
            return
        }
        let adapter = WorktreeAnnotationSQLiteDatastoreAdapter(
            workspaceID: UUIDv7.generate(),
            datastore: datastore
        )
        do {
            _ = try await adapter.fetchUnacknowledgedRecoveryProvenance()
            Issue.record("Replacement local repository must not publish after witness callback failure")
        } catch let failure as WorkspaceSQLiteDatastoreFailure {
            #expect(failure.description.contains("writeFailed"))
        }
    }

    @Test("real local SQLite restart restores demanded draft without Atom state")
    func localSQLiteRestartRestoresDraftWithoutAtomState() async throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "annotation-restart-\(UUIDv7.generate().uuidString)"
        )
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let coreURL = root.appending(path: "core.sqlite")
        let localURL = root.appending(path: "local.sqlite")
        let workspaceID = UUIDv7.generate()

        let firstDatastore = WorkspaceSQLiteDatastoreFactory(
            coreDatabaseURL: coreURL,
            localDatabaseURL: localURL
        ).makeDatastore()
        guard case .prepared = await firstDatastore.prepareDatabasesForBoot() else {
            Issue.record("Expected first datastore preparation")
            return
        }
        let workspaceStore = WorkspaceStore(
            identityAtom: WorkspaceIdentityAtom(workspaceId: workspaceID),
            sqliteDatastore: firstDatastore,
            startsObserving: false
        )
        guard case .initializedDefaultWorkspace = await workspaceStore.loadCanonicalComposition() else {
            Issue.record("Expected first datastore to persist its default workspace")
            return
        }
        let firstProjection = WorktreeAnnotationProjectionAtom()
        let firstStore = WorktreeAnnotationStore(
            projection: firstProjection,
            sqliteAdapter: .init(workspaceID: workspaceID, datastore: firstDatastore)
        )
        let committed = try await firstStore.createRootDraft(makeCreateRootDraftProps())

        let restartedDatastore = WorkspaceSQLiteDatastoreFactory(
            coreDatabaseURL: coreURL,
            localDatabaseURL: localURL
        ).makeDatastore()
        let restartedPreparation = await restartedDatastore.prepareDatabasesForBoot()
        guard case .prepared = restartedPreparation else {
            Issue.record("Expected restarted datastore preparation, received \(restartedPreparation)")
            return
        }
        let restartedProjection = WorktreeAnnotationProjectionAtom()
        let restartedStore = WorktreeAnnotationStore(
            projection: restartedProjection,
            sqliteAdapter: .init(workspaceID: workspaceID, datastore: restartedDatastore)
        )

        #expect(restartedProjection.detail(sessionID: committed.session.id) == nil)
        _ = try await restartedStore.acquireDemand(
            worktreeID: committed.session.worktreeID,
            contextID: "pane-a",
            surface: .file,
            sessionID: committed.session.id
        )
        #expect(
            restartedProjection.detail(sessionID: committed.session.id)?
                .threads.first?.messages.first?.draft?.body == "Draft"
        )
    }

    @Test("semantic mutations commit before projection and output bytes stay repository-owned")
    func semanticMutationsCommitBeforeProjectionWithoutPublishingOutputBytes() async throws {
        let repository = try makeAnnotationRepository()
        let access = RepositoryBackedWorktreeAnnotationAccess(repository: repository)
        let projection = WorktreeAnnotationProjectionAtom()
        let store = WorktreeAnnotationStore(projection: projection, repositoryAccess: access)
        var detail = try await store.createRootDraft(makeLocatedRootDraftProps())
        let rootMessage = try #require(detail.threads.first?.messages.first)

        detail = try await store.flushDraft(
            .init(
                sessionID: detail.session.id,
                messageID: rootMessage.id,
                editToken: "editor-1",
                expectedSessionRevision: detail.session.semanticRevision,
                expectedDraftRevision: 0,
                body: "Updated draft",
                now: Date(timeIntervalSince1970: 3)
            )
        )
        let updatedRoot = try #require(detail.threads.first?.messages.first)
        detail = try await store.saveDraft(
            .init(
                sessionID: detail.session.id,
                messageID: updatedRoot.id,
                editToken: "editor-1",
                expectedSessionRevision: detail.session.semanticRevision,
                expectedDraftRevision: try #require(updatedRoot.draft?.draftRevision),
                now: Date(timeIntervalSince1970: 4)
            )
        )
        let savedRoot = try #require(detail.threads.first?.messages.first)
        let savedRevision = try #require(savedRoot.savedRevision)
        let attemptID = WorktreeAnnotationOutputAttemptID.generate()
        let snapshot = try WorktreeAnnotationBatchProjector.makeSnapshot(
            .init(
                batchID: attemptID,
                createdAt: Date(timeIntervalSince1970: 5),
                sessionDetail: detail,
                selectedMessages: [.init(messageID: savedRoot.id, expectedSavedRevision: savedRevision)],
                placementsByThreadID: [:],
                sessionLabel: "Current review",
                worktreeLabel: "agent-studio.review-comments",
                comparisonLabel: nil
            )
        )
        let markdownPresentation = WorktreeAnnotationMarkdownPresentationContext(
            worktreeLabel: "agent-studio.review-comments",
            comparisonLabel: nil
        )
        let exactBytes = WorktreeAnnotationBatchProjector.markdownData(
            for: snapshot,
            presentation: markdownPresentation
        )

        let prepared = try await store.prepareOutput(
            .init(
                attemptID: attemptID,
                sessionID: detail.session.id,
                outputKind: .clipboardMarkdown,
                formatVersion: 1,
                contentType: "text/markdown; charset=utf-8",
                canonicalSnapshot: snapshot,
                exactBytes: exactBytes,
                markdownPresentation: markdownPresentation,
                destinationPath: nil,
                repeatedFromAttemptID: nil,
                selectedMessages: [.init(messageID: savedRoot.id, expectedSavedRevision: savedRevision)],
                now: Date(timeIntervalSince1970: 5)
            )
        )

        #expect(prepared.attempt.exactBytes == exactBytes)
        #expect(projection.detail(sessionID: detail.session.id)?.threads.first?.messages.first?.status == .editable)
        #expect(Mirror(reflecting: projection).children.allSatisfy { !($0.value is Data) })
    }

    @Test("detail hydration failure makes annotation projection unavailable")
    func detailHydrationFailurePublishesUnavailable() async throws {
        let projection = WorktreeAnnotationProjectionAtom()
        let store = WorktreeAnnotationStore(
            projection: projection,
            repositoryAccess: FailingHydrationWorktreeAnnotationAccess()
        )

        await #expect(throws: WorktreeAnnotationRepositoryError.invalidState) {
            try await store.acquireDemand(
                worktreeID: "worktree-1",
                contextID: "pane-a",
                surface: .file,
                sessionID: WorktreeAnnotationSessionID.generate()
            )
        }
        #expect(projection.recoveryState == .unavailable)
    }

    @Test("source placement is context scoped and stale epochs cannot overwrite current placement")
    func sourcePlacementIsContextScopedAndRejectsStaleEpochs() async throws {
        let repository = try makeAnnotationRepository()
        let store = WorktreeAnnotationStore(
            projection: WorktreeAnnotationProjectionAtom(),
            repositoryAccess: RepositoryBackedWorktreeAnnotationAccess(repository: repository)
        )
        let detail = try await store.createRootDraft(makeLocatedRootDraftProps())
        let threadID = try #require(detail.threads.first?.thread.id)
        let paneADemandGeneration = try await store.acquireDemand(
            worktreeID: detail.session.worktreeID,
            contextID: "pane-a",
            surface: .file,
            sessionID: detail.session.id
        )
        let paneARefreshSnapshot = try await store.sourceRefreshSnapshot(
            sessionID: detail.session.id
        )

        _ = try await store.refreshSource(
            .init(
                contextID: "pane-a",
                demandGeneration: paneADemandGeneration,
                sessionID: detail.session.id,
                surface: .file,
                sourceEpoch: 2,
                expectedSnapshot: paneARefreshSnapshot,
                currentFingerprint: makeSourceFingerprint(identity: "source-a"),
                material: storeSourceMaterial(
                    path: "Sources/Feature.swift",
                    sourceIdentity: "source-a"
                ),
                now: Date(timeIntervalSince1970: 3)
            )
        )
        let afterFirstRefresh = try repository.fetchSessionDetail(sessionID: detail.session.id)
        let paneBDemandGeneration = try await store.acquireDemand(
            worktreeID: detail.session.worktreeID,
            contextID: "pane-b",
            surface: .file,
            sessionID: detail.session.id
        )
        let paneBRefreshSnapshot = try await store.sourceRefreshSnapshot(
            sessionID: detail.session.id
        )
        _ = try await store.refreshSource(
            .init(
                contextID: "pane-b",
                demandGeneration: paneBDemandGeneration,
                sessionID: detail.session.id,
                surface: .file,
                sourceEpoch: 1,
                expectedSnapshot: paneBRefreshSnapshot,
                currentFingerprint: makeSourceFingerprint(identity: "source-b"),
                material: storeSourceMaterial(
                    path: "Sources/RenamedFeature.swift",
                    sourceIdentity: "source-b"
                ),
                now: Date(timeIntervalSince1970: 4)
            )
        )

        #expect(
            store.projection.placement(
                contextID: "pane-a",
                surface: .file,
                sessionID: detail.session.id,
                threadID: threadID
            )?.placement == .exact
        )
        #expect(
            store.projection.placement(
                contextID: "pane-b",
                surface: .file,
                sessionID: detail.session.id,
                threadID: threadID
            )?.placement == .relocated
        )
        await #expect(throws: WorktreeAnnotationStoreError.staleSourceEpoch) {
            let staleEpochSnapshot = try await store.sourceRefreshSnapshot(
                sessionID: detail.session.id
            )
            _ = try await store.refreshSource(
                .init(
                    contextID: "pane-a",
                    demandGeneration: paneADemandGeneration,
                    sessionID: detail.session.id,
                    surface: .file,
                    sourceEpoch: 1,
                    expectedSnapshot: staleEpochSnapshot,
                    currentFingerprint: afterFirstRefresh.session.acceptedSourceFingerprint,
                    material: .unavailable,
                    now: Date(timeIntervalSince1970: 5)
                )
            )
        }
        #expect(
            store.projection.placement(
                contextID: "pane-a",
                surface: .file,
                sessionID: detail.session.id,
                threadID: threadID
            )?.placement == .exact
        )
    }

    @Test("source refresh rejects material captured from stale durable origins")
    func sourceRefreshRejectsStaleDurableOriginSnapshot() async throws {
        // Arrange
        let repository = try makeAnnotationRepository()
        let projection = WorktreeAnnotationProjectionAtom()
        let store = WorktreeAnnotationStore(
            projection: projection,
            repositoryAccess: RepositoryBackedWorktreeAnnotationAccess(repository: repository)
        )
        let initialDetail = try await store.createRootDraft(makeLocatedRootDraftProps())
        let demandGeneration = try await store.acquireDemand(
            worktreeID: initialDetail.session.worktreeID,
            contextID: "pane-a",
            surface: .file,
            sessionID: initialDetail.session.id
        )
        let refreshSnapshot = try await store.sourceRefreshSnapshot(
            sessionID: initialDetail.session.id
        )
        let changedDetail = try await store.setSourceRelationship(
            .init(
                sessionID: initialDetail.session.id,
                relationship: .applicable,
                sourceFingerprint: makeSourceFingerprint(identity: "source-changed-during-capture"),
                expectedSessionRevision: initialDetail.session.semanticRevision,
                now: Date(timeIntervalSince1970: 3)
            )
        )

        // Act / Assert
        await #expect(throws: WorktreeAnnotationStoreError.staleSourceEpoch) {
            _ = try await store.refreshSource(
                .init(
                    contextID: "pane-a",
                    demandGeneration: demandGeneration,
                    sessionID: initialDetail.session.id,
                    surface: .file,
                    sourceEpoch: 1,
                    expectedSnapshot: refreshSnapshot,
                    currentFingerprint: makeSourceFingerprint(identity: "source-current"),
                    material: .available([
                        .init(
                            path: "Sources/Feature.swift",
                            sourceRole: .file,
                            sourceIdentity: "source-current",
                            body: "before\nselected line\nafter\n"
                        )
                    ]),
                    now: Date(timeIntervalSince1970: 4)
                )
            )
        }
        #expect(
            try repository.fetchSessionDetail(sessionID: initialDetail.session.id)
                .session.acceptedSourceFingerprint == changedDetail.session.acceptedSourceFingerprint
        )
        #expect(
            projection.placement(
                contextID: "pane-a",
                surface: .file,
                sessionID: initialDetail.session.id,
                threadID: try #require(initialDetail.threads.first?.thread.id)
            ) == nil
        )
    }

}

private func storeSourceMaterial(
    path: String,
    sourceIdentity: String
) -> WorktreeAnnotationSourceMaterial {
    .available([
        .init(
            path: path,
            sourceRole: .file,
            sourceIdentity: sourceIdentity,
            body: "before\nselected line\nafter\n"
        )
    ])
}

private enum TestAnnotationAccessError: Error {
    case writeFailed
    case unexpectedOperation
}

extension WorktreeAnnotationRepositoryAccess {
    func flushDraft(_ props: WorktreeAnnotationSQLiteRepository.FlushDraftProps) async throws
        -> WorktreeAnnotationSessionDetail
    {
        _ = props
        throw TestAnnotationAccessError.unexpectedOperation
    }

    func saveDraft(_ props: WorktreeAnnotationSQLiteRepository.SaveDraftProps) async throws
        -> WorktreeAnnotationSessionDetail
    {
        _ = props
        throw TestAnnotationAccessError.unexpectedOperation
    }

    func revertDraft(_ props: WorktreeAnnotationSQLiteRepository.RevertDraftProps) async throws
        -> WorktreeAnnotationSessionDetail
    {
        _ = props
        throw TestAnnotationAccessError.unexpectedOperation
    }

    func createReplyDraft(_ props: WorktreeAnnotationSQLiteRepository.CreateReplyDraftProps) async throws
        -> WorktreeAnnotationSessionDetail
    {
        _ = props
        throw TestAnnotationAccessError.unexpectedOperation
    }

    func setThreadResolution(_ props: WorktreeAnnotationSQLiteRepository.SetThreadResolutionProps)
        async throws
        -> WorktreeAnnotationSessionDetail
    {
        _ = props
        throw TestAnnotationAccessError.unexpectedOperation
    }

    func setSessionLifecycle(_ props: WorktreeAnnotationSQLiteRepository.SetSessionLifecycleProps)
        async throws
        -> WorktreeAnnotationSessionDetail
    {
        _ = props
        throw TestAnnotationAccessError.unexpectedOperation
    }

    func setSourceRelationship(_ props: WorktreeAnnotationSQLiteRepository.SetSourceRelationshipProps)
        async throws
        -> WorktreeAnnotationSessionDetail
    {
        _ = props
        throw TestAnnotationAccessError.unexpectedOperation
    }

    func prepareOutput(_ props: WorktreeAnnotationSQLiteRepository.PrepareOutputProps) async throws
        -> WorktreeAnnotationOutputMutationResult
    {
        _ = props
        throw TestAnnotationAccessError.unexpectedOperation
    }

    func inspectOutputAttempt(attemptID: WorktreeAnnotationOutputAttemptID) async throws
        -> WorktreeAnnotationSQLiteRepository.PreparedOutput
    {
        _ = attemptID
        throw TestAnnotationAccessError.unexpectedOperation
    }

    func cancelOutputAttempt(
        attemptID: WorktreeAnnotationOutputAttemptID,
        now: Date
    ) async throws -> WorktreeAnnotationOutputMutationResult {
        _ = (attemptID, now)
        throw TestAnnotationAccessError.unexpectedOperation
    }

    func finalizeOutputAttempt(
        attemptID: WorktreeAnnotationOutputAttemptID,
        eventKind: WorktreeAnnotationOutputEventKind,
        now: Date
    ) async throws -> WorktreeAnnotationOutputMutationResult {
        _ = (attemptID, eventKind, now)
        throw TestAnnotationAccessError.unexpectedOperation
    }

    func markPreparedOutputAttemptsUnknown(now: Date) async throws -> Int {
        _ = now
        throw TestAnnotationAccessError.unexpectedOperation
    }
}

private actor ControllableWorktreeAnnotationAccess: WorktreeAnnotationRepositoryAccess {
    private var createContinuation: CheckedContinuation<WorktreeAnnotationSessionDetail, any Error>?
    private var createStartedContinuation: CheckedContinuation<Void, Never>?
    private var didStartCreate = false

    func waitForCreateRootDraft() async {
        if didStartCreate { return }
        await withCheckedContinuation { createStartedContinuation = $0 }
    }

    func completeCreateRootDraft(with result: Result<WorktreeAnnotationSessionDetail, any Error>) {
        createContinuation?.resume(with: result)
        createContinuation = nil
    }

    func discoverSessions(worktreeID _: String) async throws -> [WorktreeAnnotationSession] { [] }

    func fetchSessionDetail(sessionID _: WorktreeAnnotationSessionID) async throws
        -> WorktreeAnnotationSessionDetail
    {
        throw WorktreeAnnotationRepositoryError.notFound
    }

    func createRootDraft(_ props: WorktreeAnnotationSQLiteRepository.CreateRootDraftProps) async throws
        -> WorktreeAnnotationSessionDetail
    {
        _ = props
        didStartCreate = true
        createStartedContinuation?.resume()
        createStartedContinuation = nil
        return try await withCheckedThrowingContinuation { createContinuation = $0 }
    }

    func fetchUnacknowledgedRecoveryProvenance() async throws -> WorktreeAnnotationRecoveryProvenance? { nil }

    func acknowledgeRecoveryProvenance(
        id _: WorktreeAnnotationRecoveryProvenanceID,
        acknowledgedAt _: Date
    ) async throws -> WorktreeAnnotationRecoveryProvenance {
        throw WorktreeAnnotationRepositoryError.notFound
    }
}

private actor ImmediateWorktreeAnnotationAccess: WorktreeAnnotationRepositoryAccess {
    let detail: WorktreeAnnotationSessionDetail
    let witness: WorktreeAnnotationRecoveryProvenance?
    private(set) var detailLoadCount = 0
    private(set) var mutationCount = 0

    init(detail: WorktreeAnnotationSessionDetail, witness: WorktreeAnnotationRecoveryProvenance? = nil) {
        self.detail = detail
        self.witness = witness
    }

    func discoverSessions(worktreeID _: String) async throws -> [WorktreeAnnotationSession] { [detail.session] }

    func fetchSessionDetail(sessionID _: WorktreeAnnotationSessionID) async throws
        -> WorktreeAnnotationSessionDetail
    {
        detailLoadCount += 1
        return detail
    }

    func createRootDraft(_ props: WorktreeAnnotationSQLiteRepository.CreateRootDraftProps) async throws
        -> WorktreeAnnotationSessionDetail
    {
        _ = props
        mutationCount += 1
        return detail
    }

    func fetchUnacknowledgedRecoveryProvenance() async throws -> WorktreeAnnotationRecoveryProvenance? {
        witness
    }

    func acknowledgeRecoveryProvenance(
        id: WorktreeAnnotationRecoveryProvenanceID,
        acknowledgedAt: Date
    ) async throws -> WorktreeAnnotationRecoveryProvenance {
        guard let witness, witness.id == id else { throw WorktreeAnnotationRepositoryError.notFound }
        return WorktreeAnnotationRecoveryProvenance(
            id: witness.id,
            recoveredAt: witness.recoveredAt,
            quarantinedFilenames: witness.quarantinedFilenames,
            reason: witness.reason,
            acknowledgedAt: acknowledgedAt
        )
    }
}

private actor FailingHydrationWorktreeAnnotationAccess: WorktreeAnnotationRepositoryAccess {
    func discoverSessions(worktreeID _: String) async throws -> [WorktreeAnnotationSession] { [] }

    func fetchSessionDetail(sessionID _: WorktreeAnnotationSessionID) async throws
        -> WorktreeAnnotationSessionDetail
    {
        throw WorktreeAnnotationRepositoryError.invalidState
    }

    func createRootDraft(_ props: WorktreeAnnotationSQLiteRepository.CreateRootDraftProps) async throws
        -> WorktreeAnnotationSessionDetail
    {
        _ = props
        throw WorktreeAnnotationRepositoryError.invalidState
    }

    func fetchUnacknowledgedRecoveryProvenance() async throws
        -> WorktreeAnnotationRecoveryProvenance?
    {
        nil
    }

    func acknowledgeRecoveryProvenance(
        id _: WorktreeAnnotationRecoveryProvenanceID,
        acknowledgedAt _: Date
    ) async throws -> WorktreeAnnotationRecoveryProvenance {
        throw WorktreeAnnotationRepositoryError.notFound
    }
}

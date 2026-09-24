import AgentStudioCore
import AgentStudioInfrastructure
import AgentStudioTestSupport
import Foundation
import Testing

@testable import AgentStudioBridge

@MainActor
@Suite("Worktree annotation Files collection subjects")
struct WorktreeAnnotationFileCollectionSubjectTests {
    @Test(
        "a second member's file and a loose document save under their own subjects and project together after restart")
    func secondMemberAndLooseDocumentAnnotationsPersistUnderTheirSubjects() async throws {
        // Arrange: a receiver collection of two Git members plus one document outside Git.
        let fixture = try await BridgeFileCollectionTestFixture()
        defer { fixture.remove() }
        let harness = try await makeMultiSubjectAnnotationHarness(fixture: fixture)

        // Act: comment on the second member and on the loose document, save both, then restart.
        let betaSessionID = try await createAndSaveRoot(
            adapter: harness.adapter,
            store: harness.firstStore,
            path: "beta/src/app.ts",
            sourceIdentity: try #require(harness.descriptorIDs["beta/src/app.ts"]),
            body: "Beta keeps its own worktree",
            productAdmission: fixture.productAdmission.context
        )
        let notesSessionID = try await createAndSaveRoot(
            adapter: harness.adapter,
            store: harness.firstStore,
            path: "Open Files/notes.md",
            sourceIdentity: try #require(harness.descriptorIDs["Open Files/notes.md"]),
            body: "Notes stay a local file",
            productAdmission: fixture.productAdmission.context
        )
        let restartedStore = try await openAnnotationStore(
            at: harness.databaseRoot,
            workspaceID: harness.workspaceID,
            initializingWorkspace: false
        )
        let scope = try await harness.collection.worktreeAnnotationScope()
        let projection = try await restartedStore.captureProjection(
            subjects: scope.subjects,
            demandedSessionIDs: [betaSessionID, notesSessionID]
        )

        // Assert: each session keeps its own subject and located origin through the restart.
        #expect(scope.key == "receiver-collection")
        #expect(scope.subjects.contains(harness.betaSubject))
        #expect(scope.subjects.contains(.localFile(fixture.notesLocation)))
        #expect(Set(projection.repositorySnapshot.sessions.map(\.id)) == [betaSessionID, notesSessionID])
        let detailsBySession = Dictionary(
            uniqueKeysWithValues: projection.repositorySnapshot.details.map { ($0.session.id, $0) }
        )
        let betaDetail = try #require(detailsBySession[betaSessionID])
        let notesDetail = try #require(detailsBySession[notesSessionID])
        #expect(betaDetail.session.subject == harness.betaSubject)
        #expect(notesDetail.session.subject == .localFile(fixture.notesLocation))
        #expect(locatedOrigin(of: betaDetail)?.repositoryRelativePath == "src/app.ts")
        #expect(locatedOrigin(of: notesDetail)?.repositoryRelativePath == "notes.md")
        #expect(locatedOrigin(of: notesDetail)?.selectedExcerpt == "# Notes outside Git")
        #expect(betaDetail.threads.first?.messages.first?.savedBody == "Beta keeps its own worktree")
        #expect(notesDetail.threads.first?.messages.first?.savedBody == "Notes stay a local file")

        // Assert: each subject is placed against its own current source; the
        // member reads its working tree through Git, the loose document its own file.
        _ = try await FilesystemTestGitRepo.runGit(at: fixture.baseURL.appending(path: "beta"), args: ["init"])
        var placements: [WorktreeAnnotationThreadID: WorktreeAnnotationThreadPlacementProjection] = [:]
        for detail in [betaDetail, notesDetail] {
            let refresh = try await harness.resolver.refresh(
                .file,
                nil,
                fixture.productAdmission.context,
                detail.session.subject,
                WorktreeAnnotationServiceActor.sourceRefreshSnapshot(from: detail).requirements
            )
            #expect(refresh.fingerprint.subject == detail.session.subject)
            let evaluation = try WorktreeAnnotationSourceEvaluator.evaluate(
                .init(
                    session: detail.session,
                    threads: detail.threads.map(\.thread),
                    surface: .file,
                    sourceEpoch: "1",
                    currentFingerprint: refresh.fingerprint,
                    material: refresh.material
                )
            )
            placements.merge(evaluation.placements) { _, replacement in replacement }
        }
        let threadIDs = [betaDetail, notesDetail].compactMap { $0.threads.first?.thread.id }
        #expect(threadIDs.map { placements[$0]?.placement } == [.exact, .exact])

        // Assert: one File projection carries both subject kinds under the collection key.
        let header = try projectionHeader(
            BridgeProductAnnotationProjectionCapture(
                scope: scope,
                recoveryStatus: .available,
                sessions: projection.repositorySnapshot.sessions,
                details: projection.repositorySnapshot.details,
                placementsByThreadID: placements,
                projectionRevision: projection.revision,
                sourceGeneration: 1
            )
        )
        #expect(header.scopeKey == "receiver-collection")
        #expect(
            Set(header.sessions.map(\.subject)) == [
                .git(worktreeId: fixture.beta.worktreeId.uuidString.lowercased()),
                .localFile(documentLocation: fixture.notesLocation.canonicalPath),
            ]
        )
    }

    @Test("a missing loose document keeps its annotation with unavailable placement")
    func missingLooseDocumentKeepsUnavailablePlacement() async throws {
        // Arrange
        let fixture = try await BridgeFileCollectionTestFixture()
        defer { fixture.remove() }
        let collection = fixture.makeCollection(members: [fixture.alpha], openedDocuments: [fixture.notesLocation])
        try await collection.open(
            subscription: fixture.snapshot(revision: 0, foregroundPaths: []),
            productAdmission: fixture.productAdmission.context,
            foregroundWorkAdmission: fixture.foregroundWorkAdmission
        ) { _ in }
        try FileManager.default.removeItem(at: fixture.notesLocation.fileURL)

        // Act
        let refresh = try await collection.currentWorktreeAnnotationRefresh(
            subject: .localFile(fixture.notesLocation),
            requirements: [],
            productAdmission: fixture.productAdmission.context
        )

        // Assert
        #expect(refresh.fingerprint.subject == .localFile(fixture.notesLocation))
        #expect(refresh.fingerprint.fileSourceIdentity == nil)
        #expect(refresh.material == .unavailable)
        await #expect(throws: WorktreeAnnotationSourceResolutionError.unavailable) {
            try await collection.currentWorktreeAnnotationRefresh(
                subject: .git(repositoryID: "outside", worktreeID: UUIDv7.generate().uuidString.lowercased()),
                requirements: [],
                productAdmission: fixture.productAdmission.context
            )
        }
    }

    @Test("a failed member file read retains its Git scope until membership removal")
    func failedMemberFileReadRetainsGitScopeUntilMembershipRemoval() async throws {
        // Arrange: both worktrees belong to the Files collection and the
        // foreground descriptors authorize reads of their source files.
        let fixture = try await BridgeFileCollectionTestFixture()
        defer { fixture.remove() }
        let collection = fixture.makeCollection(members: [fixture.alpha, fixture.beta], openedDocuments: [])
        let collector = ProductFileMetadataEventCollector()
        try await collection.open(
            subscription: fixture.snapshot(revision: 0, foregroundPaths: []),
            productAdmission: fixture.productAdmission.context,
            foregroundWorkAdmission: fixture.foregroundWorkAdmission
        ) { event in await collector.append(event) }
        try await collection.update(
            subscription: fixture.snapshot(revision: 1, foregroundPaths: ["alpha/src/app.ts", "beta/src/app.ts"]),
            productAdmission: fixture.productAdmission.context,
            foregroundWorkAdmission: fixture.foregroundWorkAdmission
        ) { event in await collector.append(event) }
        let descriptorIDs = issuedDescriptorIDs(in: await collector.events)
        let alphaSubject = try await memberSubject(fixture.alpha)
        let betaSubject = try await memberSubject(fixture.beta)
        #expect(try await collection.worktreeAnnotationScope().subjects == [alphaSubject, betaSubject])

        // Act: the issued descriptor no longer resolves to readable contents.
        try FileManager.default.removeItem(at: fixture.alphaRoot.appending(path: "src/app.ts"))
        var memberReadWasRejected = false
        do {
            _ = try await collection.captureWorktreeAnnotationSource(
                origin: .init(
                    path: "alpha/src/app.ts",
                    startLine: 1,
                    endLine: 1,
                    sourceRole: .file,
                    diffSide: nil,
                    sourceIdentity: try #require(descriptorIDs["alpha/src/app.ts"])
                ),
                productAdmission: fixture.productAdmission.context
            )
        } catch {
            memberReadWasRejected = true
        }
        let scopeAfterReadFailure = try await collection.worktreeAnnotationScope()

        // Assert: content availability does not change membership scope.
        #expect(memberReadWasRejected)
        #expect(scopeAfterReadFailure.subjects == [alphaSubject, betaSubject])

        // Assert: removing that member from the collection is what drops its subject.
        try await collection.applyMembership(members: [fixture.beta], openedDocuments: [])
        let scopeAfterRemoval = try await collection.worktreeAnnotationScope()
        #expect(scopeAfterRemoval.subjects == [betaSubject])
    }

    @Test("a worktree moved to another repository keeps its sessions in view while continuity detaches them")
    func movedWorktreeKeepsSessionsInViewButDetaches() async throws {
        // Arrange: a session recorded under the worktree's original repository.
        let databaseRoot = FileManager.default.temporaryDirectory.appending(
            path: "annotation-moved-worktree-\(UUIDv7.generate().uuidString)"
        )
        defer { try? FileManager.default.removeItem(at: databaseRoot) }
        let service = try await openAnnotationStore(
            at: databaseRoot,
            workspaceID: UUIDv7.generate(),
            initializingWorkspace: true
        )
        let detail = try await service.createRootDraft(makeLocatedRootDraftProps())
        let movedSubject = WorktreeAnnotationSubject.git(repositoryID: "repo-moved", worktreeID: "worktree-1")

        // Act
        let projection = try await service.captureProjection(
            subjects: [movedSubject],
            demandedSessionIDs: [detail.session.id]
        )
        // A demand for the session under the moved subject is admitted, not refused as foreign.
        _ = try await service.acquireDemand(
            subjects: [movedSubject],
            contextID: "pane-moved",
            surface: .file,
            sessionID: detail.session.id
        )
        let evaluation = try WorktreeAnnotationSourceEvaluator.evaluate(
            .init(
                session: detail.session,
                threads: detail.threads.map(\.thread),
                surface: .file,
                sourceEpoch: "1",
                currentFingerprint: .init(
                    subject: movedSubject,
                    fileSourceIdentity: "source-original",
                    reviewComparisonOrigin: nil
                ),
                material: .unavailable
            )
        )

        // Assert
        #expect(projection.repositorySnapshot.sessions.map(\.id) == [detail.session.id])
        #expect(evaluation.sourceRelationship == .detached)
    }

    @Test("a captured source outside the surface's current scope is refused")
    func capturedSourceOutsideScopeIsRefused() async throws {
        // Arrange: the surface shows one member; the capture names another.
        let harness = try await makeTransportAdapterHarness()
        let outsideSubject = WorktreeAnnotationSubject.git(repositoryID: "repository-1", worktreeID: "worktree-2")
        let resolver = WorktreeAnnotationSourceResolver(
            scope: { _ in .testScope(transportAdapterAnnotationSubject) },
            capture: { origin, _, _, _ in
                .init(
                    fingerprint: .init(
                        subject: outsideSubject, fileSourceIdentity: "file-source-2", reviewComparisonOrigin: nil),
                    origin: .located(
                        .init(
                            repositoryRelativePath: origin.path,
                            startLine: origin.startLine,
                            endLine: origin.endLine,
                            sourceRole: .file,
                            diffSide: nil,
                            sourceIdentity: origin.sourceIdentity,
                            selectedExcerpt: "outside",
                            contextBefore: nil,
                            contextAfter: nil
                        )
                    )
                )
            },
            currentFingerprint: { _, _, _, _ in throw WorktreeAnnotationSourceResolutionError.unavailable },
            refresh: { _, _, _, _, _ in throw WorktreeAnnotationSourceResolutionError.unavailable }
        )
        let adapter = WorktreeAnnotationTransportAdapter(
            store: harness.store, contextID: "pane-test", sourceResolver: resolver)

        // Act
        let outcome = await adapter.apply(
            try rootCreateCommand(path: "Sources/Other.swift", sourceIdentity: "file-source-2", editToken: "outside"),
            surface: .file,
            correlation: try makeAnnotationCorrelation(requestID: "outside-scope-root"),
            productAdmission: harness.productAdmission
        )

        // Assert
        #expect(outcome.status == .failed(.invalidSource))
        #expect(try await harness.store.discoverSessions(subjects: [outsideSubject]).isEmpty)
    }
}

private struct MultiSubjectAnnotationHarness {
    let collection: BridgeFileCollectionSource
    let descriptorIDs: [String: String]
    let databaseRoot: URL
    let workspaceID: UUID
    let firstStore: WorktreeAnnotationServiceActor
    let adapter: WorktreeAnnotationTransportAdapter
    let resolver: WorktreeAnnotationSourceResolver
    let betaSubject: WorktreeAnnotationSubject
}

@MainActor
private func makeMultiSubjectAnnotationHarness(
    fixture: BridgeFileCollectionTestFixture
) async throws -> MultiSubjectAnnotationHarness {
    let collection = fixture.makeCollection(
        members: [fixture.alpha, fixture.beta],
        openedDocuments: [fixture.notesLocation]
    )
    let collector = ProductFileMetadataEventCollector()
    try await collection.open(
        subscription: fixture.snapshot(revision: 0, foregroundPaths: []),
        productAdmission: fixture.productAdmission.context,
        foregroundWorkAdmission: fixture.foregroundWorkAdmission
    ) { event in await collector.append(event) }
    try await collection.update(
        subscription: fixture.snapshot(revision: 1, foregroundPaths: ["beta/src/app.ts", "Open Files/notes.md"]),
        productAdmission: fixture.productAdmission.context,
        foregroundWorkAdmission: fixture.foregroundWorkAdmission
    ) { event in await collector.append(event) }
    let resolver = WorktreeAnnotationSourceCapture.resolver(
        fileMetadataSource: collection,
        reviewScope: nil,
        reviewPublicationCoordinator: BridgeReviewPublicationCoordinator(),
        reviewContentLoaderCache: BridgeReviewContentLoaderCache(provider: BridgeUnavailableReviewSourceProvider())
    )
    let workspaceID = UUIDv7.generate()
    let databaseRoot = fixture.baseURL.appending(path: "annotation-database")
    let firstStore = try await openAnnotationStore(
        at: databaseRoot,
        workspaceID: workspaceID,
        initializingWorkspace: true
    )
    let adapter = WorktreeAnnotationTransportAdapter(
        store: firstStore,
        contextID: "pane-collection",
        sourceResolver: resolver
    )
    return MultiSubjectAnnotationHarness(
        collection: collection,
        descriptorIDs: issuedDescriptorIDs(in: await collector.events),
        databaseRoot: databaseRoot,
        workspaceID: workspaceID,
        firstStore: firstStore,
        adapter: adapter,
        resolver: resolver,
        betaSubject: try await memberSubject(fixture.beta)
    )
}

@MainActor
private func createAndSaveRoot(
    adapter: WorktreeAnnotationTransportAdapter,
    store: WorktreeAnnotationServiceActor,
    path: String,
    sourceIdentity: String,
    body: String,
    productAdmission: BridgeProductAdmissionContext
) async throws -> WorktreeAnnotationSessionID {
    let editToken = "editor-\(UUIDv7.generate().uuidString.lowercased())"
    let outcome = await adapter.apply(
        try rootCreateCommand(path: path, sourceIdentity: sourceIdentity, editToken: editToken, body: body),
        surface: .file,
        correlation: try makeAnnotationCorrelation(requestID: "root-\(editToken)"),
        productAdmission: productAdmission
    )
    #expect(outcome.status == .committed, "\(path)")
    let sessionID = WorktreeAnnotationSessionID(rawValue: try #require(outcome.sessionId))
    let detail = try await store.sourceRefreshSnapshot(sessionID: sessionID)
    let capture = try await store.captureProjection(
        subjects: [detail.acceptedSourceFingerprint.subject],
        demandedSessionIDs: [sessionID]
    )
    let message = try #require(capture.repositorySnapshot.details.first?.threads.first?.messages.first)
    _ = try await store.saveDraft(
        .init(
            sessionID: sessionID,
            messageID: message.id,
            editToken: editToken,
            expectedMessageRevision: message.semanticRevision,
            expectedDraftRevision: try #require(message.draft?.draftRevision),
            now: Date(timeIntervalSince1970: 200)
        )
    )
    return sessionID
}

private func rootCreateCommand(
    path: String,
    sourceIdentity: String,
    editToken: String,
    body: String = "Scope check"
) throws -> BridgeProductWorktreeAnnotationCommandRequest {
    let command: [String: Any] = [
        "operation": [
            "admission": ["kind": "implicitOrSingle"],
            "body": body,
            "editToken": editToken,
            "kind": "root.create",
            "origin": [
                "diffSide": NSNull(),
                "endLine": 1,
                "kind": "located",
                "path": path,
                "sourceIdentity": sourceIdentity,
                "sourceRole": "file",
                "startLine": 1,
            ],
        ]
    ]
    let data = try JSONSerialization.data(withJSONObject: command, options: [.sortedKeys])
    return try decodeAnnotationCommand(try #require(String(bytes: data, encoding: .utf8)))
}

/// Opens the annotation store over on-disk databases; a restart opens the same
/// files again under the same workspace.
@MainActor
private func openAnnotationStore(
    at root: URL,
    workspaceID: UUID,
    initializingWorkspace: Bool
) async throws -> WorktreeAnnotationServiceActor {
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let datastore = WorkspaceSQLiteDatastoreFactory(
        coreDatabaseURL: root.appending(path: "core.sqlite"),
        localDatabaseURL: root.appending(path: "local.sqlite")
    ).makeDatastore()
    guard case .prepared = await datastore.prepareDatabasesForBoot() else {
        throw WorktreeAnnotationServiceError.unavailable
    }
    if initializingWorkspace {
        let workspaceStore = WorkspaceStore(
            identityAtom: WorkspaceIdentityAtom(workspaceId: workspaceID),
            sqliteDatastore: datastore,
            startsObserving: false
        )
        guard case .initializedDefaultWorkspace = await workspaceStore.loadCanonicalComposition() else {
            throw WorktreeAnnotationServiceError.unavailable
        }
    }
    return WorktreeAnnotationServiceActor(
        sqliteAdapter: .init(workspaceID: workspaceID, datastore: datastore)
    )
}

private func memberSubject(_ member: BridgeFileCollectionMemberSource) async throws -> WorktreeAnnotationSubject {
    try #require(try await member.producer.worktreeAnnotationScope().subjects.first)
}

private func issuedDescriptorIDs(in events: [BridgeProductFileMetadataEvent]) -> [String: String] {
    var descriptorIDs: [String: String] = [:]
    for event in events {
        guard case .descriptorReady(let ready) = event,
            case .available(let descriptor) = ready.payload.availability
        else { continue }
        descriptorIDs[ready.payload.path] = descriptor.descriptorId
    }
    return descriptorIDs
}

private func locatedOrigin(of detail: WorktreeAnnotationSessionDetail) -> WorktreeAnnotationLocatedOrigin? {
    guard case .located(let origin) = detail.threads.first?.thread.origin else { return nil }
    return origin
}

private func projectionHeader(
    _ capture: BridgeProductAnnotationProjectionCapture
) throws -> BridgeProductAnnotationProjectionHeaderRecord {
    var cursor = try BridgeProductAnnotationProjectionRecordAnalysis(capture: capture).makePageCursor(pageOrdinal: 0)
    let batch = try #require(try cursor.nextEncodedBatch())
    let firstLine = try #require(batch.split(separator: 0x0A).first)
    guard
        case .header(let header) = try BridgeProductStrictJSON.decode(
            BridgeProductAnnotationProjectionRecord.self,
            from: Data(firstLine)
        )
    else {
        throw WorktreeAnnotationRepositoryError.invalidState
    }
    return header
}

import CryptoKit
import Foundation
import Testing

@testable import AgentStudio

@Suite("Bridge pane product File metadata source")
struct BridgePaneProductFileMetadataSourceTests {
    @Test("source acceptance does not wait for ignore-policy preparation")
    func sourceAcceptancePrecedesIgnorePolicyPreparation() async throws {
        // Arrange
        let fixture = try ProductFileSourceFixture(fileCount: 1)
        defer { fixture.remove() }
        let preparationGate = ProductFileMaterializationGate()
        let source = fixture.makeSource(ignorePolicyLoader: { _ in
            await preparationGate.markStarted()
            await preparationGate.waitUntilReleased()
            return .empty
        })
        let collector = ProductFileMetadataEventCollector()

        // Act
        let openTask = Task {
            try await source.open(
                subscription: fixture.openSnapshot(),
                productAdmission: fixture.productAdmission.context
            ) { event in
                await collector.append(event)
            }
        }
        await preparationGate.waitUntilStarted()
        let eventsBeforePreparationFinished = await collector.events
        await preparationGate.release()
        try await openTask.value

        // Assert
        #expect(
            eventsBeforePreparationFinished.contains {
                if case .sourceAccepted = $0 { true } else { false }
            }
        )
    }

    @Test("interest committed during preparation is fulfilled after the manifest is ready")
    func interestCommittedDuringPreparationIsFulfilled() async throws {
        // Arrange
        let fixture = try ProductFileSourceFixture(fileCount: 1)
        defer { fixture.remove() }
        let preparationGate = ProductFileMaterializationGate()
        let source = fixture.makeSource(ignorePolicyLoader: { _ in
            await preparationGate.markStarted()
            await preparationGate.waitUntilReleased()
            return .empty
        })
        let collector = ProductFileMetadataEventCollector()
        let openSnapshot = try fixture.openSnapshot()
        let openTask = Task {
            try await source.open(
                subscription: openSnapshot,
                productAdmission: fixture.productAdmission.context
            ) { event in
                await collector.append(event)
            }
        }
        await preparationGate.waitUntilStarted()

        // Act
        try await source.update(
            subscription: fixture.updatedSnapshot(from: openSnapshot),
            productAdmission: fixture.productAdmission.context
        ) { event in
            await collector.append(event)
        }
        await preparationGate.release()
        try await openTask.value

        // Assert
        #expect(
            (await collector.events).contains {
                if case .descriptorReady = $0 { true } else { false }
            }
        )
    }

    @Test("open streams bounded real tree windows and typed status")
    func openStreamsBoundedRealTreeWindowsAndStatus() async throws {
        // Arrange
        let fixture = try ProductFileSourceFixture(fileCount: 260)
        defer { fixture.remove() }
        let source = fixture.makeSource()
        let snapshot = try fixture.openSnapshot()
        let collector = ProductFileMetadataEventCollector()

        // Act
        try await source.open(
            subscription: snapshot,
            productAdmission: fixture.productAdmission.context
        ) { event in
            await collector.append(event)
        }

        // Assert
        let events = await collector.events
        let windows = events.compactMap { event -> BridgeProductFileTreeWindowEvent? in
            guard case .treeWindow(let window) = event else { return nil }
            return window
        }
        #expect(events.contains { if case .sourceAccepted = $0 { true } else { false } })
        #expect(windows.count == 2)
        #expect(
            windows.allSatisfy {
                $0.rows.count <= BridgeProductWireContract.maximumFileMetadataTreeWindowRowCount
            })
        #expect(windows.last?.finalWindow == true)
        #expect(windows.last?.totalRowCount == 260)
        #expect(windows.flatMap(\.rows).contains { $0.path == fixture.demandedPath })
        #expect(events.contains { if case .statusPatch = $0 { true } else { false } })
    }

    @Test("interest publishes exact complete metadata and a descriptor-bound read plan")
    func interestPublishesExactCompleteMetadataAndReadPlan() async throws {
        // Arrange
        let fixture = try ProductFileSourceFixture(fileCount: 1, demandedLineCount: 10_200)
        defer { fixture.remove() }
        let source = fixture.makeSource()
        let openSnapshot = try fixture.openSnapshot()
        try await source.open(
            subscription: openSnapshot,
            productAdmission: fixture.productAdmission.context
        ) { _ in }
        let updatedSnapshot = try fixture.updatedSnapshot(from: openSnapshot)
        let collector = ProductFileMetadataEventCollector()

        // Act
        try await source.update(
            subscription: updatedSnapshot,
            productAdmission: fixture.productAdmission.context
        ) { event in
            await collector.append(event)
        }

        // Assert
        let descriptorPayload = try #require(
            (await collector.events).compactMap { event -> BridgeProductFileDescriptorReadyPayload? in
                guard case .descriptorReady(let ready) = event else { return nil }
                return ready.payload
            }.first
        )
        guard case .available(let descriptor) = descriptorPayload.availability else {
            Issue.record("Expected an available text descriptor")
            return
        }
        let request = try fixture.contentRequest(descriptor: descriptor)
        let readPlan = try #require(
            await source.contentReadPlan(
                for: request,
                productAdmission: fixture.productAdmission.context
            )
        )
        let expectedData = try Data(contentsOf: fixture.demandedFileURL)
        let expectedSHA256 = sha256Hex(expectedData)
        #expect(readPlan.descriptor == descriptor)
        #expect(readPlan.relativePath == fixture.demandedPath)
        #expect(readPlan.rootURL == fixture.rootURL)
        #expect(descriptor.declaredByteLength == expectedData.count)
        #expect(descriptor.expectedSha256 == expectedSHA256)
        #expect(descriptorPayload.encoding == .utf8)
        #expect(descriptorPayload.payloadByteCount == expectedData.count)
        #expect(descriptorPayload.payloadLineCount == 10_200)
        #expect(descriptorPayload.totalLineCount == 10_200)
        #expect(descriptorPayload.truncationKind == .complete)
        #expect(!descriptorPayload.endsMidLine)
        #expect(descriptorPayload.endsWithNewline)
        #expect(descriptorPayload.virtualizedExtentKind == .exactLineCount)
    }

    @Test("interest refresh upserts a non-first row without emitting a positional window")
    func interestRefreshUpsertsNonFirstRowWithoutRelocatingFirstRow() async throws {
        // Arrange
        let fixture = try ProductFileSourceFixture(fileCount: 3, demandedIndex: 2)
        defer { fixture.remove() }
        let source = fixture.makeSource()
        let openSnapshot = try fixture.openSnapshot()
        let openCollector = ProductFileMetadataEventCollector()
        try await source.open(
            subscription: openSnapshot,
            productAdmission: fixture.productAdmission.context
        ) { event in
            await openCollector.append(event)
        }
        let initialRows = (await openCollector.events).flatMap(\.treeWindowRowsForTest)
        let initialFirstPath = try #require(initialRows.first?.path)
        let updateCollector = ProductFileMetadataEventCollector()

        // Act
        try await source.update(
            subscription: fixture.updatedSnapshot(from: openSnapshot),
            productAdmission: fixture.productAdmission.context
        ) { event in
            await updateCollector.append(event)
        }

        // Assert
        let updateEvents = await updateCollector.events
        let upsertedRows = updateEvents.flatMap(\.treeDeltaUpsertRowsForTest)
        #expect(initialFirstPath == "File-0000.swift")
        #expect(fixture.demandedPath == "File-0002.swift")
        #expect(updateEvents.allSatisfy { if case .treeWindow = $0 { false } else { true } })
        #expect(upsertedRows.map(\.path) == [fixture.demandedPath])
        #expect(!upsertedRows.contains { $0.path == initialFirstPath })
    }

    @Test("changeset emits bounded tree delta invalidation and revokes stale content")
    func changesetEmitsDeltaInvalidationAndRevokesStaleContent() async throws {
        // Arrange
        let fixture = try ProductFileSourceFixture(fileCount: 1)
        defer { fixture.remove() }
        let refreshWorkAdmission = await BridgePaneRefreshWorkAdmissionTestContext.foreground()
        let source = fixture.makeSource()
        let openSnapshot = try fixture.openSnapshot()
        try await source.open(
            subscription: openSnapshot,
            productAdmission: fixture.productAdmission.context
        ) { _ in }
        let updatedSnapshot = try fixture.updatedSnapshot(from: openSnapshot)
        let collector = ProductFileMetadataEventCollector()
        try await source.update(
            subscription: updatedSnapshot,
            productAdmission: fixture.productAdmission.context
        ) { event in
            await collector.append(event)
        }
        let descriptor = try #require(
            (await collector.events).compactMap { event -> BridgeProductFileContentDescriptor? in
                guard case .descriptorReady(let ready) = event,
                    case .available(let descriptor) = ready.payload.availability
                else { return nil }
                return descriptor
            }.first
        )
        let contentRequest = try fixture.contentRequest(descriptor: descriptor)
        #expect(
            await source.contentReadPlan(
                for: contentRequest,
                productAdmission: fixture.productAdmission.context
            ) != nil
        )
        try Data("replacement\n".utf8).write(to: fixture.demandedFileURL)

        // Act
        let emissions = try await source.publish(
            changeset: FileChangeset(
                worktreeId: fixture.worktreeId,
                repoId: fixture.repoId,
                rootPath: fixture.rootURL,
                paths: [fixture.demandedPath],
                timestamp: .now,
                batchSeq: 1
            ),
            productAdmission: fixture.productAdmission.context,
            foregroundWorkAdmission: refreshWorkAdmission.admission
        )

        // Assert
        #expect(emissions.contains { if case .treeDelta = $0.event { true } else { false } })
        #expect(emissions.contains { if case .invalidated = $0.event { true } else { false } })
        #expect(
            await source.contentReadPlan(
                for: contentRequest,
                productAdmission: fixture.productAdmission.context
            ) == nil
        )
    }

    @Test("same-subscription source replacement excludes stale lineage and content")
    func sameSubscriptionSourceReplacementExcludesStaleLineageAndContent() async throws {
        // Arrange
        let fixture = try ProductFileSourceFixture(fileCount: 1)
        defer { fixture.remove() }
        let refreshWorkAdmission = await BridgePaneRefreshWorkAdmissionTestContext.foreground()
        let source = fixture.makeSource()
        let openSnapshot = try fixture.openSnapshot()
        let updatedSnapshot = try fixture.updatedSnapshot(from: openSnapshot)
        try await source.open(
            subscription: openSnapshot,
            productAdmission: fixture.productAdmission.context
        ) { _ in }
        let originalCollector = ProductFileMetadataEventCollector()
        try await source.update(
            subscription: updatedSnapshot,
            productAdmission: fixture.productAdmission.context
        ) { event in
            await originalCollector.append(event)
        }
        let originalDescriptor = try #require(
            (await originalCollector.events).compactMap(\.availableDescriptorForTest).first
        )
        let originalRequest = try fixture.contentRequest(descriptor: originalDescriptor)
        #expect(
            await source.contentReadPlan(
                for: originalRequest,
                productAdmission: fixture.productAdmission.context
            ) != nil
        )

        // Act
        let replacementCollector = ProductFileMetadataEventCollector()
        try await source.open(
            subscription: openSnapshot,
            productAdmission: fixture.productAdmission.context
        ) { event in
            await replacementCollector.append(event)
        }
        try await source.update(
            subscription: updatedSnapshot,
            productAdmission: fixture.productAdmission.context
        ) { event in
            await replacementCollector.append(event)
        }
        let replacementEvents = await replacementCollector.events
        let replacementDescriptor = try #require(
            replacementEvents.compactMap(\.availableDescriptorForTest).first
        )
        let replacementRequest = try fixture.contentRequest(descriptor: replacementDescriptor)
        let replacementPlanBeforePublish = await source.contentReadPlan(
            for: replacementRequest,
            productAdmission: fixture.productAdmission.context
        )
        try Data("replacement\n".utf8).write(to: fixture.demandedFileURL)
        let replacementEmissions = try await source.publish(
            changeset: FileChangeset(
                worktreeId: fixture.worktreeId,
                repoId: fixture.repoId,
                rootPath: fixture.rootURL,
                paths: [fixture.demandedPath],
                timestamp: .now,
                batchSeq: 2
            ),
            productAdmission: fixture.productAdmission.context,
            foregroundWorkAdmission: refreshWorkAdmission.admission
        )

        // Assert
        #expect(originalDescriptor.source.subscriptionGeneration == 1)
        #expect(replacementDescriptor.source.subscriptionGeneration == 2)
        #expect(originalDescriptor.source != replacementDescriptor.source)
        #expect(
            await source.contentReadPlan(
                for: originalRequest,
                productAdmission: fixture.productAdmission.context
            ) == nil
        )
        #expect(replacementPlanBeforePublish != nil)
        #expect(!replacementEmissions.isEmpty)
        #expect(
            replacementEmissions.allSatisfy {
                $0.event.sourceForTest == replacementDescriptor.source
            }
        )
    }

    @Test("same-subscription replacement fences an in-flight stale producer")
    func sameSubscriptionReplacementFencesInFlightStaleProducer() async throws {
        // Arrange
        let fixture = try ProductFileSourceFixture(fileCount: 1)
        defer { fixture.remove() }
        let materializationGate = ProductFileMaterializationGate()
        let source = fixture.makeSource(descriptorMaterializer: { request in
            await materializationGate.markStarted()
            await materializationGate.waitUntilReleased()
            return try await BridgePaneProductFileContentSource.materialize(request)
        })
        let openSnapshot = try fixture.openSnapshot()
        try await source.open(
            subscription: openSnapshot,
            productAdmission: fixture.productAdmission.context
        ) { _ in }
        let staleCollector = ProductFileMetadataEventCollector()
        let staleUpdateTask = Task {
            try await source.update(
                subscription: fixture.updatedSnapshot(from: openSnapshot),
                productAdmission: fixture.productAdmission.context
            ) { event in
                await staleCollector.append(event)
            }
        }
        await materializationGate.waitUntilStarted()
        await staleCollector.removeAll()

        // Act
        try await source.open(
            subscription: openSnapshot,
            productAdmission: fixture.productAdmission.context
        ) { _ in }
        await materializationGate.release()
        _ = try await staleUpdateTask.value

        // Assert
        #expect((await staleCollector.events).isEmpty)
    }

    @Test("nonmatching worktree and repository changes cannot route File metadata")
    func nonmatchingSourceChangesCannotRouteFileMetadata() async throws {
        // Arrange
        let fixture = try ProductFileSourceFixture(fileCount: 1)
        defer { fixture.remove() }
        let refreshWorkAdmission = await BridgePaneRefreshWorkAdmissionTestContext.foreground()
        let source = fixture.makeSource()
        try await source.open(
            subscription: fixture.openSnapshot(),
            productAdmission: fixture.productAdmission.context
        ) { _ in }
        let nonmatchingWorktreeChangeset = FileChangeset(
            worktreeId: UUIDv7.generate(),
            repoId: fixture.repoId,
            rootPath: fixture.rootURL,
            paths: [fixture.demandedPath],
            timestamp: .now,
            batchSeq: 3
        )
        let nonmatchingRepositoryChangeset = FileChangeset(
            worktreeId: fixture.worktreeId,
            repoId: UUIDv7.generate(),
            rootPath: fixture.rootURL,
            paths: [fixture.demandedPath],
            timestamp: .now,
            batchSeq: 4
        )

        // Act
        let worktreeEmissions = try await source.publish(
            changeset: nonmatchingWorktreeChangeset,
            productAdmission: fixture.productAdmission.context,
            foregroundWorkAdmission: refreshWorkAdmission.admission
        )
        let repositoryEmissions = try await source.publish(
            changeset: nonmatchingRepositoryChangeset,
            productAdmission: fixture.productAdmission.context,
            foregroundWorkAdmission: refreshWorkAdmission.admission
        )

        // Assert
        #expect(worktreeEmissions.isEmpty)
        #expect(repositoryEmissions.isEmpty)
    }

    @Test("issued descriptor streams accepted data and terminal integrity frames")
    func issuedDescriptorStreamsContentFrames() async throws {
        // Arrange
        let harness = try await BridgeProductSessionLifecycleHarness.opened()
        let fixture = try ProductFileSourceFixture(
            fileCount: 1,
            demandedLineCount: 10_200,
            productAdmission: harness.productAdmission
        )
        defer { fixture.remove() }
        let source = fixture.makeSource()
        let openSnapshot = try fixture.openSnapshot()
        try await source.open(
            subscription: openSnapshot,
            productAdmission: fixture.productAdmission.context
        ) { _ in }
        let updatedSnapshot = try fixture.updatedSnapshot(from: openSnapshot)
        let collector = ProductFileMetadataEventCollector()
        try await source.update(
            subscription: updatedSnapshot,
            productAdmission: fixture.productAdmission.context
        ) { event in
            await collector.append(event)
        }
        let descriptor = try #require(
            (await collector.events).compactMap { event -> BridgeProductFileContentDescriptor? in
                guard case .descriptorReady(let ready) = event,
                    case .available(let descriptor) = ready.payload.availability
                else { return nil }
                return descriptor
            }.first
        )
        let fileRequest = try fixture.contentRequest(descriptor: descriptor)
        let expectedData = try Data(contentsOf: fixture.demandedFileURL)
        let expectedSHA256 = sha256Hex(expectedData)
        let refreshWorkAdmission = await BridgePaneRefreshWorkAdmissionTestContext.foreground()
        let provider = BridgePaneProductSchemeProvider(
            fileMetadataSource: source,
            reviewMetadataSource: BridgeUnavailablePaneProductReviewMetadataSource(),
            reviewContentSource: BridgeUnavailablePaneProductReviewContentSource(),
            markReviewItemViewed: { _, _ in },
            refreshWorkAdmissionSource: refreshWorkAdmission.source
        )
        let request = BridgeProductContentRequest.fileContent(fileRequest)
        let registration = await harness.session.registerContentProducer(
            request: request,
            productAdmission: harness.productAdmission.context
        ) { lease in
            await provider.runContentProducer(
                request: request,
                lease: lease,
                productAdmission: harness.productAdmission.context,
                session: harness.session
            )
        }
        let lease = try bridgeProductAcceptedLease(registration)
        let decoder = try BridgeProductContentFrameDecoder()
        var decodedFrames: [BridgeProductContentFrame] = []

        // Act
        while !decodedFrames.contains(where: { $0.isTerminalForTest }) {
            let queuedFrame = try #require(
                await consumeNextBridgeProductProducerFrame(
                    for: lease,
                    from: harness.session,
                    productAdmission: harness.productAdmission.context
                )
            )
            decodedFrames.append(contentsOf: try decoder.append(queuedFrame.data))
        }

        // Assert
        guard case .accepted = decodedFrames.first?.header,
            case .end(let endHeader) = decodedFrames.last?.header
        else {
            Issue.record("Expected accepted and end content frames")
            return
        }
        let dataFrames = decodedFrames.compactMap { frame -> Data? in
            guard case .data = frame.header else { return nil }
            return frame.payload
        }
        #expect(
            dataFrames.allSatisfy {
                $0.count <= BridgeProductWireContract.maximumContentDataPayloadBytes
            })
        #expect(dataFrames.reduce(into: Data()) { $0.append($1) } == expectedData)
        #expect(endHeader.endOfSource)
        #expect(endHeader.observedByteLength == expectedData.count)
        #expect(endHeader.observedSha256 == expectedSHA256)

        for _ in 0..<1000 where (await harness.session.producerSnapshot()).activeProducerTaskCount > 0 {
            await Task.yield()
        }
        let acknowledgement = try #require(await harness.session.unregisterProducer(lease))
        #expect(await harness.session.acknowledgeProducerLifecycle(acknowledgement))
    }

    @Test("exact issued File descriptor derives demand priority from committed path membership")
    func exactIssuedDescriptorDerivesCommittedDemandPriority() async throws {
        // Arrange
        let refreshWorkAdmission = await BridgePaneRefreshWorkAdmissionTestContext.foreground()
        let fixture = try ProductFileSourceFixture(fileCount: 1)
        defer { fixture.remove() }
        let source = fixture.makeSource()
        let openSnapshot = try fixture.openSnapshot()
        try await source.open(
            subscription: openSnapshot,
            productAdmission: fixture.productAdmission.context
        ) { _ in }
        let committedSnapshot = try fixture.updatedSnapshot(from: openSnapshot)
        let collector = ProductFileMetadataEventCollector()
        try await source.update(
            subscription: committedSnapshot,
            productAdmission: fixture.productAdmission.context
        ) { event in
            await collector.append(event)
        }
        let descriptor = try #require(
            (await collector.events).compactMap(\.availableDescriptorForTest).first
        )
        let request = BridgeProductContentRequest.fileContent(
            try fixture.contentRequest(descriptor: descriptor)
        )
        let coordinator = BridgePaneProductMetadataCoordinator(
            fileMetadataSource: source,
            reviewMetadataSource: BridgeUnavailablePaneProductReviewMetadataSource(),
            refreshWorkAdmissionSource: refreshWorkAdmission.source
        )
        let productAdmission = fixture.productAdmission.context
        await coordinator.apply(
            .subscriptionOpened(openSnapshot),
            productAdmission: productAdmission
        )
        await coordinator.apply(
            .subscriptionInterestsCommitted(
                barrier: .init(
                    subscriptionId: committedSnapshot.subscriptionId,
                    subscriptionKind: committedSnapshot.subscriptionKind,
                    workerDerivationEpoch: committedSnapshot.workerDerivationEpoch,
                    interestRevision: committedSnapshot.interestRevision,
                    interestSha256: committedSnapshot.interestSha256,
                    updateId: "file-priority-update-1"
                ),
                subscription: committedSnapshot
            ),
            productAdmission: productAdmission
        )

        // Act / Assert
        #expect(
            await coordinator.contentDemandInterest(
                for: request,
                productAdmission: productAdmission
            ) == .selected
        )

        await coordinator.apply(
            .subscriptionCancelled(committedSnapshot),
            productAdmission: productAdmission
        )
        #expect(
            await coordinator.contentDemandInterest(
                for: request,
                productAdmission: productAdmission
            ) == .unspecified
        )
    }

    @Test("cancelled interest materialization cannot resurrect a removed subscription")
    func cancelledMaterializationCannotResurrectRemovedSubscription() async throws {
        // Arrange
        let fixture = try ProductFileSourceFixture(fileCount: 1)
        defer { fixture.remove() }
        let gate = ProductFileMaterializationGate()
        let source = fixture.makeSource(descriptorMaterializer: { request in
            await gate.markStarted()
            await gate.waitUntilReleased()
            return try await BridgePaneProductFileContentSource.materialize(request)
        })
        let openSnapshot = try fixture.openSnapshot()
        try await source.open(
            subscription: openSnapshot,
            productAdmission: fixture.productAdmission.context
        ) { _ in }
        let collector = ProductFileMetadataEventCollector()
        let updateTask = Task {
            try await source.update(
                subscription: fixture.updatedSnapshot(from: openSnapshot),
                productAdmission: fixture.productAdmission.context
            ) { event in
                await collector.append(event)
            }
        }
        await gate.waitUntilStarted()
        await collector.removeAll()

        // Act
        updateTask.cancel()
        await source.cancel(subscriptionId: openSnapshot.subscriptionId)
        await gate.release()
        _ = await updateTask.result

        // Assert
        #expect((await collector.events).isEmpty)
    }

    @Test("a file removed between enumeration and read becomes typed unreadable metadata")
    func removedFileBecomesTypedUnreadableMetadata() async throws {
        // Arrange
        let fixture = try ProductFileSourceFixture(fileCount: 1)
        defer { fixture.remove() }
        let source = fixture.makeSource()
        let collector = ProductFileMetadataEventCollector()
        try await source.open(
            subscription: fixture.openSnapshot(),
            productAdmission: fixture.productAdmission.context
        ) { event in
            await collector.append(event)
        }
        let row = try #require((await collector.events).flatMap(\.treeWindowRowsForTest).first)
        let productSource = try #require(
            (await collector.events).compactMap { event -> BridgeProductFileSourceIdentity? in
                guard case .sourceAccepted(let accepted) = event else { return nil }
                return accepted.source
            }.first
        )
        try FileManager.default.removeItem(at: fixture.demandedFileURL)

        // Act
        let materialization = try await BridgePaneProductFileContentSource.materialize(
            .init(
                relativePath: row.path,
                rootURL: fixture.rootURL,
                row: BridgeWorktreeTreeRowMetadata(
                    rowId: row.rowId,
                    path: row.path,
                    name: row.name,
                    parentPath: row.parentPath,
                    depth: row.depth,
                    isDirectory: row.isDirectory,
                    fileId: row.fileId,
                    sizeBytes: row.sizeBytes,
                    lineCount: row.lineCount,
                    changeStatus: row.changeStatus?.rawValue
                ),
                source: productSource
            )
        )

        // Assert
        #expect(materialization.payload.virtualizedExtentKind == .unavailable)
        #expect(materialization.payload.payloadByteCount == 0)
        guard case .unavailable(let reason) = materialization.payload.availability else {
            Issue.record("Expected typed unavailable metadata")
            return
        }
        #expect(reason == .unreadable)
    }
}

extension BridgeProductContentFrame {
    fileprivate var isTerminalForTest: Bool {
        switch header {
        case .end, .error, .reset: true
        case .accepted, .data: false
        }
    }
}

extension BridgeProductFileMetadataEvent {
    fileprivate var availableDescriptorForTest: BridgeProductFileContentDescriptor? {
        guard case .descriptorReady(let ready) = self,
            case .available(let descriptor) = ready.payload.availability
        else { return nil }
        return descriptor
    }

    var sourceForTest: BridgeProductFileSourceIdentity {
        switch self {
        case .sourceAccepted(let event): event.source
        case .treeWindow(let event): event.source
        case .treeDelta(let event): event.source
        case .statusPatch(let event): event.source
        case .descriptorReady(let event): event.payload.source
        case .invalidated(let event): event.source
        }
    }

    var treeWindowRowsForTest: [BridgeProductFileTreeRow] {
        guard case .treeWindow(let window) = self else { return [] }
        return window.rows
    }

    fileprivate var treeDeltaUpsertRowsForTest: [BridgeProductFileTreeRow] {
        guard case .treeDelta(let delta) = self else { return [] }
        return delta.operations.flatMap { operation -> [BridgeProductFileTreeRow] in
            guard case .upsertRows(let rows) = operation else { return [] }
            return rows
        }
    }
}

private func sha256Hex(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

struct ProductFileSourceFixture {
    let demandedFileURL: URL
    let demandedPath: String
    let paneId = UUID(uuidString: "00000000-0000-4000-8000-000000000003")!
    let productAdmission: BridgeProductAdmissionTestContext
    let repoId = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
    let rootURL: URL
    let worktreeId = UUID(uuidString: "00000000-0000-4000-8000-000000000002")!

    init(
        fileCount: Int,
        demandedLineCount: Int = 2,
        demandedIndex: Int = 0,
        productAdmission suppliedProductAdmission: BridgeProductAdmissionTestContext? = nil
    ) throws {
        guard fileCount == 0 || (0..<fileCount).contains(demandedIndex) else {
            throw ProductFileSourceFixtureError.invalidDemandedIndex
        }
        productAdmission = try suppliedProductAdmission ?? BridgeProductAdmissionTestContext.make()
        rootURL = FileManager.default.temporaryDirectory
            .appending(path: "bridge-product-file-source-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        demandedPath = String(format: "File-%04d.swift", demandedIndex)
        demandedFileURL = rootURL.appending(path: demandedPath)
        for index in 0..<fileCount {
            let fileURL = rootURL.appending(path: String(format: "File-%04d.swift", index))
            let contents =
                index == demandedIndex
                ? String(repeating: "line\n", count: demandedLineCount)
                : "let value = \(index)\n"
            try Data(contents.utf8).write(to: fileURL)
        }
    }

    func remove() {
        try? FileManager.default.removeItem(at: rootURL)
    }

    func makeSource(
        paneId: UUID? = nil,
        constructionCoordinator: BridgeWorktreeProductConstructionCoordinator? = nil,
        snapshotPreparationLoader: BridgePaneProductFileSnapshotPreparationLoader? = nil,
        sharedSnapshotBuilder: @escaping BridgePaneProductFileSharedSnapshotBuilder =
            BridgeWorktreeFileMaterializer.buildSharedSnapshot,
        ignorePolicyLoader: @escaping BridgePaneProductFileIgnorePolicyLoader = loadTestBridgeFileIgnorePolicy,
        treeRowRefresher: BridgePaneProductFileTreeRowRefresher? = nil,
        descriptorMaterializer: @escaping BridgePaneProductFileDescriptorMaterializer =
            BridgePaneProductFileContentSource.materialize
    ) -> BridgePaneProductFileMetadataSource {
        BridgePaneProductFileMetadataSource(
            authority: .init(
                paneId: paneId ?? self.paneId,
                worktree: Worktree(
                    id: worktreeId,
                    repoId: repoId,
                    name: "fixture",
                    path: rootURL
                )
            ),
            gitReadContext: makeBridgeGitReadContext(rootURL: rootURL),
            constructionCoordinator: constructionCoordinator ?? BridgeWorktreeProductConstructionCoordinator(),
            statusProvider: ProductFileSourceStatusProvider(),
            snapshotPreparationLoader: snapshotPreparationLoader,
            sharedSnapshotBuilder: sharedSnapshotBuilder,
            ignorePolicyLoader: ignorePolicyLoader,
            treeRowRefresher: treeRowRefresher,
            descriptorMaterializer: descriptorMaterializer
        )
    }

    func openSnapshot(cwdScope: String? = nil) throws -> BridgeProductSubscriptionSnapshot {
        let cwdScopeValue: Any
        if let cwdScope {
            cwdScopeValue = cwdScope
        } else {
            cwdScopeValue = NSNull()
        }
        let request = try controlRequest(
            kind: "subscription.open",
            requestSequence: 2,
            values: [
                "subscription": [
                    "source": [
                        "cwdScope": cwdScopeValue,
                        "freshness": "live",
                        "includeStatuses": true,
                        "repoId": repoId.uuidString,
                        "rootPathToken": StableKey.fromPath(rootURL),
                        "worktreeId": worktreeId.uuidString,
                    ],
                    "subscriptionKind": "file.metadata",
                ],
                "subscriptionId": "file-subscription-1",
            ]
        )
        guard case .subscriptionOpen(let openRequest) = request else {
            throw ProductFileSourceFixtureError.invalidControlRequest
        }
        var state = BridgeProductSubscriptionState()
        _ = try state.open(openRequest)
        return try requiredSnapshot(from: state)
    }

    func updatedSnapshot(
        from openSnapshot: BridgeProductSubscriptionSnapshot,
        visiblePaths: [String] = []
    ) throws -> BridgeProductSubscriptionSnapshot {
        var interests = [
            try BridgeProductFileMetadataInterestStateGroup(
                lane: .foreground,
                paths: [demandedPath]
            )
        ]
        if !visiblePaths.isEmpty {
            interests.append(try .init(lane: .visible, paths: visiblePaths))
        }
        let targetState = BridgeProductSubscriptionInterestState.fileMetadata(
            interests: interests,
            pathScope: []
        )
        let targetSHA256 = try targetState.sha256Hex()
        let request = try controlRequest(
            kind: "subscription.updateBatch",
            requestSequence: 3,
            values: [
                "baseInterestRevision": 0,
                "baseInterestSha256": openSnapshot.interestSha256,
                "batchCount": 1,
                "batchIndex": 0,
                "delta": [
                    "add": [
                        ["lane": "foreground", "path": demandedPath]
                    ] + visiblePaths.map { ["lane": "visible", "path": $0] },
                    "addPathScope": [],
                    "removePathScope": [],
                    "removePaths": [],
                    "subscriptionKind": "file.metadata",
                ],
                "subscriptionId": "file-subscription-1",
                "subscriptionKind": "file.metadata",
                "targetInterestRevision": 1,
                "targetInterestSha256": targetSHA256,
                "totalDeltaItemCount": 1 + visiblePaths.count,
                "updateId": "file-update-1",
            ]
        )
        guard case .subscriptionUpdateBatch(let updateRequest) = request else {
            throw ProductFileSourceFixtureError.invalidControlRequest
        }
        var state = BridgeProductSubscriptionState()
        guard
            case .subscriptionOpen(let openRequest) = try controlRequest(
                kind: "subscription.open",
                requestSequence: 2,
                values: [
                    "subscription": openSnapshotSubscriptionObject,
                    "subscriptionId": "file-subscription-1",
                ]
            )
        else {
            throw ProductFileSourceFixtureError.invalidControlRequest
        }
        _ = try state.open(openRequest)
        _ = try state.apply(updateRequest)
        return try requiredSnapshot(from: state)
    }

    func contentRequest(
        descriptor: BridgeProductFileContentDescriptor
    ) throws -> BridgeProductFileContentRequest {
        let descriptorObject = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(descriptor)
        )
        let data = try JSONSerialization.data(
            withJSONObject: [
                "contentKind": "file.content",
                "contentRequestId": "file-content-request-1",
                "descriptor": descriptorObject,
                "kind": "content.open",
                "leaseId": "file-content-lease-1",
                "paneSessionId": "pane-session-1",
                "wireVersion": BridgeProductWireContract.version,
                "workerDerivationEpoch": 1,
                "workerInstanceId": "worker-instance-1",
            ],
            options: [.sortedKeys]
        )
        let request = try BridgeProductStrictJSON.decode(BridgeProductContentRequest.self, from: data)
        guard case .fileContent(let fileRequest) = request else {
            throw ProductFileSourceFixtureError.invalidContentRequest
        }
        return fileRequest
    }

    private var openSnapshotSubscriptionObject: [String: Any] {
        [
            "source": [
                "cwdScope": NSNull(),
                "freshness": "live",
                "includeStatuses": true,
                "repoId": repoId.uuidString,
                "rootPathToken": StableKey.fromPath(rootURL),
                "worktreeId": worktreeId.uuidString,
            ],
            "subscriptionKind": "file.metadata",
        ]
    }

    private func requiredSnapshot(
        from state: BridgeProductSubscriptionState
    ) throws -> BridgeProductSubscriptionSnapshot {
        guard let snapshot = state.snapshot(subscriptionId: "file-subscription-1") else {
            throw ProductFileSourceFixtureError.missingSubscription
        }
        return snapshot
    }

    private func controlRequest(
        kind: String,
        requestSequence: Int,
        values: [String: Any]
    ) throws -> BridgeProductControlRequest {
        let object: [String: Any] = [
            "kind": kind,
            "paneSessionId": "pane-session-1",
            "requestId": "request-\(requestSequence)",
            "requestSequence": requestSequence,
            "wireVersion": BridgeProductWireContract.version,
            "workerDerivationEpoch": 1,
            "workerInstanceId": "worker-instance-1",
        ].merging(values) { _, new in new }
        return try BridgeProductStrictJSON.decode(
            BridgeProductControlRequest.self,
            from: JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        )
    }
}

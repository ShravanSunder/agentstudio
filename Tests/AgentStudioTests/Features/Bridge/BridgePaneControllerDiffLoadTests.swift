import Foundation
import Testing

@testable import AgentStudio

extension WebKitSerializedTests.BridgePaneControllerTests {

    @Test("filesystem context refresh preserves revisions across changed and no-op packages")
    func filesystemContextRefreshPreservesRevisionsAcrossChangedAndNoOpPackages() async throws {
        let fixture = makeRefreshRevisionFixture()
        defer { fixture.controller.teardown() }

        let loadResult = await fixture.controller.handleDiffCommand(
            .loadDiff(
                DiffArtifact(
                    diffId: UUIDv7.generate(),
                    worktreeId: fixture.headEndpoint.worktreeId,
                    patchData: Data()
                )
            ),
            commandId: fixture.commandId,
            correlationId: nil
        )

        await setRefreshComparison(fixture, changedFile: fixture.refreshedFile)
        await postRefreshEvent(fixture, path: "Sources/App/New.swift", batchSeq: 10)
        #expect(loadResult == .success(commandId: fixture.commandId))
        #expect(fixture.controller.paneState.diff.status == .ready)
        expectRefreshPackageState(
            fixture,
            itemId: "item-new",
            revision: 1,
            addedItemIds: ["item-new"],
            removedItemIds: ["item-old"]
        )

        await postRefreshEvent(fixture, path: "Sources/App/New.swift", batchSeq: 11)
        #expect(fixture.controller.paneState.diff.packageMetadata?.orderedItemIds == ["item-new"])
        #expect(fixture.controller.paneState.diff.packageMetadata?.revision == 1)
        #expect(fixture.controller.paneState.diff.packageDelta == nil)

        await setRefreshComparison(fixture, changedFile: fixture.secondRefreshedFile)
        await postRefreshEvent(fixture, path: "Sources/App/Newer.swift", batchSeq: 12)
        expectRefreshPackageState(
            fixture,
            itemId: "item-newer",
            revision: 2,
            addedItemIds: ["item-newer"],
            removedItemIds: ["item-new"]
        )
        #expect(await fixture.provider.recordedComparisonRequestsCount() == 4)
    }

    @Test("filesystem context refresh coalesces overlapping refresh events")
    func filesystemContextRefreshCoalescesOverlappingRefreshEvents() async throws {
        let fixture = makeRefreshRevisionFixture()
        defer { fixture.controller.teardown() }
        let loadResult = await fixture.controller.handleDiffCommand(
            .loadDiff(
                DiffArtifact(
                    diffId: UUIDv7.generate(),
                    worktreeId: fixture.headEndpoint.worktreeId,
                    patchData: Data()
                )
            ),
            commandId: fixture.commandId,
            correlationId: nil
        )
        #expect(loadResult == .success(commandId: fixture.commandId))

        let gate = BridgeComparisonGate()
        await fixture.provider.setComparisonGate(gate)
        await setRefreshComparison(fixture, changedFile: fixture.refreshedFile)
        async let firstRefresh: Void = postRefreshEvent(
            fixture,
            path: "Sources/App/New.swift",
            batchSeq: 20
        )
        await gate.waitForStartedComparisonCount(1)

        await setRefreshComparison(fixture, changedFile: fixture.secondRefreshedFile)
        async let secondRefresh: Void = postRefreshEvent(
            fixture,
            path: "Sources/App/Newer.swift",
            batchSeq: 21
        )
        async let thirdRefresh: Void = postRefreshEvent(
            fixture,
            path: "Sources/App/Newer.swift",
            batchSeq: 22
        )
        await Task.yield()
        await Task.yield()

        #expect(await fixture.provider.recordedComparisonRequestsCount() == 2)
        await gate.releaseAll()
        _ = await (firstRefresh, secondRefresh, thirdRefresh)

        #expect(await fixture.provider.recordedComparisonRequestsCount() == 3)
        expectRefreshPackageState(
            fixture,
            itemId: "item-newer",
            revision: 2,
            addedItemIds: ["item-newer"],
            removedItemIds: ["item-new"]
        )
    }

    @Test("loadDiff ignores stale earlier generation completion")
    func loadDiff_ignores_stale_earlier_generation_completion() async throws {
        let baseEndpoint = makeBridgeEndpoint(endpointId: "baseline-headMinusOne", kind: .gitRef)
        let headEndpoint = makeBridgeEndpoint(endpointId: "working-tree", kind: .workingTree)
        let firstFile = makeBridgeEndpointChangedFile(
            fileId: "old",
            path: "Sources/App/Old.swift",
            sizeBytes: 100
        )
        let secondFile = makeBridgeEndpointChangedFile(
            fileId: "new",
            path: "Sources/App/New.swift",
            sizeBytes: 100
        )
        let provider = OutOfOrderBridgeReviewSourceProvider(
            firstGenerationComparison: BridgeEndpointComparison(
                baseEndpoint: baseEndpoint,
                headEndpoint: headEndpoint,
                changedFiles: [firstFile]
            ),
            laterGenerationComparison: BridgeEndpointComparison(
                baseEndpoint: baseEndpoint,
                headEndpoint: headEndpoint,
                changedFiles: [secondFile]
            )
        )
        let controller = makeController(
            state: BridgePaneState(
                panelKind: .diffViewer,
                source: .workspace(rootPath: "/tmp/worktree", baseline: .headMinusOne)
            ),
            reviewSourceProvider: provider
        )
        defer { controller.teardown() }
        let firstCommandId = UUID()
        let secondCommandId = UUID()

        async let firstResult = controller.handleDiffCommand(
            .loadDiff(
                DiffArtifact(diffId: UUIDv7.generate(), worktreeId: headEndpoint.worktreeId, patchData: Data())
            ),
            commandId: firstCommandId,
            correlationId: nil
        )
        await provider.waitForFirstGenerationStarted()
        let secondResult = await controller.handleDiffCommand(
            .loadDiff(
                DiffArtifact(diffId: UUIDv7.generate(), worktreeId: headEndpoint.worktreeId, patchData: Data())
            ),
            commandId: secondCommandId,
            correlationId: nil
        )
        await provider.releaseFirstGeneration()

        #expect(secondResult == .success(commandId: secondCommandId))
        #expect(await firstResult == .failure(.invalidPayload(description: "Stale bridge review load")))
        #expect(controller.paneState.diff.packageMetadata?.orderedItemIds == ["item-new"])
        #expect(controller.paneState.diff.packageMetadata?.itemsById["item-old"] == nil)
    }

    @Test("loadDiff close after package commit suppresses diffLoaded and success")
    func loadDiff_close_after_package_state_commit_suppresses_diffLoaded_and_success() async throws {
        // Arrange
        let baseEndpoint = makeBridgeEndpoint(endpointId: "baseline-headMinusOne", kind: .gitRef)
        let headEndpoint = makeBridgeEndpoint(endpointId: "working-tree", kind: .workingTree)
        let changedFile = makeBridgeEndpointChangedFile(
            fileId: "late-close",
            path: "Sources/App/LateClose.swift",
            sizeBytes: 100
        )
        let reviewSourceProvider = BridgeReviewSourceProviderFake(
            comparison: BridgeEndpointComparison(
                baseEndpoint: baseEndpoint,
                headEndpoint: headEndpoint,
                changedFiles: [changedFile]
            ),
            contentByHandleId: [:]
        )
        let reviewMetadataSource = DiffLoadReadyPublicationGate()
        let productProvider = BridgePaneProductSchemeProvider(
            fileMetadataSource: BridgeUnavailablePaneProductFileMetadataSource(),
            reviewMetadataSource: reviewMetadataSource,
            reviewContentSource: BridgeUnavailablePaneProductReviewContentSource(),
            markReviewItemViewed: { _, _ in }
        )
        let paneId = UUIDv7.generate()
        let productAdmissionGate = BridgeProductAdmissionGate()
        let installation = BridgePaneController.makeInitialProductSessionInstallation(
            paneSessionId: paneId.uuidString,
            provider: productProvider,
            productAdmissionGate: productAdmissionGate
        )
        let controller = BridgePaneController(
            paneId: paneId,
            state: BridgePaneState(
                panelKind: .diffViewer,
                source: .workspace(rootPath: "/tmp/worktree", baseline: .headMinusOne)
            ),
            reviewSourceProvider: reviewSourceProvider,
            productSessionDependencies: BridgePaneProductSessionDependencies(
                installation: installation,
                owner: BridgePaneController.makeProductSessionOwner(
                    paneSessionId: paneId.uuidString,
                    provider: productProvider,
                    productAdmissionGate: productAdmissionGate,
                    activeInstallation: installation
                ),
                productProvider: productProvider
            )
        )
        let productAdmission = try #require(productAdmissionGate.acquire())
        _ = try await installDiffLoadMetadataProducer(
            installation: installation,
            productProvider: productProvider,
            productAdmission: productAdmission
        )
        let commandId = UUIDv7.generate()

        // Act
        async let commandResult = controller.handleDiffCommand(
            .loadDiff(
                DiffArtifact(
                    diffId: UUIDv7.generate(),
                    worktreeId: headEndpoint.worktreeId,
                    patchData: Data()
                )
            ),
            commandId: commandId,
            correlationId: nil
        )
        await reviewMetadataSource.waitUntilReadyPublicationStarted()

        // Assert
        #expect(controller.paneState.diff.status == .ready)
        #expect(controller.paneState.diff.packageMetadata?.orderedItemIds == ["item-late-close"])
        #expect(controller.runtime.snapshot().lastSeq == 0)

        let retirementTask = controller.teardown()
        await reviewMetadataSource.releaseReadyPublication()

        #expect(
            await commandResult
                == .failure(.invalidPayload(description: "Bridge pane is closed"))
        )
        #expect(controller.runtime.snapshot().lastSeq == 0)
        let replay = await controller.runtime.eventsSince(seq: 0)
        #expect(!replay.events.contains(where: isDiffLoadWitnessEvent))
        #expect(await retirementTask.value)
        #expect(await controller.productSessionOwner.snapshot().hasZeroResidue)
    }

    @Test("loadDiff does not leak absolute workspace root in review package")
    func loadDiff_does_not_leak_absolute_workspace_root_in_review_package() async throws {
        let baseEndpoint = makeBridgeEndpoint(endpointId: "baseline-headMinusOne", kind: .gitRef)
        let headEndpoint = makeBridgeEndpoint(endpointId: "working-tree", kind: .workingTree)
        let changedFile = makeBridgeEndpointChangedFile(
            fileId: "source",
            path: "Sources/App/View.swift",
            sizeBytes: 100
        )
        let provider = BridgeReviewSourceProviderFake(
            comparison: BridgeEndpointComparison(
                baseEndpoint: baseEndpoint,
                headEndpoint: headEndpoint,
                changedFiles: [changedFile]
            ),
            contentByHandleId: [:]
        )
        let controller = makeController(
            state: BridgePaneState(
                panelKind: .diffViewer,
                source: .workspace(rootPath: "/tmp/worktree", baseline: .headMinusOne)
            ),
            reviewSourceProvider: provider
        )
        defer { controller.teardown() }
        let commandId = UUID()

        let result = await controller.handleDiffCommand(
            .loadDiff(
                DiffArtifact(diffId: UUIDv7.generate(), worktreeId: headEndpoint.worktreeId, patchData: Data())
            ),
            commandId: commandId,
            correlationId: nil
        )

        #expect(result == .success(commandId: commandId))
        let package = try #require(controller.paneState.diff.packageMetadata)
        #expect(package.orderedItemIds == ["item-source"])
        #expect(package.query.pathScope.isEmpty)
        #expect(package.headEndpoint.providerIdentity.contains("/tmp") == false)
        #expect(package.baseEndpoint.providerIdentity.contains("/tmp") == false)
    }

    @Test("loadDiff publishes typed provider unavailable failure")
    func loadDiff_publishes_typed_provider_unavailable_failure() async {
        let controller = BridgePaneController(
            paneId: UUIDv7.generate(),
            state: BridgePaneState(
                panelKind: .diffViewer,
                source: .workspace(rootPath: "/tmp/worktree", baseline: .headMinusOne)
            )
        )
        defer { controller.teardown() }
        let commandId = UUID()
        let artifact = DiffArtifact(
            diffId: UUIDv7.generate(),
            worktreeId: UUIDv7.generate(),
            patchData: Data()
        )

        let result = await controller.handleDiffCommand(
            .loadDiff(artifact),
            commandId: commandId,
            correlationId: nil
        )

        #expect(result == .failure(.backendUnavailable(backend: "BridgeReviewSourceProvider")))
        #expect(controller.paneState.diff.status == .error)
        #expect(controller.paneState.diff.error == "providerUnavailable")
        #expect(controller.paneState.diff.packageMetadata == nil)
    }
}

private enum DiffLoadWitnessError: Error {
    case expectedMetadataProducerRegistration
    case expectedWorkerSessionExecution
}

private actor DiffLoadReadyPublicationGate: BridgePaneProductReviewMetadataProducing {
    private var readyPublicationRelease: CheckedContinuation<Void, Never>?
    private var readyPublicationStarted = false
    private var readyPublicationStartedWaiters: [CheckedContinuation<Void, Never>] = []

    func open(
        subscription _: BridgeProductSubscriptionSnapshot,
        productAdmission _: BridgeProductAdmissionContext,
        emit _: @escaping BridgePaneProductReviewMetadataEventSink
    ) async throws {}

    func update(
        subscription _: BridgeProductSubscriptionSnapshot,
        productAdmission _: BridgeProductAdmissionContext,
        emit _: @escaping BridgePaneProductReviewMetadataEventSink
    ) async throws {}

    func publish(
        availability: BridgePaneProductReviewMetadataAvailability,
        productAdmission _: BridgeProductAdmissionContext
    ) async throws -> BridgePaneProductReviewMetadataPublicationOutcome {
        switch availability {
        case .loading:
            return .loading(retained: 0)
        case .failed:
            return .failed(retained: 0)
        case .ready:
            readyPublicationStarted = true
            let startedWaiters = readyPublicationStartedWaiters
            readyPublicationStartedWaiters.removeAll(keepingCapacity: false)
            for waiter in startedWaiters {
                waiter.resume()
            }
            await withCheckedContinuation { continuation in
                readyPublicationRelease = continuation
            }
            return .ready(
                BridgeReviewMetadataPublicationReceipt(
                    retained: 0,
                    publishedSubscriptions: 0,
                    emittedEvents: 0,
                    superseded: 0
                )
            )
        }
    }

    func cancel(subscriptionId _: String) {}

    func waitUntilReadyPublicationStarted() async {
        guard !readyPublicationStarted else { return }
        await withCheckedContinuation { continuation in
            readyPublicationStartedWaiters.append(continuation)
        }
    }

    func releaseReadyPublication() {
        readyPublicationRelease?.resume()
        readyPublicationRelease = nil
    }
}

private func installDiffLoadMetadataProducer(
    installation: BridgeProductSessionInstallation,
    productProvider: BridgePaneProductSchemeProvider,
    productAdmission: BridgeProductAdmissionContext
) async throws -> BridgeProductProducerLease {
    let workerOpenRequest = try diffLoadWitnessControlRequest([
        "kind": "workerSession.open",
        "paneSessionId": installation.bootstrap.paneSessionId,
        "request": NSNull(),
        "requestId": "request-open-late-close-witness",
        "requestSequence": 1,
        "wireVersion": BridgeProductWireContract.version,
        "workerInstanceId": installation.bootstrap.workerInstanceId,
    ])
    let workerOpenAdmission = await installation.session.beginControl(
        exactRequestBytes: try JSONEncoder().encode(workerOpenRequest),
        presentedCapability: try BridgeProductCapabilityHeaderEncoding.encode(
            installation.capabilityBytes
        ),
        productAdmission: productAdmission
    )
    guard case .execute(let workerOpenToken, _) = workerOpenAdmission else {
        throw DiffLoadWitnessError.expectedWorkerSessionExecution
    }
    _ = try await installation.session.completeControl(
        token: workerOpenToken,
        exactResponseBytes: try JSONEncoder().encode(
            BridgeProductControlResponse.workerSessionAccepted(correlating: workerOpenRequest)
        )
    )

    let metadataRequest = try diffLoadWitnessMetadataRequest(installation: installation)
    let registration = await installation.session.registerMetadataProducer(
        request: metadataRequest,
        productAdmission: productAdmission
    ) { lease in
        await productProvider.runMetadataProducer(
            request: metadataRequest,
            lease: lease,
            productAdmission: productAdmission,
            session: installation.session
        )
    }
    guard case .accepted(let lease) = registration else {
        throw DiffLoadWitnessError.expectedMetadataProducerRegistration
    }
    _ = await consumeNextBridgeProductProducerFrame(
        for: lease,
        from: installation.session,
        productAdmission: productAdmission
    )
    return lease
}

private func diffLoadWitnessControlRequest(
    _ object: [String: Any]
) throws -> BridgeProductControlRequest {
    try BridgeProductStrictJSON.decode(
        BridgeProductControlRequest.self,
        from: JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    )
}

private func diffLoadWitnessMetadataRequest(
    installation: BridgeProductSessionInstallation
) throws -> BridgeProductMetadataStreamRequest {
    try BridgeProductStrictJSON.decode(
        BridgeProductMetadataStreamRequest.self,
        from: JSONSerialization.data(
            withJSONObject: [
                "kind": "metadataStream.open",
                "metadataStreamId": "metadata-late-close-witness",
                "paneSessionId": installation.bootstrap.paneSessionId,
                "resumeFromStreamSequence": NSNull(),
                "wireVersion": BridgeProductWireContract.version,
                "workerInstanceId": installation.bootstrap.workerInstanceId,
            ],
            options: [.sortedKeys]
        )
    )
}

private func isDiffLoadWitnessEvent(_ envelope: RuntimeEnvelope) -> Bool {
    guard case .pane(let paneEnvelope) = envelope,
        case .diff(.diffLoaded) = paneEnvelope.event
    else {
        return false
    }
    return true
}

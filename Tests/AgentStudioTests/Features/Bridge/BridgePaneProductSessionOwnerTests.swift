import Foundation
import Testing

@testable import AgentStudio

@Suite("Bridge pane product session owner")
struct BridgePaneProductSessionOwnerTests {
    @Test("prepared candidates use fresh secure identity and remain off-path")
    func preparedCandidatesAreFreshAndUnexposed() async throws {
        // Arrange
        let provider = BridgePaneProductSessionProviderGate()
        let owner = try BridgePaneProductSessionOwner(
            paneSessionId: bridgeProductTestPaneSessionId,
            provider: provider
        )

        // Act
        let firstCandidate = try await owner.prepareCandidate()
        let secondCandidate = try await owner.prepareCandidate()

        // Assert
        #expect(firstCandidate.capabilityBytes.count == BridgeProductWireContract.capabilityByteLength)
        #expect(secondCandidate.capabilityBytes.count == BridgeProductWireContract.capabilityByteLength)
        #expect(firstCandidate.capabilityBytes != secondCandidate.capabilityBytes)
        #expect(firstCandidate.bootstrap.paneSessionId == bridgeProductTestPaneSessionId)
        #expect(secondCandidate.bootstrap.paneSessionId == bridgeProductTestPaneSessionId)
        #expect(firstCandidate.bootstrap.workerInstanceId != secondCandidate.bootstrap.workerInstanceId)
        #expect(await owner.activeInstallation == nil)
        #expect(await owner.schemeRouter.activeInstallation == nil)
    }

    @Test("replacement exposes no candidate before old revocation succeeds")
    func replacementWaitsForOldRevocationBarrier() async throws {
        // Arrange
        let provider = BridgePaneProductSessionProviderGate()
        let owner = try BridgePaneProductSessionOwner(
            paneSessionId: bridgeProductTestPaneSessionId,
            provider: provider
        )
        let oldInstallation = try await installFirstCandidate(in: owner)
        try await openBridgePaneProductSession(oldInstallation)
        let oldReply = try await startContentReply(
            installation: oldInstallation,
            provider: provider,
            identitySuffix: "held-replacement"
        )
        await provider.holdLifecycleAcknowledgements()
        let candidate = try await owner.prepareCandidate()

        // Act
        let replacementTask = Task {
            await owner.activatePreparedCandidate(candidate)
        }
        _ = await provider.waitForLifecycleAcknowledgement(count: 1)

        // Assert
        #expect(await owner.activeInstallation == nil)
        #expect(await owner.schemeRouter.activeInstallation == nil)
        #expect(!(await provider.lifecycleAcknowledgementsWereReleased))

        await provider.releaseLifecycleAcknowledgements(result: true)
        #expect(await replacementTask.value == .activated)
        #expect(
            await owner.activeInstallation?.bootstrap.workerInstanceId
                == candidate.bootstrap.workerInstanceId
        )
        #expect(
            await owner.schemeRouter.activeInstallation?.bootstrap.workerInstanceId
                == candidate.bootstrap.workerInstanceId
        )
        #expect((await oldInstallation.session.producerSnapshot()).hasZeroResidue)
        _ = try? await oldReply.value
    }

    @Test("failed revocation leaves router empty and exact retry may activate candidate")
    func failedRevocationBlocksCandidateUntilRetrySucceeds() async throws {
        // Arrange
        let provider = BridgePaneProductSessionProviderGate()
        let owner = try BridgePaneProductSessionOwner(
            paneSessionId: bridgeProductTestPaneSessionId,
            provider: provider
        )
        let oldInstallation = try await installFirstCandidate(in: owner)
        try await openBridgePaneProductSession(oldInstallation)
        let oldReply = try await startContentReply(
            installation: oldInstallation,
            provider: provider,
            identitySuffix: "failed-replacement"
        )
        let candidate = try await owner.prepareCandidate()
        await provider.failLifecycleAcknowledgements()

        // Act
        let firstResult = await owner.activatePreparedCandidate(candidate)
        let firstAcknowledgements = await provider.lifecycleAcknowledgements

        // Assert
        #expect(firstResult == .revocationFailed)
        #expect(await owner.activeInstallation == nil)
        #expect(await owner.schemeRouter.activeInstallation == nil)
        #expect(!(await oldInstallation.session.producerSnapshot()).hasZeroResidue)
        let firstAcknowledgement = try #require(firstAcknowledgements.first)

        await provider.succeedLifecycleAcknowledgements()
        let retryResult = await owner.activatePreparedCandidate(candidate)
        let allAcknowledgements = await provider.lifecycleAcknowledgements

        #expect(retryResult == .activated)
        #expect(allAcknowledgements.count >= 2)
        #expect(allAcknowledgements[0] == firstAcknowledgement)
        #expect(allAcknowledgements[1] == firstAcknowledgement)
        #expect((await oldInstallation.session.producerSnapshot()).hasZeroResidue)
        #expect(
            await owner.activeInstallation?.bootstrap.workerInstanceId
                == candidate.bootstrap.workerInstanceId
        )
        _ = try? await oldReply.value
    }

    @Test("concurrent replacements preserve invocation order behind one revocation barrier")
    func concurrentReplacementsPreserveInvocationOrder() async throws {
        // Arrange
        let provider = BridgePaneProductSessionProviderGate()
        let owner = try BridgePaneProductSessionOwner(
            paneSessionId: bridgeProductTestPaneSessionId,
            provider: provider
        )
        let oldInstallation = try await installFirstCandidate(in: owner)
        try await openBridgePaneProductSession(oldInstallation)
        let oldReply = try await startContentReply(
            installation: oldInstallation,
            provider: provider,
            identitySuffix: "concurrent-replacement"
        )
        let firstCandidate = try await owner.prepareCandidate()
        let secondCandidate = try await owner.prepareCandidate()
        await provider.holdLifecycleAcknowledgements()

        // Act
        let firstReplacementTask = Task {
            await owner.activatePreparedCandidate(firstCandidate)
        }
        _ = await provider.waitForLifecycleAcknowledgement(count: 1)
        let secondReplacementTask = Task {
            await owner.activatePreparedCandidate(secondCandidate)
        }
        let secondPublishedBeforeFirstRevocation = await waitForActiveWorkerInstance(
            secondCandidate.bootstrap.workerInstanceId,
            in: owner
        )
        await provider.releaseLifecycleAcknowledgements(result: true)
        let firstResult = await firstReplacementTask.value
        let secondResult = await secondReplacementTask.value

        // Assert
        #expect(!secondPublishedBeforeFirstRevocation)
        #expect(firstResult == .activated)
        #expect(secondResult == .activated)
        #expect(
            await owner.activeInstallation?.bootstrap.workerInstanceId
                == secondCandidate.bootstrap.workerInstanceId
        )
        #expect(
            await owner.schemeRouter.activeInstallation?.bootstrap.workerInstanceId
                == secondCandidate.bootstrap.workerInstanceId
        )
        #expect((await oldInstallation.session.producerSnapshot()).hasZeroResidue)
        _ = try? await oldReply.value
    }

    @Test("replacement waits for page reload retirement before publishing the candidate")
    func replacementWaitsForPageReloadRetirement() async throws {
        // Arrange
        let provider = BridgePaneProductSessionProviderGate()
        let owner = try BridgePaneProductSessionOwner(
            paneSessionId: bridgeProductTestPaneSessionId,
            provider: provider
        )
        let oldInstallation = try await installFirstCandidate(in: owner)
        try await openBridgePaneProductSession(oldInstallation)
        let oldReply = try await startContentReply(
            installation: oldInstallation,
            provider: provider,
            identitySuffix: "page-reload"
        )
        let replacementCandidate = try await owner.prepareCandidate()
        await provider.holdLifecycleAcknowledgements()

        // Act
        let retirementTask = Task {
            await owner.retire(reason: .pageReload)
        }
        _ = await provider.waitForLifecycleAcknowledgement(count: 1)
        let replacementTask = Task {
            await owner.activatePreparedCandidate(replacementCandidate)
        }
        let candidatePublishedBeforeRetirement = await waitForActiveWorkerInstance(
            replacementCandidate.bootstrap.workerInstanceId,
            in: owner
        )
        await provider.releaseLifecycleAcknowledgements(result: true)
        let retirementResult = await retirementTask.value
        let replacementResult = await replacementTask.value

        // Assert
        #expect(!candidatePublishedBeforeRetirement)
        #expect(retirementResult == .retired)
        #expect(replacementResult == .activated)
        #expect(
            await owner.activeInstallation?.bootstrap.workerInstanceId
                == replacementCandidate.bootstrap.workerInstanceId
        )
        #expect((await oldInstallation.session.producerSnapshot()).hasZeroResidue)
        _ = try? await oldReply.value
    }

    @Test("pane disposal is terminal before its retirement acknowledgement completes")
    func paneDisposalRejectsConcurrentAndFutureActivation() async throws {
        // Arrange
        let provider = BridgePaneProductSessionProviderGate()
        let owner = try BridgePaneProductSessionOwner(
            paneSessionId: bridgeProductTestPaneSessionId,
            provider: provider
        )
        let oldInstallation = try await installFirstCandidate(in: owner)
        try await openBridgePaneProductSession(oldInstallation)
        let oldReply = try await startContentReply(
            installation: oldInstallation,
            provider: provider,
            identitySuffix: "terminal-pane-disposal"
        )
        let candidate = try await owner.prepareCandidate()
        await provider.holdLifecycleAcknowledgements()

        // Act
        let retirementTask = Task {
            await owner.retire(reason: .paneDisposal)
        }
        _ = await provider.waitForLifecycleAcknowledgement(count: 1)
        let activationResult = await owner.activatePreparedCandidate(candidate)
        await provider.releaseLifecycleAcknowledgements(result: true)
        let retirementResult = await retirementTask.value

        // Assert
        #expect(activationResult == .ownerDisposed)
        #expect(retirementResult == .retired)
        #expect(await owner.activeInstallation == nil)
        #expect(await owner.schemeRouter.activeInstallation == nil)
        #expect((await oldInstallation.session.producerSnapshot()).hasZeroResidue)
        #expect((await candidate.session.snapshot).lifecycle == .revoked)
        await #expect(throws: BridgePaneProductSessionOwnerError.ownerDisposed) {
            _ = try await owner.prepareCandidate()
        }
        _ = try? await oldReply.value
    }

    @Test("tracked pane disposal drains scheme tasks producers leases and acknowledgements")
    func trackedDisposalReachesZeroResidue() async throws {
        // Arrange
        let provider = BridgePaneProductSessionProviderGate()
        let owner = try BridgePaneProductSessionOwner(
            paneSessionId: bridgeProductTestPaneSessionId,
            provider: provider
        )
        let installation = try await installFirstCandidate(in: owner)
        try await openBridgePaneProductSession(installation)
        let schemeRouter = await owner.schemeRouter
        let handler = BridgeSchemeHandler(
            paneId: UUID(),
            productSessionRouter: schemeRouter
        )
        let metadataReply = try await startBridgePaneProductMetadataReply(
            installation: installation,
            provider: provider,
            handler: handler
        )
        let contentReply = try await startContentReply(
            installation: installation,
            provider: provider,
            identitySuffix: "pane-disposal",
            handler: handler
        )
        let liveSnapshot = await owner.snapshot()

        // Act
        let retirement = await owner.retire(reason: .paneDisposal)
        _ = try? await metadataReply.value
        _ = try? await contentReply.value
        let finalSnapshot = await owner.snapshot()

        // Assert
        #expect(liveSnapshot.activeSchemeTaskCount == 2)
        #expect(liveSnapshot.activeProducerCount == 2)
        #expect(liveSnapshot.activeProducerTaskCount == 2)
        #expect(retirement == .retired)
        #expect(await owner.activeInstallation == nil)
        #expect(await owner.schemeRouter.activeInstallation == nil)
        #expect(finalSnapshot.activeSchemeTaskCount == 0)
        #expect(finalSnapshot.activeProducerCount == 0)
        #expect(finalSnapshot.activeProducerTaskCount == 0)
        #expect(finalSnapshot.activeContentLeaseCount == 0)
        #expect(finalSnapshot.activeTransportLeaseCount == 0)
        #expect(finalSnapshot.pendingLifecycleAcknowledgementCount == 0)
        #expect(finalSnapshot.hasZeroResidue)
    }

    @Test("control-only product work has scheme and transport residue without producers")
    func controlOnlyWorkTracksSchemeTaskAndTransportClaim() async throws {
        // Arrange
        let provider = BridgePaneProductSessionProviderGate()
        let owner = try BridgePaneProductSessionOwner(
            paneSessionId: bridgeProductTestPaneSessionId,
            provider: provider
        )
        let installation = try await installFirstCandidate(in: owner)
        try await openBridgePaneProductSession(installation)
        await provider.holdProductCallResponses()
        let schemeRouter = await owner.schemeRouter
        let handler = BridgeSchemeHandler(
            paneId: UUID(),
            productSessionRouter: schemeRouter
        )
        let request = try paneOwnerProductCallSchemeRequest(
            installation: installation,
            identitySuffix: "control-only"
        )

        // Act
        let replyTask = Task {
            try await collectBridgeSchemeHandlerProductReply(
                handler: handler,
                request: request
            )
        }
        await provider.waitUntilProductCallStarted()
        let liveSnapshot = await owner.snapshot()
        let retirementTask = Task {
            await owner.retire(reason: .paneDisposal)
        }
        await waitUntilProductRouterIsFenced(schemeRouter)
        let retiringSnapshot = await owner.snapshot()

        // Assert
        #expect(liveSnapshot.activeSchemeTaskCount == 1)
        #expect(liveSnapshot.activeTransportLeaseCount == 1)
        #expect(liveSnapshot.activeProducerCount == 0)
        #expect(liveSnapshot.activeProducerTaskCount == 0)
        #expect(liveSnapshot.activeContentLeaseCount == 0)
        #expect(retiringSnapshot.activeSchemeTaskCount == 1)
        #expect(retiringSnapshot.activeTransportLeaseCount == 1)
        #expect(!retiringSnapshot.hasZeroResidue)
        #expect(await schemeRouter.claimActiveAdapter() == nil)

        await provider.releaseProductCallResponses()
        #expect(await retirementTask.value == .retired)
        _ = try? await replyTask.value
        #expect(await owner.snapshot() == .empty)
    }

    @Test("failed retirement keeps exact lifecycle acknowledgement and visible residue")
    func failedRetirementPreservesVisibleResidueForExactRetry() async throws {
        // Arrange
        let provider = BridgePaneProductSessionProviderGate()
        let owner = try BridgePaneProductSessionOwner(
            paneSessionId: bridgeProductTestPaneSessionId,
            provider: provider
        )
        let installation = try await installFirstCandidate(in: owner)
        try await openBridgePaneProductSession(installation)
        let contentReply = try await startContentReply(
            installation: installation,
            provider: provider,
            identitySuffix: "visible-retry-residue"
        )
        await provider.holdLifecycleAcknowledgements()

        // Act
        let firstRetirementTask = Task {
            await owner.retire(reason: .pageReload)
        }
        let firstAcknowledgement = await provider.waitForLifecycleAcknowledgement(count: 1)
        let retiringSnapshot = await owner.snapshot()
        await provider.releaseLifecycleAcknowledgements(result: false)
        let firstResult = await firstRetirementTask.value
        let failedSnapshot = await owner.snapshot()

        // Assert
        #expect(!retiringSnapshot.hasZeroResidue)
        #expect(retiringSnapshot.pendingLifecycleAcknowledgementCount == 1)
        #expect(firstResult == .revocationFailed)
        #expect(!failedSnapshot.hasZeroResidue)
        #expect(failedSnapshot.pendingLifecycleAcknowledgementCount == 1)

        await provider.succeedLifecycleAcknowledgements()
        let retryResult = await owner.retire(reason: .pageReload)
        let acknowledgements = await provider.lifecycleAcknowledgements
        #expect(retryResult == .retired)
        #expect(acknowledgements.count >= 2)
        #expect(acknowledgements[0] == firstAcknowledgement)
        #expect(acknowledgements[1] == firstAcknowledgement)
        #expect(await owner.snapshot() == .empty)
        _ = try? await contentReply.value
    }

    @Test("the sole live scheme handler delegates every product route to the session router")
    func liveSchemeOwnershipIsProductOnly() throws {
        // Arrange
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let bootstrapSource = try String(
            contentsOf: projectRoot.appending(
                path: "Sources/AgentStudio/Features/Bridge/Runtime/BridgePaneController+Bootstrap.swift"
            ),
            encoding: .utf8
        )
        let schemeHandlerSource = try String(
            contentsOf: projectRoot.appending(
                path: "Sources/AgentStudio/Features/Bridge/Transport/BridgeSchemeHandler.swift"
            ),
            encoding: .utf8
        )

        // Act / Assert
        #expect(bootstrapSource.contains("BridgePaneProductSessionOwner"))
        #expect(bootstrapSource.contains("BridgeProductSchemeSessionRouter"))
        #expect(schemeHandlerSource.contains("BridgeProductSchemeSessionRouter"))
        #expect(schemeHandlerSource.contains("BridgeProductWireContract.commandRoute"))
        #expect(schemeHandlerSource.contains("BridgeProductWireContract.streamRoute"))
        #expect(schemeHandlerSource.contains("BridgeProductWireContract.contentRoute"))
        #expect(!bootstrapSource.contains("rpcDispatcher: input.rpcDispatcher"))
        #expect(!schemeHandlerSource.contains("case rpcCommand"))
    }
}

private func installFirstCandidate(
    in owner: BridgePaneProductSessionOwner
) async throws -> BridgeProductSessionInstallation {
    let candidate = try await owner.prepareCandidate()
    #expect(await owner.activatePreparedCandidate(candidate) == .activated)
    return candidate
}

private func waitForActiveWorkerInstance(
    _ workerInstanceId: String,
    in owner: BridgePaneProductSessionOwner
) async -> Bool {
    for _ in 0..<512 {
        if await owner.activeInstallation?.bootstrap.workerInstanceId == workerInstanceId {
            return true
        }
        await Task.yield()
    }
    return false
}

func openBridgePaneProductSession(
    _ installation: BridgeProductSessionInstallation
) async throws {
    let requestBody = try JSONSerialization.data(
        withJSONObject: [
            "kind": "workerSession.open",
            "paneSessionId": installation.bootstrap.paneSessionId,
            "request": NSNull(),
            "requestId": "request-open-pane-owner",
            "requestSequence": 1,
            "wireVersion": BridgeProductWireContract.version,
            "workerInstanceId": installation.bootstrap.workerInstanceId,
        ],
        options: [.sortedKeys]
    )
    let capabilityHeader = try BridgeProductCapabilityHeaderEncoding.encode(
        installation.capabilityBytes
    )
    let observation = try await collectBridgeProductSchemeReply(
        adapter: installation.productAdapter,
        request: bridgeProductSchemeRequest(
            route: BridgeProductWireContract.commandRoute,
            capability: capabilityHeader,
            body: requestBody
        )
    )
    #expect(observation.response?.statusCode == 200)
}

func startBridgePaneProductMetadataReply(
    installation: BridgeProductSessionInstallation,
    provider: BridgePaneProductSessionProviderGate,
    handler: BridgeSchemeHandler? = nil
) async throws -> Task<BridgeProductSchemeReplyObservation, any Error> {
    let body = try JSONSerialization.data(
        withJSONObject: [
            "kind": "metadataStream.open",
            "metadataStreamId": "metadata-pane-owner",
            "paneSessionId": installation.bootstrap.paneSessionId,
            "resumeFromStreamSequence": NSNull(),
            "wireVersion": BridgeProductWireContract.version,
            "workerInstanceId": installation.bootstrap.workerInstanceId,
        ],
        options: [.sortedKeys]
    )
    let capabilityHeader = try BridgeProductCapabilityHeaderEncoding.encode(
        installation.capabilityBytes
    )
    let replyTask = Task {
        try await collectPaneOwnerProductReply(
            handler: handler,
            adapter: installation.productAdapter,
            request: bridgeProductSchemeRequest(
                route: BridgeProductWireContract.streamRoute,
                capability: capabilityHeader,
                body: body
            )
        )
    }
    await provider.waitUntilMetadataProducerStarted()
    return replyTask
}

private func startContentReply(
    installation: BridgeProductSessionInstallation,
    provider: BridgePaneProductSessionProviderGate,
    identitySuffix: String,
    handler: BridgeSchemeHandler? = nil
) async throws -> Task<BridgeProductSchemeReplyObservation, any Error> {
    let request = try paneOwnerContentRequest(
        installation: installation,
        identitySuffix: identitySuffix
    )
    let capabilityHeader = try BridgeProductCapabilityHeaderEncoding.encode(
        installation.capabilityBytes
    )
    let replyTask = Task {
        try await collectPaneOwnerProductReply(
            handler: handler,
            adapter: installation.productAdapter,
            request: bridgeProductSchemeRequest(
                route: BridgeProductWireContract.contentRoute,
                capability: capabilityHeader,
                body: try JSONEncoder().encode(request)
            )
        )
    }
    await provider.waitUntilContentProducerStarted()
    return replyTask
}

private func collectPaneOwnerProductReply(
    handler: BridgeSchemeHandler?,
    adapter: BridgeProductSchemeAdapter,
    request: URLRequest
) async throws -> BridgeProductSchemeReplyObservation {
    if let handler {
        return try await collectBridgeSchemeHandlerProductReply(
            handler: handler,
            request: request
        )
    }
    return try await collectBridgeProductSchemeReply(
        adapter: adapter,
        request: request
    )
}

private func paneOwnerProductCallSchemeRequest(
    installation: BridgeProductSessionInstallation,
    identitySuffix: String
) throws -> URLRequest {
    let body = try JSONSerialization.data(
        withJSONObject: [
            "call": [
                "method": "review.markFileViewed",
                "request": ["itemId": "item-\(identitySuffix)"],
            ],
            "kind": "product.call",
            "paneSessionId": installation.bootstrap.paneSessionId,
            "requestId": "product-call-\(identitySuffix)",
            "requestSequence": 2,
            "wireVersion": BridgeProductWireContract.version,
            "workerDerivationEpoch": 1,
            "workerInstanceId": installation.bootstrap.workerInstanceId,
        ],
        options: [.sortedKeys]
    )
    return bridgeProductSchemeRequest(
        route: BridgeProductWireContract.commandRoute,
        capability: try BridgeProductCapabilityHeaderEncoding.encode(
            installation.capabilityBytes
        ),
        body: body
    )
}

private func collectBridgeSchemeHandlerProductReply(
    handler: BridgeSchemeHandler,
    request: URLRequest
) async throws -> BridgeProductSchemeReplyObservation {
    var body = Data()
    var events: [BridgeProductSchemeReplyObservation.Event] = []
    var response: HTTPURLResponse?
    for try await result in handler.reply(for: request) {
        switch result {
        case .response(let emittedResponse):
            events.append(.response)
            response = emittedResponse as? HTTPURLResponse
        case .data(let chunk):
            events.append(.data)
            body.append(chunk)
        @unknown default:
            Issue.record("Unexpected URL scheme task result")
        }
    }
    return .init(body: body, events: events, response: response)
}

private func waitUntilProductRouterIsFenced(
    _ router: BridgeProductSchemeSessionRouter
) async {
    for _ in 0..<512 {
        if await router.activeInstallation == nil { return }
        await Task.yield()
    }
    Issue.record("Product router did not fence active admission")
}

private func paneOwnerContentRequest(
    installation: BridgeProductSessionInstallation,
    identitySuffix: String
) throws -> BridgeProductContentRequest {
    let requestJSON = """
        {
          "kind": "content.open",
          "wireVersion": 2,
          "paneSessionId": "\(installation.bootstrap.paneSessionId)",
          "workerDerivationEpoch": 1,
          "workerInstanceId": "\(installation.bootstrap.workerInstanceId)",
          "contentRequestId": "content-request-\(identitySuffix)",
          "leaseId": "lease-\(identitySuffix)",
          "contentKind": "file.content",
          "descriptor": {
            "contentKind": "file.content",
            "declaredByteLength": 3,
            "descriptorId": "file-descriptor-\(identitySuffix)",
            "encoding": "utf-8",
            "expectedSha256": "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
            "fileId": "file-\(identitySuffix)",
            "maximumBytes": 2097152,
            "source": {
              "repoId": "00000000-0000-4000-8000-000000000001",
              "rootRevisionToken": null,
              "sourceCursor": "source-cursor-\(identitySuffix)",
              "sourceId": "source-\(identitySuffix)",
              "subscriptionGeneration": 11,
              "worktreeId": "00000000-0000-4000-8000-000000000002"
            },
            "window": {
              "kind": "prefix",
              "maximumBytes": 2097152,
              "maximumLines": 10000,
              "startByte": 0
            }
          }
        }
        """
    return try BridgeProductStrictJSON.decode(
        BridgeProductContentRequest.self,
        from: Data(requestJSON.utf8)
    )
}

actor BridgePaneProductSessionProviderGate: BridgeProductSchemeProvider {
    private enum AcknowledgementMode {
        case fail
        case failOnceThenHold
        case hold
        case succeed
    }

    private var acknowledgementMode = AcknowledgementMode.succeed
    private var acknowledgementWaiters: [CheckedContinuation<Bool, Never>] = []
    private var invocationWaiters: [(Int, CheckedContinuation<BridgeProductProducerLifecycleAcknowledgement, Never>)] =
        []
    private let contentOperation = BridgeProductSessionProducerOperationGate()
    private let metadataOperation = BridgeProductSessionProducerOperationGate()
    private var productCallResponseContinuation: CheckedContinuation<Void, Never>?
    private var productCallStartWaiters: [CheckedContinuation<Void, Never>] = []
    private var shouldHoldProductCallResponses = false
    private(set) var lifecycleAcknowledgements: [BridgeProductProducerLifecycleAcknowledgement] = []
    private(set) var lifecycleAcknowledgementsWereReleased = false

    func response(
        for request: BridgeProductControlRequest
    ) async -> BridgeProductControlResponse {
        do {
            switch request {
            case .workerSessionOpen:
                return try .workerSessionAccepted(correlating: request)
            case .productCall:
                let waiters = productCallStartWaiters
                productCallStartWaiters.removeAll()
                for waiter in waiters { waiter.resume() }
                if shouldHoldProductCallResponses {
                    await withCheckedContinuation { continuation in
                        productCallResponseContinuation = continuation
                    }
                }
                return try .callCompleted(
                    correlating: request,
                    result: .reviewMarkFileViewed
                )
            case .subscriptionOpen, .subscriptionUpdateBatch, .subscriptionCancel,
                .workerSessionResync:
                preconditionFailure("Unexpected pane-owner control request")
            }
        } catch {
            preconditionFailure("Could not build pane-owner control response")
        }
    }

    func runMetadataProducer(
        request: BridgeProductMetadataStreamRequest,
        lease: BridgeProductProducerLease,
        session: BridgeProductSession
    ) async {
        do {
            _ = try await session.enqueueRequiredProducerOpeningFrame(
                for: lease,
                build: { sequence in
                    try bridgeProductMetadataAcceptedFrame(
                        request: request,
                        streamSequence: sequence,
                        resumeDisposition: .snapshotRequired
                    )
                }
            )
            await metadataOperation.run(lease)
        } catch {
            Issue.record("Metadata producer failed before retirement")
        }
    }

    func runContentProducer(
        request: BridgeProductContentRequest,
        lease: BridgeProductProducerLease,
        session: BridgeProductSession
    ) async {
        do {
            _ = try await session.enqueueRequiredProducerOpeningFrame(
                for: lease,
                build: { _ in producerRegistryContentOpeningFrame(for: request) }
            )
            await contentOperation.run(lease)
        } catch {
            Issue.record("Content producer failed before retirement")
        }
    }

    func acknowledgeLifecycle(
        _ acknowledgement: BridgeProductProducerLifecycleAcknowledgement
    ) async -> Bool {
        lifecycleAcknowledgements.append(acknowledgement)
        resumeInvocationWaiters()
        switch acknowledgementMode {
        case .fail:
            return false
        case .failOnceThenHold:
            acknowledgementMode = .hold
            return false
        case .hold:
            return await withCheckedContinuation { continuation in
                acknowledgementWaiters.append(continuation)
            }
        case .succeed:
            return true
        }
    }

    func waitUntilMetadataProducerStarted() async {
        _ = await metadataOperation.waitUntilStarted()
    }

    func waitUntilContentProducerStarted() async {
        _ = await contentOperation.waitUntilStarted()
    }

    func holdProductCallResponses() {
        shouldHoldProductCallResponses = true
    }

    func waitUntilProductCallStarted() async {
        if productCallResponseContinuation != nil { return }
        await withCheckedContinuation { continuation in
            productCallStartWaiters.append(continuation)
        }
    }

    func releaseProductCallResponses() {
        shouldHoldProductCallResponses = false
        productCallResponseContinuation?.resume()
        productCallResponseContinuation = nil
    }

    func holdLifecycleAcknowledgements() {
        acknowledgementMode = .hold
        lifecycleAcknowledgementsWereReleased = false
    }

    func failLifecycleAcknowledgements() {
        acknowledgementMode = .fail
    }

    func failNextLifecycleAcknowledgementThenHoldRetries() {
        acknowledgementMode = .failOnceThenHold
        lifecycleAcknowledgementsWereReleased = false
    }

    func succeedLifecycleAcknowledgements() {
        acknowledgementMode = .succeed
    }

    func releaseLifecycleAcknowledgements(result: Bool) {
        acknowledgementMode = result ? .succeed : .fail
        lifecycleAcknowledgementsWereReleased = true
        let waiters = acknowledgementWaiters
        acknowledgementWaiters.removeAll()
        for waiter in waiters { waiter.resume(returning: result) }
    }

    func waitForLifecycleAcknowledgement(
        count: Int
    ) async -> BridgeProductProducerLifecycleAcknowledgement {
        if lifecycleAcknowledgements.count >= count {
            return lifecycleAcknowledgements[count - 1]
        }
        return await withCheckedContinuation { continuation in
            invocationWaiters.append((count, continuation))
        }
    }

    private func resumeInvocationWaiters() {
        let readyWaiters = invocationWaiters.filter { $0.0 <= lifecycleAcknowledgements.count }
        invocationWaiters.removeAll { $0.0 <= lifecycleAcknowledgements.count }
        for (count, waiter) in readyWaiters {
            waiter.resume(returning: lifecycleAcknowledgements[count - 1])
        }
    }
}

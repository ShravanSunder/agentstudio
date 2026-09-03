import AgentStudioCore
import AgentStudioGit
import AgentStudioInfrastructure
import CryptoKit
import Foundation
import Testing

@testable import AgentStudioBridge

@Suite("Bridge pane Review shared construction")
struct BridgePaneReviewSharedConstructionTests {
    @Test("shared Review construction performs no body reads before demand")
    func sharedConstructionPerformsNoReviewBodyReadsBeforeDemand() async throws {
        // Arrange
        let fixture = try BridgeSharedReviewConstructionFixture.make()
        defer { fixture.removeTestRoot() }

        // Act
        let binding = try await fixture.firstBinder.acquire(
            fixture.request(packageId: "package-metadata-only", generation: 1)
        )

        // Assert
        #expect(await fixture.gitClient.recordedDiffRequests().count == 1)
        #expect(await fixture.gitClient.recordedContentRequests().isEmpty)
        await binding.artifactPin.releaseAndWait()
    }

    @Test("first demand reads once and repeated demand uses the existing cache")
    func firstDemandReadsOnceAndSecondDemandUsesExistingCache() async throws {
        // Arrange
        let fixture = try BridgeSharedReviewConstructionFixture.make()
        defer { fixture.removeTestRoot() }
        let binding = try await fixture.firstBinder.acquire(
            fixture.request(packageId: "package-demand-cache", generation: 1)
        )
        let headHandle = try #require(
            binding.result.registeredContentHandles.first { $0.role == .head }
        )
        let productAdmission = try BridgeProductAdmissionTestContext.make()
        let cache = BridgeReviewContentLoaderCache(provider: fixture.firstProvider)

        // Act
        let readsBeforeDemand = await fixture.gitClient.recordedContentRequests()
        let first = try await cache.loadObserved(
            handle: headHandle,
            productAdmission: productAdmission.context
        )
        let second = try await cache.loadObserved(
            handle: headHandle,
            productAdmission: productAdmission.context
        )

        // Assert
        #expect(readsBeforeDemand.isEmpty)
        #expect(await fixture.gitClient.recordedContentRequests().count == 1)
        #expect(first.observation.cacheResult == .providerLoad)
        #expect(second.observation.cacheResult == .cacheHit)
        #expect(first.result.data == Data("head-a".utf8))
        #expect(second.result.data == first.result.data)
        await cache.closeAndDrain()
        productAdmission.close()
        await binding.artifactPin.releaseAndWait()
    }

    @Test("undemanded working-tree body fails closed after source advances")
    func undemandedWorkingTreeBodyFailsClosedAfterSourceAdvances() async throws {
        // Arrange
        let fixture = try BridgeSharedReviewConstructionFixture.make()
        defer { fixture.removeTestRoot() }
        let binding = try await fixture.firstBinder.acquire(
            fixture.request(packageId: "package-undemanded", generation: 1)
        )
        let headHandle = try #require(
            binding.result.registeredContentHandles.first { $0.role == .head }
        )
        let productAdmission = try BridgeProductAdmissionTestContext.make()
        let cache = BridgeReviewContentLoaderCache(provider: fixture.firstProvider)
        await fixture.advanceWorkingTree(to: "head-b")

        // Act
        let result = await Task {
            try await cache.load(
                handle: headHandle,
                productAdmission: productAdmission.context
            )
        }.result

        // Assert
        guard case .failure(let error) = result else {
            Issue.record("Undemanded stale working-tree body unexpectedly loaded")
            return
        }
        guard case .contentHashMismatch = error as? BridgeProviderFailure else {
            Issue.record("Expected contentHashMismatch, got \(error)")
            return
        }
        let cacheSnapshot = await cache.diagnosticSnapshot
        #expect(cacheSnapshot.cachedContentCount == 0)
        await cache.closeAndDrain()
        productAdmission.close()
        await binding.artifactPin.releaseAndWait()
    }

    @Test("demanded body remains cached after source advances")
    func demandedBodyRemainsCachedAfterSourceAdvances() async throws {
        // Arrange
        let fixture = try BridgeSharedReviewConstructionFixture.make()
        defer { fixture.removeTestRoot() }
        let binding = try await fixture.firstBinder.acquire(
            fixture.request(packageId: "package-demanded", generation: 1)
        )
        let headHandle = try #require(
            binding.result.registeredContentHandles.first { $0.role == .head }
        )
        let productAdmission = try BridgeProductAdmissionTestContext.make()
        let cache = BridgeReviewContentLoaderCache(provider: fixture.firstProvider)
        let first = try await cache.loadObserved(
            handle: headHandle,
            productAdmission: productAdmission.context
        )
        await fixture.advanceWorkingTree(to: "head-b")

        // Act
        let second = try await cache.loadObserved(
            handle: headHandle,
            productAdmission: productAdmission.context
        )

        // Assert
        #expect(first.result.data == Data("head-a".utf8))
        #expect(second.result.data == first.result.data)
        #expect(second.observation.cacheResult == .cacheHit)
        #expect(await fixture.gitClient.recordedContentRequests().count == 1)
        await cache.closeAndDrain()
        productAdmission.close()
        await binding.artifactPin.releaseAndWait()
    }

    @Test("exact duplicate Review panes share metadata construction without body reads")
    func exactDuplicateReviewConstructionSharesMetadataWithoutBodyReads() async throws {
        // Arrange
        let fixture = try BridgeSharedReviewConstructionFixture.make()
        defer { fixture.removeTestRoot() }

        // Act
        async let firstAcquisition = fixture.firstBinder.acquire(
            fixture.request(packageId: "package-pane-one", generation: 1)
        )
        async let secondAcquisition = fixture.secondBinder.acquire(
            fixture.request(packageId: "package-pane-two", generation: 7)
        )
        let (firstBinding, secondBinding) = try await (firstAcquisition, secondAcquisition)

        // Assert
        #expect(
            firstBinding.artifactPin.constructionLease.entryNonce
                == secondBinding.artifactPin.constructionLease.entryNonce
        )
        #expect(
            firstBinding.artifactPin.constructionLease.leaseNonce
                != secondBinding.artifactPin.constructionLease.leaseNonce
        )
        #expect(firstBinding.result.package.packageId == "package-pane-one")
        #expect(secondBinding.result.package.packageId == "package-pane-two")
        #expect(firstBinding.result.package.reviewGeneration.rawValue == 1)
        #expect(secondBinding.result.package.reviewGeneration.rawValue == 7)
        #expect(await fixture.gitClient.recordedDiffRequests().count == 1)
        #expect(await fixture.gitClient.recordedContentRequests().isEmpty)

        await firstBinding.artifactPin.releaseAndWait()
        await secondBinding.artifactPin.releaseAndWait()
        await fixture.waitUntilConstructionEntryIsRemoved()
        let drainedConstructionSnapshot = await fixture.coordinator.snapshot()
        let drainedSchedulerSnapshot = await fixture.scheduler.snapshot()
        #expect(drainedConstructionSnapshot.entryCount == 0)
        #expect(drainedConstructionSnapshot.waiterCount == 0)
        #expect(drainedConstructionSnapshot.leaseCount == 0)
        #expect(drainedConstructionSnapshot.payloadCount == 0)
        #expect(drainedConstructionSnapshot.inFlightCount == 0)
        #expect(drainedConstructionSnapshot.locatorCount == 0)
        #expect(drainedConstructionSnapshot.drainingTombstoneCount == 0)
        #expect(drainedConstructionSnapshot.retainedArtifactByteCount == 0)
        #expect(drainedSchedulerSnapshot.queuedCountByOperationClass.isEmpty)
        #expect(drainedSchedulerSnapshot.runningCountByOperationClass.isEmpty)
        #expect(drainedSchedulerSnapshot.drainingCountByOperationClass.isEmpty)
        #expect(drainedSchedulerSnapshot.activeOperationIds.isEmpty)
        #expect(drainedSchedulerSnapshot.occupiedSlotIds.isEmpty)
        #expect(drainedSchedulerSnapshot.logicalWaiterCount == 0)
        #expect(drainedSchedulerSnapshot.scheduledDeadlineCount == 0)
        await fixture.scheduler.shutdown()
    }

    @MainActor
    @Test("logical cancellation and close retain backing until the physical Git read returns")
    func cancellationAndCloseRetainBackingUntilPhysicalReturn() async throws {
        // Arrange
        let baseLocator = GitContentLocator(
            target: .commit(String(repeating: "a", count: 40)),
            path: "Sources/App.swift"
        )
        let physicalReadGate = BridgeGitContentReadGate()
        let fixture = try BridgeSharedReviewConstructionFixture.make(
            contentReadGateByLocator: [baseLocator: physicalReadGate]
        )
        defer { fixture.removeTestRoot() }
        let binding = try await fixture.firstBinder.acquire(
            fixture.request(packageId: "package-held-read", generation: 1)
        )
        let baseHandle = try #require(
            binding.result.registeredContentHandles.first { $0.role == .base }
        )
        guard case .reviewTemplate = binding.artifactPin.constructionLease.artifact else {
            Issue.record("Expected a shared Review template")
            return
        }
        let productAdmission = try BridgeProductAdmissionTestContext.make()
        let publicationCoordinator = BridgeReviewPublicationCoordinator()
        let preparedPublication = try #require(
            await BridgeReviewPreparedPublication.prepare(
                BridgeReviewPublicationCandidate(
                    package: binding.result.package,
                    delta: nil,
                    contentHandles: binding.result.registeredContentHandles,
                    artifactPin: binding.artifactPin
                )
            )
        )
        let token = try #require(
            publicationCoordinator.stage(
                preparedPublication,
                productAdmission: productAdmission.context
            )
        )
        guard
            case .committed = publicationCoordinator.commit(
                token,
                productAdmission: productAdmission.context,
                captureCommittedPresentation: reviewCommittedPresentationSnapshot,
                presentCommitted: { _ in }
            )
        else {
            Issue.record("Expected the shared Review publication to commit")
            return
        }
        let loadTask = Task {
            try await fixture.firstProvider.loadContent(
                BridgeContentLoadRequest(handle: baseHandle, requestedGeneration: 1)
            )
        }
        await physicalReadGate.waitUntilStarted()

        // Act
        loadTask.cancel()
        let logicalResult = await loadTask.result
        productAdmission.close()
        let closeDrain = publicationCoordinator.close()
        let repeatedCloseDrain = publicationCoordinator.close()
        let releaseTask = Task {
            await closeDrain.releaseAndWait()
        }
        _ = await fixture.constructionEventProbe.waitFor(.entryRemoved)

        // Assert
        guard case .failure(let logicalError) = logicalResult else {
            Issue.record("Cancelled logical content load unexpectedly succeeded")
            return
        }
        #expect(logicalError is CancellationError)
        #expect(closeDrain.artifactPins == [binding.artifactPin])
        #expect(repeatedCloseDrain.artifactPins.isEmpty)
        #expect(repeatedCloseDrain.priorReleaseTask == nil)
        #expect(await fixture.firstClient.registeredContentLocatorCount() > 0)
        #expect(
            await fixture.scheduler.snapshot().drainingCountByOperationClass[.selectedVisibleContent]
                == 1
        )

        await physicalReadGate.release()
        await releaseTask.value
        #expect(await fixture.firstClient.registeredContentLocatorCount() == 0)
        #expect(
            await fixture.scheduler.snapshot().drainingCountByOperationClass[.selectedVisibleContent]
                == nil
        )
    }

    @MainActor
    @Test("pane close joins a rejected publication pin that is still physically draining")
    func closeJoinsRejectedPublicationPhysicalDrain() async throws {
        // Arrange
        let baseLocator = GitContentLocator(
            target: .commit(String(repeating: "a", count: 40)),
            path: "Sources/App.swift"
        )
        let physicalReadGate = BridgeGitContentReadGate()
        let fixture = try BridgeSharedReviewConstructionFixture.make(
            contentReadGateByLocator: [baseLocator: physicalReadGate]
        )
        defer { fixture.removeTestRoot() }
        let binding = try await fixture.firstBinder.acquire(
            fixture.request(packageId: "package-rejected-read", generation: 1)
        )
        let baseHandle = try #require(
            binding.result.registeredContentHandles.first { $0.role == .base }
        )
        guard case .reviewTemplate = binding.artifactPin.constructionLease.artifact else {
            Issue.record("Expected a shared Review template")
            return
        }
        let productAdmission = try BridgeProductAdmissionTestContext.make()
        let publicationCoordinator = BridgeReviewPublicationCoordinator()
        let preparedPublication = try #require(
            await BridgeReviewPreparedPublication.prepare(
                BridgeReviewPublicationCandidate(
                    package: binding.result.package,
                    delta: nil,
                    contentHandles: binding.result.registeredContentHandles,
                    artifactPin: binding.artifactPin
                )
            )
        )
        let token = try #require(
            publicationCoordinator.stage(
                preparedPublication,
                productAdmission: productAdmission.context
            )
        )
        let loadTask = Task {
            try await fixture.firstProvider.loadContent(
                BridgeContentLoadRequest(handle: baseHandle, requestedGeneration: 1)
            )
        }
        await physicalReadGate.waitUntilStarted()

        // Act
        loadTask.cancel()
        _ = await loadTask.result
        #expect(
            publicationCoordinator.rejectReservation(
                token,
                productAdmission: productAdmission.context
            ) == .rejectedBeforeCommit
        )
        _ = await fixture.constructionEventProbe.waitFor(.entryRemoved)
        productAdmission.close()
        let closeDrain = publicationCoordinator.close()
        let closeDrainTask = Task {
            await closeDrain.releaseAndWait()
        }

        // Assert
        #expect(closeDrain.artifactPins.isEmpty)
        #expect(closeDrain.priorReleaseTask != nil)
        #expect(await fixture.firstClient.registeredContentLocatorCount() > 0)

        await physicalReadGate.release()
        await closeDrainTask.value
        #expect(await fixture.firstClient.registeredContentLocatorCount() == 0)
        #expect((await fixture.coordinator.snapshot()).entryCount == 0)
    }

    @Test("pre-publication result release waits for physical backing cleanup")
    func prePublicationResultReleaseWaitsForPhysicalCleanup() async throws {
        // Arrange
        let baseLocator = GitContentLocator(
            target: .commit(String(repeating: "a", count: 40)),
            path: "Sources/App.swift"
        )
        let physicalReadGate = BridgeGitContentReadGate()
        let fixture = try BridgeSharedReviewConstructionFixture.make(
            contentReadGateByLocator: [baseLocator: physicalReadGate]
        )
        defer { fixture.removeTestRoot() }
        let binding = try await fixture.firstBinder.acquire(
            fixture.request(packageId: "package-stale-before-publication", generation: 1)
        )
        let baseHandle = try #require(
            binding.result.registeredContentHandles.first { $0.role == .base }
        )
        guard case .reviewTemplate = binding.artifactPin.constructionLease.artifact else {
            Issue.record("Expected a shared Review template")
            return
        }
        let constructionResult = BridgeReviewPackageConstructionResult(
            result: binding.result,
            artifactPin: binding.artifactPin
        )
        let loadTask = Task {
            try await fixture.firstProvider.loadContent(
                BridgeContentLoadRequest(handle: baseHandle, requestedGeneration: 1)
            )
        }
        await physicalReadGate.waitUntilStarted()

        // Act
        loadTask.cancel()
        _ = await loadTask.result
        let releaseTask = Task {
            await constructionResult.releaseArtifactPin()
        }
        _ = await fixture.constructionEventProbe.waitFor(.entryRemoved)

        // Assert
        #expect(await fixture.firstClient.registeredContentLocatorCount() > 0)

        await physicalReadGate.release()
        await releaseTask.value
        #expect(await fixture.firstClient.registeredContentLocatorCount() == 0)
        #expect((await fixture.coordinator.snapshot()).entryCount == 0)
    }

    @Test("duplicate panes install shared locators and demand content independently")
    func duplicatePanesInstallSharedLocatorsAndDemandIndependently() async throws {
        // Arrange
        let fixture = try BridgeSharedReviewConstructionFixture.make()
        defer { fixture.removeTestRoot() }
        async let firstAcquire = fixture.firstBinder.acquire(
            fixture.request(packageId: "package-a1", generation: 1)
        )
        async let secondAcquire = fixture.secondBinder.acquire(
            fixture.request(packageId: "package-a2", generation: 7)
        )
        let (firstA, secondA) = try await (firstAcquire, secondAcquire)
        let firstAHandle = try #require(firstA.result.registeredContentHandles.last)
        let secondAHandle = try #require(secondA.result.registeredContentHandles.last)
        guard case .reviewTemplate = firstA.artifactPin.constructionLease.artifact else {
            Issue.record("Expected a shared Review template")
            return
        }

        // Act
        let firstContent = try await fixture.firstProvider.loadContent(
            BridgeContentLoadRequest(handle: firstAHandle, requestedGeneration: 1)
        )
        let secondContent = try await fixture.secondProvider.loadContent(
            BridgeContentLoadRequest(handle: secondAHandle, requestedGeneration: 7)
        )

        // Assert
        #expect(
            firstA.artifactPin.constructionLease.entryNonce
                == secondA.artifactPin.constructionLease.entryNonce
        )
        #expect(
            firstA.artifactPin.constructionLease.leaseNonce
                != secondA.artifactPin.constructionLease.leaseNonce
        )
        #expect(firstContent.data == Data("head-a".utf8))
        #expect(secondContent.data == firstContent.data)
        #expect(await fixture.gitClient.recordedContentRequests().count == 2)
        await firstA.artifactPin.releaseAndWait()
        let peerRetainedSnapshot = await fixture.coordinator.snapshot()
        #expect(peerRetainedSnapshot.entryCount == 1)
        #expect(peerRetainedSnapshot.leaseCount == 1)
        await secondA.artifactPin.releaseAndWait()
        let snapshot = await fixture.coordinator.snapshot()
        #expect(snapshot.entryCount == 0)
        #expect(snapshot.leaseCount == 0)
        #expect(snapshot.locatorCount == 0)
        #expect(await fixture.firstClient.registeredContentLocatorCount() == 0)
        #expect(await fixture.secondClient.registeredContentLocatorCount() == 0)
    }

    @Test("symbolic commit endpoints resolve to concrete OIDs before keying")
    func commitEndpointsResolveBeforeSemanticKeying() async throws {
        // Arrange
        let fixture = try BridgeSharedReviewConstructionFixture.make(baseRef: "main")
        defer { fixture.removeTestRoot() }

        // Act
        let first = try await fixture.firstBinder.acquire(
            fixture.request(packageId: "package-a", generation: 1)
        )
        await fixture.gitClient.replaceResolvedRevision(
            GitResolvedRevision(oid: String(repeating: "b", count: 40), shortName: "main"),
            for: .named("main")
        )
        let second = try await fixture.firstBinder.acquire(
            fixture.request(packageId: "package-b", generation: 2)
        )

        // Assert
        guard case .review(let firstKey) = first.artifactPin.constructionLease.key,
            case .review(let secondKey) = second.artifactPin.constructionLease.key
        else {
            Issue.record("Expected Review construction keys")
            return
        }
        #expect(firstKey.baseEndpoint.contentIdentity == String(repeating: "a", count: 40))
        #expect(secondKey.baseEndpoint.contentIdentity == String(repeating: "b", count: 40))
        #expect(
            first.artifactPin.constructionLease.entryNonce
                != second.artifactPin.constructionLease.entryNonce
        )
        await first.artifactPin.releaseAndWait()
        await second.artifactPin.releaseAndWait()
    }

    @Test("invalidation during endpoint resolution retries under the advanced epoch")
    func endpointResolutionIsFencedByConstructionEpoch() async throws {
        // Arrange
        let resolutionGate = BridgeGitContentReadGate()
        let fixture = try BridgeSharedReviewConstructionFixture.make(
            baseRef: "main",
            revisionResolutionGate: resolutionGate
        )
        defer { fixture.removeTestRoot() }
        let acquisition = Task {
            try await fixture.firstBinder.acquire(
                fixture.request(packageId: "package-current", generation: 1)
            )
        }
        await resolutionGate.waitUntilStarted()

        // Act
        let worktree = fixture.worktreeIdentityKey
        let advancedEpoch = await fixture.coordinator.invalidate(worktree: worktree)
        await fixture.gitClient.replaceResolvedRevision(
            GitResolvedRevision(oid: String(repeating: "b", count: 40), shortName: "main"),
            for: .named("main")
        )
        await fixture.advanceWorkingTree(to: "head-current")
        await resolutionGate.release()
        let binding = try await acquisition.value

        // Assert
        guard case .review(let key) = binding.artifactPin.constructionLease.key else {
            Issue.record("Expected a Review construction key")
            return
        }
        #expect(advancedEpoch.rawValue == 2)
        #expect(binding.artifactPin.constructionLease.epoch == advancedEpoch)
        #expect(key.baseEndpoint.contentIdentity == String(repeating: "b", count: 40))
        #expect(await fixture.gitClient.recordedRevisionResolutionRequests().count == 2)
        #expect(await fixture.gitClient.recordedDiffRequests().count == 1)
        #expect(binding.result.package.summary.filesChanged == 1)
        await binding.artifactPin.releaseAndWait()
    }

    @Test("unchanged same-pane handles retain exact generation locators until artifact cleanup")
    func unchangedHandlesRetainGenerationSpecificLocators() async throws {
        // Arrange
        let fixture = try BridgeSharedReviewConstructionFixture.make()
        defer { fixture.removeTestRoot() }
        let bindingA = try await fixture.firstBinder.acquire(
            fixture.request(packageId: "package-a", generation: 1)
        )
        let handleA = try #require(bindingA.result.registeredContentHandles.last)
        _ = await fixture.coordinator.invalidate(worktree: fixture.worktreeIdentityKey)
        let bindingB = try await fixture.firstBinder.acquire(
            fixture.request(packageId: "package-b", generation: 2)
        )
        let handleB = try #require(bindingB.result.registeredContentHandles.last)

        // Act / Assert: both exact locators coexist even though handleId is unchanged.
        #expect(handleA.handleId == handleB.handleId)
        #expect(handleA.reviewGeneration != handleB.reviewGeneration)
        #expect(
            try await fixture.firstProvider.loadContent(
                BridgeContentLoadRequest(handle: handleA, requestedGeneration: 1)
            ).data == Data("head-a".utf8)
        )
        #expect(
            try await fixture.firstProvider.loadContent(
                BridgeContentLoadRequest(handle: handleB, requestedGeneration: 2)
            ).data == Data("head-a".utf8)
        )

        await bindingA.artifactPin.releaseAndWait()
        let retiredA = await Task {
            try await fixture.firstProvider.loadContent(
                BridgeContentLoadRequest(handle: handleA, requestedGeneration: 1)
            )
        }.result
        guard case .failure = retiredA else {
            Issue.record("Retired A locator remained readable")
            return
        }
        #expect(
            try await fixture.firstProvider.loadContent(
                BridgeContentLoadRequest(handle: handleB, requestedGeneration: 2)
            ).data == Data("head-a".utf8)
        )
        await bindingB.artifactPin.releaseAndWait()
        #expect(await fixture.firstClient.registeredContentLocatorCount() == 0)
    }

    @Test("unchanged refresh candidate release preserves retained same-generation locators")
    func unchangedRefreshCandidateReleasePreservesRetainedSameGenerationLocators() async throws {
        // Arrange
        let fixture = try BridgeSharedReviewConstructionFixture.make()
        defer { fixture.removeTestRoot() }
        let request = fixture.request(packageId: "package-retained", generation: 1)
        let bindingA = try await fixture.firstBinder.acquire(request)
        let handleA = try #require(bindingA.result.registeredContentHandles.last)
        guard case .reviewTemplate(let templateA) = bindingA.artifactPin.constructionLease.artifact else {
            Issue.record("Expected retained Review backing A")
            return
        }
        let backingA = try #require(templateA.backing)
        let locatorCountAfterA = await fixture.firstClient.registeredContentLocatorCount()
        #expect(backingA.uninstallOperationCount == 1)
        let bindingAJoin = try await fixture.firstBinder.acquire(request)
        #expect(await fixture.firstClient.registeredContentLocatorCount() == locatorCountAfterA)
        #expect(backingA.uninstallOperationCount == 1)
        await bindingAJoin.artifactPin.releaseAndWait()
        _ = await fixture.coordinator.invalidate(worktree: fixture.worktreeIdentityKey)
        let bindingB = try await fixture.firstBinder.acquire(request)
        let handleB = try #require(bindingB.result.registeredContentHandles.last)
        #expect(handleA.handleId == handleB.handleId)
        #expect(handleA.reviewGeneration == handleB.reviewGeneration)

        // Act
        await bindingB.artifactPin.releaseAndWait()

        // Assert
        #expect(
            try await fixture.firstProvider.loadContent(
                BridgeContentLoadRequest(handle: handleA, requestedGeneration: 1)
            ).data == Data("head-a".utf8)
        )
        await bindingA.artifactPin.releaseAndWait()
        #expect(await fixture.firstClient.registeredContentLocatorCount() == 0)
    }

    @Test("shared descriptor versions are semantic across pane generations")
    func sharedDescriptorVersionsAreGenerationNeutralAndSourceDerived() async throws {
        // Arrange
        let fixture = try BridgeSharedReviewConstructionFixture.make()
        defer { fixture.removeTestRoot() }
        let bindingA = try await fixture.firstBinder.acquire(
            fixture.request(packageId: "package-a", generation: 1)
        )
        let bindingB = try await fixture.firstBinder.acquire(
            fixture.request(packageId: "package-b", generation: 9)
        )
        let descriptorA = try #require(bindingA.result.package.itemsById.values.first)
        let descriptorB = try #require(bindingB.result.package.itemsById.values.first)
        let handleA = try #require(bindingA.result.registeredContentHandles.first)
        let handleB = try #require(bindingB.result.registeredContentHandles.first)

        // Act
        await fixture.advanceWorkingTree(to: "head-semantic-change")
        _ = await fixture.coordinator.invalidate(worktree: fixture.worktreeIdentityKey)
        let bindingC = try await fixture.firstBinder.acquire(
            fixture.request(packageId: "package-c", generation: 10)
        )
        let descriptorC = try #require(bindingC.result.package.itemsById.values.first)

        // Assert
        #expect(descriptorA.itemVersion == descriptorB.itemVersion)
        #expect(descriptorA.itemVersion >= 0)
        #expect(descriptorA.itemVersion <= 9_007_199_254_740_991)
        #expect(descriptorC.itemVersion != descriptorA.itemVersion)
        #expect(bindingA.result.package.reviewGeneration != bindingB.result.package.reviewGeneration)
        #expect(handleA.reviewGeneration != handleB.reviewGeneration)
        await bindingC.artifactPin.releaseAndWait()
        await bindingB.artifactPin.releaseAndWait()
        await bindingA.artifactPin.releaseAndWait()
    }

}

struct BridgeSharedReviewConstructionFixture: @unchecked Sendable {
    let testRoot: URL
    let repositoryPath: URL
    let coordinator: BridgeWorktreeProductConstructionCoordinator
    let constructionEventProbe: BridgeWorktreeProductConstructionEventProbe
    let scheduler: BridgeGitReadScheduler
    let gitClient: AgentStudioGitLocalClientFake
    let firstClient: AgentStudioGitBridgeReviewDataClient<AgentStudioGitLocalClientFake>
    let secondClient: AgentStudioGitBridgeReviewDataClient<AgentStudioGitLocalClientFake>
    let firstProvider: BridgeGitReviewSourceProvider
    let secondProvider: BridgeGitReviewSourceProvider
    let firstBinder: BridgePaneReviewSharedConstructionBinder
    let secondBinder: BridgePaneReviewSharedConstructionBinder
    let baseEndpoint: BridgeSourceEndpoint
    let headEndpoint: BridgeSourceEndpoint

    static func make(
        baseRef: String = String(repeating: "a", count: 40),
        contributionDiffSnapshot: GitContributionDiffSnapshot? = nil,
        contentReadGateByLocator: [GitContentLocator: BridgeGitContentReadGate] = [:],
        revisionResolutionGate: BridgeGitContentReadGate? = nil,
        schedulerEventSink: BridgeGitReadSchedulerEventSink? = nil
    ) throws -> Self {
        let (testRoot, repositoryPath) = try makeFixturePaths()
        let baseOID = String(repeating: "a", count: 40)
        let endpointRepoId = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let endpointWorktreeId = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let baseEndpoint = BridgeSourceEndpoint(
            endpointId: "base",
            kind: .gitRef,
            repoId: endpointRepoId,
            worktreeId: endpointWorktreeId,
            label: "Base",
            createdAtUnixMilliseconds: 0,
            contentSetHash: nil,
            providerIdentity: baseRef
        )
        let headEndpoint = BridgeSourceEndpoint(
            endpointId: "head",
            kind: .workingTree,
            repoId: endpointRepoId,
            worktreeId: endpointWorktreeId,
            label: "Working tree",
            createdAtUnixMilliseconds: 0,
            contentSetHash: nil,
            providerIdentity: "working-tree"
        )
        let gitClient = AgentStudioGitLocalClientFake(
            contributionDiffSnapshot: contributionDiffSnapshot,
            diffSnapshot: Self.diffSnapshot(headContent: "head-a"),
            contentByLocator: [
                GitContentLocator(target: .commit(baseOID), path: "Sources/App.swift"):
                    bridgeSharedReviewGitContentPayload("base-a"),
                GitContentLocator(target: .workingTree, path: "Sources/App.swift"):
                    bridgeSharedReviewGitContentPayload("head-a"),
            ],
            resolvedRevisionByTarget: [
                .named(baseRef): GitResolvedRevision(oid: baseOID, shortName: baseRef)
            ],
            contentReadGateByLocator: contentReadGateByLocator,
            revisionResolutionGate: revisionResolutionGate
        )
        let scheduler = Self.makeScheduler(eventSink: schedulerEventSink)
        let firstContext = BridgeGitReadContext(
            scheduler: scheduler,
            worktreeKey: BridgeGitReadWorktreeKey(token: StableKey.fromPath(repositoryPath)),
            scopeKey: BridgeGitReadScopeKey(token: "pane-one")
        )
        let secondContext = BridgeGitReadContext(
            scheduler: scheduler,
            worktreeKey: BridgeGitReadWorktreeKey(token: StableKey.fromPath(repositoryPath)),
            scopeKey: BridgeGitReadScopeKey(token: "pane-two")
        )
        let firstClient = AgentStudioGitBridgeReviewDataClient(
            repositoryPath: repositoryPath,
            client: gitClient,
            gitReadContext: firstContext
        )
        let secondClient = AgentStudioGitBridgeReviewDataClient(
            repositoryPath: repositoryPath,
            client: gitClient,
            gitReadContext: secondContext
        )
        let firstProvider = BridgeGitReviewSourceProvider(client: firstClient)
        let secondProvider = BridgeGitReviewSourceProvider(client: secondClient)
        let (coordinator, constructionEventProbe) = makeConstructionCoordinator()
        return Self(
            testRoot: testRoot,
            repositoryPath: repositoryPath,
            coordinator: coordinator,
            constructionEventProbe: constructionEventProbe,
            scheduler: scheduler,
            gitClient: gitClient,
            firstClient: firstClient,
            secondClient: secondClient,
            firstProvider: firstProvider,
            secondProvider: secondProvider,
            firstBinder: BridgePaneReviewSharedConstructionBinder(
                coordinator: coordinator,
                pipeline: BridgeReviewPipeline(provider: firstProvider),
                repositoryPath: repositoryPath
            ),
            secondBinder: BridgePaneReviewSharedConstructionBinder(
                coordinator: coordinator,
                pipeline: BridgeReviewPipeline(provider: secondProvider),
                repositoryPath: repositoryPath
            ),
            baseEndpoint: baseEndpoint,
            headEndpoint: headEndpoint
        )
    }

    private static func makeFixturePaths() throws -> (
        testRoot: URL,
        repositoryPath: URL
    ) {
        let testRoot = FileManager.default.temporaryDirectory
            .appending(path: "bridge-review-shared-\(UUID().uuidString)")
        let repositoryPath = testRoot.appending(path: "repository")
        try FileManager.default.createDirectory(at: repositoryPath, withIntermediateDirectories: true)
        return (testRoot, repositoryPath)
    }

    private static func makeConstructionCoordinator() -> (
        BridgeWorktreeProductConstructionCoordinator,
        BridgeWorktreeProductConstructionEventProbe
    ) {
        let eventProbe = BridgeWorktreeProductConstructionEventProbe()
        return (
            BridgeWorktreeProductConstructionCoordinator(eventSink: eventProbe.eventSink),
            eventProbe
        )
    }

    func request(packageId: String, generation: BridgeReviewGeneration) -> BridgeReviewPipelineRequest {
        BridgeReviewPipelineRequest(
            packageId: packageId,
            query: makeBridgeReviewQuery(
                baseEndpointId: baseEndpoint.endpointId,
                headEndpointId: headEndpoint.endpointId
            ),
            baseEndpoint: baseEndpoint,
            headEndpoint: headEndpoint,
            checkpointIds: [],
            reviewGeneration: generation,
            generatedAtUnixMilliseconds: Int64(generation.rawValue)
        )
    }

    func preparedContributionRequest(
        packageId: String,
        generation: BridgeReviewGeneration
    ) async throws -> BridgeReviewPipelineRequest {
        let capture = try await firstProvider.captureContributionComparison(
            BridgeContributionComparisonRequest(
                symbolicTarget: .ref(name: "target"),
                baseEndpoint: baseEndpoint,
                headEndpoint: headEndpoint,
                reviewGenerationValue: generation.rawValue
            )
        )
        return try BridgeResolvedContributionRequestBuilder.build(
            request: request(packageId: packageId, generation: generation),
            symbolicTarget: .ref(name: "target"),
            capture: capture,
            reviewedSubjectLabel: "feature-review"
        )
    }

    var worktreeIdentityKey: BridgeWorktreeIdentityKey {
        let query = request(packageId: "worktree-identity", generation: 0).query
        return BridgeWorktreeIdentityKey(
            repoIdentity: query.repoId.uuidString,
            worktreeIdentity: query.worktreeId.uuidString,
            stableRootIdentity: StableKey.fromPath(repositoryPath)
        )
    }

    func advanceWorkingTree(to content: String) async {
        await gitClient.replaceDiffSnapshot(Self.diffSnapshot(headContent: content))
        await gitClient.replaceContent(
            bridgeSharedReviewGitContentPayload(content),
            for: GitContentLocator(target: .workingTree, path: "Sources/App.swift")
        )
    }

    func waitUntilConstructionEntryIsRemoved() async {
        for _ in 0..<100 {
            if await coordinator.snapshot().entryCount == 0 { return }
            await Task.yield()
        }
        Issue.record("Review construction entry did not drain")
    }

    func removeTestRoot() {
        try? FileManager.default.removeItem(at: testRoot)
    }

    private static func diffSnapshot(headContent: String) -> GitDiffSnapshot {
        GitDiffSnapshot(
            files: [
                GitDiffFile(
                    fileId: "app",
                    path: "Sources/App.swift",
                    previousPath: nil,
                    changeKind: .modified,
                    oldContentHash: bridgeSharedReviewGitBlobSHA1("base-a"),
                    newContentHash: bridgeSharedReviewGitBlobSHA1(headContent),
                    contentHashAlgorithm: "git-blob-sha1",
                    oldMode: nil,
                    newMode: nil,
                    additions: 1,
                    deletions: 1,
                    isBinary: false,
                    sizeBytes: Int64(headContent.utf8.count)
                )
            ]
        )
    }
}

private func bridgeSharedReviewGitContentPayload(_ content: String) -> GitContentPayload {
    let data = Data(content.utf8)
    return GitContentPayload(
        data: data,
        contentHash:
            "sha256:"
            + SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined(),
        contentHashAlgorithm: "sha256",
        isBinary: false
    )
}

private func bridgeSharedReviewGitBlobSHA1(_ content: String) -> String {
    Insecure.SHA1.hash(data: Data("blob \(content.utf8.count)\u{0}\(content)".utf8))
        .map { String(format: "%02x", $0) }
        .joined()
}

import AgentStudioInfrastructure
import AgentStudioTestSupport
import Foundation
import Testing

@testable import AgentStudioBridge

@Suite("Bridge development product host shared construction")
struct BridgeDevHostSharedConstructionTests {
    @Test("Review bootstrap uses the existing shared construction authority")
    func reviewBootstrapUsesSharedConstructionAuthority() async throws {
        // Arrange
        let repositoryURL = try FilesystemTestGitRepo.create(
            named: "bridge-development-product-host-shared-review"
        )
        defer { FilesystemTestGitRepo.destroy(repositoryURL) }
        let provider = BridgeDevelopmentSharedConstructionReviewProvider()
        let host = try await BridgeDevelopmentProductHost(
            source: BridgeDevelopmentProductSource(
                worktreeRoot: repositoryURL,
                reviewBase: "HEAD"
            ),
            makeReviewProvider: { _, _ in provider }
        )
        try await withShutdownDevelopmentProductHost(host) {
            let request = try makeDevelopmentBootstrapRequest(surface: "review")

            // Act
            _ = try await host.issueBootstrap(for: request)
            let snapshot = await provider.snapshot()

            // Assert
            #expect(snapshot.regularComparisonCount == 0)
            #expect(snapshot.sharedEndpointResolutionCount == 2)
            #expect(snapshot.sharedComparisonCount == 1)
            #expect(snapshot.sharedCaptureCount == 1)
            #expect(snapshot.sharedInstallCount == 1)
        }
    }

    @Test("a cancelled Review bootstrap cannot commit after its successor")
    func cancelledReviewBootstrapCannotCommitAfterSuccessor() async throws {
        // Arrange
        let repositoryURL = try FilesystemTestGitRepo.create(
            named: "bridge-development-product-host-overlap"
        )
        defer { FilesystemTestGitRepo.destroy(repositoryURL) }
        let comparisonGate = BridgeComparisonGate()
        let provider = BridgeDevelopmentSharedConstructionReviewProvider(
            comparisonGate: comparisonGate
        )
        let host = try await BridgeDevelopmentProductHost(
            source: BridgeDevelopmentProductSource(
                worktreeRoot: repositoryURL,
                reviewBase: "HEAD"
            ),
            makeReviewProvider: { _, _ in provider }
        )
        try await withShutdownDevelopmentProductHost(host) {
            let reviewRequest = try makeDevelopmentBootstrapRequest(surface: "review")
            let fileRequest = try makeDevelopmentBootstrapRequest(surface: "file")
            let abandonedBootstrap = Task {
                try await host.issueBootstrap(for: reviewRequest)
            }
            do {
                await comparisonGate.waitForStartedComparisonCount(1)

                // Act
                abandonedBootstrap.cancel()
                let successorBootstrap = Task {
                    try await host.issueBootstrap(for: fileRequest)
                }
                await comparisonGate.releaseAll()

                // Assert
                await #expect(throws: CancellationError.self) {
                    _ = try await abandonedBootstrap.value
                }
                _ = try await successorBootstrap.value
            } catch {
                abandonedBootstrap.cancel()
                await comparisonGate.releaseAll()
                _ = await abandonedBootstrap.result
                throw error
            }
        }
    }
}

private struct BridgeDevSharedReviewProviderSnapshot: Sendable {
    let regularComparisonCount: Int
    let sharedCaptureCount: Int
    let sharedComparisonCount: Int
    let sharedEndpointResolutionCount: Int
    let sharedInstallCount: Int
}

private actor BridgeDevelopmentSharedConstructionReviewProvider:
    BridgeSharedReviewConstructionSourceProvider
{
    func localDefaultBranch() async throws -> String? { nil }

    func captureContributionComparison(_ request: BridgeContributionComparisonRequest) async throws
        -> BridgeContributionComparisonCapture
    {
        throw BridgeProviderFailure.providerFailed(message: "Contribution capture not configured")
    }

    private let comparisonGate: BridgeComparisonGate?
    private var regularComparisonCount = 0
    private var sharedCaptureCount = 0
    private var sharedComparisonCount = 0
    private var sharedEndpointResolutionCount = 0
    private var sharedInstallCount = 0

    init(comparisonGate: BridgeComparisonGate? = nil) {
        self.comparisonGate = comparisonGate
    }

    func resolveEndpoint(
        _ request: BridgeEndpointResolutionRequest
    ) async throws -> BridgeSourceEndpoint {
        resolvedEndpoint(request.endpoint)
    }

    func compareEndpoints(
        _ request: BridgeEndpointComparisonRequest
    ) async throws -> BridgeEndpointComparison {
        regularComparisonCount += 1
        await comparisonGate?.waitUntilReleased()
        return BridgeEndpointComparison(
            baseEndpoint: request.baseEndpoint,
            headEndpoint: request.headEndpoint,
            changedFiles: []
        )
    }

    func readTree(_ request: BridgeTreeReadRequest) async throws -> BridgeTreeReadResult {
        BridgeTreeReadResult(endpoint: request.endpoint, descriptors: [])
    }

    func readReviewItemDescriptor(
        _ request: BridgeReviewItemDescriptorRequest
    ) async throws -> BridgeReviewItemDescriptor {
        throw BridgeProviderFailure.providerFailed(message: "No Review items are available")
    }

    func resolveCheckpointEndpoint(
        _ request: BridgeCheckpointEndpointRequest
    ) async throws -> BridgeSourceEndpoint {
        throw BridgeProviderFailure.providerFailed(message: "No checkpoints are available")
    }

    func loadContent(_ request: BridgeContentLoadRequest) async throws -> BridgeContentLoadResult {
        throw BridgeProviderFailure.missingContent(handleId: request.handle.handleId)
    }

    func resolveEndpoint(
        _ request: BridgeEndpointResolutionRequest,
        freshnessKey: BridgeGitReadFreshnessKey
    ) async throws -> BridgeSourceEndpoint {
        _ = freshnessKey
        sharedEndpointResolutionCount += 1
        return resolvedEndpoint(request.endpoint)
    }

    func compareEndpoints(
        _ request: BridgeEndpointComparisonRequest,
        freshnessKey: BridgeGitReadFreshnessKey
    ) async throws -> BridgeEndpointComparison {
        _ = freshnessKey
        sharedComparisonCount += 1
        await comparisonGate?.waitUntilReleased()
        return BridgeEndpointComparison(
            baseEndpoint: request.baseEndpoint,
            headEndpoint: request.headEndpoint,
            changedFiles: []
        )
    }

    func readTree(
        _ request: BridgeTreeReadRequest,
        freshnessKey: BridgeGitReadFreshnessKey
    ) async throws -> BridgeTreeReadResult {
        _ = freshnessKey
        return BridgeTreeReadResult(endpoint: request.endpoint, descriptors: [])
    }

    func readReviewItemDescriptor(
        _ request: BridgeReviewItemDescriptorRequest,
        freshnessKey: BridgeGitReadFreshnessKey
    ) async throws -> BridgeReviewItemDescriptor {
        _ = freshnessKey
        throw BridgeProviderFailure.providerFailed(message: "No Review items are available")
    }

    func captureSharedContent(
        handles: [BridgeContentHandle],
        freshnessKey: BridgeGitReadFreshnessKey
    ) async throws -> BridgeSharedReviewContentBacking {
        _ = handles
        _ = freshnessKey
        sharedCaptureCount += 1
        let directoryURL = FileManager.default.temporaryDirectory.appending(
            path: "bridge-development-shared-review-\(UUIDv7.generate().uuidString)"
        )
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        return BridgeSharedReviewContentBacking(
            artifactIdentity: UUIDv7.generate(),
            directoryURL: directoryURL,
            sourceByIdentity: [:],
            capturedByteCount: 0
        )
    }

    func installSharedContent(
        backing: BridgeSharedReviewContentBacking,
        handles: [BridgeContentHandle]
    ) async throws {
        _ = backing
        _ = handles
        sharedInstallCount += 1
    }

    func snapshot() -> BridgeDevSharedReviewProviderSnapshot {
        BridgeDevSharedReviewProviderSnapshot(
            regularComparisonCount: regularComparisonCount,
            sharedCaptureCount: sharedCaptureCount,
            sharedComparisonCount: sharedComparisonCount,
            sharedEndpointResolutionCount: sharedEndpointResolutionCount,
            sharedInstallCount: sharedInstallCount
        )
    }

    private func resolvedEndpoint(_ endpoint: BridgeSourceEndpoint) -> BridgeSourceEndpoint {
        guard endpoint.kind == .gitRef else { return endpoint }
        let objectId = String(repeating: "a", count: 40)
        return BridgeSourceEndpoint(
            endpointId: endpoint.endpointId,
            kind: endpoint.kind,
            repoId: endpoint.repoId,
            worktreeId: endpoint.worktreeId,
            label: endpoint.label,
            createdAtUnixMilliseconds: endpoint.createdAtUnixMilliseconds,
            contentSetHash: objectId,
            providerIdentity: objectId
        )
    }
}

private func makeDevelopmentBootstrapRequest(
    surface: String
) throws -> BridgeDevelopmentProductBootstrapRequest {
    try JSONDecoder().decode(
        BridgeDevelopmentProductBootstrapRequest.self,
        from: Data(
            #"{"navigationIntent":{"commandId":"open-\#(surface)-view","commandKind":"activateContext","surface":"\#(surface)"},"reason":"initial"}"#
                .utf8
        )
    )
}

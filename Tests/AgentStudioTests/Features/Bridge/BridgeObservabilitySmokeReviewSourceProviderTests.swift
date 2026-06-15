#if DEBUG
    import Foundation
    import Testing

    @testable import AgentStudio

    @Suite
    struct BridgeObservabilitySmokeReviewSourceProviderTests {
        @Test
        func smokeProviderBuildsPackageAndLoadsContentMatchingGeneratedHandle() async throws {
            let provider = BridgeObservabilitySmokeReviewSourceProvider()
            let baseEndpoint = makeSmokeEndpoint(endpointId: "bridge-smoke-base", kind: .gitRef)
            let headEndpoint = makeSmokeEndpoint(endpointId: "bridge-smoke-head", kind: .workingTree)
            let query = BridgeReviewQuery(
                queryId: "bridge-smoke-query",
                queryKind: .compare,
                repoId: BridgeObservabilitySmokeReviewSourceProvider.repoId,
                worktreeId: BridgeObservabilitySmokeReviewSourceProvider.worktreeId,
                baseEndpointId: baseEndpoint.endpointId,
                headEndpointId: headEndpoint.endpointId,
                comparisonSemantics: .workingTreeDelta,
                pathScope: [],
                fileTarget: nil,
                viewFilter: BridgeViewFilter(),
                grouping: BridgeChangeGrouping(kind: .flat),
                provenanceFilter: BridgeProvenanceFilter()
            )
            let pipeline = BridgeReviewPipeline(provider: provider)

            let result = try await pipeline.loadPackage(
                BridgeReviewPipelineRequest(
                    packageId: "bridge-smoke-package",
                    query: query,
                    baseEndpoint: baseEndpoint,
                    headEndpoint: headEndpoint,
                    checkpointIds: [],
                    reviewGeneration: 1,
                    generatedAtUnixMilliseconds: 1
                )
            )

            let itemId = try #require(result.package.orderedItemIds.first)
            let item = try #require(result.package.itemsById[itemId])
            let headHandle = try #require(item.contentRoles.head)
            let content = try await provider.loadContent(
                BridgeContentLoadRequest(handle: headHandle, requestedGeneration: 1)
            )

            #expect(result.package.summary.filesChanged == 1)
            #expect(result.registeredContentHandles.contains(headHandle))
            #expect(content.handle == headHandle)
            #expect(content.contentHash == headHandle.contentHash)
            #expect(try #require(String(data: content.data, encoding: .utf8)).contains("transport"))
        }

        private func makeSmokeEndpoint(
            endpointId: String,
            kind: BridgeSourceEndpoint.Kind
        ) -> BridgeSourceEndpoint {
            BridgeSourceEndpoint(
                endpointId: endpointId,
                kind: kind,
                repoId: BridgeObservabilitySmokeReviewSourceProvider.repoId,
                worktreeId: BridgeObservabilitySmokeReviewSourceProvider.worktreeId,
                label: endpointId,
                createdAtUnixMilliseconds: 1,
                contentSetHash: nil,
                providerIdentity: endpointId
            )
        }
    }
#endif

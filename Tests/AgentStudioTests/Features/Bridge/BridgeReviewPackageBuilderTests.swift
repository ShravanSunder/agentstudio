import Testing

@testable import AgentStudio

struct BridgeReviewPackageBuilderTests {
    @Test("package builder creates descriptors, handles, hidden summary, and filter state")
    func packageBuilderCreatesDescriptorsHandlesHiddenSummaryAndFilterState() throws {
        let baseEndpoint = makeBridgeEndpoint(endpointId: "base", kind: .gitRef)
        let headEndpoint = makeBridgeEndpoint(endpointId: "head", kind: .promptCheckpoint)
        let comparison = BridgeEndpointComparison(
            baseEndpoint: baseEndpoint,
            headEndpoint: headEndpoint,
            changedFiles: [
                makeBridgeEndpointChangedFile(fileId: "source", path: "Sources/App/View.swift", sizeBytes: 100),
                makeBridgeEndpointChangedFile(fileId: "generated", path: "Generated/API.swift", sizeBytes: 100),
            ]
        )
        let filter = BridgeViewFilter(excludedFileClasses: [.generated])
        let query = makeBridgeReviewQuery(
            baseEndpointId: baseEndpoint.endpointId,
            headEndpointId: headEndpoint.endpointId,
            filter: filter,
            grouping: BridgeChangeGrouping(kind: .prompt)
        )

        let package = try BridgeReviewPackageBuilder.build(
            request: BridgeReviewPackageBuildRequest(
                packageId: "package",
                query: query,
                comparison: comparison,
                checkpointIds: ["checkpoint"],
                reviewGeneration: 3,
                generatedAtUnixMilliseconds: 4
            )
        )

        #expect(package.orderedItemIds == ["item-source", "item-generated"])
        #expect(package.itemsById["item-source"]?.contentRoles.base?.reviewGeneration == 3)
        #expect(package.itemsById["item-source"]?.contentRoles.head?.reviewGeneration == 3)
        #expect(package.itemsById["item-generated"]?.isHiddenByDefault == true)
        #expect(package.groups.first?.hiddenSummary.hiddenFileCount == 1)
        #expect(package.filterState.excludedFileClasses == [.generated])
    }

    @Test("package builder keeps gitlink metadata while omitting only gitlink content roles")
    func packageBuilderKeepsGitlinkMetadataWhileOmittingOnlyGitlinkContentRoles() throws {
        let baseEndpoint = makeBridgeEndpoint(endpointId: "base", kind: .gitRef)
        let headEndpoint = makeBridgeEndpoint(endpointId: "head", kind: .workingTree)
        let comparison = BridgeEndpointComparison(
            baseEndpoint: baseEndpoint,
            headEndpoint: headEndpoint,
            changedFiles: [
                makeBridgeEndpointChangedFile(
                    fileId: "old-gitlink",
                    path: "Dependencies/Old",
                    sizeBytes: 40,
                    oldMode: 0o160000
                ),
                makeBridgeEndpointChangedFile(
                    fileId: "new-gitlink",
                    path: "Dependencies/New",
                    sizeBytes: 40,
                    newMode: 0o160000
                ),
            ]
        )

        let package = try BridgeReviewPackageBuilder.build(
            request: BridgeReviewPackageBuildRequest(
                packageId: "package",
                query: makeBridgeReviewQuery(
                    baseEndpointId: baseEndpoint.endpointId,
                    headEndpointId: headEndpoint.endpointId
                ),
                comparison: comparison,
                checkpointIds: [],
                reviewGeneration: 4,
                generatedAtUnixMilliseconds: 5
            )
        )

        #expect(package.orderedItemIds == ["item-old-gitlink", "item-new-gitlink"])
        #expect(package.itemsById["item-old-gitlink"]?.contentRoles.base == nil)
        #expect(package.itemsById["item-old-gitlink"]?.contentRoles.head != nil)
        #expect(package.itemsById["item-new-gitlink"]?.contentRoles.base != nil)
        #expect(package.itemsById["item-new-gitlink"]?.contentRoles.head == nil)
    }
}

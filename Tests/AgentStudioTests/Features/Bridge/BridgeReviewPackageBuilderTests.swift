import Testing

@testable import AgentStudioBridge

struct BridgeReviewPackageBuilderTests {
    @Test("Review descriptors classify script tests and fixtures before applying category exclusions")
    func reviewDescriptorsClassifyBeforeCategoryExclusions() throws {
        let base = makeBridgeEndpoint(endpointId: "base", kind: .gitRef)
        let head = makeBridgeEndpoint(endpointId: "head", kind: .workingTree)
        let paths = [
            "src/component.test.tsx", "src/component.spec.jsx", "src/test-fixtures/sample.json", "assets/notes.xyz",
        ]
        let comparison = BridgeEndpointComparison(
            baseEndpoint: base,
            headEndpoint: head,
            changedFiles: paths.enumerated().map { index, path in
                makeBridgeEndpointChangedFile(fileId: "\(index)", path: path, sizeBytes: 100)
            }
        )
        let package = try BridgeReviewPackageBuilder.build(
            request: BridgeReviewPackageBuildRequest(
                packageId: "classification",
                query: makeBridgeReviewQuery(
                    baseEndpointId: base.endpointId,
                    headEndpointId: head.endpointId,
                    filter: BridgeViewFilter(excludedFileClasses: [.test, .fixture])
                ),
                comparison: comparison,
                checkpointIds: [],
                reviewGeneration: 1,
                generatedAtUnixMilliseconds: 1
            ))
        #expect(package.itemsById["item-0"]?.fileClass == .test)
        #expect(package.itemsById["item-1"]?.fileClass == .test)
        #expect(package.itemsById["item-2"]?.fileClass == .fixture)
        #expect(package.itemsById["item-3"]?.fileClass == .unknown)
        for index in 0...2 {
            #expect(package.itemsById["item-\(index)"]?.isHiddenByDefault == true)
        }
        #expect(package.itemsById["item-3"]?.isHiddenByDefault == false)
    }

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

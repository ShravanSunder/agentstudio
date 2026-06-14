import Testing

@testable import AgentStudio

struct BridgeChangeCollatorTests {
    @Test("collator creates filtered group without creating checkpoints for time windows")
    func collatorCreatesFilteredGroupWithoutCreatingCheckpointsForTimeWindows() {
        let sourceDescriptor = makeBridgeReviewItemDescriptor(
            itemId: "source",
            path: "Sources/App/View.swift",
            fileClass: .source
        )
        let generatedDescriptor = makeBridgeReviewItemDescriptor(
            itemId: "generated",
            path: "Generated/API.swift",
            fileClass: .generated
        )

        let groups = BridgeChangeCollator.collate(
            BridgeChangeCollationRequest(
                descriptors: [sourceDescriptor, generatedDescriptor],
                pathScope: [],
                filter: BridgeViewFilter(includedFileClasses: [.source]),
                grouping: BridgeChangeGrouping(kind: .timeWindow, label: "Last 30 minutes"),
                checkpointIds: [],
                createdAtUnixMilliseconds: 10
            )
        )
        let group = groups.first

        #expect(group?.orderedItemIds == ["source"])
        #expect(group?.hiddenSummary.hiddenFileCount == 1)
        #expect(group?.grouping.kind == .timeWindow)
    }

    @Test("collator applies path scope and path glob filters")
    func collatorAppliesPathScopeAndPathGlobFilters() {
        let sourceDescriptor = makeBridgeReviewItemDescriptor(
            itemId: "source",
            path: "Sources/App/View.swift",
            fileClass: .source
        )
        let testDescriptor = makeBridgeReviewItemDescriptor(
            itemId: "test",
            path: "Tests/App/ViewTests.swift",
            fileClass: .test
        )
        let buildDescriptor = makeBridgeReviewItemDescriptor(
            itemId: "build",
            path: "Sources/.build/generated.swift",
            fileClass: .source
        )

        let groups = BridgeChangeCollator.collate(
            BridgeChangeCollationRequest(
                descriptors: [sourceDescriptor, testDescriptor, buildDescriptor],
                pathScope: ["Sources/**"],
                filter: BridgeViewFilter(
                    includedPathGlobs: ["**/*.swift"],
                    excludedPathGlobs: ["**/.build/**"]
                ),
                grouping: BridgeChangeGrouping(kind: .folder, label: "Sources"),
                checkpointIds: [],
                createdAtUnixMilliseconds: 10
            )
        )
        let group = groups.first

        #expect(group?.orderedItemIds == ["source"])
        #expect(group?.hiddenSummary.hiddenFileCount == 2)
    }
}

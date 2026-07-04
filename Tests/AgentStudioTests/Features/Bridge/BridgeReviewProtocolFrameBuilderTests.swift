import Foundation
import Testing

@testable import AgentStudio

struct BridgeReviewProtocolFrameBuilderTests {
    @Test("native review metadata snapshot intake frame matches BridgeWeb contract fixture")
    func nativeReviewMetadataSnapshotIntakeFrameMatchesBridgeWebContractFixture() throws {
        let intakeFrameJSON = try makeReviewMetadataSnapshotIntakeFrameJSON()
        let intakeFrameData = try #require(intakeFrameJSON.data(using: .utf8))
        let intakeFrameObject = try #require(
            JSONSerialization.jsonObject(with: intakeFrameData) as? [String: Any]
        )
        let payloadObject = try #require(intakeFrameObject["payload"] as? [String: Any])
        let comparisonObject = try #require(payloadObject["comparison"] as? [String: Any])
        let contentDescriptors = try #require(
            comparisonObject["contentDescriptors"] as? [[String: Any]]
        )
        let firstContentDescriptor = try #require(contentDescriptors.first)
        let descriptor = try #require(firstContentDescriptor["descriptor"] as? [String: Any])
        let descriptorContent = try #require(descriptor["content"] as? [String: Any])

        #expect(intakeFrameObject["kind"] as? String == "snapshot")
        #expect(intakeFrameObject["streamId"] as? String == "review:pane-1")
        #expect(intakeFrameObject["generation"] as? Int == 3)
        #expect(intakeFrameObject["sequence"] as? Int == 0)
        #expect(payloadObject["kind"] as? String == "metadataSnapshot")
        #expect(payloadObject["frameKind"] as? String == "review.metadataSnapshot")
        #expect(descriptor["protocol"] as? String == "review")
        #expect(descriptor["resourceKind"] as? String == "content")
        #expect(descriptorContent["encoding"] as? String == "utf-8")

        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let fixtureData = try Data(
            contentsOf: projectRoot.appending(
                path: "Tests/BridgeContractFixtures/valid/review-metadata-snapshot-intake-frame.json"
            )
        )
        let fixtureObject = try #require(JSONSerialization.jsonObject(with: fixtureData) as? [String: Any])
        #expect(NSDictionary(dictionary: intakeFrameObject).isEqual(to: fixtureObject))
    }

    @Test("metadata snapshot frame carries metadata and content descriptors without package body descriptor")
    func metadataSnapshotFrameCarriesMetadataAndContentDescriptorsWithoutPackageBodyDescriptor() throws {
        let package = try makeReviewPackage()

        let frame = try BridgeReviewProtocolFrameBuilder.snapshot(
            request: BridgeReviewProtocolSnapshotBuildRequest(
                paneId: "pane-1",
                sourceIdentity: "review-source-1",
                streamId: "stream-1",
                sequence: 0,
                package: package,
                changesetCluster: nil
            )
        )

        #expect(frame.kind == "metadataSnapshot")
        #expect(frame.frameKind == "review.metadataSnapshot")
        #expect(frame.comparison.packageId == package.packageId)
        #expect(frame.comparison.baseEndpoint == package.baseEndpoint)
        #expect(frame.comparison.headEndpoint == package.headEndpoint)
        #expect(frame.comparison.contentDescriptors.count == 2)
        #expect(frame.selectedItemId == package.orderedItemIds.first)
        #expect(frame.visibleItemIds == package.orderedItemIds)
        #expect(frame.itemMetadata.count == package.itemsById.count)
        #expect(
            frame.treeRows.map(\.rowId) == [
                "review-directory:Sources",
                "review-directory:Sources/App",
                "review-row:item-source",
            ]
        )
        let metadataItem = try #require(frame.itemMetadata.first)
        let item = try #require(package.itemsById[metadataItem.itemId])
        #expect(metadataItem.itemId == "item-source")
        #expect(metadataItem.contentRoles == ["base", "head"])
        #expect(
            frame.extentFacts.map { "\($0.itemId):\($0.contentRole)" } == [
                "item-source:base",
                "item-source:head",
            ]
        )
        #expect(metadataItem.contentDescriptorIdsByRole?.base != nil)
        #expect(metadataItem.contentDescriptorIdsByRole?.head != nil)
        #expect(metadataItem.contentHashesByRole?.base == item.contentRoles.base?.contentHash)
        #expect(metadataItem.contentHashesByRole?.head == item.contentRoles.head?.contentHash)
        #expect(metadataItem.mimeTypes == ["text/x-swift"])
        let treeRow = try #require(frame.treeRows.last)
        #expect(treeRow.rowId == "review-row:item-source")
        #expect(treeRow.path == "Sources/App/View.swift")
        #expect(treeRow.depth == 2)
        #expect(treeRow.isDirectory == false)
        let sourceDirectoryRow = try #require(frame.treeRows.first)
        #expect(sourceDirectoryRow.rowId == "review-directory:Sources")
        #expect(sourceDirectoryRow.itemId == nil)
        #expect(sourceDirectoryRow.path == "Sources")
        #expect(sourceDirectoryRow.depth == 0)
        #expect(sourceDirectoryRow.isDirectory == true)
        #expect(frame.extentFacts.allSatisfy { $0.lineCount > 0 })
        let contentDescriptor = try #require(frame.comparison.contentDescriptors.first)
        #expect(contentDescriptor.descriptor.protocolId == "review")
        #expect(contentDescriptor.descriptor.resourceKind == "content")
        #expect(contentDescriptor.descriptor.identity.revision == nil)
        #expect(contentDescriptor.ref.descriptorId == contentDescriptor.descriptor.descriptorId)

        let encoded = try JSONEncoder().encode(frame)
        let object = try #require(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        let comparisonObject = try #require(object["comparison"] as? [String: Any])
        #expect(comparisonObject["rootDescriptor"] == nil)
        #expect(comparisonObject["contentDescriptors"] != nil)
        #expect(object["package"] == nil)
        #expect(object["itemMetadata"] != nil)
        #expect(object["treeRows"] != nil)
        let encodedTreeRows = try #require(object["treeRows"] as? [[String: Any]])
        let encodedTreeRow = try #require(encodedTreeRows.last)
        #expect(encodedTreeRow["displayName"] == nil)
        #expect(encodedTreeRow["itemKind"] == nil)
        #expect(encodedTreeRow["parentPath"] == nil)
        #expect(encodedTreeRow["isDirectory"] as? Bool == false)
        let encodedDirectoryRow = try #require(encodedTreeRows.first)
        #expect(encodedDirectoryRow["itemId"] == nil)
        #expect(encodedDirectoryRow["path"] as? String == "Sources")
        #expect(encodedDirectoryRow["isDirectory"] as? Bool == true)
        let encodedExtentFacts = try #require(object["extentFacts"] as? [[String: Any]])
        let encodedExtentFact = try #require(encodedExtentFacts.first)
        #expect(encodedExtentFacts.count == 2)
        #expect(encodedExtentFact["contentRole"] as? String == "base")
        let encodedItems = try #require(object["itemMetadata"] as? [[String: Any]])
        let encodedItem = try #require(encodedItems.first)
        #expect(encodedItem["itemVersion"] == nil)
        #expect(encodedItem["contentDescriptorIdsByRole"] != nil)
        #expect(encodedItem["loaded_by"] as? String == "startup_window")
        #expect(encodedItem["lane"] as? String == "foreground")
        #expect(encodedTreeRows.allSatisfy { $0["loaded_by"] as? String == "startup_window" })
        #expect(encodedTreeRows.allSatisfy { $0["lane"] as? String == "foreground" })
    }

    @Test("metadata snapshot emits extent facts for actual content roles")
    func metadataSnapshotEmitsExtentFactsForActualContentRoles() throws {
        let package = try makeReviewPackage()

        let frame = try BridgeReviewProtocolFrameBuilder.snapshot(
            request: BridgeReviewProtocolSnapshotBuildRequest(
                paneId: "pane-1",
                sourceIdentity: "review-source-1",
                streamId: "stream-1",
                sequence: 0,
                package: package,
                changesetCluster: nil
            )
        )

        let item = try #require(frame.itemMetadata.first)
        #expect(item.contentRoles == ["base", "head"])
        #expect(
            frame.extentFacts.map { "\($0.itemId):\($0.contentRole)" } == [
                "item-source:base",
                "item-source:head",
            ]
        )
        #expect(frame.extentFacts.allSatisfy { $0.lineCount > 0 })
    }

    @Test("metadata snapshot has no package body resource")
    func metadataSnapshotHasNoPackageBodyResource() throws {
        let package = try makeReviewPackage()

        let frame = try BridgeReviewProtocolFrameBuilder.snapshot(
            request: BridgeReviewProtocolSnapshotBuildRequest(
                paneId: "pane-1",
                sourceIdentity: "review-source-1",
                streamId: "stream-1",
                sequence: 0,
                package: package,
                changesetCluster: nil
            )
        )

        let encoded = try JSONEncoder().encode(frame)
        let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let comparisonObject = try #require(object["comparison"] as? [String: Any])
        #expect(comparisonObject["rootDescriptor"] == nil)
        #expect(frame.comparison.contentDescriptors.allSatisfy { $0.descriptor.resourceKind == "content" })
    }

    @Test("metadata snapshot encodes nullable projection fields for BridgeWeb schema")
    func metadataSnapshotEncodesNullableProjectionFieldsForBridgeWebSchema() throws {
        let package = try makeReviewPackageWithDeletedFile()

        let frame = try BridgeReviewProtocolFrameBuilder.snapshot(
            request: BridgeReviewProtocolSnapshotBuildRequest(
                paneId: "pane-1",
                sourceIdentity: "review-source-1",
                streamId: "stream-1",
                sequence: 0,
                package: package,
                changesetCluster: nil
            )
        )

        let encoded = try JSONEncoder().encode(frame)
        let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let encodedItems = try #require(object["itemMetadata"] as? [[String: Any]])
        let encodedItem = try #require(encodedItems.first)

        #expect(encodedItem.keys.contains("basePath"))
        #expect(encodedItem.keys.contains("headPath"))
        #expect(encodedItem["basePath"] as? String == "Sources/App/Removed.swift")
        #expect(encodedItem["headPath"] is NSNull)
    }

    @Test("metadata snapshot encodes null selected item for BridgeWeb schema")
    func metadataSnapshotEncodesNullSelectedItemForBridgeWebSchema() throws {
        let package = try makeReviewPackage()
        let frame = BridgeReviewSnapshotFrame(
            streamId: "stream-1",
            generation: package.reviewGeneration.rawValue,
            sequence: 0,
            comparison: BridgeReviewComparisonIdentity(
                packageId: package.packageId,
                sourceIdentity: "review-source-1",
                generation: package.reviewGeneration.rawValue,
                revision: package.revision,
                baseEndpoint: package.baseEndpoint,
                headEndpoint: package.headEndpoint,
                contentDescriptors: [],
                changesetCluster: nil
            ),
            selectedItemId: nil,
            visibleItemIds: [],
            itemMetadata: [],
            treeRows: [],
            extentFacts: [],
            summary: package.summary
        )

        let encoded = try JSONEncoder().encode(frame)
        let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let summaryObject = try #require(object["summary"] as? [String: Any])

        #expect(object.keys.contains("selectedItemId"))
        #expect(object["selectedItemId"] is NSNull)
        #expect(summaryObject["filesChanged"] as? Int == package.summary.filesChanged)
    }

    @Test("snapshot frame omits browser integrity for non-sha256 host hashes")
    func snapshotFrameOmitsBrowserIntegrityForNonSHA256HostHashes() throws {
        let package = try makeReviewPackageWithHostContentHashAlgorithm()
        let item = try #require(package.itemsById["item-source"])
        let headHandle = try #require(item.contentRoles.head)

        let frame = try BridgeReviewProtocolFrameBuilder.snapshot(
            request: BridgeReviewProtocolSnapshotBuildRequest(
                paneId: "pane-1",
                sourceIdentity: "review-source-1",
                streamId: "stream-1",
                sequence: 0,
                package: package,
                changesetCluster: nil
            )
        )

        let hostVerifiedDescriptor = try #require(
            frame.comparison.contentDescriptors.first {
                $0.ref.descriptorId == headHandle.handleId
            }
        )
        #expect(hostVerifiedDescriptor.descriptor.content.integrity == nil)
    }

    @Test("snapshot frame builder preserves flexible changeset cluster metadata")
    func snapshotFrameBuilderPreservesFlexibleChangesetClusterMetadata() throws {
        let package = try makeReviewPackage()
        let metadata = BridgeReviewChangesetClusterMetadata(
            clusterId: "cluster-1",
            sourceId: "review-source-1",
            algorithm: "idleDebounce",
            lifecycle: "live",
            confidence: "freshScan",
            baselineCursor: "cursor-a",
            headCursor: "cursor-b",
            baselineRef: nil,
            headRef: nil,
            fromUnixMilliseconds: nil,
            toUnixMilliseconds: nil,
            includedPathHints: ["Sources/App/View.swift"],
            groupingReason: "agent idle debounce closed the batch",
            limitations: ["overflowRecovered"]
        )
        let frame = try BridgeReviewProtocolFrameBuilder.snapshot(
            request: BridgeReviewProtocolSnapshotBuildRequest(
                paneId: "pane-1",
                sourceIdentity: "review-source-1",
                streamId: "stream-1",
                sequence: 0,
                package: package,
                changesetCluster: metadata
            )
        )

        let encoded = try JSONEncoder().encode(frame)
        let object = try #require(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        let comparisonObject = try #require(object["comparison"] as? [String: Any])
        let clusterObject = try #require(comparisonObject["changesetCluster"] as? [String: Any])

        #expect(clusterObject["sourceId"] as? String == "review-source-1")
        #expect(clusterObject["algorithm"] as? String == "idleDebounce")
        #expect(clusterObject["confidence"] as? String == "freshScan")
        #expect(clusterObject["limitations"] as? [String] == ["overflowRecovered"])
    }

    @Test("snapshot frame rejects content resource URLs that do not match handle id")
    func snapshotFrameRejectsMismatchedContentResourceId() throws {
        let package = try makeReviewPackageWithMismatchedContentResourceId()

        #expect(throws: BridgeReviewProtocolFrameBuilderError.self) {
            _ = try BridgeReviewProtocolFrameBuilder.snapshot(
                request: BridgeReviewProtocolSnapshotBuildRequest(
                    paneId: "pane-1",
                    sourceIdentity: "review-source-1",
                    streamId: "stream-1",
                    sequence: 0,
                    package: package,
                    changesetCluster: nil
                )
            )
        }
    }

    @Test("snapshot protocol frame carries descriptor metadata without push wrapper")
    func snapshotProtocolFrameCarriesDescriptorMetadataWithoutPushWrapper() throws {
        let package = try makeReviewPackage()
        let frame = try BridgeReviewProtocolFrameBuilder.snapshot(
            request: BridgeReviewProtocolSnapshotBuildRequest(
                paneId: "pane-1",
                sourceIdentity: package.query.queryId,
                streamId: "review:pane-1",
                sequence: package.revision,
                package: package,
                changesetCluster: nil
            )
        )

        let encoded = try JSONEncoder().encode(BridgeReviewProtocolFrame.snapshot(frame))
        let object = try #require(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )

        #expect(object["protocolFrame"] == nil)
        #expect(object["frameKind"] as? String == "review.metadataSnapshot")
        #expect(object["comparison"] != nil)
        #expect(object["package"] == nil)
    }

    @Test("delta protocol frame carries descriptor metadata without push wrapper")
    func deltaProtocolFrameCarriesDescriptorMetadataWithoutPushWrapper() throws {
        let package = try makeReviewPackage()
        let operations = BridgeReviewDelta.Operations()
        let frame = try BridgeReviewProtocolFrameBuilder.delta(
            request: BridgeReviewProtocolDeltaBuildRequest(
                paneId: "pane-1",
                sourceIdentity: package.query.queryId,
                streamId: "review:pane-1",
                sequence: package.revision,
                fromRevision: package.revision - 1,
                toRevision: package.revision,
                package: package,
                operations: operations
            )
        )
        let encoded = try JSONEncoder().encode(BridgeReviewProtocolFrame.delta(frame))
        let object = try #require(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )

        #expect(object["protocolFrame"] == nil)
        #expect(object["frameKind"] as? String == "review.metadataDelta")
        #expect(object["packageId"] as? String == package.packageId)
        #expect(object["operationsDescriptor"] == nil)
        #expect(object["operations"] != nil)
        let encodedOperations = try #require(object["operations"] as? [[String: Any]])
        #expect(encodedOperations.isEmpty)
        #expect(object["contentDescriptors"] != nil)
    }

    @Test("metadata delta carries operations as metadata")
    func metadataDeltaCarriesOperationsAsMetadata() throws {
        let package = try makeReviewPackage()

        let frame = try BridgeReviewProtocolFrameBuilder.delta(
            request: BridgeReviewProtocolDeltaBuildRequest(
                paneId: "pane-1",
                sourceIdentity: package.query.queryId,
                streamId: "review:pane-1",
                sequence: package.revision,
                fromRevision: package.revision - 1,
                toRevision: package.revision,
                package: package
            )
        )

        let encoded = try JSONEncoder().encode(frame)
        let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect(object["frameKind"] as? String == "review.metadataDelta")
        #expect(object["operationsDescriptor"] == nil)
        let operations = try #require(object["operations"] as? [[String: Any]])
        #expect(operations.isEmpty)
    }

    @Test("metadata delta encodes typed operation array")
    func metadataDeltaEncodesTypedOperationArray() throws {
        let package = try makeReviewPackage()
        let item = try #require(package.itemsById["item-source"])
        let frame = try BridgeReviewProtocolFrameBuilder.delta(
            request: BridgeReviewProtocolDeltaBuildRequest(
                paneId: "pane-1",
                sourceIdentity: package.query.queryId,
                streamId: "review:pane-1",
                sequence: package.revision,
                fromRevision: package.revision - 1,
                toRevision: package.revision,
                package: package,
                operations: BridgeReviewDelta.Operations(
                    updateItems: [item],
                    invalidateContent: item.contentRoles.allHandles.map(\.handleId)
                )
            )
        )

        let encoded = try JSONEncoder().encode(frame)
        let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let operations = try #require(object["operations"] as? [[String: Any]])

        #expect(operations.contains { $0["kind"] as? String == "upsertItemMetadata" })
        #expect(operations.contains { $0["kind"] as? String == "upsertTreeRows" })
        let extentOperation = try #require(
            operations.first { $0["kind"] as? String == "upsertExtentFacts" }
        )
        let extentFacts = try #require(extentOperation["facts"] as? [[String: Any]])
        #expect(extentFacts.compactMap { $0["contentRole"] as? String } == ["base", "head"])
        let invalidation = try #require(
            operations.first { $0["kind"] as? String == "invalidateContentDescriptors" }
        )
        #expect(invalidation["descriptorIds"] as? [String] == item.contentRoles.allHandles.map(\.handleId))
    }

    @Test("metadata window frame carries item tree extent and content descriptor metadata")
    func metadataWindowFrameCarriesItemTreeExtentAndContentDescriptorMetadata() throws {
        let package = try makeReviewPackage()

        let frame = try BridgeReviewProtocolFrameBuilder.metadataWindow(
            request: BridgeReviewProtocolMetadataWindowBuildRequest(
                paneId: "pane-1",
                sourceIdentity: package.query.queryId,
                streamId: "review:pane-1",
                sequence: 2,
                package: package,
                itemIds: ["item-source"]
            )
        )

        #expect(frame.kind == "metadataWindow")
        #expect(frame.frameKind == "review.metadataWindow")
        #expect(frame.packageId == package.packageId)
        #expect(frame.revision == package.revision)
        #expect(frame.itemMetadata.map(\.itemId) == ["item-source"])
        #expect(
            frame.treeRows.map(\.rowId) == [
                "review-directory:Sources",
                "review-directory:Sources/App",
                "review-row:item-source",
            ]
        )
        #expect(
            frame.extentFacts.map { "\($0.itemId):\($0.contentRole)" } == [
                "item-source:base",
                "item-source:head",
            ]
        )
        #expect(frame.contentDescriptors.count == 2)

        let encoded = try JSONEncoder().encode(BridgeReviewProtocolFrame.metadataWindow(frame))
        let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])

        #expect(object["kind"] as? String == "metadataWindow")
        #expect(object["frameKind"] as? String == "review.metadataWindow")
        #expect(object["package"] == nil)
        #expect(object["itemMetadata"] != nil)
        #expect(object["treeRows"] != nil)
        #expect(object["extentFacts"] != nil)
        #expect(object["contentDescriptors"] != nil)
        let encodedItems = try #require(object["itemMetadata"] as? [[String: Any]])
        let encodedTreeRows = try #require(object["treeRows"] as? [[String: Any]])
        #expect(encodedItems.allSatisfy { $0["loaded_by"] as? String == "idle" })
        #expect(encodedItems.allSatisfy { $0["lane"] as? String == "idle" })
        #expect(encodedTreeRows.allSatisfy { $0["loaded_by"] as? String == "idle" })
        #expect(encodedTreeRows.allSatisfy { $0["lane"] as? String == "idle" })
    }

    @Test("diff state stores and clears native package facts without protocol frames")
    @MainActor
    func diffStateStoresAndClearsNativePackageFactsWithoutProtocolFrames() throws {
        let package = try makeReviewPackage()
        let delta = BridgeReviewDelta(
            packageId: package.packageId,
            reviewGeneration: package.reviewGeneration,
            revision: package.revision + 1,
            operations: BridgeReviewDelta.Operations()
        )
        let state = DiffState()

        state.setPackageMetadata(package)
        state.setPackageDelta(delta)

        #expect(state.packageMetadata == package)
        #expect(state.packageDelta == delta)

        state.setPackageMetadata(nil)
        state.setPackageDelta(nil)

        #expect(state.packageMetadata == nil)
        #expect(state.packageDelta == nil)
    }

    @Test("standalone reset and invalidation protocol frames encode without push wrapper")
    func standaloneProtocolFramesEncodeWithoutPushWrapper() throws {
        let resetFrame = BridgeReviewProtocolFrameBuilder.reset(
            request: BridgeReviewProtocolResetBuildRequest(
                sourceIdentity: "review-source-1",
                streamId: "review:pane-1",
                generation: 4,
                sequence: 5,
                reason: "authorityChanged"
            )
        )
        let resetEncoded = try JSONEncoder().encode(BridgeReviewProtocolFrame.reset(resetFrame))
        let resetObject = try #require(
            JSONSerialization.jsonObject(with: resetEncoded) as? [String: Any]
        )
        #expect(resetObject["protocolFrame"] == nil)
        #expect(resetObject["frameKind"] as? String == "review.reset")
        #expect(resetObject["sourceIdentity"] as? String == "review-source-1")

        let invalidationFrame = BridgeReviewProtocolFrameBuilder.invalidation(
            request: BridgeReviewProtocolInvalidationBuildRequest(
                streamId: "review:pane-1",
                generation: 4,
                sequence: 6,
                scope: "items",
                itemIds: ["item-a"],
                pathHints: nil,
                reason: "watchEvent"
            )
        )
        let invalidationEncoded = try JSONEncoder().encode(
            BridgeReviewProtocolFrame.invalidation(invalidationFrame)
        )
        let invalidationObject = try #require(
            JSONSerialization.jsonObject(with: invalidationEncoded) as? [String: Any]
        )
        let invalidation = try #require(invalidationObject["invalidation"] as? [String: Any])
        #expect(invalidationObject["protocolFrame"] == nil)
        #expect(invalidationObject["frameKind"] as? String == "review.invalidate")
        #expect(invalidation["itemIds"] as? [String] == ["item-a"])
    }

    @Test("snapshot frame preserves package changeset cluster through native package model")
    func snapshotFramePreservesPackageChangesetClusterThroughNativePackageModel() throws {
        let metadata = BridgeReviewChangesetClusterMetadata(
            clusterId: "cluster-1",
            sourceId: "review-source-1",
            algorithm: "idleDebounce",
            lifecycle: "closed",
            confidence: "freshScan",
            baselineCursor: nil,
            headCursor: "cursor-b",
            baselineRef: "main",
            headRef: nil,
            fromUnixMilliseconds: 1,
            toUnixMilliseconds: 2,
            includedPathHints: ["Sources/App/View.swift"],
            groupingReason: "agent idle debounce closed the batch",
            limitations: ["overflowRecovered"]
        )
        let package = try makeReviewPackage().withChangesetCluster(metadata)
        let frame = try BridgeReviewProtocolFrameBuilder.snapshot(
            request: BridgeReviewProtocolSnapshotBuildRequest(
                paneId: "pane-1",
                sourceIdentity: package.query.queryId,
                streamId: "review:pane-1",
                sequence: package.revision,
                package: package,
                changesetCluster: package.changesetCluster
            )
        )

        let encoded = try JSONEncoder().encode(BridgeReviewProtocolFrame.snapshot(frame))
        let object = try #require(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        #expect(object["protocolFrame"] == nil)
        let comparisonObject = try #require(object["comparison"] as? [String: Any])
        let clusterObject = try #require(comparisonObject["changesetCluster"] as? [String: Any])
        #expect(clusterObject["lifecycle"] as? String == "closed")
        #expect(clusterObject["headCursor"] as? String == "cursor-b")
        #expect(clusterObject["limitations"] as? [String] == ["overflowRecovered"])
    }

    @Test("reset frame carries metadata-only source identity")
    func resetFrameCarriesMetadataOnlySourceIdentity() throws {
        let frame = BridgeReviewProtocolFrameBuilder.reset(
            request: BridgeReviewProtocolResetBuildRequest(
                sourceIdentity: "review-source-1",
                streamId: "review:pane-1",
                generation: 4,
                sequence: 5,
                reason: "authorityChanged"
            )
        )

        #expect(frame.kind == "reset")
        #expect(frame.frameKind == "review.reset")
        #expect(frame.sourceIdentity == "review-source-1")
    }

    @Test("invalidation frame carries metadata-only invalidation facts")
    func invalidationFrameCarriesMetadataOnlyInvalidationFacts() throws {
        let frame = BridgeReviewProtocolFrameBuilder.invalidation(
            request: BridgeReviewProtocolInvalidationBuildRequest(
                streamId: "review:pane-1",
                generation: 4,
                sequence: 5,
                scope: "items",
                itemIds: ["item-a"],
                pathHints: nil,
                reason: "watchEvent"
            )
        )

        #expect(frame.kind == "delta")
        #expect(frame.frameKind == "review.invalidate")
        #expect(frame.invalidation.scope == "items")
        #expect(frame.invalidation.itemIds == ["item-a"])
        #expect(frame.invalidation.reason == "watchEvent")
    }

    private func makeReviewPackage() throws -> BridgeReviewPackage {
        let baseEndpoint = makeBridgeEndpoint(endpointId: "base", kind: .gitRef)
        let headEndpoint = makeBridgeEndpoint(endpointId: "head", kind: .workingTree)
        let comparison = BridgeEndpointComparison(
            baseEndpoint: baseEndpoint,
            headEndpoint: headEndpoint,
            changedFiles: [
                makeBridgeEndpointChangedFile(fileId: "source", path: "Sources/App/View.swift", sizeBytes: 100)
            ]
        )
        let query = makeBridgeReviewQuery(
            baseEndpointId: baseEndpoint.endpointId,
            headEndpointId: headEndpoint.endpointId
        )
        return try BridgeReviewPackageBuilder.build(
            request: BridgeReviewPackageBuildRequest(
                packageId: "package-1",
                query: query,
                comparison: comparison,
                checkpointIds: [],
                reviewGeneration: 3,
                generatedAtUnixMilliseconds: 4
            )
        )
    }

    private func makeReviewMetadataSnapshotIntakeFrameJSON() throws -> String {
        let package = try makeReviewPackage()
        let frame = try BridgeReviewProtocolFrameBuilder.snapshot(
            request: BridgeReviewProtocolSnapshotBuildRequest(
                paneId: "pane-1",
                sourceIdentity: package.query.queryId,
                streamId: "review:pane-1",
                sequence: package.revision,
                package: package,
                changesetCluster: package.changesetCluster
            )
        )
        let payload = try JSONEncoder().encode(BridgeReviewProtocolFrame.snapshot(frame))
        return try BridgePushEnvelopeEncoder().encodeIntakeFrame(
            metadata: BridgeIntakeFrameMetadata(
                kind: .snapshot,
                streamId: frame.streamId,
                generation: frame.generation,
                sequence: frame.sequence
            ),
            payload: payload,
            traceContext: nil
        )
    }

    private func makeReviewPackageWithHostContentHashAlgorithm() throws -> BridgeReviewPackage {
        let package = try makeReviewPackage()
        let item = try #require(package.itemsById["item-source"])
        let head = try #require(item.contentRoles.head)
        let updatedHead = BridgeContentHandle(
            handleId: head.handleId,
            itemId: head.itemId,
            role: head.role,
            endpointId: head.endpointId,
            reviewGeneration: head.reviewGeneration,
            resourceUrl: head.resourceUrl,
            contentHash: "git-oid:abc123",
            contentHashAlgorithm: "git-oid",
            cacheKey: head.cacheKey,
            mimeType: head.mimeType,
            language: head.language,
            sizeBytes: head.sizeBytes,
            isBinary: head.isBinary
        )
        let updatedItem = BridgeReviewItemDescriptor(
            itemId: item.itemId,
            itemKind: item.itemKind,
            itemVersion: item.itemVersion,
            basePath: item.basePath,
            headPath: item.headPath,
            changeKind: item.changeKind,
            fileClass: item.fileClass,
            language: item.language,
            extension: item.extension,
            sizeBytes: item.sizeBytes,
            baseContentHash: item.baseContentHash,
            headContentHash: updatedHead.contentHash,
            contentHashAlgorithm: updatedHead.contentHashAlgorithm,
            additions: item.additions,
            deletions: item.deletions,
            isHiddenByDefault: item.isHiddenByDefault,
            hiddenReason: item.hiddenReason,
            reviewPriority: item.reviewPriority,
            contentRoles: BridgeReviewItemDescriptor.ContentRoles(
                base: item.contentRoles.base,
                head: updatedHead,
                diff: item.contentRoles.diff,
                file: item.contentRoles.file
            ),
            cacheKey: item.cacheKey,
            provenance: item.provenance,
            annotationSummary: item.annotationSummary,
            reviewState: item.reviewState,
            collapsed: item.collapsed
        )
        return BridgeReviewPackage(
            packageId: package.packageId,
            schemaVersion: package.schemaVersion,
            reviewGeneration: package.reviewGeneration,
            revision: package.revision,
            query: package.query,
            baseEndpoint: package.baseEndpoint,
            headEndpoint: package.headEndpoint,
            orderedItemIds: package.orderedItemIds,
            itemsById: package.itemsById.merging([updatedItem.itemId: updatedItem]) { _, next in next },
            groups: package.groups,
            summary: package.summary,
            filterState: package.filterState,
            generatedAtUnixMilliseconds: package.generatedAtUnixMilliseconds
        )
    }

    private func makeReviewPackageWithDeletedFile() throws -> BridgeReviewPackage {
        let baseEndpoint = makeBridgeEndpoint(endpointId: "base", kind: .gitRef)
        let headEndpoint = makeBridgeEndpoint(endpointId: "head", kind: .workingTree)
        let comparison = BridgeEndpointComparison(
            baseEndpoint: baseEndpoint,
            headEndpoint: headEndpoint,
            changedFiles: [
                makeBridgeEndpointChangedFile(
                    fileId: "removed",
                    path: "Sources/App/Removed.swift",
                    sizeBytes: 100,
                    changeKind: .deleted
                )
            ]
        )
        let query = makeBridgeReviewQuery(
            baseEndpointId: baseEndpoint.endpointId,
            headEndpointId: headEndpoint.endpointId
        )
        return try BridgeReviewPackageBuilder.build(
            request: BridgeReviewPackageBuildRequest(
                packageId: "package-removed",
                query: query,
                comparison: comparison,
                checkpointIds: [],
                reviewGeneration: 3,
                generatedAtUnixMilliseconds: 4
            )
        )
    }

    private func makeReviewPackageWithMismatchedContentResourceId() throws -> BridgeReviewPackage {
        let package = try makeReviewPackage()
        let item = try #require(package.itemsById["item-source"])
        let head = try #require(item.contentRoles.head)
        let updatedHead = BridgeContentHandle(
            handleId: head.handleId,
            itemId: head.itemId,
            role: head.role,
            endpointId: head.endpointId,
            reviewGeneration: head.reviewGeneration,
            resourceUrl: "agentstudio://resource/review/content/foreign-\(head.handleId)?generation=3",
            contentHash: head.contentHash,
            contentHashAlgorithm: head.contentHashAlgorithm,
            cacheKey: head.cacheKey,
            mimeType: head.mimeType,
            language: head.language,
            sizeBytes: head.sizeBytes,
            isBinary: head.isBinary
        )
        let updatedItem = BridgeReviewItemDescriptor(
            itemId: item.itemId,
            itemKind: item.itemKind,
            itemVersion: item.itemVersion,
            basePath: item.basePath,
            headPath: item.headPath,
            changeKind: item.changeKind,
            fileClass: item.fileClass,
            language: item.language,
            extension: item.extension,
            sizeBytes: item.sizeBytes,
            baseContentHash: item.baseContentHash,
            headContentHash: item.headContentHash,
            contentHashAlgorithm: item.contentHashAlgorithm,
            additions: item.additions,
            deletions: item.deletions,
            isHiddenByDefault: item.isHiddenByDefault,
            hiddenReason: item.hiddenReason,
            reviewPriority: item.reviewPriority,
            contentRoles: BridgeReviewItemDescriptor.ContentRoles(
                base: item.contentRoles.base,
                head: updatedHead,
                diff: item.contentRoles.diff,
                file: item.contentRoles.file
            ),
            cacheKey: item.cacheKey,
            provenance: item.provenance,
            annotationSummary: item.annotationSummary,
            reviewState: item.reviewState,
            collapsed: item.collapsed
        )
        return BridgeReviewPackage(
            packageId: package.packageId,
            schemaVersion: package.schemaVersion,
            reviewGeneration: package.reviewGeneration,
            revision: package.revision,
            query: package.query,
            baseEndpoint: package.baseEndpoint,
            headEndpoint: package.headEndpoint,
            orderedItemIds: package.orderedItemIds,
            itemsById: package.itemsById.merging([updatedItem.itemId: updatedItem]) { _, next in next },
            groups: package.groups,
            summary: package.summary,
            filterState: package.filterState,
            generatedAtUnixMilliseconds: package.generatedAtUnixMilliseconds
        )
    }
}

import Foundation
import Testing

@testable import AgentStudio

@Suite("Bridge product Review metadata contracts")
struct BridgeProductReviewMetadataContractTests {
    @Test("decodes the six Review events and six delta operations")
    func decodesClosedReviewMetadataUnion() throws {
        var window = reviewSnapshotObject()
        window["eventKind"] = "review.window"
        window.removeValue(forKey: "baseEndpoint")
        window.removeValue(forKey: "headEndpoint")
        window.removeValue(forKey: "query")

        var delta = reviewIdentityObject(eventKind: "review.delta")
        delta["contentSources"] = [reviewContentSourceObject()]
        delta["fromRevision"] = 10
        delta["operations"] = [
            ["item": reviewItemMetadataObject(), "operationKind": "upsertItem"],
            ["itemIds": ["review-item-1"], "operationKind": "removeItems"],
            ["itemIds": ["review-item-1"], "operationKind": "replaceItemOrder"],
            [
                "deleteCount": 1,
                "operationKind": "spliceTreeRows",
                "rows": [reviewTreeRowObject()],
                "startIndex": 0,
            ],
            [
                "facts": [reviewExtentFactObject()],
                "operationKind": "upsertExtentFacts",
            ],
            [
                "descriptorIds": ["review-descriptor-1"],
                "operationKind": "invalidateContentSources",
            ],
        ]
        delta["summary"] = reviewSummaryObject()
        delta["toRevision"] = 11

        var invalidated = reviewIdentityObject(eventKind: "review.invalidated")
        invalidated["itemIds"] = ["review-item-1"]
        invalidated["pathHints"] = ["src/file.ts"]
        invalidated["reason"] = "watchEvent"
        invalidated["scope"] = "items"

        var reset = reviewIdentityObject(eventKind: "review.reset")
        reset["reason"] = "providerRestart"

        let eventObjects = [
            reviewIdentityObject(eventKind: "review.sourceAccepted"),
            reviewSnapshotObject(),
            window,
            delta,
            invalidated,
            reset,
        ]

        let events = try eventObjects.map(decodeReviewMetadataEvent)

        #expect(events.count == 6)
        #expect(events.map(\.generation) == Array(repeating: 7, count: 6))
        #expect(events.map(\.packageId) == Array(repeating: "review-package-1", count: 6))
        guard case .delta(let deltaEvent) = events[3] else {
            Issue.record("Expected Review delta event")
            return
        }
        #expect(deltaEvent.operations.count == 6)
    }

    @Test("rejects deep unknown keys, legacy fields, and retired tree operations")
    func rejectsUnknownAndLegacyReviewMetadata() throws {
        var snapshot = reviewSnapshotObject()
        var baseEndpoint = try #require(snapshot["baseEndpoint"] as? [String: Any])
        baseEndpoint["legacyEndpoint"] = true
        snapshot["baseEndpoint"] = baseEndpoint
        #expect(throws: (any Error).self) { try decodeReviewMetadataEvent(snapshot) }

        snapshot = reviewSnapshotObject()
        var items = try #require(snapshot["itemMetadata"] as? [[String: Any]])
        items[0]["resourceUrl"] = "agentstudio://resource/review/content/legacy"
        snapshot["itemMetadata"] = items
        #expect(throws: (any Error).self) { try decodeReviewMetadataEvent(snapshot) }

        snapshot = reviewSnapshotObject()
        var sources = try #require(snapshot["contentSources"] as? [[String: Any]])
        sources[0]["contents"] = "inline bytes are forbidden"
        snapshot["contentSources"] = sources
        #expect(throws: (any Error).self) { try decodeReviewMetadataEvent(snapshot) }

        for legacyField in ["resourceUrl", "selectedItemId", "selectedFilePath"] {
            snapshot = reviewSnapshotObject()
            snapshot[legacyField] = "legacy"
            #expect(throws: (any Error).self) { try decodeReviewMetadataEvent(snapshot) }
        }

        for retiredOperation in ["upsertTreeRows", "removeTreeRows"] {
            var delta = reviewDeltaObject(
                operations: [
                    [
                        "operationKind": retiredOperation,
                        "rows": [reviewTreeRowObject()],
                    ]
                ]
            )
            delta["revision"] = 11
            #expect(throws: (any Error).self) { try decodeReviewMetadataEvent(delta) }
        }
    }

    @Test("enforces ordered window count, bounds, finality, and snapshot origin")
    func enforcesReviewWindowInvariants() throws {
        var snapshot = reviewSnapshotObject()
        var itemWindow = try #require(snapshot["itemWindow"] as? [String: Any])
        itemWindow["itemCount"] = 0
        snapshot["itemWindow"] = itemWindow
        #expect(throws: (any Error).self) { try decodeReviewMetadataEvent(snapshot) }

        snapshot = reviewSnapshotObject()
        itemWindow = try #require(snapshot["itemWindow"] as? [String: Any])
        itemWindow["finalWindow"] = false
        snapshot["itemWindow"] = itemWindow
        #expect(throws: (any Error).self) { try decodeReviewMetadataEvent(snapshot) }

        snapshot = reviewSnapshotObject()
        itemWindow = try #require(snapshot["itemWindow"] as? [String: Any])
        itemWindow["startIndex"] = 1
        itemWindow["totalItemCount"] = 2
        snapshot["itemWindow"] = itemWindow
        #expect(throws: (any Error).self) { try decodeReviewMetadataEvent(snapshot) }

        var window = reviewSnapshotObject()
        window["eventKind"] = "review.window"
        window.removeValue(forKey: "baseEndpoint")
        window.removeValue(forKey: "headEndpoint")
        window.removeValue(forKey: "query")
        itemWindow = try #require(window["itemWindow"] as? [String: Any])
        itemWindow["startIndex"] = 3
        itemWindow["totalItemCount"] = 4
        window["itemWindow"] = itemWindow
        var treeWindow = try #require(window["treeWindow"] as? [String: Any])
        treeWindow["startIndex"] = 6
        treeWindow["totalRowCount"] = 7
        window["treeWindow"] = treeWindow
        _ = try decodeReviewMetadataEvent(window)

        itemWindow["totalItemCount"] = 3
        window["itemWindow"] = itemWindow
        #expect(throws: (any Error).self) { try decodeReviewMetadataEvent(window) }
    }

    @Test("enforces content-source identity, delta lineage, and unique item ordering")
    func enforcesReviewIdentityAndDeltaInvariants() throws {
        for mismatch in [
            ("packageId", "review-package-2"),
            ("reviewGeneration", 8),
            ("sourceIdentity", "review-query-2"),
        ] as [(String, Any)] {
            var snapshot = reviewSnapshotObject()
            var sources = try #require(snapshot["contentSources"] as? [[String: Any]])
            sources[0][mismatch.0] = mismatch.1
            snapshot["contentSources"] = sources
            #expect(throws: (any Error).self) { try decodeReviewMetadataEvent(snapshot) }
        }

        var delta = reviewDeltaObject()
        delta["revision"] = 12
        #expect(throws: (any Error).self) { try decodeReviewMetadataEvent(delta) }

        delta = reviewDeltaObject()
        delta["fromRevision"] = 12
        #expect(throws: (any Error).self) { try decodeReviewMetadataEvent(delta) }

        for operationKind in ["removeItems", "replaceItemOrder"] {
            delta = reviewDeltaObject(
                operations: [
                    [
                        "itemIds": ["review-item-1", "review-item-1"],
                        "operationKind": operationKind,
                    ]
                ]
            )
            #expect(throws: (any Error).self) { try decodeReviewMetadataEvent(delta) }
        }
    }

    @Test("requires frame generation parity and preflights the 128 KiB metadata ceiling")
    func enforcesReviewFrameGenerationAndBodyCeiling() throws {
        var frameObject = reviewMetadataFrameObject(event: reviewSnapshotObject())
        let validFrame = try decodeReviewMetadataFrame(frameObject)
        let encodedFrame = try BridgeProductMetadataFrameCodec.encode(validFrame)
        let decoder = try BridgeProductMetadataFrameDecoder()

        let decodedFrames = try decoder.append(encodedFrame)
        try decoder.finish()

        #expect(decodedFrames == [validFrame])
        #expect(encodedFrame.count <= BridgeProductWireContract.maximumMetadataFrameBytes + 4)

        frameObject["sourceGeneration"] = 8
        #expect(throws: (any Error).self) { try decodeReviewMetadataFrame(frameObject) }

        var oversizedSnapshot = reviewSnapshotObject()
        let repeatedItems = Array(repeating: reviewItemMetadataObject(), count: 256)
        oversizedSnapshot["itemMetadata"] = repeatedItems
        var oversizedWindow = try #require(oversizedSnapshot["itemWindow"] as? [String: Any])
        oversizedWindow["itemCount"] = repeatedItems.count
        oversizedWindow["totalItemCount"] = repeatedItems.count
        oversizedSnapshot["itemWindow"] = oversizedWindow
        let oversizedFrame = try decodeReviewMetadataFrame(
            reviewMetadataFrameObject(event: oversizedSnapshot)
        )

        #expect(throws: (any Error).self) {
            try BridgeProductMetadataFrameCodec.encode(oversizedFrame)
        }
    }
}

private func decodeReviewMetadataEvent(_ object: [String: Any]) throws -> BridgeProductReviewMetadataEvent {
    let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    return try BridgeProductStrictJSON.decode(BridgeProductReviewMetadataEvent.self, from: data)
}

private func decodeReviewMetadataFrame(_ object: [String: Any]) throws -> BridgeProductMetadataFrame {
    let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    return try BridgeProductStrictJSON.decode(BridgeProductMetadataFrame.self, from: data)
}

private func reviewIdentityObject(eventKind: String) -> [String: Any] {
    [
        "eventKind": eventKind,
        "generation": 7,
        "packageId": "review-package-1",
        "revision": 11,
        "sourceIdentity": "review-query-1",
    ]
}

private func reviewSnapshotObject() -> [String: Any] {
    var snapshot = reviewIdentityObject(eventKind: "review.snapshot")
    snapshot["baseEndpoint"] = reviewEndpointObject(
        endpointId: "review-base-endpoint",
        kind: "gitRef",
        label: "main",
        providerIdentity: "git-ref:main"
    )
    snapshot["contentSources"] = [reviewContentSourceObject()]
    snapshot["extentFacts"] = [reviewExtentFactObject()]
    snapshot["headEndpoint"] = reviewEndpointObject(
        endpointId: "review-head-endpoint",
        kind: "workingTree",
        label: "Working Tree",
        providerIdentity: "working-tree"
    )
    snapshot["itemMetadata"] = [reviewItemMetadataObject()]
    snapshot["itemWindow"] = [
        "finalWindow": true,
        "itemCount": 1,
        "startIndex": 0,
        "totalItemCount": 1,
    ]
    snapshot["query"] = reviewQueryObject()
    snapshot["summary"] = reviewSummaryObject()
    snapshot["treeRows"] = [reviewTreeRowObject()]
    snapshot["treeWindow"] = [
        "finalWindow": true,
        "rowCount": 1,
        "startIndex": 0,
        "totalRowCount": 1,
    ]
    return snapshot
}

private func reviewDeltaObject(
    operations: [[String: Any]] = [
        [
            "deleteCount": 0,
            "operationKind": "spliceTreeRows",
            "rows": [reviewTreeRowObject()],
            "startIndex": 0,
        ]
    ]
) -> [String: Any] {
    var delta = reviewIdentityObject(eventKind: "review.delta")
    delta["contentSources"] = [reviewContentSourceObject()]
    delta["fromRevision"] = 10
    delta["operations"] = operations
    delta["summary"] = reviewSummaryObject()
    delta["toRevision"] = 11
    return delta
}

private func reviewEndpointObject(
    endpointId: String,
    kind: String,
    label: String,
    providerIdentity: String
) -> [String: Any] {
    [
        "createdAtUnixMilliseconds": 1,
        "endpointId": endpointId,
        "kind": kind,
        "label": label,
        "providerIdentity": providerIdentity,
        "repoId": "repo-1",
        "worktreeId": "worktree-1",
    ]
}

private func reviewContentSourceObject() -> [String: Any] {
    [
        "contentDigest": [
            "algorithm": "sha256",
            "authority": "authoritative",
            "value": String(repeating: "a", count: 64),
        ],
        "contentKind": "review.content",
        "descriptorId": "review-descriptor-1",
        "encoding": "utf-8",
        "endpointId": "review-endpoint-1",
        "handleId": "review-handle-1",
        "isBinary": false,
        "itemId": "review-item-1",
        "language": "typescript",
        "mimeType": "text/plain",
        "packageId": "review-package-1",
        "reviewGeneration": 7,
        "role": "head",
        "sourceIdentity": "review-query-1",
        "wholeByteLength": 12,
    ]
}

private func reviewItemMetadataObject() -> [String: Any] {
    [
        "basePath": "src/file.ts",
        "changeKind": "modified",
        "contentDescriptorIdsByRole": ["head": "review-descriptor-1"],
        "contentHashesByRole": ["head": String(repeating: "a", count: 64)],
        "contentRoles": ["head"],
        "extension": "ts",
        "fileClass": "source",
        "headPath": "src/file.ts",
        "isHiddenByDefault": false,
        "itemId": "review-item-1",
        "language": "typescript",
        "mimeTypes": ["text/plain"],
        "provenance": [
            "agentSessionIds": [],
            "operationIds": [],
            "promptIds": [],
        ],
        "reviewPriority": "normal",
        "reviewState": "unreviewed",
    ]
}

private func reviewTreeRowObject() -> [String: Any] {
    [
        "depth": 0,
        "isDirectory": false,
        "itemId": "review-item-1",
        "path": "src/file.ts",
        "rowId": "review-row-1",
    ]
}

private func reviewExtentFactObject() -> [String: Any] {
    [
        "contentRole": "head",
        "itemId": "review-item-1",
        "lineCount": 3,
    ]
}

private func reviewSummaryObject() -> [String: Any] {
    [
        "additions": 2,
        "deletions": 1,
        "filesChanged": 1,
        "hiddenFileCount": 0,
        "visibleFileCount": 1,
    ]
}

private func reviewQueryObject() -> [String: Any] {
    [
        "baseEndpointId": "review-base-endpoint",
        "comparisonSemantics": "threeDot",
        "fileTarget": NSNull(),
        "grouping": ["kind": "folder"],
        "headEndpointId": "review-head-endpoint",
        "pathScope": [],
        "provenanceFilter": [
            "agentSessionIds": [],
            "operationIds": [],
            "paneIds": [],
            "promptIds": [],
            "sourceKinds": [],
        ],
        "queryId": "review-query-1",
        "queryKind": "compare",
        "repoId": "repo-1",
        "viewFilter": [
            "changeKinds": [],
            "excludedExtensions": [],
            "excludedFileClasses": [],
            "excludedPathGlobs": [],
            "includedExtensions": [],
            "includedFileClasses": [],
            "includedPathGlobs": [],
            "reviewStates": [],
            "showBinaryFiles": true,
            "showHiddenFiles": false,
            "showLargeFiles": true,
        ],
        "worktreeId": "worktree-1",
    ]
}

private func reviewMetadataFrameObject(event: [String: Any]) -> [String: Any] {
    [
        "cursor": "review-cursor-1",
        "data": [
            "event": event,
            "subscriptionKind": "review.metadata",
        ],
        "interestRevision": 1,
        "interestSha256": String(repeating: "a", count: 64),
        "kind": "subscription.data",
        "metadataStreamId": "metadata-stream-1",
        "paneSessionId": "pane-session-1",
        "sourceGeneration": 7,
        "streamSequence": 1,
        "subscriptionId": "review-subscription-1",
        "subscriptionKind": "review.metadata",
        "subscriptionSequence": 1,
        "wireVersion": 2,
        "workerDerivationEpoch": 3,
        "workerInstanceId": "worker-instance-1",
    ]
}

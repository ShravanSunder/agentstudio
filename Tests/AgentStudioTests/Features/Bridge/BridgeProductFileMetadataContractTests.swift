import Foundation
import Testing

@testable import AgentStudioBridge

struct BridgeProductFileMetadataContractTests {
    @Test("File metadata accepts every closed event and round-trips exactly")
    func acceptsEveryClosedEventAndRoundTripsExactly() throws {
        let events: [[String: Any]] = [
            ["eventKind": "file.sourceAccepted", "source": source],
            memberGroupsEvent,
            [
                "eventKind": "file.treeWindow",
                "finalWindow": true,
                "lineage": ["lane": "foreground", "loadedBy": "startup_window"],
                "pathScope": ["src"],
                "rows": [row, openedDocumentRow],
                "source": source,
                "startIndex": 0,
                "totalRowCount": 2,
            ],
            [
                "eventKind": "file.treeDelta",
                "operations": [
                    ["op": "upsertRows", "rows": [row]],
                    ["op": "removeRows", "paths": ["src/old.ts"], "rowIds": ["row-old"]],
                ],
                "source": source,
            ],
            [
                "eventKind": "file.statusPatch",
                "patch": [
                    "ahead": 1,
                    "behind": 0,
                    "branchName": "main",
                    "patchKind": "summary",
                    "staged": 1,
                    "unstaged": 2,
                    "untracked": 3,
                ],
                "source": source,
            ],
            descriptorReady,
            lineLimitedDescriptorReady,
            binaryDescriptorReady,
            unavailableDescriptorReady,
            [
                "eventKind": "file.invalidated",
                "fileId": "file-1",
                "path": "src/file.ts",
                "reason": "contentChanged",
                "replacementDescriptor": descriptorReadyPayload,
                "source": source,
            ],
        ]

        for event in events {
            do {
                let decoded = try decode(event)
                let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(decoded)) as? NSDictionary
                #expect(encoded?.isEqual(to: event) == true)
            } catch {
                let eventKind = event["eventKind"] as? String ?? "unknown event"
                Issue.record("\(eventKind): \(error)")
            }
        }
    }

    @Test("File metadata requires nullable facts and rejects legacy or cross-wired fields")
    func rejectsLegacyCrossWiredAndMissingNullableFacts() throws {
        var missingLanguage = descriptorReady
        missingLanguage.removeValue(forKey: "language")
        var legacyHandle = descriptorReady
        legacyHandle["contentHandle"] = "legacy-handle"
        var mismatchedSource = descriptorReady
        var mismatchedAvailability = try #require(mismatchedSource["availability"] as? [String: Any])
        var mismatchedContentDescriptor = try #require(
            mismatchedAvailability["contentDescriptor"] as? [String: Any]
        )
        var mismatchedContentSource = try #require(
            mismatchedContentDescriptor["source"] as? [String: Any]
        )
        mismatchedContentSource["sourceCursor"] = "different-source-cursor"
        mismatchedContentDescriptor["source"] = mismatchedContentSource
        mismatchedAvailability["contentDescriptor"] = mismatchedContentDescriptor
        mismatchedSource["availability"] = mismatchedAvailability
        var legacyEnvelope: [String: Any] = [
            "eventKind": "file.treeWindow",
            "finalWindow": true,
            "lineage": ["lane": "foreground", "loadedBy": "startup_window"],
            "pathScope": [],
            "rows": [],
            "source": source,
            "startIndex": 0,
            "totalRowCount": 0,
        ]
        legacyEnvelope["streamId"] = "legacy-stream"
        legacyEnvelope["generation"] = 11
        legacyEnvelope["sequence"] = 1
        var ignoredStatusRow = row
        ignoredStatusRow["changeStatus"] = "ignored"
        var missingFileClassRow = row
        missingFileClassRow.removeValue(forKey: "fileClass")
        var invalidFileClassRow = row
        invalidFileClassRow["fileClass"] = "text"
        var missingDocumentLocationRow = row
        missingDocumentLocationRow.removeValue(forKey: "documentLocation")
        var relativeDocumentLocationRow = openedDocumentRow
        relativeDocumentLocationRow["documentLocation"] = "tmp/notes.md"
        var directoryDocumentLocationRow = openedDocumentRow
        directoryDocumentLocationRow["isDirectory"] = true
        directoryDocumentLocationRow["fileClass"] = NSNull()
        let closedStatusWindow: [String: Any] = [
            "eventKind": "file.treeWindow",
            "finalWindow": true,
            "lineage": ["lane": "foreground", "loadedBy": "startup_window"],
            "pathScope": [],
            "rows": [ignoredStatusRow],
            "source": source,
            "startIndex": 0,
            "totalRowCount": 1,
        ]
        func treeWindow(row: [String: Any]) -> [String: Any] {
            [
                "eventKind": "file.treeWindow",
                "finalWindow": true,
                "lineage": ["lane": "foreground", "loadedBy": "startup_window"],
                "pathScope": [],
                "rows": [row],
                "source": source,
                "startIndex": 0,
                "totalRowCount": 1,
            ]
        }
        let crossWiredStatusPatch: [String: Any] = [
            "eventKind": "file.statusPatch",
            "patch": [
                "patchKind": "invalidated",
                "reason": "git_status_changed",
                "staged": 1,
            ],
            "source": source,
        ]

        for event in [
            missingLanguage,
            legacyHandle,
            mismatchedSource,
            legacyEnvelope,
            closedStatusWindow,
            treeWindow(row: missingFileClassRow),
            treeWindow(row: invalidFileClassRow),
            treeWindow(row: missingDocumentLocationRow),
            treeWindow(row: relativeDocumentLocationRow),
            treeWindow(row: directoryDocumentLocationRow),
            crossWiredStatusPatch,
        ] {
            #expect(throws: (any Error).self) { _ = try decode(event) }
        }
    }

    @Test("File member groups name each worktree, group path and opened document once and reject unknown keys")
    func memberGroupsRejectDuplicatesAndUnknownKeys() throws {
        // Arrange
        var duplicateWorktree = memberGroupsEvent
        duplicateWorktree["groups"] = [memberGroup("app", "worktree-a"), memberGroup("app (2)", "worktree-a")]
        var duplicateGroupPath = memberGroupsEvent
        duplicateGroupPath["groups"] = [memberGroup("app", "worktree-a"), memberGroup("app", "worktree-b")]
        var unknownGroupKey = memberGroupsEvent
        unknownGroupKey["groups"] = [memberGroup("app", "worktree-a").merging(["rootPath": "/tmp/app"]) { $1 }]
        var missingNestedRoots = memberGroupsEvent
        missingNestedRoots["groups"] = [
            ["groupPath": "app", "identityPrefix": "mapp.", "worktreeId": "worktree-a"]
        ]
        var negativeRevision = memberGroupsEvent
        negativeRevision["membershipRevision"] = -1
        var missingRevision = memberGroupsEvent
        missingRevision.removeValue(forKey: "membershipRevision")
        var missingOpenedDocuments = memberGroupsEvent
        missingOpenedDocuments.removeValue(forKey: "openedDocuments")
        var duplicateDocumentLocation = memberGroupsEvent
        duplicateDocumentLocation["openedDocuments"] = [
            openedDocument("Open Files/notes.md", "/Users/example/notes.md"),
            openedDocument("Open Files/notes (2).md", "/Users/example/notes.md"),
        ]
        var relativeDocumentLocation = memberGroupsEvent
        relativeDocumentLocation["openedDocuments"] = [openedDocument("Open Files/notes.md", "notes.md")]

        // Act / Assert
        for invalid in [
            duplicateWorktree, duplicateGroupPath, unknownGroupKey, missingNestedRoots, negativeRevision,
            missingRevision, missingOpenedDocuments, duplicateDocumentLocation, relativeDocumentLocation,
        ] {
            #expect(throws: (any Error).self) { try decode(invalid) }
        }
    }

    @Test("File descriptors enforce canonical UTF-8 prefix and truncation facts")
    func enforcesCanonicalPrefixAndTruncationFacts() throws {
        var mismatchedPayloadLength = descriptorReady
        mismatchedPayloadLength["payloadByteCount"] = 119
        var invalidEncoding = descriptorReady
        invalidEncoding["encoding"] = "utf-16"
        var fabricatedBinaryFacts = binaryDescriptorReady
        fabricatedBinaryFacts["payloadLineCount"] = 1
        var invalidLineLimit = descriptorReady
        invalidLineLimit["payloadByteCount"] = 119
        invalidLineLimit["payloadLineCount"] = 10_000
        invalidLineLimit["totalLineCount"] = NSNull()
        invalidLineLimit["truncationKind"] = "lineLimit"
        invalidLineLimit["endsWithNewline"] = false
        invalidLineLimit["virtualizedExtentKind"] = "previewBounded"
        var invalidMidLine = descriptorReady
        invalidMidLine["endsMidLine"] = true
        invalidMidLine["endsWithNewline"] = true
        var nullableDigestDescriptor = contentDescriptor
        nullableDigestDescriptor["expectedSha256"] = NSNull()
        var nullableDigest = descriptorReady
        nullableDigest["availability"] = [
            "availabilityKind": "available",
            "contentDescriptor": nullableDigestDescriptor,
        ]
        var nullableLengthDescriptor = contentDescriptor
        nullableLengthDescriptor["declaredByteLength"] = NSNull()
        var nullableLength = descriptorReady
        nullableLength["availability"] = [
            "availabilityKind": "available",
            "contentDescriptor": nullableLengthDescriptor,
        ]
        var narrowLineWindowDescriptor = contentDescriptor
        var narrowLineWindow = try #require(narrowLineWindowDescriptor["window"] as? [String: Any])
        narrowLineWindow["maximumLines"] = 11
        narrowLineWindowDescriptor["window"] = narrowLineWindow
        var narrowLineWindowEvent = descriptorReady
        narrowLineWindowEvent["availability"] = [
            "availabilityKind": "available",
            "contentDescriptor": narrowLineWindowDescriptor,
        ]
        var emptyWithNewline = descriptorReady
        emptyWithNewline["availability"] = [
            "availabilityKind": "available",
            "contentDescriptor": emptyContentDescriptor,
        ]
        emptyWithNewline["endsWithNewline"] = true
        emptyWithNewline["payloadByteCount"] = 0
        emptyWithNewline["payloadLineCount"] = 0
        emptyWithNewline["sizeBytes"] = 0
        emptyWithNewline["totalLineCount"] = 0
        var completePreview = descriptorReady
        completePreview["virtualizedExtentKind"] = "previewBounded"
        var availableUnavailable = descriptorReady
        availableUnavailable["virtualizedExtentKind"] = "unavailable"
        var truncatedExact = lineLimitedDescriptorReady
        truncatedExact["totalLineCount"] = 10_000
        truncatedExact["virtualizedExtentKind"] = "exactLineCount"
        var removedTooLarge = unavailableDescriptorReady
        removedTooLarge["availability"] = [
            "availabilityKind": "unavailable",
            "reason": "too_large",
        ]

        for event in [
            mismatchedPayloadLength,
            invalidEncoding,
            fabricatedBinaryFacts,
            invalidLineLimit,
            invalidMidLine,
            nullableDigest,
            nullableLength,
            narrowLineWindowEvent,
            emptyWithNewline,
            completePreview,
            availableUnavailable,
            truncatedExact,
            estimatedDescriptorReady,
            removedTooLarge,
        ] {
            #expect(throws: (any Error).self) { _ = try decode(event) }
        }
    }

    @Test("File metadata caps tree rows, operations, and aggregate delta members")
    func enforcesCollectionCeilings() throws {
        #expect(BridgeProductWireContract.maximumFileMetadataTreeWindowRowCount == 256)
        #expect(BridgeProductWireContract.maximumFileMetadataOperationCount == 256)
        #expect(BridgeProductWireContract.maximumFileMetadataDeltaMemberCount == 256)

        let excessRows = (0...BridgeProductWireContract.maximumFileMetadataTreeWindowRowCount).map {
            treeRow(index: $0)
        }
        let oversizedWindow: [String: Any] = [
            "eventKind": "file.treeWindow",
            "finalWindow": true,
            "lineage": ["lane": "foreground", "loadedBy": "startup_window"],
            "pathScope": [],
            "rows": excessRows,
            "source": source,
            "startIndex": 0,
            "totalRowCount": excessRows.count,
        ]
        #expect(throws: (any Error).self) { _ = try decode(oversizedWindow) }

        let excessOperations = (0...BridgeProductWireContract.maximumFileMetadataOperationCount).map {
            ["op": "removeRows", "paths": [], "rowIds": ["row-\($0)"]] as [String: Any]
        }
        #expect(throws: (any Error).self) {
            _ = try decode([
                "eventKind": "file.treeDelta",
                "operations": excessOperations,
                "source": source,
            ])
        }

        #expect(throws: (any Error).self) {
            _ = try decode([
                "eventKind": "file.treeDelta",
                "operations": [["op": "upsertRows", "rows": excessRows]],
                "source": source,
            ])
        }
    }

    @Test("File metadata rejects invalid producer values during encoding")
    func rejectsInvalidProducerValuesDuringEncoding() {
        #expect(throws: (any Error).self) {
            _ = try JSONEncoder().encode(
                BridgeProductFileTreeOperation.removeRows(paths: [], rowIds: [])
            )
        }
        #expect(throws: (any Error).self) {
            _ = try JSONEncoder().encode(
                BridgeProductFileStatusPatch.summary(
                    BridgeProductFileStatusSummary(
                        ahead: -1,
                        behind: nil,
                        branchName: nil,
                        staged: nil,
                        unstaged: nil,
                        untracked: nil
                    )
                )
            )
        }
    }

    private var source: [String: Any] {
        [
            "collectionToken": "root-token-1",
            "rootRevisionToken": NSNull(),
            "sourceCursor": "source-cursor-1",
            "sourceId": "source-1",
            "subscriptionGeneration": 11,
        ]
    }

    private var row: [String: Any] { treeRow(index: 1) }

    private var openedDocumentRow: [String: Any] {
        [
            "changeStatus": NSNull(),
            "depth": 1,
            "documentLocation": "/private/tmp/notes.md",
            "fileId": "opened-file-1",
            "fileClass": "docs",
            "isDirectory": false,
            "lineCount": NSNull(),
            "name": "notes.md",
            "parentPath": "Open Files",
            "path": "Open Files/notes.md",
            "rowId": "opened-row-1",
            "sizeBytes": 42,
        ]
    }

    private func treeRow(index: Int) -> [String: Any] {
        [
            "changeStatus": "modified",
            "depth": 1,
            "documentLocation": NSNull(),
            "fileId": "file-\(index)",
            "fileClass": "source",
            "isDirectory": false,
            "lineCount": 12,
            "name": "file-\(index).ts",
            "parentPath": "src",
            "path": "src/file-\(index).ts",
            "rowId": "row-\(index)",
            "sizeBytes": 120,
        ]
    }

    private var descriptorReadyPayload: [String: Any] {
        [
            "availability": ["availabilityKind": "available", "contentDescriptor": contentDescriptor],
            "encoding": "utf-8",
            "endsMidLine": false,
            "endsWithNewline": true,
            "estimatedContentHeightPixels": NSNull(),
            "fileExtension": "ts",
            "fileId": "file-1",
            "language": "typescript",
            "modifiedAtUnixMilliseconds": 1_720_000_000_000,
            "path": "src/file.ts",
            "payloadByteCount": 120,
            "payloadLineCount": 12,
            "rowId": "row-1",
            "sizeBytes": 120,
            "source": source,
            "totalLineCount": 12,
            "truncationKind": "none",
            "virtualizedExtentKind": "exactLineCount",
        ]
    }

    private var descriptorReady: [String: Any] {
        var value = descriptorReadyPayload
        value["eventKind"] = "file.descriptorReady"
        return value
    }

    private var binaryDescriptorReady: [String: Any] {
        var value = descriptorReady
        value["availability"] = ["availabilityKind": "binary"]
        value["encoding"] = NSNull()
        value["endsMidLine"] = false
        value["endsWithNewline"] = false
        value["estimatedContentHeightPixels"] = NSNull()
        value["fileExtension"] = NSNull()
        value["language"] = NSNull()
        value["modifiedAtUnixMilliseconds"] = NSNull()
        value["payloadByteCount"] = 0
        value["payloadLineCount"] = 0
        value["totalLineCount"] = NSNull()
        value["truncationKind"] = "none"
        value["virtualizedExtentKind"] = "unavailable"
        return value
    }

    private var lineLimitedDescriptorReady: [String: Any] {
        var value = descriptorReady
        value["payloadLineCount"] = 10_000
        value["sizeBytes"] = 121
        value["totalLineCount"] = NSNull()
        value["truncationKind"] = "lineLimit"
        value["virtualizedExtentKind"] = "previewBounded"
        return value
    }

    private var unavailableDescriptorReady: [String: Any] {
        var value = binaryDescriptorReady
        value["availability"] = [
            "availabilityKind": "unavailable",
            "reason": "unsupported_encoding",
        ]
        value["virtualizedExtentKind"] = "unavailable"
        return value
    }

    private var estimatedDescriptorReady: [String: Any] {
        var value = binaryDescriptorReady
        value["estimatedContentHeightPixels"] = 123.5
        value["virtualizedExtentKind"] = "estimatedHeight"
        return value
    }

    private var contentDescriptor: [String: Any] {
        [
            "contentKind": "file.content",
            "declaredByteLength": 120,
            "descriptorId": "descriptor-1",
            "encoding": "utf-8",
            "expectedSha256": String(repeating: "a", count: 64),
            "fileId": "file-1",
            "maximumBytes": 120,
            "source": source,
            "window": [
                "kind": "prefix",
                "maximumBytes": 120,
                "maximumLines": 10_000,
                "startByte": 0,
            ],
        ]
    }

    /// Mirrored in BridgeWeb's `bridge-product-file-member-group-contracts.unit.test.ts`.
    private var memberGroupsEvent: [String: Any] {
        [
            "eventKind": "file.memberGroups",
            "groups": [
                [
                    "groupPath": "app",
                    "identityPrefix": "m0123456789ab.",
                    "nestedMemberRelativeRoots": [".worktrees/feature"],
                    "worktreeId": "0198f3a2-0000-7000-8000-00000000000a",
                ],
                memberGroup("feature", "0198f3a2-0000-7000-8000-00000000000b"),
            ],
            "membershipRevision": 2,
            "openedDocuments": [
                [
                    "displayPath": "Open Files/notes.md",
                    "documentLocation": "/Users/example/notes.md",
                    "identityPrefix": "d0123456789ab.",
                ]
            ],
            "source": source,
        ]
    }

    private func openedDocument(_ displayPath: String, _ documentLocation: String) -> [String: Any] {
        ["displayPath": displayPath, "documentLocation": documentLocation, "identityPrefix": "dnotes."]
    }

    private func memberGroup(_ groupPath: String, _ worktreeId: String) -> [String: Any] {
        [
            "groupPath": groupPath, "identityPrefix": "m\(groupPath).", "nestedMemberRelativeRoots": [],
            "worktreeId": worktreeId,
        ]
    }

    private var emptyContentDescriptor: [String: Any] {
        var descriptor = contentDescriptor
        descriptor["declaredByteLength"] = 0
        descriptor["expectedSha256"] =
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        descriptor["maximumBytes"] = 0
        descriptor["window"] = [
            "kind": "prefix",
            "maximumBytes": 0,
            "maximumLines": 10_000,
            "startByte": 0,
        ]
        return descriptor
    }

    private func decode(_ object: [String: Any]) throws -> BridgeProductFileMetadataEvent {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return try BridgeProductStrictJSON.decode(BridgeProductFileMetadataEvent.self, from: data)
    }
}

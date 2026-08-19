import Foundation

enum BridgeProductStrictJSONError: Error, Equatable {
    case duplicateObjectMember
    case inputExceedsCeiling
    case invalidJSON
    case invalidUTF8
    case nestingExceedsCeiling
    case objectMemberCountExceedsCeiling
}

struct BridgeProductStrictJSONMemberVocabulary {
    fileprivate let exactUTF8MemberNames: Set<Data>

    init(_ memberNames: Set<String>) {
        exactUTF8MemberNames = Set(memberNames.map { Data($0.utf8) })
    }
}

enum BridgeProductStrictJSON {
    private static let maximumInputBytes = 256 * 1024
    private static let maximumNestingDepth = 64
    private static let maximumObjectMembers = 64
    private static let productMemberVocabulary = BridgeProductStrictJSONMemberVocabulary(
        Set([
            "activeSubscriptions",
            "activeSource",
            "activeTarget",
            "add",
            "addPathScope",
            "additions",
            "admission",
            "ahead",
            "agentSessionIds",
            "algorithm",
            "aggregateSha256",
            "attempt",
            "attemptId",
            "authority",
            "authorKind",
            "authoredAt",
            "availability",
            "availabilityKind",
            "base",
            "baseEndpoint",
            "baseEndpointId",
            "baseInterestRevision",
            "baseInterestSha256",
            "basePath",
            "baseRole",
            "basis",
            "batchCount",
            "batchIndex",
            "behind",
            "bindingRevision",
            "body",
            "branchName",
            "branches",
            "call",
            "capturedAtUnixMilliseconds",
            "candidates",
            "changeKind",
            "changeKinds",
            "changeStatus",
            "code",
            "commandId",
            "commandKind",
            "commandOutcomes",
            "comparedRole",
            "comparisonOrigin",
            "comparisonSemantics",
            "completedAt",
            "confirmsUnresolvedWork",
            "contentDescriptor",
            "contentDescriptorIdsByRole",
            "contentDigest",
            "contentHashesByRole",
            "contentKind",
            "contentRequestId",
            "contentRole",
            "contentRoles",
            "contentSequence",
            "contentSetHash",
            "contentSources",
            "contentType",
            "context",
            "baseOID",
            "cutoffUnixMilliseconds",
            "createdAfterUnixMilliseconds",
            "createdAt",
            "createdAtUnixMilliseconds",
            "createdBeforeUnixMilliseconds",
            "cursor",
            "cwdScope",
            "data",
            "declaredByteLength",
            "deleteCount",
            "deletions",
            "defaultTarget",
            "delta",
            "depth",
            "decision",
            "descriptor",
            "descriptorId",
            "descriptorIds",
            "displayedSnapshot",
            "disposition",
            "diff",
            "diffSide",
            "draft",
            "editToken",
            "eligibleMessageCount",
            "eligibleWithoutInlinePlacementCount",
            "encoding",
            "endLine",
            "endOfSource",
            "endsMidLine",
            "endsWithNewline",
            "endpointId",
            "estimatedContentHeightPixels",
            "event",
            "eventKind",
            "excerpt",
            "excludedExtensions",
            "excludedFileClasses",
            "excludedPathGlobs",
            "expectedSha256",
            "expectedDraftRevision",
            "expectedMessageCount",
            "expectedOpenThreadCount",
            "expectedSessionRevision",
            "expectedSessionCount",
            "expectedThreadCount",
            "extension",
            "extentFacts",
            "facts",
            "file",
            "fileClass",
            "fileExtension",
            "fileId",
            "fileTarget",
            "failureKind",
            "filesChanged",
            "finalWindow",
            "freshness",
            "fromRevision",
            "formatVersion",
            "flatOrdinal",
            "generation",
            "grouping",
            "handleId",
            "head",
            "headEndpoint",
            "headEndpointId",
            "headPath",
            "header",
            "hiddenFileCount",
            "identity",
            "includeStatuses",
            "includedExtensions",
            "includedFileClasses",
            "includedPathGlobs",
            "interestRevision",
            "interestSha256",
            "interests",
            "isBinary",
            "isDirectory",
            "isHiddenByDefault",
            "isLastBatchForThread",
            "isLastPage",
            "item",
            "itemCount",
            "itemId",
            "itemIds",
            "itemMetadata",
            "itemWindow",
            "kind",
            "label",
            "lane",
            "language",
            "lastAcceptedRequestSequence",
            "lastAcceptedStreamSequence",
            "savedBody",
            "savedRevision",
            "leaseId",
            "lineCount",
            "lineage",
            "limit",
            "lifecycle",
            "loadedBy",
            "location",
            "activeEditToken",
            "maximumBytes",
            "maximumContentBytes",
            "maximumLines",
            "maximumMetadataFrameBytes",
            "maximumQueuedStreamBytes",
            "maximumQueuedStreamFrames",
            "maximumRequestBodyBytes",
            "message",
            "messageId",
            "messageRevision",
            "messages",
            "metadataSourceId",
            "metadataStreamSequenceBarrier",
            "metadataStreamId",
            "method",
            "mimeType",
            "mimeTypes",
            "modifiedAtUnixMilliseconds",
            "name",
            "nativeActivity",
            "nativeSelectionRequestId",
            "nextCursor",
            "navigationCommand",
            "nextExpectedRequestSequence",
            "observedByteLength",
            "observedSha256",
            "oid",
            "offsetBytes",
            "op",
            "operationIds",
            "operationKind",
            "operation",
            "operations",
            "ordinal",
            "origin",
            "outputHistory",
            "outputKind",
            "outcome",
            "packageId",
            "paneSessionId",
            "paneIds",
            "parentPath",
            "patch",
            "patchKind",
            "page",
            "pageOrdinal",
            "path",
            "pathScope",
            "pathHints",
            "paths",
            "payload",
            "payloadByteCount",
            "payloadLineCount",
            "policy",
            "placement",
            "presentationRevision",
            "projectionRevision",
            "priorWorkerDerivationEpoch",
            "promptIds",
            "provenance",
            "provenanceFilter",
            "providerIdentity",
            "publicationId",
            "query",
            "queryId",
            "queryKind",
            "reason",
            "reconciliation",
            "recoveryStatus",
            "readiness",
            "refreshingLanes",
            "removeItemIds",
            "removePathScope",
            "removePaths",
            "replacementDescriptor",
            "remoteName",
            "repoId",
            "request",
            "requestId",
            "repositoryDefaultTarget",
            "requestSequence",
            "result",
            "resolution",
            "requiredWorkerDerivationEpoch",
            "resumeDisposition",
            "resumeFromStreamSequence",
            "retryAfterMilliseconds",
            "retryable",
            "revision",
            "reviewGeneration",
            "reviewComparison",
            "reviewItemId",
            "reviewPriority",
            "reviewState",
            "reviewStates",
            "reviewedHeadOID",
            "reviewedSubjectLabel",
            "role",
            "rootPathToken",
            "rootRevisionToken",
            "resolvedTargetOID",
            "rowId",
            "rowIds",
            "rowCount",
            "rows",
            "safeMessage",
            "scope",
            "semanticRevision",
            "sequence",
            "sessionId",
            "sessionIds",
            "sessionRevision",
            "sessions",
            "selection",
            "selectionMode",
            "messageIds",
            "excludedMessageIds",
            "sizeBytes",
            "source",
            "sourceCursor",
            "sourceEpoch",
            "sourceGeneration",
            "sourceId",
            "sourceIdentity",
            "sourceKind",
            "sourceKinds",
            "sourceRelationship",
            "sourceRole",
            "startByte",
            "startIndex",
            "startLine",
            "staged",
            "status",
            "state",
            "streamSequence",
            "streamKind",
            "streamId",
            "showBinaryFiles",
            "showHiddenFiles",
            "showLargeFiles",
            "summary",
            "summaries",
            "surface",
            "subscription",
            "subscriptionGeneration",
            "subscriptionId",
            "subscriptionKind",
            "subscriptionSequence",
            "symbolicTarget",
            "snapshotId",
            "target",
            "targetKind",
            "targetInterestRevision",
            "targetInterestSha256",
            "terminalFrameReserve",
            "threadId",
            "transferId",
            "toRevision",
            "totalDeltaItemCount",
            "totalItemCount",
            "totalLineCount",
            "totalRowCount",
            "treeRows",
            "treeWindow",
            "truncationKind",
            "unstaged",
            "untracked",
            "updateId",
            "updatedAt",
            "value",
            "version",
            "versionId",
            "viewFilter",
            "visibleFileCount",
            "virtualizedExtentKind",
            "wholeByteLength",
            "window",
            "wireVersion",
            "workerDerivationEpoch",
            "workerInstanceId",
            "worktreeId",
        ])
    )

    static func validate(_ data: Data) throws {
        try validate(data, memberVocabulary: nil)
    }

    private static func validate(
        _ data: Data,
        memberVocabulary: BridgeProductStrictJSONMemberVocabulary?
    ) throws {
        guard data.count <= maximumInputBytes else {
            throw BridgeProductStrictJSONError.inputExceedsCeiling
        }
        guard String(data: data, encoding: .utf8) != nil else {
            throw BridgeProductStrictJSONError.invalidUTF8
        }
        try data.withUnsafeBytes { bytes in
            var scanner = DuplicateMemberScanner(
                bytes: bytes,
                allowedObjectMemberNames: memberVocabulary?.exactUTF8MemberNames
            )
            try scanner.validate()
        }
    }

    static func decode<DecodedValue: Decodable>(
        _ type: DecodedValue.Type,
        from data: Data
    ) throws -> DecodedValue {
        try decode(type, from: data, memberVocabulary: productMemberVocabulary)
    }

    static func decode<DecodedValue: Decodable>(
        _ type: DecodedValue.Type,
        from data: Data,
        memberVocabulary: BridgeProductStrictJSONMemberVocabulary
    ) throws -> DecodedValue {
        try decode(
            type,
            from: data,
            memberVocabulary: memberVocabulary,
            maximumInputBytes: maximumInputBytes
        )
    }

    static func decode<DecodedValue: Decodable>(
        _ type: DecodedValue.Type,
        from data: Data,
        memberVocabulary: BridgeProductStrictJSONMemberVocabulary,
        maximumInputBytes: Int?
    ) throws -> DecodedValue {
        if let maximumInputBytes, data.count > maximumInputBytes {
            throw BridgeProductStrictJSONError.inputExceedsCeiling
        }
        guard String(data: data, encoding: .utf8) != nil else {
            throw BridgeProductStrictJSONError.invalidUTF8
        }
        try data.withUnsafeBytes { bytes in
            var scanner = DuplicateMemberScanner(
                bytes: bytes,
                allowedObjectMemberNames: memberVocabulary.exactUTF8MemberNames
            )
            try scanner.validate()
        }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw BridgeProductStrictJSONError.invalidJSON
        }
    }

    private struct DuplicateMemberScanner {
        private enum ContainerKind {
            case array
            case object
        }

        private struct ContainerScope {
            let kind: ContainerKind
            var decodedMemberNames = Set<Data>()
            var memberCount = 0
        }

        let bytes: UnsafeRawBufferPointer
        let allowedObjectMemberNames: Set<Data>?
        private var scopes: [ContainerScope] = []

        init(
            bytes: UnsafeRawBufferPointer,
            allowedObjectMemberNames: Set<Data>?
        ) {
            self.bytes = bytes
            self.allowedObjectMemberNames = allowedObjectMemberNames
        }

        mutating func validate() throws {
            var cursor = 0
            while cursor < bytes.count {
                switch bytes[cursor] {
                case 0x22:
                    let stringEnd = findStringEnd(openingQuote: cursor)
                    let nextToken = skipWhitespace(startingAt: min(stringEnd + 1, bytes.count))
                    if stringEnd < bytes.count,
                        scopes.last?.kind == .object,
                        nextToken < bytes.count,
                        bytes[nextToken] == 0x3a
                    {
                        try recordObjectMember(openingQuote: cursor, closingQuote: stringEnd)
                    }
                    cursor = min(stringEnd + 1, bytes.count)
                case 0x7b:
                    try pushScope(kind: .object)
                    cursor += 1
                case 0x5b:
                    try pushScope(kind: .array)
                    cursor += 1
                case 0x7d:
                    if scopes.last?.kind == .object {
                        scopes.removeLast()
                    }
                    cursor += 1
                case 0x5d:
                    if scopes.last?.kind == .array {
                        scopes.removeLast()
                    }
                    cursor += 1
                default:
                    cursor += 1
                }
            }
        }

        private mutating func pushScope(kind: ContainerKind) throws {
            guard scopes.count < BridgeProductStrictJSON.maximumNestingDepth else {
                throw BridgeProductStrictJSONError.nestingExceedsCeiling
            }
            scopes.append(ContainerScope(kind: kind))
        }

        private mutating func recordObjectMember(
            openingQuote: Int,
            closingQuote: Int
        ) throws {
            let rawMemberName = Data(
                bytes[(openingQuote)...closingQuote]
            )
            guard
                let decodedMemberName = try? JSONDecoder().decode(
                    String.self,
                    from: rawMemberName
                )
            else { return }

            let objectScopeIndex = scopes.count - 1
            scopes[objectScopeIndex].memberCount += 1
            guard
                scopes[objectScopeIndex].memberCount
                    <= BridgeProductStrictJSON.maximumObjectMembers
            else {
                throw BridgeProductStrictJSONError.objectMemberCountExceedsCeiling
            }

            let exactDecodedName = Data(decodedMemberName.utf8)
            guard
                allowedObjectMemberNames == nil
                    || allowedObjectMemberNames?.contains(exactDecodedName) == true
            else {
                throw BridgeProductStrictJSONError.invalidJSON
            }
            guard scopes[objectScopeIndex].decodedMemberNames.insert(exactDecodedName).inserted else {
                throw BridgeProductStrictJSONError.duplicateObjectMember
            }
        }

        private func findStringEnd(openingQuote: Int) -> Int {
            var cursor = openingQuote + 1
            while cursor < bytes.count {
                switch bytes[cursor] {
                case 0x22:
                    return cursor
                case 0x5c:
                    cursor = min(cursor + 2, bytes.count)
                default:
                    cursor += 1
                }
            }
            return bytes.count
        }

        private func skipWhitespace(startingAt start: Int) -> Int {
            var cursor = start
            while cursor < bytes.count {
                switch bytes[cursor] {
                case 0x20, 0x09, 0x0a, 0x0d:
                    cursor += 1
                default:
                    return cursor
                }
            }
            return cursor
        }
    }
}

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
            "activityRevision",
            "add",
            "addPathScope",
            "additions",
            "ahead",
            "agentSessionIds",
            "algorithm",
            "authority",
            "availability",
            "availabilityKind",
            "base",
            "baseEndpoint",
            "baseEndpointId",
            "baseInterestRevision",
            "baseInterestSha256",
            "basePath",
            "batchCount",
            "batchIndex",
            "behind",
            "branchName",
            "call",
            "changeKind",
            "changeKinds",
            "changeStatus",
            "code",
            "comparisonSemantics",
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
            "createdAfterUnixMilliseconds",
            "createdAtUnixMilliseconds",
            "createdBeforeUnixMilliseconds",
            "cursor",
            "cwdScope",
            "data",
            "declaredByteLength",
            "deleteCount",
            "deletions",
            "delta",
            "depth",
            "descriptor",
            "descriptorId",
            "descriptorIds",
            "disposition",
            "diff",
            "encoding",
            "endOfSource",
            "endsMidLine",
            "endsWithNewline",
            "endpointId",
            "estimatedContentHeightPixels",
            "event",
            "eventKind",
            "excludedExtensions",
            "excludedFileClasses",
            "excludedPathGlobs",
            "expectedSha256",
            "extension",
            "extentFacts",
            "facts",
            "file",
            "fileClass",
            "fileExtension",
            "fileId",
            "fileTarget",
            "filesChanged",
            "finalWindow",
            "freshness",
            "fromRevision",
            "generation",
            "grouping",
            "handleId",
            "head",
            "headEndpoint",
            "headEndpointId",
            "headPath",
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
            "leaseId",
            "lineCount",
            "lineage",
            "loadedBy",
            "maximumBytes",
            "maximumContentBytes",
            "maximumLines",
            "maximumMetadataFrameBytes",
            "maximumQueuedStreamBytes",
            "maximumQueuedStreamFrames",
            "maximumRequestBodyBytes",
            "metadataStreamSequenceBarrier",
            "metadataStreamId",
            "method",
            "mimeType",
            "mimeTypes",
            "modifiedAtUnixMilliseconds",
            "name",
            "nativeActivity",
            "nativeSelectionRequestId",
            "nextExpectedRequestSequence",
            "observedByteLength",
            "observedSha256",
            "offsetBytes",
            "op",
            "operationIds",
            "operationKind",
            "operations",
            "packageId",
            "paneSessionId",
            "paneIds",
            "parentPath",
            "patch",
            "patchKind",
            "path",
            "pathScope",
            "pathHints",
            "paths",
            "payloadByteCount",
            "payloadLineCount",
            "policy",
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
            "refreshingLanes",
            "removeItemIds",
            "removePathScope",
            "removePaths",
            "replacementDescriptor",
            "repoId",
            "request",
            "requestId",
            "requestSequence",
            "result",
            "requiredWorkerDerivationEpoch",
            "resumeDisposition",
            "resumeFromStreamSequence",
            "retryAfterMilliseconds",
            "retryable",
            "revision",
            "reviewGeneration",
            "reviewPriority",
            "reviewState",
            "reviewStates",
            "role",
            "rootPathToken",
            "rootRevisionToken",
            "rowId",
            "rowIds",
            "rowCount",
            "rows",
            "safeMessage",
            "scope",
            "selectionRevision",
            "sequence",
            "sessionId",
            "sizeBytes",
            "source",
            "sourceCursor",
            "sourceGeneration",
            "sourceId",
            "sourceIdentity",
            "sourceKinds",
            "startByte",
            "startIndex",
            "staged",
            "status",
            "streamSequence",
            "streamKind",
            "streamId",
            "showBinaryFiles",
            "showHiddenFiles",
            "showLargeFiles",
            "summary",
            "surface",
            "subscription",
            "subscriptionGeneration",
            "subscriptionId",
            "subscriptionKind",
            "subscriptionSequence",
            "targetInterestRevision",
            "targetInterestSha256",
            "terminalFrameReserve",
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
            "value",
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
        try validate(data, memberVocabulary: memberVocabulary)
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

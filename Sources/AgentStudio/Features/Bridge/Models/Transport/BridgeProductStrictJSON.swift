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
            "add",
            "addPathScope",
            "baseInterestRevision",
            "baseInterestSha256",
            "batchCount",
            "batchIndex",
            "call",
            "code",
            "contentKind",
            "contentRequestId",
            "contentSequence",
            "cursor",
            "cwdScope",
            "data",
            "declaredByteLength",
            "delta",
            "descriptor",
            "descriptorId",
            "disposition",
            "encoding",
            "event",
            "eventKind",
            "expectedSha256",
            "fileId",
            "freshness",
            "generation",
            "identity",
            "includeStatuses",
            "interestRevision",
            "interestSha256",
            "interests",
            "itemId",
            "itemIds",
            "kind",
            "lane",
            "lastAcceptedRequestSequence",
            "lastAcceptedStreamSequence",
            "leaseId",
            "maximumBytes",
            "maximumContentBytes",
            "maximumLines",
            "maximumMetadataFrameBytes",
            "maximumQueuedStreamBytes",
            "maximumQueuedStreamFrames",
            "maximumRequestBodyBytes",
            "metadataStreamId",
            "method",
            "nextExpectedRequestSequence",
            "observedByteLength",
            "observedSha256",
            "offsetBytes",
            "packageId",
            "paneSessionId",
            "path",
            "pathScope",
            "paths",
            "policy",
            "reason",
            "removeItemIds",
            "removePathScope",
            "removePaths",
            "repoId",
            "request",
            "requestId",
            "requestSequence",
            "result",
            "resumeDisposition",
            "resumeFromStreamSequence",
            "retryAfterMilliseconds",
            "retryable",
            "revision",
            "rootPathToken",
            "rootRevisionToken",
            "safeMessage",
            "source",
            "sourceCursor",
            "sourceGeneration",
            "sourceId",
            "sourceIdentity",
            "startByte",
            "streamSequence",
            "subscription",
            "subscriptionGeneration",
            "subscriptionId",
            "subscriptionKind",
            "subscriptionSequence",
            "targetInterestRevision",
            "targetInterestSha256",
            "terminalFrameReserve",
            "totalDeltaItemCount",
            "updateId",
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

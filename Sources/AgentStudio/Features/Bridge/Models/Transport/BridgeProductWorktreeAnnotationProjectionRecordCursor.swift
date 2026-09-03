import CryptoKit
import Foundation

struct BridgeProductAnnotationProjectionHeaderRecord: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case expectedMessageCount
        case expectedSessionCount
        case expectedThreadCount
        case projectionRevision
        case recoveryStatus
        case sessions
        case sourceGeneration
        case worktreeId
    }

    let expectedMessageCount: Int
    let expectedSessionCount: Int
    let expectedThreadCount: Int
    let projectionRevision: Int
    let recoveryStatus: BridgeProductAnnotationProjectionRecoveryStatus
    let sessions: [BridgeProductWorktreeAnnotationSessionSummary]
    let sourceGeneration: Int
    let worktreeID: String

    init(
        expectedMessageCount: Int,
        expectedSessionCount: Int,
        expectedThreadCount: Int,
        projectionRevision: Int,
        recoveryStatus: BridgeProductAnnotationProjectionRecoveryStatus,
        sessions: [BridgeProductWorktreeAnnotationSessionSummary],
        sourceGeneration: Int,
        worktreeID: String
    ) {
        self.expectedMessageCount = expectedMessageCount
        self.expectedSessionCount = expectedSessionCount
        self.expectedThreadCount = expectedThreadCount
        self.projectionRevision = projectionRevision
        self.recoveryStatus = recoveryStatus
        self.sessions = sessions
        self.sourceGeneration = sourceGeneration
        self.worktreeID = worktreeID
    }

    init(from decoder: Decoder) throws {
        try rejectAnnotationProjectionRecordUnknownKeys(decoder, keys: CodingKeys.allCases)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        expectedMessageCount = try container.decode(Int.self, forKey: .expectedMessageCount)
        expectedSessionCount = try container.decode(Int.self, forKey: .expectedSessionCount)
        expectedThreadCount = try container.decode(Int.self, forKey: .expectedThreadCount)
        projectionRevision = try container.decode(Int.self, forKey: .projectionRevision)
        recoveryStatus = try container.decode(
            BridgeProductAnnotationProjectionRecoveryStatus.self,
            forKey: .recoveryStatus
        )
        sessions = try container.decode(
            [BridgeProductWorktreeAnnotationSessionSummary].self,
            forKey: .sessions
        )
        sourceGeneration = try container.decode(Int.self, forKey: .sourceGeneration)
        worktreeID = try container.decode(String.self, forKey: .worktreeId)
        guard expectedMessageCount >= 0, expectedSessionCount >= 0, expectedThreadCount >= 0,
            projectionRevision >= 0, sourceGeneration >= 0, !worktreeID.isEmpty,
            expectedSessionCount == sessions.count
        else {
            throw BridgeProductContractDecoding.invalidValue(
                "Annotation projection header is invalid",
                codingPath: decoder.codingPath
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(expectedMessageCount, forKey: .expectedMessageCount)
        try container.encode(expectedSessionCount, forKey: .expectedSessionCount)
        try container.encode(expectedThreadCount, forKey: .expectedThreadCount)
        try container.encode(projectionRevision, forKey: .projectionRevision)
        try container.encode(recoveryStatus, forKey: .recoveryStatus)
        try container.encode(sessions, forKey: .sessions)
        try container.encode(sourceGeneration, forKey: .sourceGeneration)
        try container.encode(worktreeID, forKey: .worktreeId)
    }
}

struct BridgeProductAnnotationProjectionMessageRecord: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case context
        case message
    }

    let context: BridgeProductWorktreeAnnotationThreadContext
    let message: BridgeProductWorktreeAnnotationMessageEntry

    init(
        context: BridgeProductWorktreeAnnotationThreadContext,
        message: BridgeProductWorktreeAnnotationMessageEntry
    ) {
        self.context = context
        self.message = message
    }

    init(from decoder: Decoder) throws {
        try rejectAnnotationProjectionRecordUnknownKeys(decoder, keys: CodingKeys.allCases)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        context = try container.decode(BridgeProductWorktreeAnnotationThreadContext.self, forKey: .context)
        message = try container.decode(BridgeProductWorktreeAnnotationMessageEntry.self, forKey: .message)
        guard context.threadId == message.threadId,
            message.savedBody.map({
                $0.utf8.count <= WorktreeAnnotationMessagePolicy.maximumBodyUTF8Bytes
            }) ?? true,
            message.draft.map({
                $0.body.utf8.count <= WorktreeAnnotationMessagePolicy.maximumBodyUTF8Bytes
            }) ?? true
        else {
            throw BridgeProductContractDecoding.invalidValue(
                "Annotation message record content or thread identity is invalid",
                codingPath: decoder.codingPath
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(context, forKey: .context)
        try container.encode(message, forKey: .message)
    }
}

enum BridgeProductAnnotationProjectionRecord: Codable, Equatable, Sendable {
    case header(BridgeProductAnnotationProjectionHeaderRecord)
    case message(BridgeProductAnnotationProjectionMessageRecord)

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case header
        case kind
        case message
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(String.self, forKey: .kind)
        switch kind {
        case "header":
            try BridgeProductContractDecoding.rejectUnknownKeys(
                from: decoder,
                allowedKeys: [CodingKeys.header.rawValue, CodingKeys.kind.rawValue],
                contract: "annotation projection header record"
            )
            self = .header(
                try container.decode(BridgeProductAnnotationProjectionHeaderRecord.self, forKey: .header)
            )
        case "message":
            try BridgeProductContractDecoding.rejectUnknownKeys(
                from: decoder,
                allowedKeys: [CodingKeys.kind.rawValue, CodingKeys.message.rawValue],
                contract: "annotation projection message record"
            )
            self = .message(
                try container.decode(BridgeProductAnnotationProjectionMessageRecord.self, forKey: .message)
            )
        default:
            throw BridgeProductContractDecoding.invalidValue(
                "Invalid annotation projection record kind",
                codingPath: decoder.codingPath
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .header(let header):
            try container.encode(header, forKey: .header)
            try container.encode("header", forKey: .kind)
        case .message(let message):
            try container.encode("message", forKey: .kind)
            try container.encode(message, forKey: .message)
        }
    }
}

enum BridgeProductAnnotationProjectionRecordCursorError: Error, Equatable, Sendable {
    case invalidCapture
    case invalidPageOrdinal(Int)
    case pageCountExceedsMaximum(actualCount: Int, maximumCount: Int)
    case singletonRecordExceedsFrameMaximum(actualBytes: Int, maximumBytes: Int)
    case singletonRecordExceedsPageMaximum(actualBytes: Int, maximumBytes: Int)
    case traversalInvariantViolation
}

struct BridgeProductAnnotationProjectionRecordAnalysis: Sendable {
    let aggregateSHA256: String
    let expectedMessageCount: Int
    let expectedSessionCount: Int
    let expectedThreadCount: Int
    let pageCount: Int
    let projectionRevision: Int
    let sourceGeneration: Int

    private let capture: BridgeProductAnnotationProjectionCapture
    private let maximumFrameBytes: Int
    private let pageBoundaries: [BridgeProductAnnotationProjectionPageBoundary]

    init(
        capture: BridgeProductAnnotationProjectionCapture,
        maximumPageCount: Int = BridgeProductAnnotationProjectionContract.maximumPageCount,
        maximumPageBytes: Int = BridgeProductAnnotationProjectionContract.maximumPageBytes,
        maximumFrameBytes: Int = BridgeProductWireContract.maximumContentDataPayloadBytes
    ) throws {
        guard maximumPageCount > 0, maximumPageBytes > 0, maximumFrameBytes > 0,
            capture.projectionRevision >= 0, capture.sourceGeneration >= 0,
            !capture.worktreeID.isEmpty
        else {
            throw BridgeProductAnnotationProjectionRecordCursorError.invalidCapture
        }

        let counts = try validateAndCount(capture)
        let header = makeHeader(capture: capture, counts: counts)
        var traversal = BridgeProductAnnotationProjectionTraversal(capture: capture, header: header)
        var aggregateHasher = SHA256()
        var boundaries: [BridgeProductAnnotationProjectionPageBoundary] = []
        var pageStart = traversal.position
        var pageBytes = 0

        while let record = try traversal.currentRecord() {
            let encodedRecord = try encodeAnnotationProjectionRecord(record)
            guard encodedRecord.count <= maximumFrameBytes else {
                throw BridgeProductAnnotationProjectionRecordCursorError.singletonRecordExceedsFrameMaximum(
                    actualBytes: encodedRecord.count,
                    maximumBytes: maximumFrameBytes
                )
            }
            guard encodedRecord.count <= maximumPageBytes else {
                throw BridgeProductAnnotationProjectionRecordCursorError.singletonRecordExceedsPageMaximum(
                    actualBytes: encodedRecord.count,
                    maximumBytes: maximumPageBytes
                )
            }
            if pageBytes > 0, pageBytes + encodedRecord.count > maximumPageBytes {
                boundaries.append(
                    .init(start: pageStart, end: traversal.position, byteCount: pageBytes)
                )
                pageStart = traversal.position
                pageBytes = 0
            }
            aggregateHasher.update(data: encodedRecord)
            pageBytes += encodedRecord.count
            traversal.advance()
        }
        guard pageBytes > 0 else {
            throw BridgeProductAnnotationProjectionRecordCursorError.traversalInvariantViolation
        }
        boundaries.append(.init(start: pageStart, end: traversal.position, byteCount: pageBytes))
        guard boundaries.count <= maximumPageCount else {
            throw BridgeProductAnnotationProjectionRecordCursorError.pageCountExceedsMaximum(
                actualCount: boundaries.count,
                maximumCount: maximumPageCount
            )
        }

        self.aggregateSHA256 = aggregateHasher.finalize().map { String(format: "%02x", $0) }.joined()
        self.expectedMessageCount = counts.messageCount
        self.expectedSessionCount = counts.sessionCount
        self.expectedThreadCount = counts.threadCount
        self.pageCount = boundaries.count
        self.projectionRevision = capture.projectionRevision
        self.sourceGeneration = capture.sourceGeneration
        self.capture = capture
        self.maximumFrameBytes = maximumFrameBytes
        self.pageBoundaries = boundaries
    }

    func pageByteCount(pageOrdinal: Int) throws -> Int {
        guard pageBoundaries.indices.contains(pageOrdinal) else {
            throw BridgeProductAnnotationProjectionRecordCursorError.invalidPageOrdinal(pageOrdinal)
        }
        return pageBoundaries[pageOrdinal].byteCount
    }

    func makePageCursor(pageOrdinal: Int) throws -> BridgeProductAnnotationProjectionPageRecordCursor {
        guard pageBoundaries.indices.contains(pageOrdinal) else {
            throw BridgeProductAnnotationProjectionRecordCursorError.invalidPageOrdinal(pageOrdinal)
        }
        return BridgeProductAnnotationProjectionPageRecordCursor(
            capture: capture,
            boundary: pageBoundaries[pageOrdinal],
            maximumFrameBytes: maximumFrameBytes,
            counts: .init(
                sessionCount: expectedSessionCount,
                threadCount: expectedThreadCount,
                messageCount: expectedMessageCount
            )
        )
    }
}

struct BridgeProductAnnotationProjectionPageRecordCursor: Sendable {
    private let boundary: BridgeProductAnnotationProjectionPageBoundary
    private let maximumFrameBytes: Int
    private var traversal: BridgeProductAnnotationProjectionTraversal

    fileprivate init(
        capture: BridgeProductAnnotationProjectionCapture,
        boundary: BridgeProductAnnotationProjectionPageBoundary,
        maximumFrameBytes: Int,
        counts: BridgeProductAnnotationProjectionCounts
    ) {
        self.boundary = boundary
        self.maximumFrameBytes = maximumFrameBytes
        self.traversal = BridgeProductAnnotationProjectionTraversal(
            capture: capture,
            header: makeHeader(capture: capture, counts: counts),
            position: boundary.start
        )
    }

    mutating func nextEncodedBatch() throws -> Data? {
        guard traversal.position != boundary.end else { return nil }
        var batch = Data()
        while traversal.position != boundary.end {
            guard let record = try traversal.currentRecord() else {
                throw BridgeProductAnnotationProjectionRecordCursorError.traversalInvariantViolation
            }
            let encodedRecord = try encodeAnnotationProjectionRecord(record)
            if !batch.isEmpty, batch.count + encodedRecord.count > maximumFrameBytes {
                break
            }
            guard batch.count + encodedRecord.count <= maximumFrameBytes else {
                throw BridgeProductAnnotationProjectionRecordCursorError.singletonRecordExceedsFrameMaximum(
                    actualBytes: encodedRecord.count,
                    maximumBytes: maximumFrameBytes
                )
            }
            batch.append(encodedRecord)
            traversal.advance()
        }
        return batch
    }
}

private struct BridgeProductAnnotationProjectionCounts: Sendable {
    let sessionCount: Int
    let threadCount: Int
    let messageCount: Int
}

private struct BridgeProductAnnotationProjectionPageBoundary: Sendable {
    let start: BridgeProductAnnotationProjectionTraversalPosition
    let end: BridgeProductAnnotationProjectionTraversalPosition
    let byteCount: Int
}

private enum BridgeProductAnnotationProjectionTraversalPosition: Equatable, Sendable {
    case header
    case message(detailIndex: Int, threadIndex: Int, messageIndex: Int)
    case end
}

private struct BridgeProductAnnotationProjectionTraversal: Sendable {
    let capture: BridgeProductAnnotationProjectionCapture
    let header: BridgeProductAnnotationProjectionHeaderRecord
    var position: BridgeProductAnnotationProjectionTraversalPosition

    init(
        capture: BridgeProductAnnotationProjectionCapture,
        header: BridgeProductAnnotationProjectionHeaderRecord,
        position: BridgeProductAnnotationProjectionTraversalPosition = .header
    ) {
        self.capture = capture
        self.header = header
        self.position = position
    }

    func currentRecord() throws -> BridgeProductAnnotationProjectionRecord? {
        switch position {
        case .header:
            return .header(header)
        case .message(let detailIndex, let threadIndex, let messageIndex):
            let detail = capture.details[detailIndex]
            let threadDetail = detail.threads[threadIndex]
            return .message(
                .init(
                    context: try BridgeProductWorktreeAnnotationThreadContext(
                        threadDetail.thread,
                        placement: capture.placementsByThreadID[threadDetail.thread.id]
                    ),
                    message: try BridgeProductWorktreeAnnotationMessageEntry(
                        message: threadDetail.messages[messageIndex],
                        session: detail.session,
                        thread: threadDetail.thread
                    )
                )
            )
        case .end:
            return nil
        }
    }

    mutating func advance() {
        switch position {
        case .header:
            position = firstMessagePosition() ?? .end
        case .message(let detailIndex, let threadIndex, let messageIndex):
            let threadDetail = capture.details[detailIndex].threads[threadIndex]
            if messageIndex + 1 < threadDetail.messages.count {
                position = .message(
                    detailIndex: detailIndex,
                    threadIndex: threadIndex,
                    messageIndex: messageIndex + 1
                )
            } else {
                position =
                    nextThreadMessagePosition(
                        afterDetailIndex: detailIndex,
                        threadIndex: threadIndex
                    ) ?? .end
            }
        case .end:
            break
        }
    }

    private func firstMessagePosition() -> BridgeProductAnnotationProjectionTraversalPosition? {
        nextThreadMessagePosition(afterDetailIndex: 0, threadIndex: -1)
    }

    private func nextThreadMessagePosition(
        afterDetailIndex detailIndex: Int,
        threadIndex: Int
    ) -> BridgeProductAnnotationProjectionTraversalPosition? {
        guard !capture.details.isEmpty else { return nil }
        for candidateDetailIndex in detailIndex..<capture.details.count {
            let firstThreadIndex = candidateDetailIndex == detailIndex ? threadIndex + 1 : 0
            let threads = capture.details[candidateDetailIndex].threads
            guard firstThreadIndex < threads.count else { continue }
            for candidateThreadIndex in firstThreadIndex..<threads.count {
                if !threads[candidateThreadIndex].messages.isEmpty {
                    return .message(
                        detailIndex: candidateDetailIndex,
                        threadIndex: candidateThreadIndex,
                        messageIndex: 0
                    )
                }
            }
        }
        return nil
    }
}

private func validateAndCount(
    _ capture: BridgeProductAnnotationProjectionCapture
) throws -> BridgeProductAnnotationProjectionCounts {
    let sessionIDs = capture.sessions.map(\.id)
    guard Set(sessionIDs).count == sessionIDs.count,
        capture.sessions.allSatisfy({ $0.worktreeID == capture.worktreeID }),
        Set(capture.details.map { $0.session.id }).count == capture.details.count,
        capture.details.allSatisfy({ detail in
            detail.session.worktreeID == capture.worktreeID
                && capture.sessions.contains(detail.session)
        })
    else {
        throw BridgeProductAnnotationProjectionRecordCursorError.invalidCapture
    }

    var threadIDs = Set<WorktreeAnnotationThreadID>()
    var messageIDs = Set<WorktreeAnnotationMessageID>()
    var messageCount = 0
    for detail in capture.details {
        for threadDetail in detail.threads {
            guard threadDetail.thread.sessionID == detail.session.id,
                threadIDs.insert(threadDetail.thread.id).inserted,
                case .located = threadDetail.thread.origin,
                !threadDetail.messages.isEmpty
            else {
                throw BridgeProductAnnotationProjectionRecordCursorError.invalidCapture
            }
            for message in threadDetail.messages {
                guard message.threadID == threadDetail.thread.id,
                    messageIDs.insert(message.id).inserted,
                    message.savedBody.map({ $0.utf8.count <= WorktreeAnnotationMessagePolicy.maximumBodyUTF8Bytes })
                        ?? true,
                    message.draft.map({
                        $0.body.utf8.count <= WorktreeAnnotationMessagePolicy.maximumBodyUTF8Bytes
                    }) ?? true
                else {
                    throw BridgeProductAnnotationProjectionRecordCursorError.invalidCapture
                }
                messageCount += 1
            }
        }
    }
    return .init(
        sessionCount: capture.sessions.count,
        threadCount: threadIDs.count,
        messageCount: messageCount
    )
}

private func makeHeader(
    capture: BridgeProductAnnotationProjectionCapture,
    counts: BridgeProductAnnotationProjectionCounts
) -> BridgeProductAnnotationProjectionHeaderRecord {
    let summaries = capture.sessions.map { session in
        let detail = capture.details.first { $0.session.id == session.id }
        let eligibleMessagesByThread: [(WorktreeAnnotationThreadID, Int)] =
            detail?.threads.map { threadDetail in
                let count = threadDetail.messages.filter { message in
                    message.status == .editable && message.savedBody != nil
                        && message.savedRevision != nil && message.draft == nil
                }.count
                return (threadDetail.thread.id, count)
            } ?? []
        let eligibleMessageCount = eligibleMessagesByThread.reduce(0) { $0 + $1.1 }
        let missingPlacementCount = eligibleMessagesByThread.reduce(0) { count, entry in
            let placement = capture.placementsByThreadID[entry.0]?.placement
            return count + ((placement == .exact || placement == .relocated) ? 0 : entry.1)
        }
        return BridgeProductWorktreeAnnotationSessionSummary(
            session,
            eligibleMessageCount: eligibleMessageCount,
            eligibleWithoutInlinePlacementCount: missingPlacementCount
        )
    }
    return .init(
        expectedMessageCount: counts.messageCount,
        expectedSessionCount: counts.sessionCount,
        expectedThreadCount: counts.threadCount,
        projectionRevision: capture.projectionRevision,
        recoveryStatus: capture.recoveryStatus,
        sessions: summaries,
        sourceGeneration: capture.sourceGeneration,
        worktreeID: capture.worktreeID
    )
}

private func encodeAnnotationProjectionRecord(
    _ record: BridgeProductAnnotationProjectionRecord
) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    var data = try encoder.encode(record)
    data.append(0x0A)
    return data
}

private func rejectAnnotationProjectionRecordUnknownKeys<TCodingKey: CodingKey & RawRepresentable>(
    _ decoder: Decoder,
    keys: [TCodingKey]
) throws where TCodingKey.RawValue == String {
    try BridgeProductContractDecoding.rejectUnknownKeys(
        from: decoder,
        allowedKeys: Set(keys.map(\.rawValue)),
        contract: "annotation projection record"
    )
}

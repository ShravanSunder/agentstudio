import AgentStudioCore
import Foundation

enum WorktreeAnnotationBatchProjectorError: Error, Equatable, Sendable {
    case duplicateSelection
    case emptySelection
    case invalidDocument
    case invalidGeneratedContext
    case savedMessageNotFound
    case unsupportedFormatVersion
}

enum WorktreeAnnotationBatchProjector {
    struct Input: Sendable {
        let batchID: WorktreeAnnotationOutputAttemptID
        let createdAt: Date
        let sessionDetail: WorktreeAnnotationSessionDetail
        let selectedMessages: [WorktreeAnnotationSQLiteRepository.OutputMessageSelection]
        let placementsByThreadID: [WorktreeAnnotationThreadID: WorktreeAnnotationThreadPlacementProjection]
        let sessionLabel: String
        let worktreeLabel: String
        let comparisonLabel: String?
    }

    private struct EntrySortKey {
        let path: String
        let line: Int
        let threadID: String
        let messageOrdinal: Int
        let messageID: String
        let savedRevision: Int
    }

    static func makeSnapshot(_ input: Input) throws -> WorktreeAnnotationBatchSnapshotV2 {
        guard !input.selectedMessages.isEmpty else {
            throw WorktreeAnnotationBatchProjectorError.emptySelection
        }
        guard Set(input.selectedMessages.map(\.messageID)).count == input.selectedMessages.count else {
            throw WorktreeAnnotationBatchProjectorError.duplicateSelection
        }
        try validateGeneratedContext(input)

        let selectionByMessageID = Dictionary(
            uniqueKeysWithValues: input.selectedMessages.map { ($0.messageID, $0.expectedSavedRevision) }
        )
        var entries: [WorktreeAnnotationBatchSnapshotV2.Entry] = []
        for threadDetail in input.sessionDetail.threads {
            guard case .located(let locatedOrigin) = threadDetail.thread.origin else {
                if threadDetail.messages.contains(where: { selectionByMessageID[$0.id] != nil }) {
                    throw WorktreeAnnotationBatchProjectorError.invalidDocument
                }
                continue
            }
            let origin = try batchOrigin(
                locatedOrigin,
                fingerprint: input.sessionDetail.session.acceptedSourceFingerprint
            )
            let placement = try batchPlacement(
                input.placementsByThreadID[threadDetail.thread.id]
                    ?? unavailablePlacement(),
                origin: locatedOrigin,
                fingerprint: input.sessionDetail.session.acceptedSourceFingerprint
            )
            for message in threadDetail.messages {
                guard let expectedSavedRevision = selectionByMessageID[message.id] else { continue }
                guard message.savedRevision == expectedSavedRevision,
                    let savedBody = message.savedBody,
                    message.draft == nil
                else {
                    throw WorktreeAnnotationBatchProjectorError.savedMessageNotFound
                }
                entries.append(
                    .init(
                        batchOrdinal: 0,
                        thread: .init(
                            threadID: threadDetail.thread.id,
                            resolution: threadDetail.thread.resolution,
                            origin: origin,
                            placement: placement
                        ),
                        message: .init(
                            messageID: message.id,
                            messageOrdinal: message.ordinal,
                            authorKind: message.authorKind,
                            savedRevision: expectedSavedRevision,
                            bodyMarkdown: savedBody
                        )
                    )
                )
            }
        }
        guard entries.count == input.selectedMessages.count else {
            throw WorktreeAnnotationBatchProjectorError.savedMessageNotFound
        }
        entries.sort(by: entryPrecedes)
        entries = entries.enumerated().map { ordinal, entry in
            WorktreeAnnotationBatchSnapshotV2.Entry(
                batchOrdinal: ordinal,
                thread: entry.thread,
                message: entry.message
            )
        }
        let snapshot = WorktreeAnnotationBatchSnapshotV2(
            batchID: input.batchID,
            createdAt: createdAtString(input.createdAt),
            session: .init(
                sessionID: input.sessionDetail.session.id,
                label: input.sessionLabel,
                repositoryID: input.sessionDetail.session.repositoryID,
                worktreeID: input.sessionDetail.session.worktreeID,
                lifecycle: input.sessionDetail.session.lifecycle,
                sourceRelationship: input.sessionDetail.session.sourceRelationship
            ),
            entries: entries
        )
        try validate(snapshot)
        return snapshot
    }

    static func markdownData(
        for snapshot: WorktreeAnnotationBatchSnapshotV2,
        presentation: WorktreeAnnotationMarkdownPresentationContext
    ) -> Data {
        WorktreeAnnotationMarkdownProjector.project(snapshot, presentation: presentation)
    }

    static func jsonData(for snapshot: WorktreeAnnotationBatchSnapshotV2) throws -> Data {
        try validate(snapshot)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(snapshot)
    }

    static func decodeJSON(_ data: Data) throws -> WorktreeAnnotationBatchSnapshotV2 {
        let snapshot = try BridgeProductStrictJSON.decode(
            WorktreeAnnotationBatchSnapshotV2.self,
            from: data,
            memberVocabulary: WorktreeAnnotationBatchJSON.memberVocabulary,
            maximumInputBytes: nil
        )
        try validate(snapshot)
        return snapshot
    }

    static func validate(_ snapshot: WorktreeAnnotationBatchSnapshotV2) throws {
        guard snapshot.schema == WorktreeAnnotationBatchSnapshotV2.schema else {
            throw WorktreeAnnotationBatchProjectorError.invalidDocument
        }
        guard snapshot.formatVersion == WorktreeAnnotationBatchSnapshotV2.currentFormatVersion else {
            throw WorktreeAnnotationBatchProjectorError.unsupportedFormatVersion
        }
        guard isRFC3339UTC(snapshot.createdAt),
            isNonemptyContext(snapshot.session.label),
            !snapshot.session.repositoryID.isEmpty,
            !snapshot.session.worktreeID.isEmpty,
            !snapshot.entries.isEmpty
        else {
            throw WorktreeAnnotationBatchProjectorError.invalidDocument
        }
        guard snapshot.entries.enumerated().allSatisfy({ $0.offset == $0.element.batchOrdinal }),
            Set(snapshot.entries.map(\.messageID)).count == snapshot.entries.count,
            snapshot.entries.elementsEqual(snapshot.entries.sorted(by: entryPrecedes))
        else {
            throw WorktreeAnnotationBatchProjectorError.invalidDocument
        }

        var contextByThreadID: [WorktreeAnnotationThreadID: WorktreeAnnotationBatchSnapshotV2.ThreadContext] = [:]
        for entry in snapshot.entries {
            guard entry.messageOrdinal >= 0, entry.savedRevision > 0 else {
                throw WorktreeAnnotationBatchProjectorError.invalidDocument
            }
            _ = try WorktreeAnnotationMessagePolicy.validate(entry.bodyMarkdown)
            try validate(origin: entry.origin)
            try validate(placement: entry.placement)
            if let priorContext = contextByThreadID[entry.threadID], priorContext != entry.thread {
                throw WorktreeAnnotationBatchProjectorError.invalidDocument
            }
            contextByThreadID[entry.threadID] = entry.thread
        }
    }

    static func jsonData(forV1 snapshot: WorktreeAnnotationBatchSnapshotV1) throws -> Data {
        try validateV1(snapshot)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(snapshot)
    }

    static func validateV1(_ snapshot: WorktreeAnnotationBatchSnapshotV1) throws {
        guard snapshot.schema == WorktreeAnnotationBatchSnapshotV1.schema else {
            throw WorktreeAnnotationBatchProjectorError.invalidDocument
        }
        guard snapshot.formatVersion == WorktreeAnnotationBatchSnapshotV1.currentFormatVersion else {
            throw WorktreeAnnotationBatchProjectorError.unsupportedFormatVersion
        }
        guard isRFC3339UTC(snapshot.createdAt),
            isNonemptyContext(snapshot.session.label),
            !snapshot.session.repositoryID.isEmpty,
            !snapshot.session.worktreeID.isEmpty,
            !snapshot.entries.isEmpty
        else {
            throw WorktreeAnnotationBatchProjectorError.invalidDocument
        }
        guard snapshot.entries.enumerated().allSatisfy({ $0.offset == $0.element.batchOrdinal }),
            Set(snapshot.entries.map(\.messageID)).count == snapshot.entries.count,
            snapshot.entries.elementsEqual(snapshot.entries.sorted(by: entryPrecedesV1))
        else {
            throw WorktreeAnnotationBatchProjectorError.invalidDocument
        }

        var contextByThreadID: [WorktreeAnnotationThreadID: WorktreeAnnotationBatchSnapshotV1.ThreadContext] = [:]
        for entry in snapshot.entries {
            guard entry.messageOrdinal >= 0, entry.savedRevision > 0 else {
                throw WorktreeAnnotationBatchProjectorError.invalidDocument
            }
            _ = try WorktreeAnnotationMessagePolicy.validate(entry.bodyMarkdown)
            try validate(origin: entry.origin)
            try validate(placement: entry.placement)
            if let priorContext = contextByThreadID[entry.threadID], priorContext != entry.thread {
                throw WorktreeAnnotationBatchProjectorError.invalidDocument
            }
            contextByThreadID[entry.threadID] = entry.thread
        }
    }

    static func batchOrigin(
        _ origin: WorktreeAnnotationLocatedOrigin,
        fingerprint: WorktreeAnnotationSourceFingerprint
    ) throws -> WorktreeAnnotationBatchSnapshot.Origin {
        let source = try batchSource(
            sourceRole: origin.sourceRole,
            diffSide: origin.diffSide,
            sourceIdentity: origin.sourceIdentity,
            fingerprint: fingerprint
        )
        let excerptLines = worktreeAnnotationSelectedExcerptLines(origin.selectedExcerpt)
            .enumerated()
            .map { offset, text in
                WorktreeAnnotationBatchSnapshot.ExcerptLine(
                    lineNumber: origin.startLine + offset,
                    text: text
                )
            }
        return .init(
            path: origin.repositoryRelativePath,
            source: source,
            startLine: origin.startLine,
            endLine: origin.endLine,
            excerpt: excerptLines
        )
    }

    private static func batchPlacement(
        _ placement: WorktreeAnnotationThreadPlacementProjection,
        origin: WorktreeAnnotationLocatedOrigin,
        fingerprint: WorktreeAnnotationSourceFingerprint
    ) throws -> WorktreeAnnotationBatchSnapshot.Placement {
        switch placement.placement {
        case .exact, .relocated:
            guard let path = placement.currentPath,
                let startLine = placement.currentStartLine,
                let endLine = placement.currentEndLine,
                let sourceIdentity = placement.currentSourceIdentity
            else {
                throw WorktreeAnnotationBatchProjectorError.invalidDocument
            }
            let coordinate = WorktreeAnnotationBatchSnapshot.Coordinate(
                path: path,
                source: try batchSource(
                    sourceRole: origin.sourceRole,
                    diffSide: origin.diffSide,
                    sourceIdentity: sourceIdentity,
                    fingerprint: fingerprint
                ),
                startLine: startLine,
                endLine: endLine
            )
            return placement.placement == .exact ? .exact(coordinate) : .relocated(coordinate)
        case .outdated:
            try requireAbsentCurrentCoordinate(placement)
            return .outdated
        case .unavailable:
            try requireAbsentCurrentCoordinate(placement)
            return .unavailable
        }
    }

    private static func batchSource(
        sourceRole: WorktreeAnnotationSourceRole,
        diffSide: WorktreeAnnotationDiffSide?,
        sourceIdentity: String,
        fingerprint: WorktreeAnnotationSourceFingerprint
    ) throws -> WorktreeAnnotationBatchSnapshot.Source {
        switch sourceRole {
        case .file:
            guard diffSide == nil else { throw WorktreeAnnotationBatchProjectorError.invalidDocument }
            return .file(sourceIdentity: sourceIdentity)
        case .reviewBase:
            guard diffSide == .deletions, let reviewOrigin = fingerprint.reviewComparisonOrigin else {
                throw WorktreeAnnotationBatchProjectorError.invalidDocument
            }
            return .diff(
                side: .old,
                sourceIdentity: sourceIdentity,
                comparisonOrigin: try comparisonOrigin(reviewOrigin)
            )
        case .reviewHead:
            guard diffSide == .additions, let reviewOrigin = fingerprint.reviewComparisonOrigin else {
                throw WorktreeAnnotationBatchProjectorError.invalidDocument
            }
            return .diff(
                side: .new,
                sourceIdentity: sourceIdentity,
                comparisonOrigin: try comparisonOrigin(reviewOrigin)
            )
        }
    }

    private static func comparisonOrigin(
        _ origin: WorktreeAnnotationReviewComparisonOrigin
    ) throws -> WorktreeAnnotationBatchSnapshot.ComparisonOrigin {
        guard let targetData = origin.symbolicTarget.data(using: .utf8) else {
            throw WorktreeAnnotationBatchProjectorError.invalidDocument
        }
        let target: WorkspaceReviewContributionTarget
        do {
            target = try JSONDecoder().decode(WorkspaceReviewContributionTarget.self, from: targetData)
        } catch {
            throw WorktreeAnnotationBatchProjectorError.invalidDocument
        }
        guard
            let baseRole = WorktreeAnnotationBatchSnapshot.ComparisonOrigin.BaseRole(
                rawValue: origin.baseRole
            )
        else {
            throw WorktreeAnnotationBatchProjectorError.invalidDocument
        }
        return .init(
            baseRole: baseRole,
            symbolicTarget: comparisonTarget(target),
            resolvedTargetOID: origin.resolvedTargetOID,
            reviewedHeadOID: origin.reviewedHeadOID,
            baseOID: origin.baseOID
        )
    }

    private static func comparisonTarget(
        _ target: WorkspaceReviewContributionTarget
    ) -> WorktreeAnnotationBatchSnapshot.ComparisonTarget {
        switch target {
        case .localDefaultBranch(let branchName, let basis):
            .localDefaultBranch(basis: basis.rawValue, branchName: branchName)
        case .originDefaultBranch(let remoteName, let branchName, let basis):
            .originDefaultBranch(basis: basis.rawValue, branchName: branchName, remoteName: remoteName)
        case .branch(let name, let basis):
            .branch(basis: basis.rawValue, name: name)
        case .commit(let oid):
            .commit(oid: oid)
        case .ref(let name, let basis):
            .ref(basis: basis.rawValue, name: name)
        }
    }

    private static func validate(origin: WorktreeAnnotationBatchSnapshot.Origin) throws {
        guard isRepositoryRelativePath(origin.path),
            origin.startLine > 0,
            origin.endLine >= origin.startLine,
            !origin.excerpt.isEmpty,
            origin.excerpt.allSatisfy({ $0.lineNumber > 0 }),
            zip(origin.excerpt, origin.excerpt.dropFirst()).allSatisfy({ $0.lineNumber < $1.lineNumber }),
            Set(origin.excerpt.map(\.lineNumber)).isSuperset(
                of: Set(origin.startLine...origin.endLine)
            )
        else {
            throw WorktreeAnnotationBatchProjectorError.invalidDocument
        }
        try validate(source: origin.source)
    }

    private static func validate(placement: WorktreeAnnotationBatchSnapshot.Placement) throws {
        switch placement {
        case .exact(let coordinate), .relocated(let coordinate):
            guard isRepositoryRelativePath(coordinate.path),
                coordinate.startLine > 0,
                coordinate.endLine >= coordinate.startLine
            else {
                throw WorktreeAnnotationBatchProjectorError.invalidDocument
            }
            try validate(source: coordinate.source)
        case .outdated, .unavailable:
            break
        }
    }

    private static func validate(source: WorktreeAnnotationBatchSnapshot.Source) throws {
        switch source {
        case .file(let sourceIdentity):
            guard !sourceIdentity.isEmpty else { throw WorktreeAnnotationBatchProjectorError.invalidDocument }
        case .diff(_, let sourceIdentity, let origin):
            guard !sourceIdentity.isEmpty,
                !origin.resolvedTargetOID.isEmpty,
                !origin.reviewedHeadOID.isEmpty,
                !origin.baseOID.isEmpty
            else {
                throw WorktreeAnnotationBatchProjectorError.invalidDocument
            }
            try validate(target: origin.symbolicTarget)
        }
    }

    private static func validate(target: WorktreeAnnotationBatchSnapshot.ComparisonTarget) throws {
        switch target {
        case .localDefaultBranch(let basis, let branchName):
            try validateTargetName(branchName, basis: basis)
        case .originDefaultBranch(let basis, let branchName, let remoteName):
            try validateTargetName(branchName, basis: basis)
            guard !remoteName.isEmpty else { throw WorktreeAnnotationBatchProjectorError.invalidDocument }
        case .branch(let basis, let name), .ref(let basis, let name):
            try validateTargetName(name, basis: basis)
        case .commit(let oid):
            guard [40, 64].contains(oid.count), oid.allSatisfy(\.isHexDigit) else {
                throw WorktreeAnnotationBatchProjectorError.invalidDocument
            }
        }
    }

    private static func validateTargetName(_ name: String, basis: String) throws {
        guard !name.isEmpty, basis == "commonCommit" || basis == "branchTip" else {
            throw WorktreeAnnotationBatchProjectorError.invalidDocument
        }
    }

    private static func validateGeneratedContext(_ input: Input) throws {
        let values = [input.sessionLabel, input.worktreeLabel] + (input.comparisonLabel.map { [$0] } ?? [])
        guard values.allSatisfy(isNonemptyContext), !input.worktreeLabel.hasPrefix("/") else {
            throw WorktreeAnnotationBatchProjectorError.invalidGeneratedContext
        }
    }

    private static func isNonemptyContext(_ value: String) -> Bool {
        !value.isEmpty
            && !value.contains(where: { character in
                character.isNewline || (character.isASCII && (character.asciiValue ?? 0) < 0x20)
            })
    }

    private static func isRepositoryRelativePath(_ path: String) -> Bool {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\\") else { return false }
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        return !components.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." })
    }

    private static func requireAbsentCurrentCoordinate(
        _ placement: WorktreeAnnotationThreadPlacementProjection
    ) throws {
        guard placement.currentPath == nil,
            placement.currentStartLine == nil,
            placement.currentEndLine == nil,
            placement.currentSourceIdentity == nil
        else {
            throw WorktreeAnnotationBatchProjectorError.invalidDocument
        }
    }

    private static func unavailablePlacement() -> WorktreeAnnotationThreadPlacementProjection {
        .init(
            placement: .unavailable,
            currentPath: nil,
            currentStartLine: nil,
            currentEndLine: nil,
            currentSourceIdentity: nil
        )
    }

    private static func entryPrecedes(
        _ lhs: WorktreeAnnotationBatchSnapshotV2.Entry,
        _ rhs: WorktreeAnnotationBatchSnapshotV2.Entry
    ) -> Bool {
        let lhsKey = sortKey(lhs)
        let rhsKey = sortKey(rhs)
        if lhsKey.path != rhsKey.path { return lhsKey.path < rhsKey.path }
        if lhsKey.line != rhsKey.line { return lhsKey.line < rhsKey.line }
        if lhsKey.threadID != rhsKey.threadID { return lhsKey.threadID < rhsKey.threadID }
        if lhsKey.messageOrdinal != rhsKey.messageOrdinal { return lhsKey.messageOrdinal < rhsKey.messageOrdinal }
        if lhsKey.messageID != rhsKey.messageID { return lhsKey.messageID < rhsKey.messageID }
        return lhsKey.savedRevision < rhsKey.savedRevision
    }

    private static func sortKey(_ entry: WorktreeAnnotationBatchSnapshotV2.Entry) -> EntrySortKey {
        let currentCoordinate: WorktreeAnnotationBatchSnapshot.Coordinate? =
            switch entry.placement {
            case .exact(let coordinate), .relocated(let coordinate): coordinate
            case .outdated, .unavailable: nil
            }
        return .init(
            path: currentCoordinate?.path ?? entry.origin.path,
            line: currentCoordinate?.startLine ?? entry.origin.startLine,
            threadID: entry.threadID.rawValue.uuidString,
            messageOrdinal: entry.messageOrdinal,
            messageID: entry.messageID.rawValue.uuidString,
            savedRevision: entry.savedRevision
        )
    }

    private static func entryPrecedesV1(
        _ lhs: WorktreeAnnotationBatchSnapshotV1.Entry,
        _ rhs: WorktreeAnnotationBatchSnapshotV1.Entry
    ) -> Bool {
        let lhsKey = sortKeyV1(lhs)
        let rhsKey = sortKeyV1(rhs)
        if lhsKey.path != rhsKey.path { return lhsKey.path < rhsKey.path }
        if lhsKey.line != rhsKey.line { return lhsKey.line < rhsKey.line }
        if lhsKey.threadID != rhsKey.threadID { return lhsKey.threadID < rhsKey.threadID }
        if lhsKey.messageOrdinal != rhsKey.messageOrdinal { return lhsKey.messageOrdinal < rhsKey.messageOrdinal }
        if lhsKey.messageID != rhsKey.messageID { return lhsKey.messageID < rhsKey.messageID }
        return lhsKey.savedRevision < rhsKey.savedRevision
    }

    private static func sortKeyV1(_ entry: WorktreeAnnotationBatchSnapshotV1.Entry) -> EntrySortKey {
        let currentCoordinate: WorktreeAnnotationBatchSnapshotV1.Coordinate? =
            switch entry.placement {
            case .exact(let coordinate), .relocated(let coordinate): coordinate
            case .outdated, .unavailable: nil
            }
        return .init(
            path: currentCoordinate?.path ?? entry.origin.path,
            line: currentCoordinate?.startLine ?? entry.origin.startLine,
            threadID: entry.threadID.rawValue.uuidString,
            messageOrdinal: entry.messageOrdinal,
            messageID: entry.messageID.rawValue.uuidString,
            savedRevision: entry.savedRevision
        )
    }

    static func createdAtString(_ date: Date) -> String {
        date.formatted(
            .iso8601
                .year().month().day()
                .time(includingFractionalSeconds: true)
                .timeZone(separator: .omitted)
        )
    }

    private static func isRFC3339UTC(_ value: String) -> Bool {
        guard value.hasSuffix("Z") else { return false }
        return (try? Date(value, strategy: .iso8601)) != nil
    }
}

enum WorktreeAnnotationBatchJSON {
    static let memberVocabulary = BridgeProductStrictJSONMemberVocabulary(
        Set([
            "author", "baseOID", "baseRole", "basis", "batchId", "batchOrdinal",
            "bodyMarkdown", "branchName", "comparedRole", "comparisonOrigin", "createdAt",
            "current", "endLine", "entries", "excerpt", "formatVersion", "kind", "label",
            "lifecycle", "lineNumber", "message", "messageId", "messageOrdinal", "name", "oid",
            "origin", "path", "placement", "remoteName", "repositoryId", "resolution",
            "resolvedTargetOID", "reviewedHeadOID", "savedRevision", "schema", "session", "sessionId",
            "side", "source", "sourceIdentity", "sourceRelationship", "startLine", "status",
            "symbolicTarget", "text", "thread", "threadId", "worktreeId",
        ])
    )
}

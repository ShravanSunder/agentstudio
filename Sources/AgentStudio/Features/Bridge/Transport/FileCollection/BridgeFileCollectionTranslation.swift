import AgentStudioCore
import Foundation

/// Rewrites one member source's File metadata into the collection's keys and
/// its single wire identity.
///
/// Member rows keep their own tree shape under the member's group directory;
/// row, file and descriptor identifiers are namespaced by member so equal
/// relative paths in two worktrees never collide. Rows that belong to a deeper
/// nested member translate to nil.
struct BridgeFileCollectionMemberTranslation: Sendable {
    let group: BridgeFileCollectionLayout.MemberGroup
    let collectionSource: BridgeProductFileSourceIdentity

    func displayPath(_ relativePath: String) -> String? {
        guard !group.belongsToNestedMember(relativePath) else { return nil }
        return "\(group.groupPath)/\(relativePath)"
    }

    func identifier(_ memberIdentifier: String) -> String {
        BridgeFileCollectionLayout.namespacedIdentifier(
            prefix: group.identityPrefix,
            identifier: memberIdentifier
        )
    }

    func row(_ row: BridgeProductFileTreeRow) throws -> BridgeProductFileTreeRow? {
        guard let path = displayPath(row.path) else { return nil }
        return try BridgeProductFileTreeRow(
            changeStatus: row.changeStatus,
            depth: row.depth + 1,
            documentLocation: nil,
            fileId: row.fileId.map(identifier),
            fileClass: row.fileClass,
            isDirectory: row.isDirectory,
            lineCount: row.lineCount,
            name: row.name,
            parentPath: row.parentPath.map { "\(group.groupPath)/\($0)" } ?? group.groupPath,
            path: path,
            rowId: identifier(row.rowId),
            sizeBytes: row.sizeBytes
        )
    }

    func rows(_ rows: [BridgeProductFileTreeRow]) throws -> [BridgeProductFileTreeRow] {
        try rows.compactMap(row)
    }

    func operation(_ operation: BridgeProductFileTreeOperation) throws -> BridgeProductFileTreeOperation? {
        switch operation {
        case .upsertRows(let memberRows):
            let translated = try rows(memberRows)
            return translated.isEmpty ? nil : .upsertRows(translated)
        case .removeRows(let paths, let rowIds):
            let translatedPaths = paths.compactMap(displayPath)
            guard !translatedPaths.isEmpty || !rowIds.isEmpty else { return nil }
            return .removeRows(paths: translatedPaths, rowIds: rowIds.map(identifier))
        }
    }

    func descriptor(
        _ memberDescriptor: BridgeProductFileContentDescriptor
    ) throws -> BridgeProductFileContentDescriptor {
        try BridgeProductFileContentDescriptor(
            declaredByteLength: memberDescriptor.declaredByteLength,
            descriptorId: identifier(memberDescriptor.descriptorId),
            expectedSha256: memberDescriptor.expectedSha256,
            fileId: identifier(memberDescriptor.fileId),
            maximumBytes: memberDescriptor.maximumBytes,
            source: collectionSource,
            window: memberDescriptor.window
        )
    }

    func descriptorPayload(
        _ payload: BridgeProductFileDescriptorReadyPayload
    ) throws -> BridgeProductFileDescriptorReadyPayload? {
        guard let path = displayPath(payload.path) else { return nil }
        return try payload.replacingCollectionIdentity(
            availability: availability(payload.availability),
            fileId: identifier(payload.fileId),
            path: path,
            rowId: identifier(payload.rowId),
            source: collectionSource
        )
    }

    private func availability(
        _ availability: BridgeProductFileDescriptorAvailability
    ) throws -> BridgeProductFileDescriptorAvailability {
        switch availability {
        case .available(let memberDescriptor): .available(try descriptor(memberDescriptor))
        case .binary: .binary
        case .unavailable(let reason): .unavailable(reason)
        }
    }
}

enum BridgeFileCollectionRows {
    static func groupRow(path: String, identityPrefix: String) throws -> BridgeProductFileTreeRow {
        try BridgeProductFileTreeRow(
            changeStatus: nil,
            depth: 0,
            documentLocation: nil,
            fileId: nil,
            fileClass: nil,
            isDirectory: true,
            lineCount: nil,
            name: path,
            parentPath: nil,
            path: path,
            rowId: "\(identityPrefix)group",
            sizeBytes: nil
        )
    }

    static let openedDocumentsGroupIdentityPrefix = "opened."

    /// A row for an individually opened document. A document that is missing or
    /// unreadable keeps its row, so a restored entry stays identifiable as
    /// unavailable instead of disappearing (R15).
    static func openedDocumentRow(
        _ entry: BridgeFileCollectionLayout.OpenedDocumentEntry,
        metadata: BridgeWorktreeTreeRowMetadata?
    ) throws -> BridgeProductFileTreeRow {
        try BridgeProductFileTreeRow(
            changeStatus: nil,
            depth: 1,
            documentLocation: entry.location.canonicalPath,
            fileId: openedDocumentFileId(entry),
            fileClass: metadata?.fileClass
                ?? BridgeReviewFileClassifier.classify(
                    path: entry.location.displayName,
                    isBinary: false,
                    sizeBytes: 0
                ),
            isDirectory: false,
            lineCount: metadata?.lineCount,
            name: (entry.displayPath as NSString).lastPathComponent,
            parentPath: BridgeFileCollectionLayout.openedDocumentsGroupPath,
            path: entry.displayPath,
            rowId: "\(entry.identityPrefix)row",
            sizeBytes: metadata?.sizeBytes
        )
    }

    static func openedDocumentFileId(_ entry: BridgeFileCollectionLayout.OpenedDocumentEntry) -> String {
        "\(entry.identityPrefix)file"
    }
}

extension BridgeProductFileDescriptorReadyPayload {
    func replacingCollectionIdentity(
        availability: BridgeProductFileDescriptorAvailability,
        fileId: String,
        path: String,
        rowId: String,
        source: BridgeProductFileSourceIdentity
    ) throws -> Self {
        try Self(
            availability: availability,
            encoding: encoding,
            endsMidLine: endsMidLine,
            endsWithNewline: endsWithNewline,
            estimatedContentHeightPixels: estimatedContentHeightPixels,
            fileExtension: fileExtension,
            fileId: fileId,
            language: language,
            modifiedAtUnixMilliseconds: modifiedAtUnixMilliseconds,
            path: path,
            payloadByteCount: payloadByteCount,
            payloadLineCount: payloadLineCount,
            rowId: rowId,
            sizeBytes: sizeBytes,
            source: source,
            totalLineCount: totalLineCount,
            truncationKind: truncationKind,
            virtualizedExtentKind: virtualizedExtentKind
        )
    }
}

extension BridgeProductFileContentRequest {
    /// The same request addressed to the member source that issued `descriptor`.
    func replacingDescriptor(_ descriptor: BridgeProductFileContentDescriptor) -> Self {
        Self(addressing: self, descriptor: descriptor)
    }

    private init(addressing request: Self, descriptor: BridgeProductFileContentDescriptor) {
        contentRequestId = request.contentRequestId
        self.descriptor = descriptor
        leaseId = request.leaseId
        operationCorrelationID = request.operationCorrelationID
        paneSessionId = request.paneSessionId
        wireVersion = request.wireVersion
        workerDerivationEpoch = request.workerDerivationEpoch
        workerInstanceId = request.workerInstanceId
    }
}

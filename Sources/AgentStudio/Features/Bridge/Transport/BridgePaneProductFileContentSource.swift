import CryptoKit
import Foundation

struct BridgePaneProductFileContentBody: Equatable, Sendable {
    let data: Data
    let descriptor: BridgeProductFileContentDescriptor
    let endOfSource: Bool
    let sha256: String
}

struct BridgePaneProductFileDescriptorMaterialization: Sendable {
    let body: BridgePaneProductFileContentBody?
    let payload: BridgeProductFileDescriptorReadyPayload
}

struct BridgePaneProductFileMaterializationRequest: Sendable {
    let relativePath: String
    let rootURL: URL
    let row: BridgeWorktreeTreeRowMetadata
    let source: BridgeProductFileSourceIdentity
}

typealias BridgePaneProductFileDescriptorMaterializer =
    @Sendable (BridgePaneProductFileMaterializationRequest) async throws
    -> BridgePaneProductFileDescriptorMaterialization

enum BridgePaneProductFileContentSource {
    static func materialize(
        _ request: BridgePaneProductFileMaterializationRequest
    ) async throws -> BridgePaneProductFileDescriptorMaterialization {
        // File I/O and prefix parsing stay outside the provider actor executor.
        // swiftlint:disable:next no_task_detached
        let materializationTask = Task.detached(priority: .userInitiated) {
            try materializeSynchronously(
                rootURL: request.rootURL,
                relativePath: request.relativePath,
                row: request.row,
                source: request.source
            )
        }
        do {
            return try await withTaskCancellationHandler(
                operation: {
                    let materialization = try await materializationTask.value
                    try Task.checkCancellation()
                    return materialization
                },
                onCancel: {
                    materializationTask.cancel()
                }
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch is CocoaError {
            return try unreadableMaterialization(request)
        } catch is POSIXError {
            return try unreadableMaterialization(request)
        }
    }

    private static func materializeSynchronously(
        rootURL: URL,
        relativePath: String,
        row: BridgeWorktreeTreeRowMetadata,
        source: BridgeProductFileSourceIdentity
    ) throws -> BridgePaneProductFileDescriptorMaterialization {
        let fileURL = rootURL.appending(path: relativePath)
        let resourceValues = try fileURL.resourceValues(
            forKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]
        )
        guard resourceValues.isRegularFile == true else {
            throw CocoaError(.fileReadUnsupportedScheme)
        }
        let sourceByteCount = max(resourceValues.fileSize ?? 0, 0)
        let prefix = try BridgeProductFilePrefixReader.read(fileURL)
        let fileId = row.fileId ?? stableFileId(relativePath)
        let modifiedAtUnixMilliseconds = resourceValues.contentModificationDate.map {
            max(Int($0.timeIntervalSince1970 * 1000), 0)
        }
        let fileExtension = nonempty(fileURL.pathExtension)
        let extentKind: BridgeProductFileVirtualizedExtentKind =
            prefix.didReachEnd ? .exactLineCount : .previewBounded
        let totalLineCount = prefix.didReachEnd ? prefix.lineCount : nil
        let availability: BridgeProductFileDescriptorAvailability
        let encoding: BridgeProductFileEncoding?
        var body: BridgePaneProductFileContentBody?
        if prefix.isBinary {
            availability = .binary
            encoding = nil
            body = nil
        } else if !prefix.isValidUTF8 {
            availability = .unavailable(.unsupportedEncoding)
            encoding = nil
            body = nil
        } else {
            let window = try BridgeProductFileContentWindow(
                maximumBytes: BridgeProductWireContract.maximumContentBytes,
                maximumLines: BridgeProductWireContract.maximumContentLines
            )
            let descriptorId = stableDescriptorId(
                relativePath: relativePath,
                prefixSHA256: prefix.sha256
            )
            let descriptor = try BridgeProductFileContentDescriptor(
                declaredByteLength: prefix.data.count,
                descriptorId: descriptorId,
                expectedSha256: prefix.sha256,
                fileId: fileId,
                maximumBytes: BridgeProductWireContract.maximumContentBytes,
                source: source,
                window: window
            )
            availability = .available(descriptor)
            encoding = .utf8
            body = BridgePaneProductFileContentBody(
                data: prefix.data,
                descriptor: descriptor,
                endOfSource: prefix.didReachEnd,
                sha256: prefix.sha256
            )
        }
        let payload = try BridgeProductFileDescriptorReadyPayload(
            availability: availability,
            encoding: encoding,
            endsMidLine: body == nil ? false : prefix.endsMidLine,
            endsWithNewline: body == nil ? false : prefix.endsWithNewline,
            estimatedContentHeightPixels: nil,
            fileExtension: fileExtension,
            fileId: fileId,
            language: language(for: fileExtension),
            modifiedAtUnixMilliseconds: modifiedAtUnixMilliseconds,
            path: relativePath,
            payloadByteCount: body == nil ? 0 : prefix.data.count,
            payloadLineCount: body == nil ? 0 : prefix.lineCount,
            rowId: row.rowId,
            sizeBytes: max(sourceByteCount, prefix.data.count),
            source: source,
            totalLineCount: body == nil ? nil : totalLineCount,
            truncationKind: body == nil ? .complete : prefix.truncationKind,
            virtualizedExtentKind: body == nil ? .unavailable : extentKind
        )
        return .init(body: body, payload: payload)
    }

    private static func unreadableMaterialization(
        _ request: BridgePaneProductFileMaterializationRequest
    ) throws -> BridgePaneProductFileDescriptorMaterialization {
        let fileURL = request.rootURL.appending(path: request.relativePath)
        let fileId = request.row.fileId ?? stableFileId(request.relativePath)
        let payload = try BridgeProductFileDescriptorReadyPayload(
            availability: .unavailable(.unreadable),
            encoding: nil,
            endsMidLine: false,
            endsWithNewline: false,
            estimatedContentHeightPixels: nil,
            fileExtension: nonempty(fileURL.pathExtension),
            fileId: fileId,
            language: language(for: nonempty(fileURL.pathExtension)),
            modifiedAtUnixMilliseconds: nil,
            path: request.relativePath,
            payloadByteCount: 0,
            payloadLineCount: 0,
            rowId: request.row.rowId,
            sizeBytes: max(request.row.sizeBytes ?? 0, 0),
            source: request.source,
            totalLineCount: nil,
            truncationKind: .complete,
            virtualizedExtentKind: .unavailable
        )
        return .init(body: nil, payload: payload)
    }

    private static func stableFileId(_ relativePath: String) -> String {
        "worktree-file-\(sha256(relativePath).prefix(32))"
    }

    private static func stableDescriptorId(
        relativePath: String,
        prefixSHA256: String
    ) -> String {
        "file-content-\(sha256("\(relativePath):\(prefixSHA256)").prefix(32))"
    }

    private static func sha256(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func language(for fileExtension: String?) -> String? {
        switch fileExtension {
        case "swift": "swift"
        case "ts", "tsx": "typescript"
        case "js", "jsx": "javascript"
        case "json": "json"
        case "md": "markdown"
        case .some(let fileExtension): fileExtension
        case nil: nil
        }
    }

    private static func nonempty(_ value: String) -> String? {
        value.isEmpty ? nil : value
    }
}

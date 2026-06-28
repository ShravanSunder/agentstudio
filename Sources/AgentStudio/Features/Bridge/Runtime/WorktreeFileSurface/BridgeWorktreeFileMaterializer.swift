import CryptoKit
import Foundation

struct BridgeWorktreeMaterializedFileDescriptor: Sendable {
    let frame: BridgeWorktreeFileDescriptorFrame
    let resource: BridgeTransportResourceURL
    let body: BridgeWorktreeFileResourceBody
}

struct BridgeWorktreeFileMaterializationRequest: Sendable {
    let rootURL: URL
    let paneId: UUID
    let openedSource: BridgeWorktreeFileOpenedSource
    let streamId: String
    let firstSequence: Int
}

struct BridgeWorktreeChangedFileMaterializationRequest: Sendable {
    let rootURL: URL
    let paneId: UUID
    let source: BridgeWorktreeFileSurfaceSourceIdentity
    let streamId: String
    let firstSequence: Int
    let relativePaths: [String]
}

private struct BridgeWorktreeFileDescriptorMaterializationProps: Sendable {
    let paneId: UUID
    let source: BridgeWorktreeFileSurfaceSourceIdentity
    let streamId: String
    let fileURL: URL
    let relativePath: String
    let sequence: Int
}

private struct BridgeWorktreeFileAnalysis: Sendable {
    let contentHash: String
    let isBinary: Bool
    let lineCount: Int?
    let sizeBytes: Int
    let streamContentHash: String
    let streamByteCount: Int
}

enum BridgeWorktreeFileMaterializer {
    static func materializeInitialFileDescriptors(
        request: BridgeWorktreeFileMaterializationRequest
    ) async throws -> [BridgeWorktreeMaterializedFileDescriptor] {
        guard request.openedSource.includeFileDescriptors else {
            return []
        }

        // swiftlint:disable:next no_task_detached
        return try await Task.detached(priority: .utility) {
            try materializeInitialFileDescriptorsSynchronously(request: request)
        }.value
    }

    static func materializeChangedFileDescriptors(
        request: BridgeWorktreeChangedFileMaterializationRequest
    ) async throws -> [BridgeWorktreeMaterializedFileDescriptor] {
        // swiftlint:disable:next no_task_detached
        try await Task.detached(priority: .utility) {
            try materializeChangedFileDescriptorsSynchronously(request: request)
        }.value
    }

    private static func materializeInitialFileDescriptorsSynchronously(
        request: BridgeWorktreeFileMaterializationRequest
    ) throws -> [BridgeWorktreeMaterializedFileDescriptor] {
        var materializedDescriptors: [BridgeWorktreeMaterializedFileDescriptor] = []
        var nextSequence = request.firstSequence

        for relativePath in request.openedSource.canonicalPathScope where relativePath != "." {
            let fileURL = request.rootURL.appending(path: relativePath)
            let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey])
            guard values?.isRegularFile == true else {
                continue
            }

            let materializedDescriptor = try materializeFileDescriptor(
                request: request,
                fileURL: fileURL,
                relativePath: relativePath,
                sequence: nextSequence
            )
            materializedDescriptors.append(materializedDescriptor)
            nextSequence += 1
        }

        return materializedDescriptors
    }

    private static func materializeChangedFileDescriptorsSynchronously(
        request: BridgeWorktreeChangedFileMaterializationRequest
    ) throws -> [BridgeWorktreeMaterializedFileDescriptor] {
        var materializedDescriptors: [BridgeWorktreeMaterializedFileDescriptor] = []
        var nextSequence = request.firstSequence

        for relativePath in request.relativePaths where relativePath != "." {
            let fileURL = request.rootURL.appending(path: relativePath)
            let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey])
            guard values?.isRegularFile == true else {
                continue
            }

            let materializedDescriptor = try materializeFileDescriptor(
                request: request,
                fileURL: fileURL,
                relativePath: relativePath,
                sequence: nextSequence
            )
            materializedDescriptors.append(materializedDescriptor)
            nextSequence += 1
        }

        return materializedDescriptors
    }

    private static func materializeFileDescriptor(
        request: BridgeWorktreeFileMaterializationRequest,
        fileURL: URL,
        relativePath: String,
        sequence: Int
    ) throws -> BridgeWorktreeMaterializedFileDescriptor {
        try materializeFileDescriptor(
            props: BridgeWorktreeFileDescriptorMaterializationProps(
                paneId: request.paneId,
                source: request.openedSource.source,
                streamId: request.streamId,
                fileURL: fileURL,
                relativePath: relativePath,
                sequence: sequence
            )
        )
    }

    private static func materializeFileDescriptor(
        request: BridgeWorktreeChangedFileMaterializationRequest,
        fileURL: URL,
        relativePath: String,
        sequence: Int
    ) throws -> BridgeWorktreeMaterializedFileDescriptor {
        try materializeFileDescriptor(
            props: BridgeWorktreeFileDescriptorMaterializationProps(
                paneId: request.paneId,
                source: request.source,
                streamId: request.streamId,
                fileURL: fileURL,
                relativePath: relativePath,
                sequence: sequence
            )
        )
    }

    private static func materializeFileDescriptor(
        props: BridgeWorktreeFileDescriptorMaterializationProps
    ) throws -> BridgeWorktreeMaterializedFileDescriptor {
        let fileAnalysis = try analyzeFile(props.fileURL)
        let fileExtension = nonEmpty(props.fileURL.pathExtension)
        let contentHandle = "worktree-file-content-\(fileAnalysis.contentHash.prefix(32))"
        let fileId = "worktree-file-\(sha256Hex(Data(props.relativePath.utf8)).prefix(32))"
        let virtualizedExtentKind = virtualizedExtentKind(
            isBinary: fileAnalysis.isBinary,
            sizeBytes: fileAnalysis.sizeBytes
        )
        let frame = try BridgeWorktreeFileSurfaceFrameBuilder.fileDescriptor(
            request: BridgeWorktreeFileDescriptorBuildRequest(
                paneId: props.paneId.uuidString,
                source: props.source,
                streamId: props.streamId,
                sequence: props.sequence,
                path: props.relativePath,
                fileId: String(fileId),
                contentHandle: String(contentHandle),
                sizeBytes: fileAnalysis.sizeBytes,
                isBinary: fileAnalysis.isBinary,
                contentAvailability: fileAnalysis.sizeBytes > AppPolicies.Bridge.contentMaxBytesPerItem
                    ? .metadataOnly
                    : .readable,
                language: language(for: fileExtension),
                fileExtension: fileExtension,
                virtualizedExtentKind: virtualizedExtentKind,
                lineCount: virtualizedExtentKind == .exactLineCount ? fileAnalysis.lineCount : nil,
                estimatedContentHeightPixels: nil
            )
        )
        let resource = try parsedContentResource(
            descriptor: frame.descriptor.contentDescriptor.descriptor
        )
        let mimeType = frame.descriptor.contentDescriptor.descriptor.content.mediaType
        return BridgeWorktreeMaterializedFileDescriptor(
            frame: frame,
            resource: resource,
            body: BridgeWorktreeFileResourceBody(
                fileURL: props.fileURL,
                byteCount: fileAnalysis.streamByteCount,
                mimeType: mimeType,
                expectedSHA256Hex: fileAnalysis.streamContentHash
            )
        )
    }

    private static func virtualizedExtentKind(
        isBinary: Bool,
        sizeBytes: Int
    ) -> BridgeWorktreeFileVirtualizedExtentKind {
        if isBinary {
            return .unavailable
        }
        if sizeBytes > AppPolicies.Bridge.contentMaxBytesPerItem {
            return .previewBounded
        }
        return .exactLineCount
    }

    private static func boundedBodyByteCount(_ sizeBytes: Int) -> Int {
        let maxBytes = AppPolicies.Bridge.contentMaxBytesPerItem
        return min(sizeBytes, maxBytes)
    }

    private static func language(for fileExtension: String?) -> String? {
        guard let fileExtension else {
            return nil
        }
        switch fileExtension {
        case "swift":
            return "swift"
        case "ts", "tsx":
            return "typescript"
        case "js", "jsx":
            return "javascript"
        case "json":
            return "json"
        case "md":
            return "markdown"
        default:
            return fileExtension
        }
    }

    private static func nonEmpty(_ value: String) -> String? {
        value.isEmpty ? nil : value
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func sha256Hex(_ digest: SHA256.Digest) -> String {
        digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func analyzeFile(_ fileURL: URL) throws -> BridgeWorktreeFileAnalysis {
        let fileSize = try fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        let fileHandle = try FileHandle(forReadingFrom: fileURL)
        defer {
            try? fileHandle.close()
        }

        var hasher = SHA256()
        var streamHasher = SHA256()
        var observedBytes = 0
        var streamObservedBytes = 0
        let maxStreamBytes = AppPolicies.Bridge.contentMaxBytesPerItem
        var containsNulByte = false
        var newlineCount = 0
        while let chunk = try fileHandle.read(upToCount: 64 * 1024), !chunk.isEmpty {
            observedBytes += chunk.count
            hasher.update(data: chunk)
            let remainingStreamBytes = max(maxStreamBytes - streamObservedBytes, 0)
            if remainingStreamBytes > 0 {
                let streamChunk = chunk.prefix(remainingStreamBytes)
                streamObservedBytes += streamChunk.count
                streamHasher.update(data: Data(streamChunk))
            }
            if !containsNulByte, chunk.contains(0) {
                containsNulByte = true
            }
            newlineCount += chunk.reduce(into: 0) { count, byte in
                if byte == UInt8(ascii: "\n") {
                    count += 1
                }
            }
        }

        let sizeBytes = max(fileSize, observedBytes)
        let isBinary = containsNulByte
        let lineCount =
            isBinary || sizeBytes > AppPolicies.Bridge.contentMaxBytesPerItem
            ? nil
            : (observedBytes == 0 ? 0 : newlineCount + 1)
        return BridgeWorktreeFileAnalysis(
            contentHash: sha256Hex(hasher.finalize()),
            isBinary: isBinary,
            lineCount: lineCount,
            sizeBytes: sizeBytes,
            streamContentHash: sha256Hex(streamHasher.finalize()),
            streamByteCount: boundedBodyByteCount(sizeBytes)
        )
    }

    private static func parsedContentResource(
        descriptor: BridgeResourceDescriptor
    ) throws -> BridgeTransportResourceURL {
        guard
            let resource = BridgeTransportResourceURL.parse(
                descriptor.resourceUrl,
                allowedResourceKindsByProtocol: BridgeResourceProtocolRegistry.reviewViewerAllowedResourceKinds
            )
        else {
            throw RPCMethodDispatchError.handlerFailure("Invalid Worktree/File content descriptor URL")
        }
        return resource
    }
}

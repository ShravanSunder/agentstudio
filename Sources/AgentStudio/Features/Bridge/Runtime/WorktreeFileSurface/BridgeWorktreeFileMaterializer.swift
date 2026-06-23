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

    private static func materializeFileDescriptor(
        request: BridgeWorktreeFileMaterializationRequest,
        fileURL: URL,
        relativePath: String,
        sequence: Int
    ) throws -> BridgeWorktreeMaterializedFileDescriptor {
        let data = try Data(contentsOf: fileURL)
        let text = String(data: data, encoding: .utf8)
        let isBinary = text == nil
        let fileExtension = nonEmpty(fileURL.pathExtension)
        let contentHash = sha256Hex(data)
        let contentHandle = "worktree-file-content-\(contentHash.prefix(32))"
        let fileId = "worktree-file-\(sha256Hex(Data(relativePath.utf8)).prefix(32))"
        let virtualizedExtentKind = virtualizedExtentKind(
            isBinary: isBinary,
            sizeBytes: data.count
        )
        let lineCount = text.map(lineCount)
        let bodyData = boundedBodyData(data)
        let frame = try BridgeWorktreeFileSurfaceFrameBuilder.fileDescriptor(
            request: BridgeWorktreeFileDescriptorBuildRequest(
                paneId: request.paneId.uuidString,
                source: request.openedSource.source,
                streamId: request.streamId,
                sequence: sequence,
                path: relativePath,
                fileId: String(fileId),
                contentHandle: String(contentHandle),
                sizeBytes: data.count,
                isBinary: isBinary,
                contentAvailability: data.count > AppPolicies.Bridge.contentMaxBytesPerItem
                    ? .metadataOnly
                    : .readable,
                language: language(for: fileExtension),
                fileExtension: fileExtension,
                virtualizedExtentKind: virtualizedExtentKind,
                lineCount: virtualizedExtentKind == .exactLineCount ? lineCount : nil,
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
            body: BridgeWorktreeFileResourceBody(data: bodyData, mimeType: mimeType)
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

    private static func boundedBodyData(_ data: Data) -> Data {
        let maxBytes = AppPolicies.Bridge.contentMaxBytesPerItem
        guard data.count > maxBytes else {
            return data
        }
        return Data(data.prefix(maxBytes))
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

    private static func lineCount(for text: String) -> Int {
        guard !text.isEmpty else {
            return 0
        }
        return text.reduce(into: 1) { count, character in
            if character == "\n" {
                count += 1
            }
        }
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
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

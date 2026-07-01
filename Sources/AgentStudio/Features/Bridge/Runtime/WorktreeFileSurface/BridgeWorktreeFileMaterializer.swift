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
    let ignorePolicy: BridgeWorktreeFileIgnorePolicy
    let source: BridgeWorktreeFileSurfaceSourceIdentity
    let streamId: String
    let firstSequence: Int
    let relativePaths: [String]
}

struct BridgeWorktreeRequestedFileDescriptorRequest: Sendable {
    let rootURL: URL
    let paneId: UUID
    let ignorePolicy: BridgeWorktreeFileIgnorePolicy
    let source: BridgeWorktreeFileSurfaceSourceIdentity
    let streamId: String
    let sequence: Int
    let relativePath: String
}

struct BridgeWorktreeTreeRowWindowBatch: Sendable {
    let discoveredRowCount: Int
    let isFinalWindow: Bool
    let rows: [BridgeWorktreeTreeRowMetadata]
    let startIndex: Int
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
    private static let initialTreeMetadataWindowLimit =
        AppPolicies.Bridge.worktreeFileTreeMetadataWindowRowLimit

    static func canMaterializeDemandPath(
        _ relativePath: String,
        openedSource: BridgeWorktreeFileOpenedSource
    ) -> Bool {
        guard isPublishedTreePath(relativePath, ignorePolicy: openedSource.ignorePolicy) else {
            return false
        }
        let pathScope = openedSource.canonicalPathScope
        guard !pathScope.isEmpty else {
            return true
        }
        return pathScope.contains { scopedPath in
            scopedPath == "."
                || relativePath == scopedPath
                || relativePath.hasPrefix("\(scopedPath)/")
        }
    }

    static func materializeInitialTreeRows(
        request: BridgeWorktreeFileMaterializationRequest
    ) async throws -> [BridgeWorktreeTreeRowMetadata] {
        // swiftlint:disable:next no_task_detached
        try await Task.detached(priority: .utility) {
            try materializeInitialTreeRowsSynchronously(request: request)
        }.value
    }

    static func materializeAllTreeRows(
        request: BridgeWorktreeFileMaterializationRequest
    ) async throws -> [BridgeWorktreeTreeRowMetadata] {
        // swiftlint:disable:next no_task_detached
        try await Task.detached(priority: .utility) {
            try materializeTreeRowsSynchronously(request: request, maxCount: nil)
        }.value
    }

    static func materializeTreeRowWindows(
        request: BridgeWorktreeFileMaterializationRequest,
        afterCount: Int,
        windowSize: Int
    ) -> AsyncThrowingStream<BridgeWorktreeTreeRowWindowBatch, Error> {
        AsyncThrowingStream { continuation in
            // swiftlint:disable:next no_task_detached
            let task = Task.detached(priority: .utility) {
                do {
                    try materializeTreeRowWindowsSynchronously(
                        request: request,
                        afterCount: afterCount,
                        windowSize: windowSize
                    ) { batch in
                        continuation.yield(batch)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    static func materializeChangedFileDescriptors(
        request: BridgeWorktreeChangedFileMaterializationRequest
    ) async throws -> [BridgeWorktreeMaterializedFileDescriptor] {
        // swiftlint:disable:next no_task_detached
        try await Task.detached(priority: .utility) {
            try materializeChangedFileDescriptorsSynchronously(request: request)
        }.value
    }

    static func materializeRequestedFileDescriptor(
        request: BridgeWorktreeRequestedFileDescriptorRequest
    ) async throws -> BridgeWorktreeMaterializedFileDescriptor {
        // swiftlint:disable:next no_task_detached
        try await Task.detached(priority: .utility) {
            try materializeRequestedFileDescriptorSynchronously(request: request)
        }.value
    }

    private static func materializeInitialTreeRowsSynchronously(
        request: BridgeWorktreeFileMaterializationRequest
    ) throws -> [BridgeWorktreeTreeRowMetadata] {
        try materializeTreeRowsSynchronously(request: request, maxCount: initialTreeMetadataWindowLimit)
    }

    private static func materializeTreeRowsSynchronously(
        request: BridgeWorktreeFileMaterializationRequest,
        maxCount: Int?
    ) throws -> [BridgeWorktreeTreeRowMetadata] {
        let relativePaths = try initialTreeRowPaths(
            rootURL: request.rootURL,
            canonicalPathScope: request.openedSource.canonicalPathScope,
            ignorePolicy: request.openedSource.ignorePolicy,
            maxCount: maxCount
        )
        var rowsByPath: [String: BridgeWorktreeTreeRowMetadata] = [:]
        var orderedRows: [BridgeWorktreeTreeRowMetadata] = []

        func appendRow(_ row: BridgeWorktreeTreeRowMetadata) {
            if let maxCount, orderedRows.count >= maxCount {
                return
            }
            guard rowsByPath[row.path] == nil else {
                return
            }
            rowsByPath[row.path] = row
            orderedRows.append(row)
        }

        for relativePath in relativePaths {
            appendAncestorRows(for: relativePath, appendRow: appendRow)
            if let maxCount, orderedRows.count >= maxCount {
                break
            }
            let fileURL = request.rootURL.appending(path: relativePath)
            let values = try? fileURL.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
            if values?.isDirectory == true {
                appendRow(directoryTreeRow(relativePath: relativePath))
            } else if values?.isRegularFile == true {
                appendRow(try fileTreeRow(fileURL: fileURL, relativePath: relativePath))
            }
        }

        return orderedRows
    }

    private static func materializeTreeRowWindowsSynchronously(
        request: BridgeWorktreeFileMaterializationRequest,
        afterCount: Int,
        windowSize: Int,
        yield: (BridgeWorktreeTreeRowWindowBatch) -> Void
    ) throws {
        guard afterCount >= 0, windowSize > 0 else {
            return
        }
        var rowsByPath: [String: BridgeWorktreeTreeRowMetadata] = [:]
        var orderedRowCount = 0
        var windowRows: [BridgeWorktreeTreeRowMetadata] = []
        var windowStartIndex: Int?

        func flushWindowIfNeeded(force: Bool = false) {
            guard !windowRows.isEmpty, force || windowRows.count >= windowSize else {
                return
            }
            yield(
                BridgeWorktreeTreeRowWindowBatch(
                    discoveredRowCount: orderedRowCount,
                    isFinalWindow: force,
                    rows: windowRows,
                    startIndex: windowStartIndex ?? orderedRowCount - windowRows.count
                )
            )
            windowRows.removeAll(keepingCapacity: true)
            windowStartIndex = nil
        }

        func appendRow(_ row: BridgeWorktreeTreeRowMetadata) throws {
            if Task.isCancelled {
                throw CancellationError()
            }
            guard rowsByPath[row.path] == nil else {
                return
            }
            let rowIndex = orderedRowCount
            rowsByPath[row.path] = row
            orderedRowCount += 1
            guard rowIndex >= afterCount else {
                return
            }
            if windowRows.isEmpty {
                windowStartIndex = rowIndex
            }
            windowRows.append(row)
            flushWindowIfNeeded()
        }

        try forEachInitialTreeRowPath(
            rootURL: request.rootURL,
            canonicalPathScope: request.openedSource.canonicalPathScope,
            ignorePolicy: request.openedSource.ignorePolicy,
            maxPathCount: nil
        ) { relativePath in
            try appendAncestorRowsThrowing(for: relativePath) { row in
                try appendRow(row)
            }
            let fileURL = request.rootURL.appending(path: relativePath)
            let values = try? fileURL.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
            if values?.isDirectory == true {
                try appendRow(directoryTreeRow(relativePath: relativePath))
            } else if values?.isRegularFile == true {
                try appendRow(try fileTreeRow(fileURL: fileURL, relativePath: relativePath))
            }
            return true
        }
        flushWindowIfNeeded(force: true)
    }

    private static func initialTreeRowPaths(
        rootURL: URL,
        canonicalPathScope: [String],
        ignorePolicy: BridgeWorktreeFileIgnorePolicy,
        maxCount: Int?
    ) throws -> [String] {
        var relativePaths: [String] = []
        try forEachInitialTreeRowPath(
            rootURL: rootURL,
            canonicalPathScope: canonicalPathScope,
            ignorePolicy: ignorePolicy,
            maxPathCount: maxCount
        ) { relativePath in
            relativePaths.append(relativePath)
            return true
        }
        return relativePaths
    }

    private static func forEachInitialTreeRowPath(
        rootURL: URL,
        canonicalPathScope: [String],
        ignorePolicy: BridgeWorktreeFileIgnorePolicy,
        maxPathCount: Int?,
        visit: (String) throws -> Bool
    ) throws {
        let scopedPaths =
            canonicalPathScope.isEmpty
            ? ["."]
            : canonicalPathScope
        var seenPaths = Set<String>()
        var visitedPathCount = 0

        func visitIfNeeded(_ relativePath: String) throws -> Bool {
            guard !seenPaths.contains(relativePath) else {
                return true
            }
            seenPaths.insert(relativePath)
            if let maxPathCount, visitedPathCount >= maxPathCount {
                return false
            }
            visitedPathCount += 1
            return try visit(relativePath)
        }

        for scopedPath in scopedPaths {
            if let maxPathCount, visitedPathCount >= maxPathCount {
                break
            }
            let scopedURL = scopedPath == "." ? rootURL : rootURL.appending(path: scopedPath)
            let values = try? scopedURL.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
            if values?.isRegularFile == true {
                if isPublishedTreePath(scopedPath, ignorePolicy: ignorePolicy) {
                    guard try visitIfNeeded(scopedPath) else {
                        return
                    }
                }
                continue
            }
            guard values?.isDirectory == true else {
                continue
            }
            if scopedPath != "." && isPublishedTreePath(scopedPath, ignorePolicy: ignorePolicy) {
                guard try visitIfNeeded(scopedPath) else {
                    return
                }
            }
            if scopedPath != "." && isNestedGitWorktreeRoot(scopedURL, rootURL: rootURL) {
                continue
            }
            try enumerateTreeRowPaths(
                rootURL: rootURL,
                scopedURL: scopedURL,
                ignorePolicy: ignorePolicy,
                maxCount: maxPathCount.map { max($0 - visitedPathCount, 0) }
            ) { relativePath in
                try visitIfNeeded(relativePath)
            }
        }
    }

    private static func enumerateTreeRowPaths(
        rootURL: URL,
        scopedURL: URL,
        ignorePolicy: BridgeWorktreeFileIgnorePolicy,
        maxCount: Int?,
        visit: (String) throws -> Bool
    ) throws {
        if let maxCount, maxCount <= 0 {
            return
        }

        var pathCount = 0
        var pendingDirectories = [scopedURL]
        while !pendingDirectories.isEmpty {
            if let maxCount, pathCount >= maxCount {
                break
            }
            let directoryURL = pendingDirectories.removeFirst()
            let childURLs = try FileManager.default.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
                options: []
            )
            for fileURL in childURLs.sorted(by: compareFileDiscoveryOrder) {
                if let maxCount, pathCount >= maxCount {
                    return
                }
                let relativePath = relativePath(fileURL: fileURL, rootURL: rootURL)
                if !isPublishedTreePath(relativePath, ignorePolicy: ignorePolicy) {
                    continue
                }
                let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey])
                if values?.isRegularFile == true {
                    pathCount += 1
                    guard try visit(relativePath) else {
                        return
                    }
                } else if values?.isDirectory == true {
                    pathCount += 1
                    guard try visit(relativePath) else {
                        return
                    }
                    if !isNestedGitWorktreeRoot(fileURL, rootURL: rootURL) {
                        pendingDirectories.append(fileURL)
                    }
                }
            }
        }
    }

    private static func enumerateTreeRowPaths(
        rootURL: URL,
        scopedURL: URL,
        ignorePolicy: BridgeWorktreeFileIgnorePolicy,
        maxCount: Int?
    ) throws -> [String] {
        if let maxCount, maxCount <= 0 {
            return []
        }

        var paths: [String] = []
        try enumerateTreeRowPaths(
            rootURL: rootURL,
            scopedURL: scopedURL,
            ignorePolicy: ignorePolicy,
            maxCount: maxCount
        ) { relativePath in
            paths.append(relativePath)
            return true
        }
        return paths
    }

    private static func appendAncestorRowsThrowing(
        for relativePath: String,
        appendRow: (BridgeWorktreeTreeRowMetadata) throws -> Void
    ) throws {
        let pathComponents = relativePath.split(separator: "/").map(String.init)
        guard pathComponents.count > 1 else {
            return
        }
        for componentCount in 1..<pathComponents.count {
            let ancestorPath = pathComponents.prefix(componentCount).joined(separator: "/")
            try appendRow(directoryTreeRow(relativePath: ancestorPath))
        }
    }

    private static func appendAncestorRows(
        for relativePath: String,
        appendRow: (BridgeWorktreeTreeRowMetadata) -> Void
    ) {
        try? appendAncestorRowsThrowing(for: relativePath) { row in
            appendRow(row)
        }
    }

    // Manifest ordering is deterministic and policy-owned: plain code-unit
    // comparison of sibling names, breadth-first by directory. A generic
    // provider must not encode a specific repository's folder names.
    private static func compareFileDiscoveryOrder(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs.lastPathComponent.utf8.lexicographicallyPrecedes(rhs.lastPathComponent.utf8)
    }

    private static func relativePath(fileURL: URL, rootURL: URL) -> String {
        let rootPath = rootURL.standardizedFileURL.path
        let filePath = fileURL.standardizedFileURL.path
        let prefix = rootPath == "/" ? "/" : rootPath + "/"
        guard let range = filePath.range(of: prefix, options: [.anchored]) else {
            return fileURL.lastPathComponent
        }
        return String(filePath[range.upperBound...])
    }

    private static func directoryTreeRow(relativePath: String) -> BridgeWorktreeTreeRowMetadata {
        let pathComponents = relativePath.split(separator: "/").map(String.init)
        return BridgeWorktreeTreeRowMetadata(
            rowId: "worktree-directory-\(sha256Hex(Data(relativePath.utf8)).prefix(32))",
            path: relativePath,
            name: pathComponents.last ?? relativePath,
            parentPath: parentPath(for: pathComponents),
            depth: max(pathComponents.count - 1, 0),
            isDirectory: true,
            fileId: nil,
            sizeBytes: nil,
            lineCount: nil,
            changeStatus: nil
        )
    }

    private static func fileTreeRow(fileURL: URL, relativePath: String) throws -> BridgeWorktreeTreeRowMetadata {
        let pathComponents = relativePath.split(separator: "/").map(String.init)
        let sizeBytes = try fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        let fileId = "worktree-file-\(sha256Hex(Data(relativePath.utf8)).prefix(32))"
        return BridgeWorktreeTreeRowMetadata(
            rowId: "worktree-file-row-\(sha256Hex(Data(relativePath.utf8)).prefix(32))",
            path: relativePath,
            name: pathComponents.last ?? relativePath,
            parentPath: parentPath(for: pathComponents),
            depth: max(pathComponents.count - 1, 0),
            isDirectory: false,
            fileId: String(fileId),
            sizeBytes: sizeBytes,
            lineCount: nil,
            changeStatus: nil
        )
    }

    private static func parentPath(for pathComponents: [String]) -> String? {
        guard pathComponents.count > 1 else {
            return nil
        }
        return pathComponents.dropLast().joined(separator: "/")
    }

    private static func isGitInternalPath(_ path: String) -> Bool {
        path == ".git" || path.hasPrefix(".git/")
    }

    private static func isNestedGitWorktreeRoot(_ directoryURL: URL, rootURL: URL) -> Bool {
        let canonicalDirectoryURL = directoryURL.standardizedFileURL.resolvingSymlinksInPath()
        let canonicalRootURL = rootURL.standardizedFileURL.resolvingSymlinksInPath()
        guard canonicalDirectoryURL.path != canonicalRootURL.path else {
            return false
        }
        return FileManager.default.fileExists(atPath: canonicalDirectoryURL.appending(path: ".git").path)
    }

    private static func isSafeDemandPath(_ path: String) -> Bool {
        guard path.isEmpty == false, path.hasPrefix("/") == false, isGitInternalPath(path) == false else {
            return false
        }
        let components = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard components.allSatisfy({ $0.isEmpty == false && $0 != "." && $0 != ".." }) else {
            return false
        }
        return true
    }

    // Publication policy is git-truth only (accepted product decision
    // 2026-07-01): repository ignore policy plus structural exclusions
    // (`.git` internals via isSafeDemandPath, nested worktree roots at the
    // enumeration boundary). Hidden dotfiles and generated-dependency
    // directories are published unless gitignored.
    private static func isPublishedTreePath(
        _ path: String,
        ignorePolicy: BridgeWorktreeFileIgnorePolicy
    ) -> Bool {
        isSafeDemandPath(path)
            && !ignorePolicy.isIgnored(relativePath: path)
    }

    private static func materializeChangedFileDescriptorsSynchronously(
        request: BridgeWorktreeChangedFileMaterializationRequest
    ) throws -> [BridgeWorktreeMaterializedFileDescriptor] {
        var materializedDescriptors: [BridgeWorktreeMaterializedFileDescriptor] = []
        var nextSequence = request.firstSequence

        for relativePath in request.relativePaths where relativePath != "." {
            guard isPublishedTreePath(relativePath, ignorePolicy: request.ignorePolicy) else {
                continue
            }
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

    private static func materializeRequestedFileDescriptorSynchronously(
        request: BridgeWorktreeRequestedFileDescriptorRequest
    ) throws -> BridgeWorktreeMaterializedFileDescriptor {
        guard isPublishedTreePath(request.relativePath, ignorePolicy: request.ignorePolicy) else {
            throw RPCMethodDispatchError.invalidParams("worktree_file.descriptor_path_invalid")
        }
        let fileURL = request.rootURL.appending(path: request.relativePath)
        let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey])
        guard values?.isRegularFile == true else {
            throw RPCMethodDispatchError.invalidParams("worktree_file.descriptor_path_not_file")
        }
        return try materializeFileDescriptor(
            request: request,
            fileURL: fileURL,
            relativePath: request.relativePath,
            sequence: request.sequence
        )
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
        request: BridgeWorktreeRequestedFileDescriptorRequest,
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
            throw RPCMethodDispatchError.handlerFailure("worktree_file.invalid_content_descriptor_url")
        }
        return resource
    }
}

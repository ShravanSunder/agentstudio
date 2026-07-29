import CryptoKit
import Foundation

@testable import AgentStudioBridge

func makeBridgeEndpoint(
    endpointId: String,
    kind: BridgeSourceEndpoint.Kind
) -> BridgeSourceEndpoint {
    BridgeSourceEndpoint(
        endpointId: endpointId,
        kind: kind,
        repoId: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
        worktreeId: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
        label: endpointId,
        createdAtUnixMilliseconds: 1,
        contentSetHash: "sha256:\(endpointId)",
        providerIdentity: endpointId
    )
}

func makeBridgeReviewQuery(
    baseEndpointId: String = "base",
    headEndpointId: String = "head",
    filter: BridgeViewFilter = BridgeViewFilter(),
    grouping: BridgeChangeGrouping = BridgeChangeGrouping(kind: .flat),
    options: BridgeReviewQueryTestOptions = BridgeReviewQueryTestOptions()
) -> BridgeReviewQuery {
    BridgeReviewQuery(
        queryId: "query",
        queryKind: options.queryKind,
        repoId: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
        worktreeId: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
        baseEndpointId: baseEndpointId,
        headEndpointId: headEndpointId,
        comparisonSemantics: .checkpointDelta,
        pathScope: options.pathScope,
        fileTarget: options.fileTarget,
        viewFilter: filter,
        grouping: grouping,
        provenanceFilter: BridgeProvenanceFilter()
    )
}

struct BridgeReviewQueryTestOptions {
    let queryKind: BridgeReviewQuery.Kind
    let fileTarget: String?
    let pathScope: [String]

    init(
        queryKind: BridgeReviewQuery.Kind = .compare,
        fileTarget: String? = nil,
        pathScope: [String] = []
    ) {
        self.queryKind = queryKind
        self.fileTarget = fileTarget
        self.pathScope = pathScope
    }
}

func makeBridgeContentHandle(
    itemId: String,
    role: BridgeContentHandle.Role,
    endpointId: String = "endpoint",
    reviewGeneration: BridgeReviewGeneration = 7,
    contentHash: String = bridgeSHA256ContentHash("content"),
    sizeBytes: Int = 100,
    isBinary: Bool = false
) -> BridgeContentHandle {
    let handleId = "handle-\(endpointId)-\(itemId)-\(role.rawValue)"
    return BridgeContentHandle(
        handleId: handleId,
        itemId: itemId,
        role: role,
        endpointId: endpointId,
        reviewGeneration: reviewGeneration,
        contentHash: contentHash,
        contentHashAlgorithm: "sha256",
        cacheKey: "\(endpointId):\(itemId):\(role.rawValue)",
        mimeType: "text/plain",
        language: nil,
        sizeBytes: sizeBytes,
        isBinary: isBinary
    )
}

func makeContentResult(handle: BridgeContentHandle, data: String) -> BridgeContentLoadResult {
    BridgeContentLoadResult(
        handle: handle,
        data: Data(data.utf8),
        mimeType: handle.mimeType,
        contentHash: handle.contentHash,
        contentHashAlgorithm: handle.contentHashAlgorithm
    )
}

func makeBridgeReviewItemDescriptor(
    itemId: String,
    path: String,
    fileClass: BridgeFileClass,
    contentRoles: BridgeReviewItemDescriptor.ContentRoles? = nil
) -> BridgeReviewItemDescriptor {
    let roles =
        contentRoles
        ?? BridgeReviewItemDescriptor.ContentRoles(
            head: makeBridgeContentHandle(itemId: itemId, role: .head)
        )
    return BridgeReviewItemDescriptor(
        itemId: itemId,
        itemKind: .diff,
        itemVersion: 9,
        basePath: path,
        headPath: path,
        changeKind: .modified,
        fileClass: fileClass,
        language: "swift",
        extension: "swift",
        sizeBytes: 100,
        baseContentHash: "sha256:old-\(itemId)",
        headContentHash: "sha256:new-\(itemId)",
        contentHashAlgorithm: "sha256",
        additions: 1,
        deletions: 1,
        isHiddenByDefault: fileClass == .generated,
        hiddenReason: fileClass == .generated ? "generated" : nil,
        reviewPriority: .normal,
        contentRoles: roles,
        cacheKey: roles.allHandles.map(\.cacheKey).joined(separator: "|"),
        provenance: BridgeProvenanceSummary(),
        annotationSummary: BridgeAnnotationSummary(threadCount: 0, unresolvedThreadCount: 0, commentCount: 0),
        reviewState: .unreviewed,
        collapsed: fileClass == .generated
    )
}

func makeBridgeEndpointChangedFile(
    fileId: String,
    path: String,
    sizeBytes: Int,
    changeKind: BridgeFileChangeKind = .modified,
    oldContentHash: String? = nil,
    newContentHash: String? = nil,
    oldMode: Int32? = nil,
    newMode: Int32? = nil
) -> BridgeEndpointChangedFile {
    BridgeEndpointChangedFile(
        fileId: fileId,
        path: path,
        oldPath: nil,
        changeKind: changeKind,
        language: "swift",
        fileExtension: "swift",
        sizeBytes: sizeBytes,
        oldContentHash: changeKind == .added ? nil : (oldContentHash ?? "sha256:old-\(fileId)"),
        newContentHash: changeKind == .deleted ? nil : (newContentHash ?? "sha256:new-\(fileId)"),
        contentHashAlgorithm: "sha256",
        oldMode: oldMode,
        newMode: newMode,
        additions: changeKind == .deleted ? 0 : 1,
        deletions: changeKind == .added ? 0 : 1,
        isBinary: false,
        mimeType: "text/x-swift"
    )
}

func bridgeSHA256ContentHash(_ content: String) -> String {
    let digest = SHA256.hash(data: Data(content.utf8))
    let hex = digest.map { String(format: "%02x", $0) }.joined()
    return "sha256:\(hex)"
}

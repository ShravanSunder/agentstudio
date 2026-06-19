import Foundation

public struct IPCBridgePaneParams: Codable, Equatable, Sendable {
    public let handle: String

    public init(handle: String) {
        self.handle = handle
    }
}

public struct IPCBridgeReviewOpenParams: Codable, Equatable, Sendable {
    public let correlationId: UUID?
    public let worktreeId: UUID?

    public init(correlationId: UUID? = nil, worktreeId: UUID? = nil) {
        self.correlationId = correlationId
        self.worktreeId = worktreeId
    }
}

public struct IPCBridgeReviewOpenResult: Codable, Equatable, Sendable {
    public let paneId: UUID
    public let handle: String
    public let correlationId: UUID?

    public init(paneId: UUID, handle: String, correlationId: UUID?) {
        self.paneId = paneId
        self.handle = handle
        self.correlationId = correlationId
    }
}

public struct IPCBridgeReviewRefreshParams: Codable, Equatable, Sendable {
    public let handle: String
    public let correlationId: UUID?

    public init(handle: String, correlationId: UUID? = nil) {
        self.handle = handle
        self.correlationId = correlationId
    }
}

public struct IPCBridgeReviewRefreshResult: Codable, Equatable, Sendable {
    public let paneId: UUID
    public let refreshed: Bool
    public let status: String
    public let packageId: String?
    public let reviewGeneration: Int?
    public let correlationId: UUID?

    public init(
        paneId: UUID,
        refreshed: Bool,
        status: String,
        packageId: String?,
        reviewGeneration: Int?,
        correlationId: UUID?
    ) {
        self.paneId = paneId
        self.refreshed = refreshed
        self.status = status
        self.packageId = packageId
        self.reviewGeneration = reviewGeneration
        self.correlationId = correlationId
    }
}

public struct IPCBridgeReviewPackageResult: Codable, Equatable, Sendable {
    public let paneId: UUID
    public let status: String
    public let selectedItemId: String?
    public let package: IPCBridgeReviewPackage?

    public init(
        paneId: UUID,
        status: String,
        selectedItemId: String?,
        package: IPCBridgeReviewPackage?
    ) {
        self.paneId = paneId
        self.status = status
        self.selectedItemId = selectedItemId
        self.package = package
    }
}

public struct IPCBridgeRenderStateResult: Codable, Equatable, Sendable {
    public let paneId: UUID
    public let summary: IPCBridgeRenderSummary
    public let diagnostics: IPCBridgeRenderDiagnostics

    public init(
        paneId: UUID,
        summary: IPCBridgeRenderSummary,
        diagnostics: IPCBridgeRenderDiagnostics
    ) {
        self.paneId = paneId
        self.summary = summary
        self.diagnostics = diagnostics
    }
}

public struct IPCBridgeRenderSummary: Codable, Equatable, Sendable {
    public let pageTitle: String?
    public let hasAppRoot: Bool
    public let hasEmptyShell: Bool
    public let hasReviewShell: Bool
    public let sidebarPosition: String?

    public init(
        pageTitle: String?,
        hasAppRoot: Bool,
        hasEmptyShell: Bool,
        hasReviewShell: Bool,
        sidebarPosition: String?
    ) {
        self.pageTitle = pageTitle
        self.hasAppRoot = hasAppRoot
        self.hasEmptyShell = hasEmptyShell
        self.hasReviewShell = hasReviewShell
        self.sidebarPosition = sidebarPosition
    }
}

public struct IPCBridgeRenderDiagnostics: Codable, Equatable, Sendable {
    public let evaluateSucceeded: Bool
    public let pageErrorCount: Int
    public let pageErrorKinds: [String]
    public let pageErrorMessages: [String]

    public init(
        evaluateSucceeded: Bool,
        pageErrorCount: Int,
        pageErrorKinds: [String],
        pageErrorMessages: [String]
    ) {
        self.evaluateSucceeded = evaluateSucceeded
        self.pageErrorCount = pageErrorCount
        self.pageErrorKinds = pageErrorKinds
        self.pageErrorMessages = pageErrorMessages
    }
}

public struct IPCBridgeReviewPackage: Codable, Equatable, Sendable {
    public let packageId: String
    public let reviewGeneration: Int
    public let revision: Int
    public let orderedItemIds: [String]
    public let summary: IPCBridgeReviewPackageSummary
    public let items: [IPCBridgeReviewItem]

    public init(
        packageId: String,
        reviewGeneration: Int,
        revision: Int,
        orderedItemIds: [String],
        summary: IPCBridgeReviewPackageSummary,
        items: [IPCBridgeReviewItem]
    ) {
        self.packageId = packageId
        self.reviewGeneration = reviewGeneration
        self.revision = revision
        self.orderedItemIds = orderedItemIds
        self.summary = summary
        self.items = items
    }
}

public struct IPCBridgeReviewPackageSummary: Codable, Equatable, Sendable {
    public let filesChanged: Int
    public let additions: Int
    public let deletions: Int
    public let visibleFileCount: Int
    public let hiddenFileCount: Int

    public init(
        filesChanged: Int,
        additions: Int,
        deletions: Int,
        visibleFileCount: Int,
        hiddenFileCount: Int
    ) {
        self.filesChanged = filesChanged
        self.additions = additions
        self.deletions = deletions
        self.visibleFileCount = visibleFileCount
        self.hiddenFileCount = hiddenFileCount
    }
}

public struct IPCBridgeReviewItem: Codable, Equatable, Sendable {
    public let itemId: String
    public let itemKind: String
    public let basePath: String?
    public let headPath: String?
    public let changeKind: String
    public let fileClass: String
    public let language: String?
    public let additions: Int
    public let deletions: Int
    public let isHiddenByDefault: Bool
    public let reviewPriority: String
    public let contentRoles: IPCBridgeContentRoles

    public init(
        identity: IPCBridgeReviewItemIdentity,
        paths: IPCBridgeReviewItemPaths,
        classification: IPCBridgeReviewItemClassification,
        stats: IPCBridgeReviewItemStats,
        contentRoles: IPCBridgeContentRoles
    ) {
        itemId = identity.itemId
        itemKind = identity.itemKind
        basePath = paths.basePath
        headPath = paths.headPath
        changeKind = classification.changeKind
        fileClass = classification.fileClass
        language = paths.language
        additions = stats.additions
        deletions = stats.deletions
        isHiddenByDefault = classification.isHiddenByDefault
        reviewPriority = classification.reviewPriority
        self.contentRoles = contentRoles
    }
}

public struct IPCBridgeReviewItemIdentity: Codable, Equatable, Sendable {
    public let itemId: String
    public let itemKind: String

    public init(itemId: String, itemKind: String) {
        self.itemId = itemId
        self.itemKind = itemKind
    }
}

public struct IPCBridgeReviewItemPaths: Codable, Equatable, Sendable {
    public let basePath: String?
    public let headPath: String?
    public let language: String?

    public init(basePath: String?, headPath: String?, language: String?) {
        self.basePath = basePath
        self.headPath = headPath
        self.language = language
    }
}

public struct IPCBridgeReviewItemClassification: Codable, Equatable, Sendable {
    public let changeKind: String
    public let fileClass: String
    public let isHiddenByDefault: Bool
    public let reviewPriority: String

    public init(changeKind: String, fileClass: String, isHiddenByDefault: Bool, reviewPriority: String) {
        self.changeKind = changeKind
        self.fileClass = fileClass
        self.isHiddenByDefault = isHiddenByDefault
        self.reviewPriority = reviewPriority
    }
}

public struct IPCBridgeReviewItemStats: Codable, Equatable, Sendable {
    public let additions: Int
    public let deletions: Int

    public init(additions: Int, deletions: Int) {
        self.additions = additions
        self.deletions = deletions
    }
}

public struct IPCBridgeContentRoles: Codable, Equatable, Sendable {
    public let base: IPCBridgeContentHandleSummary?
    public let head: IPCBridgeContentHandleSummary?
    public let diff: IPCBridgeContentHandleSummary?
    public let file: IPCBridgeContentHandleSummary?

    public init(
        base: IPCBridgeContentHandleSummary?,
        head: IPCBridgeContentHandleSummary?,
        diff: IPCBridgeContentHandleSummary?,
        file: IPCBridgeContentHandleSummary?
    ) {
        self.base = base
        self.head = head
        self.diff = diff
        self.file = file
    }
}

public struct IPCBridgeContentHandleSummary: Codable, Equatable, Sendable {
    public let handleId: String
    public let itemId: String
    public let role: String
    public let reviewGeneration: Int
    public let resourceUrl: String
    public let mimeType: String
    public let language: String?
    public let sizeBytes: Int
    public let isBinary: Bool

    public init(
        identity: IPCBridgeContentHandleIdentity,
        presentation: IPCBridgeContentHandlePresentation,
        size: IPCBridgeContentHandleSize
    ) {
        handleId = identity.handleId
        itemId = identity.itemId
        role = identity.role
        reviewGeneration = identity.reviewGeneration
        resourceUrl = presentation.resourceUrl
        mimeType = presentation.mimeType
        language = presentation.language
        sizeBytes = size.sizeBytes
        isBinary = size.isBinary
    }
}

public struct IPCBridgeContentHandleIdentity: Codable, Equatable, Sendable {
    public let handleId: String
    public let itemId: String
    public let role: String
    public let reviewGeneration: Int

    public init(handleId: String, itemId: String, role: String, reviewGeneration: Int) {
        self.handleId = handleId
        self.itemId = itemId
        self.role = role
        self.reviewGeneration = reviewGeneration
    }
}

public struct IPCBridgeContentHandlePresentation: Codable, Equatable, Sendable {
    public let resourceUrl: String
    public let mimeType: String
    public let language: String?

    public init(resourceUrl: String, mimeType: String, language: String?) {
        self.resourceUrl = resourceUrl
        self.mimeType = mimeType
        self.language = language
    }
}

public struct IPCBridgeContentHandleSize: Codable, Equatable, Sendable {
    public let sizeBytes: Int
    public let isBinary: Bool

    public init(sizeBytes: Int, isBinary: Bool) {
        self.sizeBytes = sizeBytes
        self.isBinary = isBinary
    }
}

public struct IPCBridgeReviewSelectFileParams: Codable, Equatable, Sendable {
    public let handle: String
    public let itemId: String
    public let correlationId: UUID?

    public init(handle: String, itemId: String, correlationId: UUID? = nil) {
        self.handle = handle
        self.itemId = itemId
        self.correlationId = correlationId
    }
}

public struct IPCBridgeReviewSelectFileResult: Codable, Equatable, Sendable {
    public let paneId: UUID
    public let itemId: String
    public let selected: Bool
    public let correlationId: UUID?

    public init(paneId: UUID, itemId: String, selected: Bool, correlationId: UUID?) {
        self.paneId = paneId
        self.itemId = itemId
        self.selected = selected
        self.correlationId = correlationId
    }
}

public struct IPCBridgeContentGetParams: Codable, Equatable, Sendable {
    public let handle: String
    public let contentHandleId: String
    public let reviewGeneration: Int

    public init(handle: String, contentHandleId: String, reviewGeneration: Int) {
        self.handle = handle
        self.contentHandleId = contentHandleId
        self.reviewGeneration = reviewGeneration
    }
}

public struct IPCBridgeContentGetResult: Codable, Equatable, Sendable {
    public let paneId: UUID
    public let handle: IPCBridgeContentHandleSummary
    public let mimeType: String
    public let byteCount: Int
    public let isUtf8: Bool
    public let contentText: String?
    public let contentBase64: String?

    public init(
        paneId: UUID,
        handle: IPCBridgeContentHandleSummary,
        mimeType: String,
        body: IPCBridgeContentBody
    ) {
        self.paneId = paneId
        self.handle = handle
        self.mimeType = mimeType
        byteCount = body.byteCount
        isUtf8 = body.isUtf8
        contentText = body.contentText
        contentBase64 = body.contentBase64
    }
}

public struct IPCBridgeContentBody: Codable, Equatable, Sendable {
    public let byteCount: Int
    public let isUtf8: Bool
    public let contentText: String?
    public let contentBase64: String?

    public init(byteCount: Int, isUtf8: Bool, contentText: String?, contentBase64: String?) {
        self.byteCount = byteCount
        self.isUtf8 = isUtf8
        self.contentText = contentText
        self.contentBase64 = contentBase64
    }
}

public struct IPCBridgeTelemetryFlushResult: Codable, Equatable, Sendable {
    public let paneId: UUID
    public let flushed: Bool

    public init(paneId: UUID, flushed: Bool) {
        self.paneId = paneId
        self.flushed = flushed
    }
}

public struct IPCBridgeTelemetrySnapshotResult: Codable, Equatable, Sendable {
    public let paneId: UUID
    public let recorderAttached: Bool
    public let traceExportEnabled: Bool
    public let status: String
    public let packageId: String?
    public let reviewGeneration: Int?
    public let selectedItemId: String?

    public init(
        paneId: UUID,
        recorderAttached: Bool,
        traceExportEnabled: Bool,
        status: String,
        packageId: String?,
        reviewGeneration: Int?,
        selectedItemId: String?
    ) {
        self.paneId = paneId
        self.recorderAttached = recorderAttached
        self.traceExportEnabled = traceExportEnabled
        self.status = status
        self.packageId = packageId
        self.reviewGeneration = reviewGeneration
        self.selectedItemId = selectedItemId
    }
}

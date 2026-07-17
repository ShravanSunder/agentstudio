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

public struct IPCBridgeFileViewOpenParams: Codable, Equatable, Sendable {
    public let correlationId: UUID?
    public let worktreeId: UUID?

    public init(correlationId: UUID? = nil, worktreeId: UUID? = nil) {
        self.correlationId = correlationId
        self.worktreeId = worktreeId
    }
}

public struct IPCBridgeFileViewOpenResult: Codable, Equatable, Sendable {
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

public struct IPCBridgeReviewItemSummary: Codable, Equatable, Sendable {
    public let itemId: String
    public let displayPath: String
    public let itemKind: String
    public let changeKind: String
    public let collapsed: Bool

    public init(
        itemId: String,
        displayPath: String,
        itemKind: String,
        changeKind: String,
        collapsed: Bool
    ) {
        self.itemId = itemId
        self.displayPath = displayPath
        self.itemKind = itemKind
        self.changeKind = changeKind
        self.collapsed = collapsed
    }
}

public struct IPCBridgeReviewPackageResult: Codable, Equatable, Sendable {
    public let paneId: UUID
    public let status: String
    public let error: String?
    public let selectedItemId: String?
    public let packageId: String?
    public let reviewGeneration: Int?
    public let revision: Int?
    public let summary: IPCBridgeReviewPackageSummary?
    public let items: [IPCBridgeReviewItemSummary]

    public init(
        paneId: UUID,
        status: String,
        error: String? = nil,
        selectedItemId: String?,
        packageId: String?,
        reviewGeneration: Int?,
        revision: Int?,
        summary: IPCBridgeReviewPackageSummary?,
        items: [IPCBridgeReviewItemSummary] = []
    ) {
        self.paneId = paneId
        self.status = status
        self.error = error
        self.selectedItemId = selectedItemId
        self.packageId = packageId
        self.reviewGeneration = reviewGeneration
        self.revision = revision
        self.summary = summary
        self.items = items
    }
}

public struct IPCBridgeRenderStateResult: Codable, Equatable, Sendable {
    public let paneId: UUID
    public let summary: IPCBridgeRenderSummary
    public let diagnostics: IPCBridgeRenderDiagnostics
    public let visibleHydrationStateProbe: IPCBridgeVisibleHydrationStateProbe?
    public let visibleHydrationDiscardProbe: IPCBridgeVisibleHydrationDiscardProbe?
    public let frameJankProbe: IPCBridgeFrameJankProbe?

    public init(
        paneId: UUID,
        summary: IPCBridgeRenderSummary,
        diagnostics: IPCBridgeRenderDiagnostics,
        visibleHydrationStateProbe: IPCBridgeVisibleHydrationStateProbe? = nil,
        visibleHydrationDiscardProbe: IPCBridgeVisibleHydrationDiscardProbe? = nil,
        frameJankProbe: IPCBridgeFrameJankProbe? = nil
    ) {
        self.paneId = paneId
        self.summary = summary
        self.diagnostics = diagnostics
        self.visibleHydrationStateProbe = visibleHydrationStateProbe
        self.visibleHydrationDiscardProbe = visibleHydrationDiscardProbe
        self.frameJankProbe = frameJankProbe
    }
}

public struct IPCBridgeRenderSummary: Codable, Equatable, Sendable {
    public let pageTitle: String?
    public let hasAppRoot: Bool
    public let hasEmptyShell: Bool
    public let hasReviewShell: Bool
    public let sidebarPosition: String?
    public let hasFileShell: Bool?
    public let hasFileTree: Bool?
    public let hasFileCodeView: Bool?
    public let bridgeProtocol: String?
    public let worktreeSourceState: String?
    public let worktreeOpenFileState: String?
    public let worktreeOpenFilePath: String?
    public let worktreeRenderedFilePath: String?
    public let worktreeSelectedDisplayPath: String?
    public let worktreeDescriptorCount: Int?
    public let worktreeTotalDescriptorCount: Int?
    public let worktreeIntakeFrameCount: Int?
    public let worktreeCommandCount: Int?
    public let worktreeOpenSourceCommandCount: Int?
    public let worktreeCodeTextLength: Int?
    public let activeViewerMode: String?
    public let documentVisibilityState: String?
    public let frameLivenessRafAlive: String?
    public let reviewSelectedItemId: String?
    public let reviewCodeTextLength: Int?
    public let visibleHydrationStateProbe: IPCBridgeVisibleHydrationStateProbe?
    public let visibleHydrationDiscardProbe: IPCBridgeVisibleHydrationDiscardProbe?
    public let frameJankProbe: IPCBridgeFrameJankProbe?

    public init(
        pageTitle: String?,
        hasAppRoot: Bool,
        hasEmptyShell: Bool,
        hasReviewShell: Bool,
        sidebarPosition: String?,
        hasFileShell: Bool? = nil,
        hasFileTree: Bool? = nil,
        hasFileCodeView: Bool? = nil,
        bridgeProtocol: String? = nil,
        worktreeSourceState: String? = nil,
        worktreeOpenFileState: String? = nil,
        worktreeOpenFilePath: String? = nil,
        worktreeRenderedFilePath: String? = nil,
        worktreeSelectedDisplayPath: String? = nil,
        worktreeDescriptorCount: Int? = nil,
        worktreeTotalDescriptorCount: Int? = nil,
        worktreeIntakeFrameCount: Int? = nil,
        worktreeCommandCount: Int? = nil,
        worktreeOpenSourceCommandCount: Int? = nil,
        worktreeCodeTextLength: Int? = nil,
        activeViewerMode: String? = nil,
        documentVisibilityState: String? = nil,
        frameLivenessRafAlive: String? = nil,
        reviewSelectedItemId: String? = nil,
        reviewCodeTextLength: Int? = nil,
        visibleHydrationStateProbe: IPCBridgeVisibleHydrationStateProbe? = nil,
        visibleHydrationDiscardProbe: IPCBridgeVisibleHydrationDiscardProbe? = nil,
        frameJankProbe: IPCBridgeFrameJankProbe? = nil
    ) {
        self.pageTitle = pageTitle
        self.hasAppRoot = hasAppRoot
        self.hasEmptyShell = hasEmptyShell
        self.hasReviewShell = hasReviewShell
        self.sidebarPosition = sidebarPosition
        self.hasFileShell = hasFileShell
        self.hasFileTree = hasFileTree
        self.hasFileCodeView = hasFileCodeView
        self.bridgeProtocol = bridgeProtocol
        self.worktreeSourceState = worktreeSourceState
        self.worktreeOpenFileState = worktreeOpenFileState
        self.worktreeOpenFilePath = worktreeOpenFilePath
        self.worktreeRenderedFilePath = worktreeRenderedFilePath
        self.worktreeSelectedDisplayPath = worktreeSelectedDisplayPath
        self.worktreeDescriptorCount = worktreeDescriptorCount
        self.worktreeTotalDescriptorCount = worktreeTotalDescriptorCount
        self.worktreeIntakeFrameCount = worktreeIntakeFrameCount
        self.worktreeCommandCount = worktreeCommandCount
        self.worktreeOpenSourceCommandCount = worktreeOpenSourceCommandCount
        self.worktreeCodeTextLength = worktreeCodeTextLength
        self.activeViewerMode = activeViewerMode
        self.documentVisibilityState = documentVisibilityState
        self.frameLivenessRafAlive = frameLivenessRafAlive
        self.reviewSelectedItemId = reviewSelectedItemId
        self.reviewCodeTextLength = reviewCodeTextLength
        self.visibleHydrationStateProbe = visibleHydrationStateProbe
        self.visibleHydrationDiscardProbe = visibleHydrationDiscardProbe
        self.frameJankProbe = frameJankProbe
    }
}

public struct IPCBridgeVisibleHydrationStateProbe: Codable, Equatable, Sendable {
    public let reportedVisibleItemCount: Int?
    public let trackedVisibleItemCount: Int?
    public let truncatedVisibleItemCount: Int?
    public let untrackedItemCount: Int?
    public let loadingItemCount: Int?
    public let readyItemCount: Int?
    public let failedItemCount: Int?
    public let deferredItemCount: Int?
    public let abortedItemCount: Int?
    public let pausedNow: Bool?

    public init(
        reportedVisibleItemCount: Int?,
        trackedVisibleItemCount: Int?,
        truncatedVisibleItemCount: Int?,
        untrackedItemCount: Int?,
        loadingItemCount: Int?,
        readyItemCount: Int?,
        failedItemCount: Int?,
        deferredItemCount: Int?,
        abortedItemCount: Int?,
        pausedNow: Bool?
    ) {
        self.reportedVisibleItemCount = reportedVisibleItemCount
        self.trackedVisibleItemCount = trackedVisibleItemCount
        self.truncatedVisibleItemCount = truncatedVisibleItemCount
        self.untrackedItemCount = untrackedItemCount
        self.loadingItemCount = loadingItemCount
        self.readyItemCount = readyItemCount
        self.failedItemCount = failedItemCount
        self.deferredItemCount = deferredItemCount
        self.abortedItemCount = abortedItemCount
        self.pausedNow = pausedNow
    }
}

public struct IPCBridgeVisibleHydrationDiscardProbe: Codable, Equatable, Sendable {
    public let readyResultDiscardCount: Int?
    public let records: [IPCBridgeVisibleHydrationDiscardRecord]

    public init(
        readyResultDiscardCount: Int?,
        records: [IPCBridgeVisibleHydrationDiscardRecord]
    ) {
        self.readyResultDiscardCount = readyResultDiscardCount
        self.records = records
    }
}

public struct IPCBridgeVisibleHydrationDiscardRecord: Codable, Equatable, Sendable {
    public let hadState: Bool?
    public let pausedNow: Bool?

    public init(hadState: Bool?, pausedNow: Bool?) {
        self.hadState = hadState
        self.pausedNow = pausedNow
    }
}

public struct IPCBridgeFrameJankProbe: Codable, Equatable, Sendable {
    public let longTask: IPCBridgeFrameJankLongTaskSummary
    public let droppedFrame: IPCBridgeFrameJankDroppedFrameSummary
    public let lastLongTaskAtMs: Double?

    public init(
        longTask: IPCBridgeFrameJankLongTaskSummary,
        droppedFrame: IPCBridgeFrameJankDroppedFrameSummary,
        lastLongTaskAtMs: Double?
    ) {
        self.longTask = longTask
        self.droppedFrame = droppedFrame
        self.lastLongTaskAtMs = lastLongTaskAtMs
    }
}

public struct IPCBridgeFrameJankLongTaskSummary: Codable, Equatable, Sendable {
    public let count: Int?
    public let totalMs: Double?
    public let maxMs: Double?

    public init(count: Int?, totalMs: Double?, maxMs: Double?) {
        self.count = count
        self.totalMs = totalMs
        self.maxMs = maxMs
    }
}

public struct IPCBridgeFrameJankDroppedFrameSummary: Codable, Equatable, Sendable {
    public let count: Int?
    public let worstGapMs: Double?

    public init(count: Int?, worstGapMs: Double?) {
        self.count = count
        self.worstGapMs = worstGapMs
    }
}

public enum IPCBridgeNativeActivity: String, Codable, Equatable, Sendable {
    case foreground
    case loadedHidden
    case dormant
    case closed
}

public struct IPCBridgeRenderDiagnostics: Codable, Equatable, Sendable {
    public let evaluateSucceeded: Bool
    public let pageErrorCount: Int
    public let pageErrorKinds: [String]
    public let pageErrorMessages: [String]
    public let nativeActivity: IPCBridgeNativeActivity
    public let foregroundWorkEpoch: UInt64
    public let dirtyFactPresent: Bool
    public let activeRefreshPassPresent: Bool
    public let refreshPassCount: Int
    public let productMetadataStream: IPCBridgeProductMetadataStreamDiagnostic?
    public let productSession: IPCBridgeProductSessionDiagnostic

    public init(
        evaluateSucceeded: Bool,
        pageErrorCount: Int,
        pageErrorKinds: [String],
        pageErrorMessages: [String],
        nativeActivity: IPCBridgeNativeActivity,
        foregroundWorkEpoch: UInt64,
        dirtyFactPresent: Bool,
        activeRefreshPassPresent: Bool,
        refreshPassCount: Int,
        productMetadataStream: IPCBridgeProductMetadataStreamDiagnostic? = nil,
        productSession: IPCBridgeProductSessionDiagnostic
    ) {
        self.evaluateSucceeded = evaluateSucceeded
        self.pageErrorCount = pageErrorCount
        self.pageErrorKinds = pageErrorKinds
        self.pageErrorMessages = pageErrorMessages
        self.nativeActivity = nativeActivity
        self.foregroundWorkEpoch = foregroundWorkEpoch
        self.dirtyFactPresent = dirtyFactPresent
        self.activeRefreshPassPresent = activeRefreshPassPresent
        self.refreshPassCount = refreshPassCount
        self.productMetadataStream = productMetadataStream
        self.productSession = productSession
    }
}

public struct IPCBridgeProductSessionDiagnostic: Codable, Equatable, Sendable {
    public let activeProducerCount: Int
    public let activeProducerTaskCount: Int
    public let activeContentLeaseCount: Int
    public let queuedFrameCount: Int
    public let queuedByteCount: Int
    public let pendingFrameWaiterCount: Int
    public let inFlightFrameReceiptCount: Int
    public let pendingLifecycleAcknowledgementCount: Int
    public let nextMetadataStreamSequence: Int

    public init(
        activeProducerCount: Int,
        activeProducerTaskCount: Int,
        activeContentLeaseCount: Int,
        queuedFrameCount: Int,
        queuedByteCount: Int,
        pendingFrameWaiterCount: Int,
        inFlightFrameReceiptCount: Int,
        pendingLifecycleAcknowledgementCount: Int,
        nextMetadataStreamSequence: Int
    ) {
        self.activeProducerCount = activeProducerCount
        self.activeProducerTaskCount = activeProducerTaskCount
        self.activeContentLeaseCount = activeContentLeaseCount
        self.queuedFrameCount = queuedFrameCount
        self.queuedByteCount = queuedByteCount
        self.pendingFrameWaiterCount = pendingFrameWaiterCount
        self.inFlightFrameReceiptCount = inFlightFrameReceiptCount
        self.pendingLifecycleAcknowledgementCount = pendingLifecycleAcknowledgementCount
        self.nextMetadataStreamSequence = nextMetadataStreamSequence
    }
}

public struct IPCBridgeProductMetadataStreamDiagnostic: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Equatable, Sendable {
        case productMetadataStream
    }

    public let kind: Kind
    public let acknowledgedFrameCount: Int?
    public let activeSubscriptionCount: Int?
    public let committedFrameCount: Int?
    public let decoderState: String?
    public let expectedNextStreamSequence: Int?
    public let failureCode: String?
    public let failureStage: String?
    public let identityMismatchField: String?
    public let lastChunkByteCount: Int?
    public let lastAcknowledgedStreamSequence: Int?
    public let lastCommittedFrameKind: String?
    public let lastRoutedFrameKind: String?
    public let lifecycleState: String?
    public let peakRetainedByteCount: Int?
    public let pushCount: Int?
    public let readFulfilledCount: Int?
    public let readPending: Bool?
    public let readRequestCount: Int?
    public let receivedByteCount: Int?
    public let retainedByteCount: Int?
    public let routeFailureCode: String?
    public let routedFrameCount: Int?
    public let streamOpenCount: Int?
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

public struct IPCBridgeContentHandleSummary: Codable, Equatable, Sendable {
    public let handleId: String
    public let itemId: String
    public let role: String
    public let reviewGeneration: Int
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
    public let mimeType: String
    public let language: String?

    public init(mimeType: String, language: String?) {
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

public struct IPCBridgeDiffScrollToFileParams: Codable, Equatable, Sendable {
    public let handle: String
    public let itemId: String
    public let correlationId: UUID?

    public init(handle: String, itemId: String, correlationId: UUID? = nil) {
        self.handle = handle
        self.itemId = itemId
        self.correlationId = correlationId
    }
}

public struct IPCBridgeDiffExpandFileParams: Codable, Equatable, Sendable {
    public let handle: String
    public let itemId: String
    public let correlationId: UUID?

    public init(handle: String, itemId: String, correlationId: UUID? = nil) {
        self.handle = handle
        self.itemId = itemId
        self.correlationId = correlationId
    }
}

public struct IPCBridgeDiffCollapseFileParams: Codable, Equatable, Sendable {
    public let handle: String
    public let itemId: String
    public let correlationId: UUID?

    public init(handle: String, itemId: String, correlationId: UUID? = nil) {
        self.handle = handle
        self.itemId = itemId
        self.correlationId = correlationId
    }
}

public struct IPCBridgeFileTreeSearchParams: Codable, Equatable, Sendable {
    public let handle: String
    public let searchText: String
    public let searchMode: IPCBridgeReviewSearchMode
    public let correlationId: UUID?

    public init(
        handle: String,
        searchText: String,
        searchMode: IPCBridgeReviewSearchMode = .text,
        correlationId: UUID? = nil
    ) {
        self.handle = handle
        self.searchText = searchText
        self.searchMode = searchMode
        self.correlationId = correlationId
    }

    private enum CodingKeys: String, CodingKey {
        case handle
        case searchText
        case searchMode
        case correlationId
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        handle = try container.decode(String.self, forKey: .handle)
        searchText = try container.decode(String.self, forKey: .searchText)
        searchMode =
            try container.decodeIfPresent(IPCBridgeReviewSearchMode.self, forKey: .searchMode) ?? .text
        correlationId = try container.decodeIfPresent(UUID.self, forKey: .correlationId)
    }
}

public struct IPCBridgeFileTreeSetFilterParams: Codable, Equatable, Sendable {
    public let handle: String
    public let gitStatusFilter: String
    public let fileClassFilter: String
    public let correlationId: UUID?

    public init(
        handle: String,
        gitStatusFilter: String,
        fileClassFilter: String,
        correlationId: UUID? = nil
    ) {
        self.handle = handle
        self.gitStatusFilter = gitStatusFilter
        self.fileClassFilter = fileClassFilter
        self.correlationId = correlationId
    }
}

public struct IPCBridgeFileTreeRevealPathParams: Codable, Equatable, Sendable {
    public let handle: String
    public let path: String
    public let correlationId: UUID?

    public init(handle: String, path: String, correlationId: UUID? = nil) {
        self.handle = handle
        self.path = path
        self.correlationId = correlationId
    }
}

public struct IPCBridgeFileViewShowMarkdownPreviewParams: Codable, Equatable, Sendable {
    public let handle: String
    public let itemId: String?
    public let correlationId: UUID?

    public init(handle: String, itemId: String? = nil, correlationId: UUID? = nil) {
        self.handle = handle
        self.itemId = itemId
        self.correlationId = correlationId
    }
}

public struct IPCBridgeReviewSearchMode: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Equatable, Sendable {
        case text
        case regex
    }

    public static let text = Self(kind: .text)
    public static let regex = Self(kind: .regex)

    public let kind: Kind

    public init(kind: Kind) {
        self.kind = kind
    }
}

public enum IPCBridgePageControlCommand: Equatable, Sendable {
    case scrollToFile(itemId: String)
    case expandFile(itemId: String)
    case collapseFile(itemId: String)
    case fileTreeSearch(searchText: String, searchMode: IPCBridgeReviewSearchMode = .text)
    case fileTreeSetFilter(gitStatusFilter: String, fileClassFilter: String)
    case fileTreeRevealPath(path: String)
    case fileViewShowMarkdownPreview(itemId: String?)

    public var method: String {
        switch self {
        case .scrollToFile:
            "bridge.diff.scrollToFile"
        case .expandFile:
            "bridge.diff.expandFile"
        case .collapseFile:
            "bridge.diff.collapseFile"
        case .fileTreeSearch:
            "bridge.fileTree.search"
        case .fileTreeSetFilter:
            "bridge.fileTree.setFilter"
        case .fileTreeRevealPath:
            "bridge.fileTree.revealPath"
        case .fileViewShowMarkdownPreview:
            "bridge.fileView.showMarkdownPreview"
        }
    }
}

extension IPCBridgePageControlCommand: Codable {
    private enum CodingKeys: String, CodingKey {
        case method
        case itemId
        case searchText
        case searchMode
        case gitStatusFilter
        case fileClassFilter
        case path
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let method = try container.decode(String.self, forKey: .method)
        switch method {
        case "bridge.diff.scrollToFile":
            self = .scrollToFile(itemId: try container.decode(String.self, forKey: .itemId))
        case "bridge.diff.expandFile":
            self = .expandFile(itemId: try container.decode(String.self, forKey: .itemId))
        case "bridge.diff.collapseFile":
            self = .collapseFile(itemId: try container.decode(String.self, forKey: .itemId))
        case "bridge.fileTree.search":
            self = .fileTreeSearch(
                searchText: try container.decode(String.self, forKey: .searchText),
                searchMode: try container.decode(IPCBridgeReviewSearchMode.self, forKey: .searchMode)
            )
        case "bridge.fileTree.setFilter":
            self = .fileTreeSetFilter(
                gitStatusFilter: try container.decode(String.self, forKey: .gitStatusFilter),
                fileClassFilter: try container.decode(String.self, forKey: .fileClassFilter)
            )
        case "bridge.fileTree.revealPath":
            self = .fileTreeRevealPath(path: try container.decode(String.self, forKey: .path))
        case "bridge.fileView.showMarkdownPreview":
            self = .fileViewShowMarkdownPreview(
                itemId: try container.decodeIfPresent(String.self, forKey: .itemId)
            )
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .method,
                in: container,
                debugDescription: "Unsupported Bridge page-control method \(method)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(method, forKey: .method)
        switch self {
        case .scrollToFile(let itemId):
            try container.encode(itemId, forKey: .itemId)
        case .expandFile(let itemId):
            try container.encode(itemId, forKey: .itemId)
        case .collapseFile(let itemId):
            try container.encode(itemId, forKey: .itemId)
        case .fileTreeSearch(let searchText, let searchMode):
            try container.encode(searchText, forKey: .searchText)
            try container.encode(searchMode, forKey: .searchMode)
        case .fileTreeSetFilter(let gitStatusFilter, let fileClassFilter):
            try container.encode(gitStatusFilter, forKey: .gitStatusFilter)
            try container.encode(fileClassFilter, forKey: .fileClassFilter)
        case .fileTreeRevealPath(let path):
            try container.encode(path, forKey: .path)
        case .fileViewShowMarkdownPreview(let itemId):
            try container.encodeIfPresent(itemId, forKey: .itemId)
        }
    }
}

public struct IPCBridgePageControlResult: Codable, Equatable, Sendable {
    public let paneId: UUID
    public let method: String
    public let status: String
    public let itemId: String?
    public let path: String?
    public let treeSearchText: String
    public let gitStatusFilter: String
    public let fileClassFilter: String
    public let renderMode: String
    public let reason: String?
    public let correlationId: UUID?

    public init(
        paneId: UUID,
        method: String,
        status: String,
        itemId: String?,
        path: String?,
        treeSearchText: String,
        gitStatusFilter: String,
        fileClassFilter: String,
        renderMode: String,
        reason: String?,
        correlationId: UUID?
    ) {
        self.paneId = paneId
        self.method = method
        self.status = status
        self.itemId = itemId
        self.path = path
        self.treeSearchText = treeSearchText
        self.gitStatusFilter = gitStatusFilter
        self.fileClassFilter = fileClassFilter
        self.renderMode = renderMode
        self.reason = reason
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
    public let isBinary: Bool

    public init(
        paneId: UUID,
        handle: IPCBridgeContentHandleSummary,
        mimeType: String
    ) {
        self.paneId = paneId
        self.handle = handle
        self.mimeType = mimeType
        byteCount = handle.sizeBytes
        isBinary = handle.isBinary
    }
}

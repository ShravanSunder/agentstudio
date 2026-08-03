import AgentStudioInfrastructure
import Foundation

struct BridgePaneSurfaceSelectionRequest: Equatable, Sendable {
    let navigationCommand: BridgeProductNavigationCommand
    let paneSessionId: String
    let workerInstanceId: String

    var requestId: String { navigationCommand.commandId }
    var bindingRevision: Int { navigationCommand.bindingRevision }
    var surface: BridgeProductSurface { navigationCommand.surface }
}

enum BridgePaneSurfaceSelectionIntent: Equatable, Sendable {
    case context(commandId: String, surface: BridgeProductSurface)
    case reviewTarget(
        commandId: String,
        source: BridgeProductNavigationReviewSource,
        target: BridgeProductNavigationReviewTarget
    )

    var commandId: String {
        switch self {
        case .context(let commandId, _), .reviewTarget(let commandId, _, _): commandId
        }
    }

    var surface: BridgeProductSurface {
        switch self {
        case .context(_, let surface): surface
        case .reviewTarget: .review
        }
    }

    func bind(revision: Int) -> BridgeProductNavigationCommand {
        switch self {
        case .context(let commandId, let surface):
            .activateContext(
                commandId: commandId,
                bindingRevision: revision,
                surface: surface
            )
        case .reviewTarget(let commandId, let source, let target):
            .activateReviewTarget(
                commandId: commandId,
                bindingRevision: revision,
                source: source,
                target: target
            )
        }
    }
}

enum BridgePaneSurfaceSelectionReceiptRejection: Equatable, Sendable {
    case staleRequest
    case wrongMode
    case wrongPaneSession
    case wrongWorkerInstance
}

enum BridgePaneSurfaceSelectionReceiptDisposition: Equatable, Sendable {
    case accepted
    case idempotentReplay
    case rejected(BridgePaneSurfaceSelectionReceiptRejection)
}

struct BridgePaneSurfaceSelectionAuthority: Sendable {
    struct DiagnosticSnapshot: Equatable, Sendable {
        let currentRequest: BridgePaneSurfaceSelectionRequest?
        let desiredSurface: BridgeProductSurface?
        let lastAcceptedRequest: BridgePaneSurfaceSelectionRequest?
        let needsDelivery: Bool
    }

    private var currentRequest: BridgePaneSurfaceSelectionRequest?
    private var retainedIntent: BridgePaneSurfaceSelectionIntent?
    private var lastAcceptedRequest: BridgePaneSurfaceSelectionRequest?
    private var needsDelivery = false
    private var nextBindingRevision = 0

    var diagnosticSnapshot: DiagnosticSnapshot {
        DiagnosticSnapshot(
            currentRequest: currentRequest,
            desiredSurface: retainedIntent?.surface,
            lastAcceptedRequest: lastAcceptedRequest,
            needsDelivery: needsDelivery
        )
    }

    @discardableResult
    mutating func retainIntent(surface: BridgeProductSurface) -> String {
        if case .context(let commandId, let retainedSurface) = retainedIntent,
            retainedSurface == surface
        {
            if currentRequest == nil, lastAcceptedRequest == nil {
                needsDelivery = true
            }
            return commandId
        }
        let commandId = UUIDv7.generate().uuidString
        replaceRetainedIntent(
            .context(
                commandId: commandId,
                surface: surface
            )
        )
        return commandId
    }

    @discardableResult
    mutating func retainReviewTarget(
        source: BridgeProductNavigationReviewSource,
        target: BridgeProductNavigationReviewTarget
    ) -> String {
        let commandId = UUIDv7.generate().uuidString
        replaceRetainedIntent(
            .reviewTarget(
                commandId: commandId,
                source: source,
                target: target
            )
        )
        return commandId
    }

    mutating func bindRetainedIntent(
        commandId: String,
        paneSessionId: String,
        workerInstanceId: String
    ) throws -> BridgePaneSurfaceSelectionRequest? {
        guard retainedIntent?.commandId == commandId else { return nil }
        return try bindCurrentRetainedIntent(
            paneSessionId: paneSessionId,
            workerInstanceId: workerInstanceId
        )
    }

    mutating func rebindRetainedIntent(
        paneSessionId: String,
        workerInstanceId: String
    ) throws -> BridgePaneSurfaceSelectionRequest? {
        try bindCurrentRetainedIntent(
            paneSessionId: paneSessionId,
            workerInstanceId: workerInstanceId
        )
    }

    mutating func invalidateFailedExactIntent(commandId: String) {
        guard case .reviewTarget(let retainedCommandId, _, _) = retainedIntent,
            retainedCommandId == commandId
        else {
            return
        }
        invalidate()
    }

    private mutating func bindCurrentRetainedIntent(
        paneSessionId: String,
        workerInstanceId: String
    ) throws -> BridgePaneSurfaceSelectionRequest? {
        guard let retainedIntent else { return nil }
        if let currentRequest,
            currentRequest.navigationCommand.commandId == retainedIntent.commandId,
            currentRequest.paneSessionId == paneSessionId,
            currentRequest.workerInstanceId == workerInstanceId
        {
            return nil
        }
        let acceptedBindingChanged =
            lastAcceptedRequest.map {
                $0.navigationCommand.commandId == retainedIntent.commandId
                    && ($0.paneSessionId != paneSessionId
                        || $0.workerInstanceId != workerInstanceId)
            } ?? false
        guard needsDelivery || currentRequest != nil || acceptedBindingChanged else { return nil }
        try BridgeProductContractDecoding.validateIdentifier(paneSessionId, codingPath: [])
        try BridgeProductContractDecoding.validateIdentifier(workerInstanceId, codingPath: [])
        nextBindingRevision += 1
        let request = BridgePaneSurfaceSelectionRequest(
            navigationCommand: retainedIntent.bind(revision: nextBindingRevision),
            paneSessionId: paneSessionId,
            workerInstanceId: workerInstanceId
        )
        currentRequest = request
        needsDelivery = false
        return request
    }

    mutating func invalidateCurrentBinding() {
        currentRequest = nil
        lastAcceptedRequest = nil
        needsDelivery = retainedIntent != nil
    }

    mutating func invalidateRetainedReviewTarget(
        ifSourceDoesNotMatch source: BridgeProductNavigationReviewSource
    ) {
        guard case .reviewTarget(_, let retainedSource, _) = retainedIntent,
            retainedSource != source
        else {
            return
        }
        invalidate()
    }

    mutating func invalidate() {
        currentRequest = nil
        retainedIntent = nil
        lastAcceptedRequest = nil
        needsDelivery = false
    }

    mutating func admitReceipt(
        nativeSelectionRequestId: String,
        mode: BridgeActiveViewerMode,
        paneSessionId: String,
        workerInstanceId: String
    ) -> BridgePaneSurfaceSelectionReceiptDisposition {
        if let lastAcceptedRequest,
            lastAcceptedRequest.requestId == nativeSelectionRequestId
        {
            return receiptMatches(
                lastAcceptedRequest,
                mode: mode,
                paneSessionId: paneSessionId,
                workerInstanceId: workerInstanceId
            )
                ? .idempotentReplay
                : mismatchDisposition(
                    lastAcceptedRequest,
                    mode: mode,
                    paneSessionId: paneSessionId,
                    workerInstanceId: workerInstanceId
                )
        }
        guard let currentRequest, currentRequest.requestId == nativeSelectionRequestId else {
            return .rejected(.staleRequest)
        }
        guard
            receiptMatches(
                currentRequest,
                mode: mode,
                paneSessionId: paneSessionId,
                workerInstanceId: workerInstanceId
            )
        else {
            return mismatchDisposition(
                currentRequest,
                mode: mode,
                paneSessionId: paneSessionId,
                workerInstanceId: workerInstanceId
            )
        }
        self.currentRequest = nil
        lastAcceptedRequest = currentRequest
        needsDelivery = false
        return .accepted
    }

    private mutating func replaceRetainedIntent(
        _ intent: BridgePaneSurfaceSelectionIntent
    ) {
        retainedIntent = intent
        currentRequest = nil
        lastAcceptedRequest = nil
        needsDelivery = true
    }

    private func receiptMatches(
        _ request: BridgePaneSurfaceSelectionRequest,
        mode: BridgeActiveViewerMode,
        paneSessionId: String,
        workerInstanceId: String
    ) -> Bool {
        request.surface.activeViewerMode == mode
            && request.paneSessionId == paneSessionId
            && request.workerInstanceId == workerInstanceId
    }

    private func mismatchDisposition(
        _ request: BridgePaneSurfaceSelectionRequest,
        mode: BridgeActiveViewerMode,
        paneSessionId: String,
        workerInstanceId: String
    ) -> BridgePaneSurfaceSelectionReceiptDisposition {
        if request.surface.activeViewerMode != mode { return .rejected(.wrongMode) }
        if request.paneSessionId != paneSessionId { return .rejected(.wrongPaneSession) }
        return .rejected(.wrongWorkerInstance)
    }
}

extension BridgeProductSurface {
    var activeViewerMode: BridgeActiveViewerMode {
        switch self {
        case .file: .file
        case .review: .review
        }
    }
}

import Foundation

struct BridgePaneSurfaceSelectionRequest: Equatable, Sendable {
    let requestId: String
    let selectionRevision: Int
    let surface: BridgeProductSurface
    let paneSessionId: String
    let workerInstanceId: String
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
    private var desiredSurface: BridgeProductSurface?
    private var lastAcceptedRequest: BridgePaneSurfaceSelectionRequest?
    private var needsDelivery = false
    private var nextSelectionRevision = 0

    var diagnosticSnapshot: DiagnosticSnapshot {
        DiagnosticSnapshot(
            currentRequest: currentRequest,
            desiredSurface: desiredSurface,
            lastAcceptedRequest: lastAcceptedRequest,
            needsDelivery: needsDelivery
        )
    }

    mutating func retainIntent(surface: BridgeProductSurface) {
        if desiredSurface == surface {
            if currentRequest == nil {
                needsDelivery = true
            }
            return
        }
        desiredSurface = surface
        currentRequest = nil
        needsDelivery = true
    }

    mutating func bindRetainedIntent(
        paneSessionId: String,
        workerInstanceId: String
    ) throws -> BridgePaneSurfaceSelectionRequest? {
        guard let desiredSurface else { return nil }
        if let currentRequest,
            currentRequest.surface == desiredSurface,
            currentRequest.paneSessionId == paneSessionId,
            currentRequest.workerInstanceId == workerInstanceId
        {
            return nil
        }
        guard needsDelivery || currentRequest != nil else { return nil }
        try BridgeProductContractDecoding.validateIdentifier(paneSessionId, codingPath: [])
        try BridgeProductContractDecoding.validateIdentifier(workerInstanceId, codingPath: [])
        nextSelectionRevision += 1
        let request = BridgePaneSurfaceSelectionRequest(
            requestId: UUID().uuidString,
            selectionRevision: nextSelectionRevision,
            surface: desiredSurface,
            paneSessionId: paneSessionId,
            workerInstanceId: workerInstanceId
        )
        currentRequest = request
        needsDelivery = false
        return request
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

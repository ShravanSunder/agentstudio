import Foundation
import WebKit
import os.log

private let bridgeProductSchemeTaskLogger = Logger(
    subsystem: "com.agentstudio",
    category: "BridgeProductSchemeTask"
)

extension BridgeSchemeHandler.PathType {
    var supportsPostRequests: Bool {
        switch self {
        case .telemetryBatch, .product:
            true
        case .app, .invalid:
            false
        }
    }
}

extension BridgeSchemeHandler {
    func startProductReplyTask(
        request: URLRequest,
        continuation: AsyncThrowingStream<URLSchemeTaskResult, any Error>.Continuation
    ) {
        let route = request.url?.absoluteString ?? "missing-url"
        let task = Task {
            bridgeProductSchemeTaskLogger.debug("Product scheme task started route=\(route, privacy: .public)")
            guard !Task.isCancelled else {
                bridgeProductSchemeTaskLogger.debug(
                    "Product scheme task cancelled before claim route=\(route, privacy: .public)"
                )
                continuation.finish(throwing: CancellationError())
                return
            }
            guard let url = request.url else {
                continuation.finish(throwing: BridgeSchemeError.invalidRequest("Missing URL"))
                return
            }
            guard
                let presentedCapability = request.value(
                    forHTTPHeaderField: BridgeProductWireContract.capabilityHeaderName
                )
            else {
                emitProductAdmissionResponse(
                    statusCode: 401,
                    url: url,
                    continuation: continuation
                )
                return
            }
            guard let productSessionRouter else {
                bridgeProductSchemeTaskLogger.error(
                    "Product scheme task rejected without active session route=\(route, privacy: .public)"
                )
                continuation.finish(throwing: BridgeSchemeError.invalidRoute("product-session-unavailable"))
                return
            }
            let transportAdmission = await productSessionRouter.claimActiveAdapter(
                presentedCapability: presentedCapability
            )
            let transportClaim: BridgeProductSchemeTransportClaim
            switch transportAdmission {
            case .admitted(let admittedClaim):
                transportClaim = admittedClaim
            case .conflict:
                emitProductAdmissionResponse(
                    statusCode: 409,
                    url: url,
                    continuation: continuation
                )
                return
            case .unauthorized:
                emitProductAdmissionResponse(
                    statusCode: 403,
                    url: url,
                    continuation: continuation
                )
                return
            }
            guard !Task.isCancelled else {
                bridgeProductSchemeTaskLogger.debug(
                    "Product scheme task cancelled after claim route=\(route, privacy: .public)"
                )
                continuation.finish(throwing: CancellationError())
                await transportClaim.finish()
                return
            }
            await transportClaim.adapter.route(
                request,
                productAdmission: transportClaim.productAdmission,
                continuation: continuation
            )
            bridgeProductSchemeTaskLogger.debug(
                "Product scheme task completed route=\(route, privacy: .public)"
            )
            await transportClaim.finish()
        }
        continuation.onTermination = { termination in
            bridgeProductSchemeTaskLogger.debug(
                "Product scheme consumer terminated route=\(route, privacy: .public) termination=\(String(describing: termination), privacy: .public)"
            )
            task.cancel()
        }
    }

    private func emitProductAdmissionResponse(
        statusCode: Int,
        url: URL,
        continuation: AsyncThrowingStream<URLSchemeTaskResult, any Error>.Continuation
    ) {
        continuation.yield(
            .response(
                Self.response(
                    url: url,
                    mimeType: "application/json",
                    expectedContentLength: 0,
                    allowedMethods: "OPTIONS, POST",
                    allowedHeaders:
                        "Content-Type, \(BridgeProductWireContract.capabilityHeaderName)",
                    statusCode: statusCode
                )
            )
        )
        continuation.finish()
    }
}

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
        case .app, .leasedContent, .invalid:
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
            guard let productSessionRouter,
                let transportClaim = await productSessionRouter.claimActiveAdapter()
            else {
                bridgeProductSchemeTaskLogger.error(
                    "Product scheme task rejected without active session route=\(route, privacy: .public)"
                )
                continuation.finish(throwing: BridgeSchemeError.invalidRoute("product-session-unavailable"))
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
            await transportClaim.adapter.route(request, continuation: continuation)
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
}

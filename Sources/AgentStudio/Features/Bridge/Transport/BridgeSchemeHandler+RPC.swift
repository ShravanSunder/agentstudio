import Foundation
import WebKit

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
        let task = Task {
            guard !Task.isCancelled else {
                continuation.finish(throwing: CancellationError())
                return
            }
            guard let productSessionRouter,
                let transportClaim = await productSessionRouter.claimActiveAdapter()
            else {
                continuation.finish(throwing: BridgeSchemeError.invalidRoute("product-session-unavailable"))
                return
            }
            guard !Task.isCancelled else {
                continuation.finish(throwing: CancellationError())
                await transportClaim.finish()
                return
            }
            do {
                for try await result in transportClaim.adapter.reply(for: request) {
                    try Task.checkCancellation()
                    continuation.yield(result)
                }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
            await transportClaim.finish()
        }
        continuation.onTermination = { _ in
            task.cancel()
        }
    }
}

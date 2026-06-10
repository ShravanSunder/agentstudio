import Foundation

actor BridgeContentStore {
    private struct ContentKey: Hashable {
        let handleId: String
        let reviewGeneration: BridgeReviewGeneration
        let itemId: String
        let role: BridgeContentHandle.Role
        let endpointId: String
        let contentHash: String
    }

    private var contentByKey: [ContentKey: BridgeContentLoadResult] = [:]
    private var keyByHandleId: [String: ContentKey] = [:]

    func register(_ result: BridgeContentLoadResult) {
        let key = ContentKey(
            handleId: result.handle.handleId,
            reviewGeneration: result.handle.reviewGeneration,
            itemId: result.handle.itemId,
            role: result.handle.role,
            endpointId: result.handle.endpointId,
            contentHash: result.handle.contentHash
        )
        contentByKey[key] = result
        keyByHandleId[result.handle.handleId] = key
    }

    func load(handleId: String, requestedGeneration: BridgeReviewGeneration) throws -> BridgeContentLoadResult {
        guard let key = keyByHandleId[handleId],
            let result = contentByKey[key]
        else {
            throw BridgeProviderFailure.missingContent(handleId: handleId)
        }
        guard result.handle.reviewGeneration == requestedGeneration else {
            throw BridgeProviderFailure.staleReviewGeneration(
                expected: result.handle.reviewGeneration,
                actual: requestedGeneration
            )
        }
        return result
    }
}

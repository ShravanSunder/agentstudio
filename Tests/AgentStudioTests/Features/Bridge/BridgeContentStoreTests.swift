import Foundation
import Testing

@testable import AgentStudio

struct BridgeContentStoreTests {
    @Test("content store resolves base and head content by scoped handle")
    func contentStoreResolvesBaseAndHeadContentByScopedHandle() async throws {
        let store = BridgeContentStore()
        let baseHandle = makeBridgeContentHandle(itemId: "item-1", role: .base, endpointId: "base", reviewGeneration: 7)
        let headHandle = makeBridgeContentHandle(itemId: "item-1", role: .head, endpointId: "head", reviewGeneration: 7)
        let baseResult = makeContentResult(handle: baseHandle, data: "old")
        let headResult = makeContentResult(handle: headHandle, data: "new")

        await store.register(baseResult)
        await store.register(headResult)
        let loadedBase = try await store.load(handleId: baseHandle.handleId, requestedGeneration: 7)
        let loadedHead = try await store.load(handleId: headHandle.handleId, requestedGeneration: 7)

        #expect(loadedBase == baseResult)
        #expect(loadedHead == headResult)
    }

    @Test("content store rejects stale review generation requests")
    func contentStoreRejectsStaleReviewGenerationRequests() async throws {
        let store = BridgeContentStore()
        let handle = makeBridgeContentHandle(itemId: "item-1", role: .head, reviewGeneration: 7)
        await store.register(makeContentResult(handle: handle, data: "hello"))

        await #expect(throws: BridgeProviderFailure.self) {
            _ = try await store.load(handleId: handle.handleId, requestedGeneration: 6)
        }
    }
}

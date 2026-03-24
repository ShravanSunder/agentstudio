import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
@MainActor
struct WindowRestoreBridgeTests {
    @Test("stream yields latest bounds exactly once when store becomes ready")
    func test_windowRestoreBridge_streamYieldsLatestBoundsExactlyOnce() async throws {
        let store = WindowLifecycleStore()
        let bridge = WindowRestoreBridge(windowLifecycleStore: store)
        var iterator = bridge.stream.makeAsyncIterator()
        let firstBounds = CGRect(x: 0, y: 0, width: 900, height: 500)
        let finalBounds = CGRect(x: 0, y: 0, width: 1140, height: 824)

        store.recordTerminalContainerBounds(firstBounds)
        store.recordTerminalContainerBounds(finalBounds)
        store.recordLaunchLayoutSettled()

        let yieldedBounds = try #require(await iterator.next())
        #expect(yieldedBounds == finalBounds)
        #expect(await iterator.next() == nil)
    }

    @Test("stream does not yield before store is ready")
    func test_windowRestoreBridge_streamDoesNotYieldBeforeStoreReady() async {
        let store = WindowLifecycleStore()
        let bridge = WindowRestoreBridge(windowLifecycleStore: store)
        let probe = BridgeYieldProbe()

        let consumeTask = Task { @MainActor in
            var iterator = bridge.stream.makeAsyncIterator()
            if await iterator.next() != nil {
                await probe.markYielded()
            }
        }

        store.recordTerminalContainerBounds(CGRect(x: 0, y: 0, width: 1140, height: 824))

        await Task.yield()
        await Task.yield()
        #expect(await probe.hasYielded() == false)

        consumeTask.cancel()
        _ = await consumeTask.result
    }

    @Test("stream yields immediately when store is already ready at init")
    func test_windowRestoreBridge_streamYieldsImmediatelyWhenStoreAlreadyReady() async throws {
        let store = WindowLifecycleStore()
        let readyBounds = CGRect(x: 0, y: 0, width: 1140, height: 824)
        store.recordTerminalContainerBounds(readyBounds)
        store.recordLaunchLayoutSettled()

        let bridge = WindowRestoreBridge(windowLifecycleStore: store)
        var iterator = bridge.stream.makeAsyncIterator()

        let yieldedBounds = try #require(await iterator.next())
        #expect(yieldedBounds == readyBounds)
        #expect(await iterator.next() == nil)
    }
}

private actor BridgeYieldProbe {
    private var yielded = false

    func markYielded() {
        yielded = true
    }

    func hasYielded() -> Bool {
        yielded
    }
}

import Foundation

@testable import AgentStudio

actor ProductFileMetadataEventCollector {
    private(set) var events: [BridgeProductFileMetadataEvent] = []
    private var treeWindowWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

    func append(_ event: BridgeProductFileMetadataEvent) {
        events.append(event)
        let treeWindowCount = events.count { if case .treeWindow = $0 { true } else { false } }
        let readyWaiters = treeWindowWaiters.filter { $0.count <= treeWindowCount }
        treeWindowWaiters.removeAll { $0.count <= treeWindowCount }
        for waiter in readyWaiters { waiter.continuation.resume() }
    }

    func removeAll() {
        events.removeAll(keepingCapacity: false)
    }

    func waitForTreeWindowCount(_ expectedCount: Int) async {
        let treeWindowCount = events.count { if case .treeWindow = $0 { true } else { false } }
        guard treeWindowCount < expectedCount else { return }
        await withCheckedContinuation { continuation in
            treeWindowWaiters.append((count: expectedCount, continuation: continuation))
        }
    }
}

import Foundation

@MainActor
final class RuntimeRegistry {
    private var runtimes: [PaneId: any PaneRuntime] = [:]
    private var kindIndex: [PaneContentType: Set<PaneId>] = [:]

    func register(_ runtime: any PaneRuntime) {
        precondition(runtimes[runtime.paneId] == nil, "Duplicate registration for pane \(runtime.paneId)")
        runtimes[runtime.paneId] = runtime
        kindIndex[runtime.metadata.contentType, default: []].insert(runtime.paneId)
    }

    @discardableResult
    func unregister(_ paneId: PaneId) -> (any PaneRuntime)? {
        guard let runtime = runtimes.removeValue(forKey: paneId) else {
            return nil
        }
        kindIndex[runtime.metadata.contentType]?.remove(paneId)
        return runtime
    }

    func runtime(for paneId: PaneId) -> (any PaneRuntime)? {
        runtimes[paneId]
    }

    func runtimes(ofType type: PaneContentType) -> [any PaneRuntime] {
        (kindIndex[type] ?? []).compactMap { runtimes[$0] }
    }

    var readyRuntimes: [any PaneRuntime] {
        runtimes.values.filter { $0.lifecycle == .ready }
    }

    func shutdownAll(timeout: Duration) async -> [PaneId: [UUID]] {
        var unfinished: [PaneId: [UUID]] = [:]
        for (paneId, runtime) in runtimes {
            let ids = await runtime.shutdown(timeout: timeout)
            if !ids.isEmpty {
                unfinished[paneId] = ids
            }
        }
        runtimes.removeAll()
        kindIndex.removeAll()
        return unfinished
    }

    var count: Int { runtimes.count }
}

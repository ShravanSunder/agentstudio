import Foundation
import os.log

private let runtimeRegistryLogger = Logger(subsystem: "com.agentstudio", category: "RuntimeRegistry")

@MainActor
final class RuntimeRegistry {
    static let shared = RuntimeRegistry()

    enum RegistrationResult: Equatable {
        case inserted
        case duplicateRejected
    }

    private var runtimes: [PaneId: any PaneRuntime] = [:]
    private var kindIndex: [PaneContentType: Set<PaneId>] = [:]

    @discardableResult
    func register(_ runtime: any PaneRuntime) -> RegistrationResult {
        if runtimes[runtime.paneId] != nil {
            runtimeRegistryLogger.error(
                "Duplicate registration rejected for pane \(runtime.paneId, privacy: .public); existing runtime preserved"
            )
            return .duplicateRejected
        }

        runtimes[runtime.paneId] = runtime
        kindIndex[runtime.metadata.contentType, default: []].insert(runtime.paneId)
        return .inserted
    }

    @discardableResult
    func unregister(_ paneId: PaneId) -> (any PaneRuntime)? {
        guard let runtime = runtimes.removeValue(forKey: paneId) else {
            return nil
        }
        removeFromKindIndex(paneId: paneId, contentType: runtime.metadata.contentType)
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
        // PaneRuntime is MainActor-isolated, so shutdown is intentionally ordered here.
        // A task group would still hop back to MainActor for each call without true parallel execution.
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

    private func removeFromKindIndex(paneId: PaneId, contentType: PaneContentType) {
        kindIndex[contentType]?.remove(paneId)
        if kindIndex[contentType]?.isEmpty == true {
            kindIndex.removeValue(forKey: contentType)
        }
    }
}

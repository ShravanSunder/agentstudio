import Foundation

extension RepoScannerTraversalSession {
    func shouldSuspendBeforeConsumingPath(
        _ path: URL,
        usage: MutableQuantumUsage
    ) -> Bool {
        let pathByteCount = path.path.utf8.count
        return usage.enumeratedItemCount > 0
            && pathByteCount
                > quantumBudget.maximumPathBytes - usage.enumeratedPathByteCount
    }
}

import AgentStudioCore
import Foundation

/// Holds one real File status read so the two-pane journey can inspect the
/// updating chrome while that File refresh is still in progress.
actor BridgeProductWebKitGatedGitStatusProvider: GitWorkingTreeStatusProvider {
    private let base: any GitWorkingTreeStatusProvider
    private var shouldBlockNextStatusRead = false
    private var blockedStatusReadCount = 0
    private var blockedStatusReadContinuation: CheckedContinuation<Void, Never>?
    private var blockedStatusReadWaiters: [(Int, CheckedContinuation<Int, Never>)] = []

    init(base: any GitWorkingTreeStatusProvider) {
        self.base = base
    }

    func armNextStatusRead() {
        shouldBlockNextStatusRead = true
    }

    func waitForBlockedStatusReadCount(_ count: Int) async -> Int {
        if blockedStatusReadCount < count {
            return await withCheckedContinuation { continuation in
                blockedStatusReadWaiters.append((count, continuation))
            }
        }
        return blockedStatusReadCount
    }

    func releaseBlockedStatusRead() {
        shouldBlockNextStatusRead = false
        blockedStatusReadContinuation?.resume()
        blockedStatusReadContinuation = nil
    }

    func statusResult(for rootPath: URL, pathspecs: [String]?) async -> GitWorkingTreeStatusResult {
        if shouldBlockNextStatusRead {
            shouldBlockNextStatusRead = false
            blockedStatusReadCount += 1
            let readyWaiters = blockedStatusReadWaiters.filter { blockedStatusReadCount >= $0.0 }
            blockedStatusReadWaiters.removeAll { blockedStatusReadCount >= $0.0 }
            for (_, continuation) in readyWaiters {
                continuation.resume(returning: blockedStatusReadCount)
            }
            await withTaskCancellationHandler {
                await withCheckedContinuation { continuation in
                    if Task.isCancelled {
                        continuation.resume()
                    } else {
                        blockedStatusReadContinuation = continuation
                    }
                }
            } onCancel: {
                Task { await self.releaseBlockedStatusRead() }
            }
        }
        return await base.statusResult(for: rootPath, pathspecs: pathspecs)
    }

    func statusFactsResult(
        for rootPath: URL,
        pathspecs: [String]?
    ) async -> GitWorkingTreeStatusFactsResult {
        await base.statusFactsResult(for: rootPath, pathspecs: pathspecs)
    }

    func lineDetailResult(for rootPath: URL) async -> GitWorkingTreeLineDetailResult {
        await base.lineDetailResult(for: rootPath)
    }
}

import Foundation

/// Delays title-only publication while preserving the existing next-turn path
/// for presentation, activity, and lifecycle work.
final class TerminalLocalActionDrainScheduler: @unchecked Sendable {
    static let titlePublicationWindowMilliseconds = 250

    private struct PendingDrain {
        let token: UInt64
        let workItem: DispatchWorkItem
    }

    private let lock = NSLock()
    private let schedulingQueue = DispatchQueue(
        label: "com.agentstudio.terminal-local-action-drain",
        qos: .userInteractive
    )
    private let drain: @MainActor @Sendable (UUID) async -> Void
    private var nextToken: UInt64 = 0
    private var pendingTitleDrainsBySurfaceID: [UUID: PendingDrain] = [:]

    init(drain: @escaping @MainActor @Sendable (UUID) async -> Void) {
        self.drain = drain
    }

    func schedule(_ surfaceID: UUID, _ schedule: TerminalLocalDrainSchedule) {
        switch schedule {
        case .immediate:
            cancel(for: surfaceID)
            Task { @MainActor [drain] in
                await drain(surfaceID)
            }
        case .titleWindow:
            scheduleTitleWindow(for: surfaceID)
        }
    }

    func cancel(for surfaceID: UUID) {
        lock.withLock {
            pendingTitleDrainsBySurfaceID.removeValue(forKey: surfaceID)?.workItem.cancel()
        }
    }

    private func scheduleTitleWindow(for surfaceID: UUID) {
        let workItem = lock.withLock { () -> DispatchWorkItem? in
            guard pendingTitleDrainsBySurfaceID[surfaceID] == nil else { return nil }
            nextToken &+= 1
            let token = nextToken
            let workItem = DispatchWorkItem { [weak self] in
                self?.executeDrain(for: surfaceID, token: token)
            }
            pendingTitleDrainsBySurfaceID[surfaceID] = PendingDrain(token: token, workItem: workItem)
            return workItem
        }
        guard let workItem else { return }
        schedulingQueue.asyncAfter(
            deadline: .now() + .milliseconds(Self.titlePublicationWindowMilliseconds),
            execute: workItem
        )
    }

    private func executeDrain(for surfaceID: UUID, token: UInt64) {
        let shouldDrain = lock.withLock { () -> Bool in
            guard pendingTitleDrainsBySurfaceID[surfaceID]?.token == token else { return false }
            pendingTitleDrainsBySurfaceID.removeValue(forKey: surfaceID)
            return true
        }
        guard shouldDrain else { return }
        Task { @MainActor [drain] in
            await drain(surfaceID)
        }
    }
}

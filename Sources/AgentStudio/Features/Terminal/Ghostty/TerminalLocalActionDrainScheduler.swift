import Foundation

typealias TerminalMainActorDrainOperation = @MainActor @Sendable () async -> Void

/// Delays title-only publication while preserving the existing next-turn path
/// for presentation, activity, and lifecycle work.
final class TerminalLocalActionDrainScheduler: @unchecked Sendable {
    static let titlePublicationMaximumMilliseconds = 250
    static let titleAdmissionSlackMilliseconds = 25
    static let titleDrainAdmissionDelayMilliseconds =
        titlePublicationMaximumMilliseconds - titleAdmissionSlackMilliseconds

    private enum ClaimPhase {
        case titleDeadline(DispatchWorkItem)
        case mainActorAdmission
    }

    private struct DrainClaim {
        let token: UInt64
        var phase: ClaimPhase
        var followUpSchedule: TerminalLocalDrainSchedule?
    }

    private let lock = NSLock()
    private let schedulingQueue = DispatchQueue(
        label: "com.agentstudio.terminal-local-action-drain",
        qos: .userInteractive
    )
    private let drain: @MainActor @Sendable (UUID) async -> Void
    private let scheduleTitleDeadline: @Sendable (DispatchWorkItem) -> Void
    private let enqueueMainActorDrain: @Sendable (@escaping TerminalMainActorDrainOperation) -> Void
    private var nextToken: UInt64 = 0
    private var drainClaimsBySurfaceID: [UUID: DrainClaim] = [:]

    init(
        drain: @escaping @MainActor @Sendable (UUID) async -> Void,
        scheduleTitleDeadline: (@Sendable (DispatchWorkItem) -> Void)? = nil,
        enqueueMainActorDrain: (@Sendable (@escaping TerminalMainActorDrainOperation) -> Void)? = nil
    ) {
        self.drain = drain
        self.scheduleTitleDeadline =
            scheduleTitleDeadline
            ?? { [schedulingQueue] workItem in
                schedulingQueue.asyncAfter(
                    deadline: .now() + .milliseconds(Self.titleDrainAdmissionDelayMilliseconds),
                    execute: workItem
                )
            }
        self.enqueueMainActorDrain =
            enqueueMainActorDrain
            ?? { operation in
                Task { @MainActor in
                    await operation()
                }
            }
    }

    func schedule(_ surfaceID: UUID, _ schedule: TerminalLocalDrainSchedule) {
        switch schedule {
        case .immediate:
            scheduleImmediate(for: surfaceID)
        case .titleWindow:
            scheduleTitleWindow(for: surfaceID)
        }
    }

    func scheduleFollowUp(_ surfaceID: UUID, _ schedule: TerminalLocalDrainSchedule) {
        let shouldScheduleNormally = lock.withLock { () -> Bool in
            guard var claim = drainClaimsBySurfaceID[surfaceID] else { return true }
            claim.followUpSchedule = merged(claim.followUpSchedule, schedule)
            drainClaimsBySurfaceID[surfaceID] = claim
            return false
        }
        if shouldScheduleNormally {
            self.schedule(surfaceID, schedule)
        }
    }

    func cancel(for surfaceID: UUID) {
        lock.withLock {
            guard let claim = drainClaimsBySurfaceID.removeValue(forKey: surfaceID) else { return }
            if case .titleDeadline(let workItem) = claim.phase {
                workItem.cancel()
            }
        }
    }

    var pendingDrainClaimCount: Int {
        lock.withLock { drainClaimsBySurfaceID.count }
    }

    private func scheduleTitleWindow(for surfaceID: UUID) {
        let workItem = lock.withLock { () -> DispatchWorkItem? in
            guard drainClaimsBySurfaceID[surfaceID] == nil else { return nil }
            nextToken &+= 1
            let token = nextToken
            let workItem = DispatchWorkItem { [weak self] in
                self?.claimTitleDeadline(for: surfaceID, token: token)
            }
            drainClaimsBySurfaceID[surfaceID] = DrainClaim(
                token: token,
                phase: .titleDeadline(workItem),
                followUpSchedule: nil
            )
            return workItem
        }
        guard let workItem else { return }
        scheduleTitleDeadline(workItem)
    }

    private func scheduleImmediate(for surfaceID: UUID) {
        let token = lock.withLock { () -> UInt64? in
            if var claim = drainClaimsBySurfaceID[surfaceID] {
                switch claim.phase {
                case .titleDeadline(let workItem):
                    workItem.cancel()
                    claim.phase = .mainActorAdmission
                    drainClaimsBySurfaceID[surfaceID] = claim
                    return claim.token
                case .mainActorAdmission:
                    return nil
                }
            }
            nextToken &+= 1
            let token = nextToken
            drainClaimsBySurfaceID[surfaceID] = DrainClaim(
                token: token,
                phase: .mainActorAdmission,
                followUpSchedule: nil
            )
            return token
        }
        guard let token else { return }
        enqueueClaimedDrain(for: surfaceID, token: token)
    }

    private func claimTitleDeadline(for surfaceID: UUID, token: UInt64) {
        let shouldEnqueue = lock.withLock { () -> Bool in
            guard var claim = drainClaimsBySurfaceID[surfaceID], claim.token == token else { return false }
            guard case .titleDeadline = claim.phase else { return false }
            claim.phase = .mainActorAdmission
            drainClaimsBySurfaceID[surfaceID] = claim
            return true
        }
        guard shouldEnqueue else { return }
        enqueueClaimedDrain(for: surfaceID, token: token)
    }

    private func enqueueClaimedDrain(for surfaceID: UUID, token: UInt64) {
        // Enqueue after releasing the scheduler lock. The drain may enter the
        // accumulator, preserving the documented accumulator -> scheduler order.
        enqueueMainActorDrain { [weak self] in
            guard let self, self.claimIsCurrent(for: surfaceID, token: token) else { return }
            await self.drain(surfaceID)
            self.completeClaim(for: surfaceID, token: token)
        }
    }

    private func claimIsCurrent(for surfaceID: UUID, token: UInt64) -> Bool {
        lock.withLock {
            drainClaimsBySurfaceID[surfaceID]?.token == token
        }
    }

    private func completeClaim(for surfaceID: UUID, token: UInt64) {
        let followUpSchedule = lock.withLock { () -> TerminalLocalDrainSchedule? in
            guard let claim = drainClaimsBySurfaceID[surfaceID], claim.token == token else { return nil }
            drainClaimsBySurfaceID.removeValue(forKey: surfaceID)
            return claim.followUpSchedule
        }
        if let followUpSchedule {
            schedule(surfaceID, followUpSchedule)
        }
    }

    private func merged(
        _ current: TerminalLocalDrainSchedule?,
        _ requested: TerminalLocalDrainSchedule
    ) -> TerminalLocalDrainSchedule {
        switch (current, requested) {
        case (.immediate, _), (_, .immediate):
            return .immediate
        case (.titleWindow, .titleWindow), (nil, .titleWindow):
            return .titleWindow
        }
    }
}

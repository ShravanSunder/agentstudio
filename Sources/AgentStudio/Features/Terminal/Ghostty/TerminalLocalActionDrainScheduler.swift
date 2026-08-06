import Foundation

typealias TerminalMainActorDrainOperation = @MainActor @Sendable () async -> Void

/// Owns one scheduler claim per independent local-action lane.
final class TerminalLocalActionDrainScheduler: @unchecked Sendable {
    private enum ClaimPhase {
        case titleDeadline(DispatchWorkItem)
        case mainActorAdmission
    }

    private struct ClaimKey: Hashable {
        let surfaceID: UUID
        let lane: TerminalLocalActionLane
    }

    private struct DrainClaim {
        let token: UInt64
        var phase: ClaimPhase
        var followUpRequest: TerminalLocalDrainRequest?
    }

    private let lock = NSLock()
    private let schedulingQueue = DispatchQueue(
        label: "com.agentstudio.terminal-local-action-drain", qos: .userInteractive)
    private let drain: @MainActor @Sendable (UUID, TerminalLocalActionLane) async -> Void
    private let scheduleTitleDeadline: @Sendable (UInt64, DispatchWorkItem) -> Void
    private let enqueueMainActorDrain: @Sendable (@escaping TerminalMainActorDrainOperation) -> Void
    private var nextToken: UInt64 = 0
    private var claims: [ClaimKey: DrainClaim] = [:]

    init(
        drain: @escaping @MainActor @Sendable (UUID, TerminalLocalActionLane) async -> Void,
        scheduleTitleDeadline: (@Sendable (UInt64, DispatchWorkItem) -> Void)? = nil,
        enqueueMainActorDrain: (@Sendable (@escaping TerminalMainActorDrainOperation) -> Void)? = nil
    ) {
        self.drain = drain
        self.scheduleTitleDeadline =
            scheduleTitleDeadline ?? { [schedulingQueue] deadline, workItem in
                schedulingQueue.asyncAfter(deadline: DispatchTime(uptimeNanoseconds: deadline), execute: workItem)
            }
        self.enqueueMainActorDrain =
            enqueueMainActorDrain ?? { operation in
                Task { @MainActor in await operation() }
            }
    }

    func schedule(_ surfaceID: UUID, _ request: TerminalLocalDrainRequest) {
        let key = ClaimKey(surfaceID: surfaceID, lane: request.lane)
        switch request.lane {
        case .immediate: scheduleImmediate(key: key)
        case .title: scheduleTitle(key: key, request: request)
        }
    }

    func scheduleFollowUp(_ surfaceID: UUID, _ request: TerminalLocalDrainRequest) {
        let key = ClaimKey(surfaceID: surfaceID, lane: request.lane)
        let scheduleNormally = lock.withLock { () -> Bool in
            guard var claim = claims[key] else { return true }
            claim.followUpRequest = request
            claims[key] = claim
            return false
        }
        if scheduleNormally { schedule(surfaceID, request) }
    }

    func cancel(for surfaceID: UUID) {
        lock.withLock {
            for key in claims.keys.filter({ $0.surfaceID == surfaceID }) {
                if case .titleDeadline(let workItem) = claims.removeValue(forKey: key)?.phase { workItem.cancel() }
            }
        }
    }

    func cancelTitle(for surfaceID: UUID) {
        let key = ClaimKey(surfaceID: surfaceID, lane: .title)
        lock.withLock {
            if case .titleDeadline(let workItem) = claims.removeValue(forKey: key)?.phase { workItem.cancel() }
        }
    }

    var pendingDrainClaimCount: Int { lock.withLock { claims.count } }

    private func scheduleTitle(key: ClaimKey, request: TerminalLocalDrainRequest) {
        guard let deadline = request.absoluteDeadlineNanoseconds else {
            preconditionFailure("Title requests require an absolute deadline")
        }
        let item = lock.withLock { () -> DispatchWorkItem? in
            guard claims[key] == nil else { return nil }
            nextToken &+= 1
            let token = nextToken
            let item = DispatchWorkItem { [weak self] in self?.claimTitleDeadline(key: key, token: token) }
            claims[key] = DrainClaim(token: token, phase: .titleDeadline(item), followUpRequest: nil)
            return item
        }
        if let item { scheduleTitleDeadline(deadline, item) }
    }

    private func scheduleImmediate(key: ClaimKey) {
        let token = lock.withLock { () -> UInt64? in
            guard claims[key] == nil else { return nil }
            nextToken &+= 1
            claims[key] = DrainClaim(
                token: nextToken, phase: .mainActorAdmission, followUpRequest: nil)
            return nextToken
        }
        if let token { enqueueClaimedDrain(key: key, token: token) }
    }

    private func claimTitleDeadline(key: ClaimKey, token: UInt64) {
        let shouldEnqueue = lock.withLock { () -> Bool in
            guard var claim = claims[key], claim.token == token, case .titleDeadline = claim.phase else { return false }
            claim.phase = .mainActorAdmission
            claims[key] = claim
            return true
        }
        if shouldEnqueue { enqueueClaimedDrain(key: key, token: token) }
    }

    private func enqueueClaimedDrain(key: ClaimKey, token: UInt64) {
        enqueueMainActorDrain { [weak self] in
            guard let self, self.claimIsCurrent(key: key, token: token) else { return }
            await self.drain(key.surfaceID, key.lane)
            self.completeClaim(key: key, token: token)
        }
    }

    private func claimIsCurrent(key: ClaimKey, token: UInt64) -> Bool {
        lock.withLock { claims[key]?.token == token }
    }

    private func completeClaim(key: ClaimKey, token: UInt64) {
        let followUp = lock.withLock { () -> TerminalLocalDrainRequest? in
            guard let claim = claims[key], claim.token == token else { return nil }
            claims.removeValue(forKey: key)
            return claim.followUpRequest
        }
        if let followUp { schedule(key.surfaceID, followUp) }
    }
}

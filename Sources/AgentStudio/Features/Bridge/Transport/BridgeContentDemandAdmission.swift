import Foundation

enum BridgeContentDemandInterest: String, Equatable, Sendable {
    case selected
    case visible
    case nearby
    case speculative
    case background
    case unspecified

    static let queryKey = "interest"

    static func parse(_ resourceURL: String) -> Self? {
        guard let components = URLComponents(string: resourceURL) else {
            return nil
        }
        let values = (components.queryItems ?? [])
            .filter { $0.name == queryKey }
            .map(\.value)
        guard values.count <= 1 else {
            return nil
        }
        guard let value = values.first else {
            return .unspecified
        }
        return value.flatMap(Self.init(rawValue:))
    }

    static func parseQueryValue(_ value: String?) -> Self? {
        guard let value else {
            return nil
        }
        return Self(rawValue: value)
    }

    var isUserBlocking: Bool {
        self == .selected || self == .visible
    }

    var isBackgroundFill: Bool {
        self == .background
    }
}

struct BridgeContentDemandAdmissionSnapshot: Equatable, Sendable {
    let activeScopedAdmissionCount: Int
    let backgroundCancellationTombstoneCount: Int
    let backgroundWaiterRegistrationCount: Int
    let backgroundWaiterCount: Int
    let hasBackgroundCooldownTask: Bool
    let hasBackgroundPacingTask: Bool
    let isClosed: Bool
    let pendingUserDemandCount: Int
}

actor BridgeContentDemandAdmission {
    private let delay: AsyncDelay
    private var activeScopedAdmissionCount = 0
    private var backgroundWaiterCancellationTombstones: Set<UUID> = []
    private var backgroundWaiterContinuationsById: [UUID: CheckedContinuation<Void, Error>] = [:]
    private var backgroundWaiterIds: [UUID] = []
    private var backgroundWaiterRegistrationIds: Set<UUID> = []
    private var pendingUserDemandCount = 0
    private var backgroundPacingTask: Task<Void, Never>?
    private var backgroundCooldownTask: Task<Void, Never>?
    private var closingBackgroundCooldownTask: Task<Void, Never>?
    private var closingBackgroundPacingTask: Task<Void, Never>?
    private var cooldownGeneration = 0
    private var closeAndDrainWaiters: [CheckedContinuation<Void, Never>] = []
    private var isBackgroundCooldownActive = false
    private var isClosed = false
    private var backgroundFillTokens = AppPolicies.Bridge.contentBackgroundFillInteractiveBurstBudget

    init(clock: (any Clock<Duration> & Sendable)? = nil) {
        delay = clock.map(AsyncDelay.clock) ?? .taskSleep
    }

    func withAdmission<ReturnValue: Sendable>(
        for interest: BridgeContentDemandInterest,
        operation: @Sendable () async throws -> ReturnValue
    ) async throws -> ReturnValue {
        try await beginScopedAdmission(interest)
        defer { finishScopedAdmission(interest) }
        try Task.checkCancellation()
        return try await operation()
    }

    func snapshot() -> BridgeContentDemandAdmissionSnapshot {
        BridgeContentDemandAdmissionSnapshot(
            activeScopedAdmissionCount: activeScopedAdmissionCount,
            backgroundCancellationTombstoneCount: backgroundWaiterCancellationTombstones.count,
            backgroundWaiterRegistrationCount: backgroundWaiterRegistrationIds.count,
            backgroundWaiterCount: backgroundWaiterContinuationsById.count,
            hasBackgroundCooldownTask: backgroundCooldownTask != nil || closingBackgroundCooldownTask != nil,
            hasBackgroundPacingTask: backgroundPacingTask != nil || closingBackgroundPacingTask != nil,
            isClosed: isClosed,
            pendingUserDemandCount: pendingUserDemandCount
        )
    }

    func start(_ interest: BridgeContentDemandInterest) async {
        guard !isClosed else { return }
        if interest.isUserBlocking {
            recordUserDemandStart()
            return
        }
        if interest.isBackgroundFill {
            try? await awaitBackgroundTurn()
        }
    }

    func finish(_ interest: BridgeContentDemandInterest) {
        guard interest.isUserBlocking else {
            return
        }
        if pendingUserDemandCount > 0 {
            pendingUserDemandCount -= 1
        }
        guard !isClosed else { return }
        if pendingUserDemandCount == 0 {
            beginBackgroundCooldown()
            releaseEligibleBackgroundWaiters()
        }
    }

    func waitForBackgroundTurn(_ interest: BridgeContentDemandInterest) async {
        guard !isClosed, interest.isBackgroundFill else {
            return
        }
        try? await awaitBackgroundTurn()
    }

    func waitForBackgroundTurn() async {
        guard !isClosed else { return }
        try? await awaitBackgroundTurn()
    }

    func closeAndDrain() async {
        if !isClosed {
            isClosed = true
            pendingUserDemandCount = 0
            isBackgroundCooldownActive = false
            backgroundFillTokens = 0
            cooldownGeneration += 1

            closingBackgroundCooldownTask = backgroundCooldownTask
            closingBackgroundPacingTask = backgroundPacingTask
            backgroundCooldownTask = nil
            backgroundPacingTask = nil
            closingBackgroundCooldownTask?.cancel()
            closingBackgroundPacingTask?.cancel()

            backgroundWaiterIds.removeAll(keepingCapacity: false)
            let backgroundWaiters = Array(backgroundWaiterContinuationsById.values)
            backgroundWaiterContinuationsById.removeAll(keepingCapacity: false)
            backgroundWaiterRegistrationIds.removeAll(keepingCapacity: false)
            backgroundWaiterCancellationTombstones.removeAll(keepingCapacity: false)
            for waiter in backgroundWaiters {
                waiter.resume(throwing: CancellationError())
            }
        }

        await closingBackgroundCooldownTask?.value
        await closingBackgroundPacingTask?.value
        closingBackgroundCooldownTask = nil
        closingBackgroundPacingTask = nil

        guard activeScopedAdmissionCount > 0 else { return }
        await withCheckedContinuation { continuation in
            closeAndDrainWaiters.append(continuation)
        }
    }

    private func beginScopedAdmission(_ interest: BridgeContentDemandInterest) async throws {
        try Task.checkCancellation()
        guard !isClosed else { throw CancellationError() }
        if interest.isUserBlocking {
            recordUserDemandStart()
            activeScopedAdmissionCount += 1
            return
        }
        if interest.isBackgroundFill {
            try await awaitBackgroundTurn()
        }
        guard !isClosed else { throw CancellationError() }
        activeScopedAdmissionCount += 1
    }

    private func finishScopedAdmission(_ interest: BridgeContentDemandInterest) {
        finish(interest)
        if activeScopedAdmissionCount > 0 {
            activeScopedAdmissionCount -= 1
        }
        resumeCloseAndDrainWaitersIfNeeded()
    }

    private func awaitBackgroundTurn() async throws {
        try Task.checkCancellation()
        guard !isClosed else { throw CancellationError() }
        if shouldYieldForPendingUserDemand {
            try await enqueueBackgroundWaiter()
            return
        }
        guard isBackgroundCooldownActive else {
            backgroundFillTokens = AppPolicies.Bridge.contentBackgroundFillInteractiveBurstBudget
            return
        }
        guard backgroundFillTokens > 0 else {
            try await enqueueBackgroundWaiter()
            return
        }
        backgroundFillTokens -= 1
    }

    private var shouldYieldForPendingUserDemand: Bool {
        pendingUserDemandCount >= AppPolicies.Bridge.contentBackgroundFillUserInterestYieldThreshold
    }

    private var isInteractiveUseActive: Bool {
        shouldYieldForPendingUserDemand || isBackgroundCooldownActive
    }

    private func recordUserDemandStart() {
        let wasInteractiveUseActive = isInteractiveUseActive
        pendingUserDemandCount += 1
        isBackgroundCooldownActive = false
        backgroundCooldownTask?.cancel()
        backgroundCooldownTask = nil
        cooldownGeneration += 1
        if !wasInteractiveUseActive {
            backgroundFillTokens = AppPolicies.Bridge.contentBackgroundFillInteractiveBurstBudget
        }
    }

    private func beginBackgroundCooldown() {
        guard !isClosed else { return }
        isBackgroundCooldownActive = true
        cooldownGeneration += 1
        let generation = cooldownGeneration
        backgroundCooldownTask?.cancel()
        let delay = self.delay
        backgroundCooldownTask = Task {
            do {
                try await delay.wait(AppPolicies.Bridge.contentBackgroundFillInteractiveCooldown)
            } catch {
                return
            }
            self.finishBackgroundCooldown(generation: generation)
        }
    }

    private func finishBackgroundCooldown(generation: Int) {
        guard !isClosed, generation == cooldownGeneration, pendingUserDemandCount == 0 else {
            return
        }
        isBackgroundCooldownActive = false
        backgroundFillTokens = AppPolicies.Bridge.contentBackgroundFillInteractiveBurstBudget
        backgroundCooldownTask = nil
        backgroundPacingTask?.cancel()
        backgroundPacingTask = nil
        resumeBackgroundWaiters()
    }

    private func enqueueBackgroundWaiter() async throws {
        let waiterId = UUID()
        backgroundWaiterRegistrationIds.insert(waiterId)
        let admission = self
        do {
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    registerBackgroundWaiter(waiterId, continuation: continuation)
                }
                try Task.checkCancellation()
            } onCancel: {
                Task {
                    await admission.cancelBackgroundWaiter(waiterId)
                }
            }
        } catch {
            discardBackgroundWaiterRegistration(waiterId)
            throw error
        }
        discardBackgroundWaiterRegistration(waiterId)
    }

    private func registerBackgroundWaiter(
        _ waiterId: UUID,
        continuation: CheckedContinuation<Void, Error>
    ) {
        guard backgroundWaiterRegistrationIds.remove(waiterId) != nil else {
            continuation.resume(throwing: CancellationError())
            return
        }
        if backgroundWaiterCancellationTombstones.remove(waiterId) != nil {
            continuation.resume(throwing: CancellationError())
            return
        }
        backgroundWaiterIds.append(waiterId)
        backgroundWaiterContinuationsById[waiterId] = continuation
        releaseEligibleBackgroundWaiters()
    }

    private func cancelBackgroundWaiter(_ waiterId: UUID) {
        if let continuation = backgroundWaiterContinuationsById.removeValue(forKey: waiterId) {
            backgroundWaiterIds.removeAll { $0 == waiterId }
            cancelBackgroundPacingIfNoWaiters()
            continuation.resume(throwing: CancellationError())
            return
        }
        guard backgroundWaiterRegistrationIds.contains(waiterId) else { return }
        backgroundWaiterCancellationTombstones.insert(waiterId)
    }

    private func discardBackgroundWaiterRegistration(_ waiterId: UUID) {
        backgroundWaiterRegistrationIds.remove(waiterId)
        backgroundWaiterCancellationTombstones.remove(waiterId)
    }

    private func releaseEligibleBackgroundWaiters() {
        guard !isClosed else { return }
        guard !backgroundWaiterIds.isEmpty else {
            cancelBackgroundPacingIfNoWaiters()
            return
        }
        guard !shouldYieldForPendingUserDemand else {
            return
        }
        guard isBackgroundCooldownActive else {
            resumeBackgroundWaiters()
            return
        }

        while backgroundFillTokens > 0, let waiterId = backgroundWaiterIds.first {
            backgroundWaiterIds.removeFirst()
            guard let continuation = backgroundWaiterContinuationsById.removeValue(forKey: waiterId)
            else { continue }
            backgroundFillTokens -= 1
            continuation.resume()
        }
        if backgroundWaiterIds.isEmpty {
            cancelBackgroundPacingIfNoWaiters()
        } else {
            scheduleBackgroundPacingTickIfNeeded()
        }
    }

    private func scheduleBackgroundPacingTickIfNeeded() {
        guard !isClosed,
            backgroundPacingTask == nil,
            isBackgroundCooldownActive,
            !shouldYieldForPendingUserDemand,
            !backgroundWaiterIds.isEmpty
        else {
            return
        }
        let delay = self.delay
        backgroundPacingTask = Task {
            do {
                try await delay.wait(AppPolicies.Bridge.contentBackgroundFillInteractiveRefillInterval)
            } catch {
                return
            }
            self.refillBackgroundFillTokens()
        }
    }

    private func refillBackgroundFillTokens() {
        backgroundPacingTask = nil
        guard !isClosed else { return }
        guard isBackgroundCooldownActive else {
            releaseEligibleBackgroundWaiters()
            return
        }
        guard !shouldYieldForPendingUserDemand else {
            return
        }
        backgroundFillTokens = min(
            AppPolicies.Bridge.contentBackgroundFillInteractiveBurstBudget,
            backgroundFillTokens + AppPolicies.Bridge.contentBackgroundFillInteractiveRefillBudget
        )
        releaseEligibleBackgroundWaiters()
    }

    private func resumeBackgroundWaiters() {
        let waiterIds = backgroundWaiterIds
        backgroundWaiterIds.removeAll(keepingCapacity: false)
        for waiterId in waiterIds {
            backgroundWaiterContinuationsById.removeValue(forKey: waiterId)?.resume()
        }
    }

    private func cancelBackgroundPacingIfNoWaiters() {
        guard backgroundWaiterIds.isEmpty else { return }
        backgroundPacingTask?.cancel()
        backgroundPacingTask = nil
    }

    private func resumeCloseAndDrainWaitersIfNeeded() {
        guard isClosed, activeScopedAdmissionCount == 0 else { return }
        let waiters = closeAndDrainWaiters
        closeAndDrainWaiters.removeAll(keepingCapacity: false)
        for waiter in waiters {
            waiter.resume()
        }
    }
}

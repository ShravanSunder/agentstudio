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

actor BridgeContentDemandAdmission {
    private let delay: AsyncDelay
    private var pendingUserDemandCount = 0
    private var backgroundWaiters: [CheckedContinuation<Void, Never>] = []
    private var backgroundPacingTask: Task<Void, Never>?
    private var backgroundCooldownTask: Task<Void, Never>?
    private var cooldownGeneration = 0
    private var isBackgroundCooldownActive = false
    private var backgroundFillTokens = AppPolicies.Bridge.contentBackgroundFillInteractiveBurstBudget

    init(clock: (any Clock<Duration> & Sendable)? = nil) {
        delay = clock.map(AsyncDelay.clock) ?? .taskSleep
    }

    func start(_ interest: BridgeContentDemandInterest) async {
        if interest.isUserBlocking {
            recordUserDemandStart()
            return
        }
        if interest.isBackgroundFill {
            await waitForBackgroundTurn()
        }
    }

    func finish(_ interest: BridgeContentDemandInterest) {
        guard interest.isUserBlocking, pendingUserDemandCount > 0 else {
            return
        }
        pendingUserDemandCount -= 1
        if pendingUserDemandCount == 0 {
            beginBackgroundCooldown()
            releaseEligibleBackgroundWaiters()
        }
    }

    func waitForBackgroundTurn(_ interest: BridgeContentDemandInterest) async {
        guard interest.isBackgroundFill else {
            return
        }
        await waitForBackgroundTurn()
    }

    func waitForBackgroundTurn() async {
        if shouldYieldForPendingUserDemand {
            await enqueueBackgroundWaiter()
            return
        }
        guard isBackgroundCooldownActive else {
            backgroundFillTokens = AppPolicies.Bridge.contentBackgroundFillInteractiveBurstBudget
            return
        }
        guard backgroundFillTokens > 0 else {
            await enqueueBackgroundWaiter()
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
        guard generation == cooldownGeneration, pendingUserDemandCount == 0 else {
            return
        }
        isBackgroundCooldownActive = false
        backgroundFillTokens = AppPolicies.Bridge.contentBackgroundFillInteractiveBurstBudget
        backgroundCooldownTask = nil
        backgroundPacingTask?.cancel()
        backgroundPacingTask = nil
        resumeBackgroundWaiters()
    }

    private func enqueueBackgroundWaiter() async {
        await withCheckedContinuation { continuation in
            backgroundWaiters.append(continuation)
            scheduleBackgroundPacingTickIfNeeded()
        }
    }

    private func releaseEligibleBackgroundWaiters() {
        guard !backgroundWaiters.isEmpty else {
            backgroundPacingTask?.cancel()
            backgroundPacingTask = nil
            return
        }
        guard !shouldYieldForPendingUserDemand else {
            return
        }
        guard isBackgroundCooldownActive else {
            resumeBackgroundWaiters()
            return
        }

        var releasedWaiters: [CheckedContinuation<Void, Never>] = []
        while backgroundFillTokens > 0, !backgroundWaiters.isEmpty {
            backgroundFillTokens -= 1
            releasedWaiters.append(backgroundWaiters.removeFirst())
        }
        if backgroundWaiters.isEmpty {
            backgroundPacingTask?.cancel()
            backgroundPacingTask = nil
        } else {
            scheduleBackgroundPacingTickIfNeeded()
        }
        for waiter in releasedWaiters {
            waiter.resume()
        }
    }

    private func scheduleBackgroundPacingTickIfNeeded() {
        guard backgroundPacingTask == nil,
            isBackgroundCooldownActive,
            !shouldYieldForPendingUserDemand,
            !backgroundWaiters.isEmpty
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
        let waiters = backgroundWaiters
        backgroundWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }
}

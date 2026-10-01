import AgentStudioInfrastructure
import Foundation

actor BridgeFileSurfaceReconciler {
    struct Attempt: Equatable, Sendable {
        let inputGeneration: UInt64
        let nonce: UUID
    }

    enum FailureDisposition: Equatable, Sendable {
        case retryable
        case permanent
    }

    enum FailurePhase: String, Equatable, Sendable {
        case build
        case delivery
    }

    enum FailureCause: String, Equatable, Sendable {
        case missingRoot
        case unreadableRoot
        case accessRefused
        case repeatedSupersession
        case progressExpired
        case providerFailure
        case unrecognizedProviderFailure
    }

    struct Failure: Equatable, Sendable {
        let disposition: FailureDisposition
        let phase: FailurePhase
        let cause: FailureCause
    }

    enum BuilderOutcome: Equatable, Sendable {
        case built
        case superseded(newerInputGeneration: UInt64)
        case failed(Failure)
    }

    enum Action: Equatable, Sendable {
        case start(Attempt)
        case restart(retiring: Attempt, starting: Attempt)
        case rest
        case failed(Failure)
    }

    private(set) var currentInputGeneration: UInt64?
    private(set) var activeAttempt: Attempt?
    private(set) var retiringAttempt: Attempt?
    private(set) var currentFailure: Failure?
    private let maximumUnchangedInputSupersessions: Int
    private var unchangedInputSupersessionCount = 0

    init(
        maximumUnchangedInputSupersessions: Int = AppPolicies.Bridge
            .fileSurfaceMaximumUnchangedInputSupersessions
    ) {
        precondition(maximumUnchangedInputSupersessions > 0)
        self.maximumUnchangedInputSupersessions = maximumUnchangedInputSupersessions
    }

    func beginAttempt(inputGeneration: UInt64) -> Action {
        guard activeAttempt == nil else { return .rest }
        guard currentFailure == nil else { return .rest }
        guard let currentInputGeneration else {
            self.currentInputGeneration = inputGeneration
            return startAttempt(inputGeneration: inputGeneration)
        }
        guard inputGeneration >= currentInputGeneration else { return .rest }
        if inputGeneration > currentInputGeneration {
            return inputsChanged(to: inputGeneration)
        }
        return startAttempt(inputGeneration: inputGeneration)
    }

    func inputsChanged(to inputGeneration: UInt64) -> Action {
        guard currentInputGeneration.map({ inputGeneration > $0 }) ?? true else {
            return .rest
        }
        currentInputGeneration = inputGeneration
        unchangedInputSupersessionCount = 0
        currentFailure = nil
        guard let activeAttempt else {
            return startAttempt(inputGeneration: inputGeneration)
        }
        retiringAttempt = activeAttempt
        let successor = makeAttempt(inputGeneration: inputGeneration)
        self.activeAttempt = successor
        return .restart(retiring: activeAttempt, starting: successor)
    }

    func builderFinished(
        _ attempt: Attempt,
        outcome: BuilderOutcome
    ) -> Action {
        guard activeAttempt == attempt,
            let currentInputGeneration
        else { return .rest }
        activeAttempt = nil

        switch outcome {
        case .built:
            currentFailure = nil
            return .rest
        case .superseded(let newerInputGeneration):
            let latestInputGeneration = max(currentInputGeneration, newerInputGeneration)
            if latestInputGeneration > attempt.inputGeneration {
                self.currentInputGeneration = latestInputGeneration
                unchangedInputSupersessionCount = 0
                currentFailure = nil
                retiringAttempt = attempt
                let successor = makeAttempt(inputGeneration: latestInputGeneration)
                activeAttempt = successor
                return .restart(retiring: attempt, starting: successor)
            }

            unchangedInputSupersessionCount += 1
            guard unchangedInputSupersessionCount <= maximumUnchangedInputSupersessions else {
                let failure = Failure(
                    disposition: .retryable,
                    phase: .build,
                    cause: .repeatedSupersession
                )
                currentFailure = failure
                return .failed(failure)
            }
            return startAttempt(inputGeneration: currentInputGeneration)
        case .failed(let failure):
            currentFailure = failure
            return .failed(failure)
        }
    }

    func retry() -> Action {
        guard activeAttempt == nil,
            currentFailure?.disposition == .retryable,
            let currentInputGeneration
        else { return .rest }
        currentFailure = nil
        unchangedInputSupersessionCount = 0
        return startAttempt(inputGeneration: currentInputGeneration)
    }

    func retirementCompleted(_ attempt: Attempt) {
        guard retiringAttempt == attempt else { return }
        retiringAttempt = nil
    }

    private func startAttempt(inputGeneration: UInt64) -> Action {
        let attempt = makeAttempt(inputGeneration: inputGeneration)
        activeAttempt = attempt
        return .start(attempt)
    }

    private func makeAttempt(inputGeneration: UInt64) -> Attempt {
        Attempt(inputGeneration: inputGeneration, nonce: UUIDv7.generate())
    }
}

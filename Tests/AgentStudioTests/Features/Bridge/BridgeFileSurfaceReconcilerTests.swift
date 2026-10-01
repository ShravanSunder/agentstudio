import Foundation
import Testing

@testable import AgentStudioBridge

@Suite("Bridge File surface reconciliation")
struct BridgeFileSurfaceReconcilerTests {
    @Test("newer material input restarts at its generation without spending unchanged-input budget")
    func newerMaterialInputRestartsAtItsGenerationWithoutSpendingUnchangedInputBudget() async throws {
        let reconciler = BridgeFileSurfaceReconciler(maximumUnchangedInputSupersessions: 1)
        guard case .start(let initialAttempt) = await reconciler.beginAttempt(inputGeneration: 7) else {
            Issue.record("Expected the initial File attempt to start")
            return
        }

        let changedInputAction = await reconciler.builderFinished(
            initialAttempt,
            outcome: .superseded(newerInputGeneration: 8)
        )

        guard case .restart(let retiringAttempt, let changedInputAttempt) = changedInputAction else {
            Issue.record("Expected a material input change to restart the File attempt")
            return
        }
        #expect(retiringAttempt == initialAttempt)
        #expect(changedInputAttempt.inputGeneration == 8)
        #expect(changedInputAttempt.nonce != initialAttempt.nonce)
        #expect(await reconciler.inputsChanged(to: 8) == .rest)

        let unchangedInputAction = await reconciler.builderFinished(
            changedInputAttempt,
            outcome: .superseded(newerInputGeneration: 8)
        )

        guard case .start(let unchangedInputRetry) = unchangedInputAction else {
            Issue.record("A material input change must leave the unchanged-input retry available")
            return
        }
        #expect(unchangedInputRetry.inputGeneration == 8)
        #expect(unchangedInputRetry.nonce != changedInputAttempt.nonce)

        let boundedFailureAction = await reconciler.builderFinished(
            unchangedInputRetry,
            outcome: .superseded(newerInputGeneration: 8)
        )
        guard case .failed(let repeatedSupersessionFailure) = boundedFailureAction else {
            Issue.record("Repeated supersession at unchanged input must end in a bounded failure")
            return
        }
        #expect(repeatedSupersessionFailure.disposition == .retryable)
        #expect(repeatedSupersessionFailure.cause == .repeatedSupersession)
        #expect(await reconciler.beginAttempt(inputGeneration: 8) == .rest)

        guard case .start(let retryAttempt) = await reconciler.retry() else {
            Issue.record("Explicit Retry must renew the unchanged-input attempt budget")
            return
        }
        #expect(retryAttempt.inputGeneration == 8)
        #expect(retryAttempt.nonce != unchangedInputRetry.nonce)
    }
}

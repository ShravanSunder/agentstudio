import AgentStudioInfrastructure
import AgentStudioTestHarness
import Foundation
import Testing

@testable import AgentStudioBridge

private typealias OperationRead = BridgeProductOperationResultResponse?

@Suite("Bridge product operation result table")
struct BridgeProductOperationTableTests {
    @Test("revocation observes an execution registered with its admission")
    func revocationTracksExecutionFromAdmission() async throws {
        let harness = try await BridgeProductSessionLifecycleHarness.opened()
        let request = try BridgeProductStrictJSON.decode(
            BridgeProductControlRequest.self,
            from: bridgeProductSchemeReviewCallBody(requestSequence: 2)
        )
        guard case .execute(let token, _) = try await harness.begin(request) else {
            Issue.record("Expected a product call admission")
            return
        }
        let heldExecution = HeldStep<Void>(
            "operationExecutionAfterRevocation",
            cancellation: .holdThroughCancellation
        )
        let admitted = try await harness.session.admitControlOperation(token: token) { _ in
            try? await heldExecution.arrive(())
        }
        _ = try await heldExecution.firstArrival()
        #expect((await harness.session.diagnosticSnapshot).activeOperationExecutionCount == 1)

        let revocation = await harness.session.revoke(acknowledgeLifecycle: { _ in true })
        #expect(await revocation.wait())
        try await heldExecution.cancellationObserved()
        #expect((await harness.session.diagnosticSnapshot).activeOperationExecutionCount == 1)

        heldExecution.release()
        await harness.session.waitForOperationExecution(operationId: admitted.operationId)
        #expect((await harness.session.diagnosticSnapshot).activeOperationExecutionCount == 0)
    }

    @Test("cancelled result reader releases its waiter without consuming the eventual settlement")
    func cancellingResultReaderPreservesSettlement() async throws {
        let request = try BridgeProductStrictJSON.decode(
            BridgeProductControlRequest.self,
            from: bridgeProductSchemeReviewCallBody(requestSequence: 3)
        )
        let token = BridgeProductControlAdmissionToken(identifier: 1, requestSequence: 3)
        let operationId = UUIDv7.generate().uuidString.lowercased()
        var table = BridgeProductOperationTable()
        table.admit(
            operationId: operationId,
            waitKind: .ordinary,
            admission: .init(
                deferredResyncEpochs: [:],
                productAdmission: try BridgeProductAdmissionTestContext.make().context,
                request: request,
                token: token
            )
        )

        let cancelledWaiterId = UUIDv7.generate()
        let cancelledRead: OperationRead = await withCheckedContinuation { continuation in
            table.observeResult(
                operationId: operationId,
                waiterId: cancelledWaiterId,
                continuation: continuation
            )
            table.cancelResultWaiter(operationId: operationId, waiterId: cancelledWaiterId)
        }
        #expect(cancelledRead == nil)
        #expect(table.entriesById[operationId]?.resultWaiters.isEmpty == true)

        let settlement = BridgeProductOperationResultResponse(
            operationId: operationId,
            outcome: .failed
        )
        let didSettle = table.settle(settlement)
        #expect(didSettle)
        let repeatedRead: OperationRead = await withCheckedContinuation { continuation in
            table.observeResult(
                operationId: operationId,
                waiterId: UUIDv7.generate(),
                continuation: continuation
            )
        }
        #expect(repeatedRead == settlement)
        let didAcknowledge = table.acknowledge(operationId: operationId)
        #expect(didAcknowledge)
        #expect(table.entriesById.isEmpty)
    }

    @Test("session end sends cancelled to a pending reader and forgets every retained result")
    func sessionEndSettlesReaderAndClearsStore() async throws {
        let request = try BridgeProductStrictJSON.decode(
            BridgeProductControlRequest.self,
            from: bridgeProductSchemeReviewCallBody(requestSequence: 3)
        )
        let operationId = UUIDv7.generate().uuidString.lowercased()
        var table = BridgeProductOperationTable()
        table.admit(
            operationId: operationId,
            waitKind: .ordinary,
            admission: .init(
                deferredResyncEpochs: [:],
                productAdmission: try BridgeProductAdmissionTestContext.make().context,
                request: request,
                token: BridgeProductControlAdmissionToken(identifier: 2, requestSequence: 3)
            )
        )

        let observed: OperationRead = await withCheckedContinuation { continuation in
            table.observeResult(
                operationId: operationId,
                waiterId: UUIDv7.generate(),
                continuation: continuation
            )
            table.cancelAndForgetAllOperations()
        }
        #expect(observed?.outcome == .cancelled)
        #expect(table.entriesById.isEmpty)
        #expect(table.executionTasksById.isEmpty)
    }
}

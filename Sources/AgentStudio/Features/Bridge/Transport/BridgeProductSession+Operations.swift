import AgentStudioInfrastructure
import Foundation

extension BridgeProductSession {
    func operationWaitKind(
        for request: BridgeProductControlRequest
    ) -> BridgeProductOperationWaitKind {
        guard case .productCall(let callRequest) = request else { return .ordinary }
        let annotationOperation: BridgeProductWorktreeAnnotationOperation
        switch callRequest.call {
        case .fileAnnotationsCommand(let command), .reviewAnnotationsCommand(let command):
            annotationOperation = command.operation
        default:
            return .ordinary
        }
        switch annotationOperation {
        case .repeatOutput:
            return .human
        case .outputScopeCommit(let body) where body.outputKind == .jsonFile:
            return .human
        default:
            return .ordinary
        }
    }

    func admitControlOperation(
        token: BridgeProductControlAdmissionToken,
        execute: @escaping @Sendable (String) async -> Void
    ) throws -> (operationId: String, responseBytes: Data, waitKind: BridgeProductOperationWaitKind) {
        guard let pendingControl, pendingControl.token == token, lifecycle != .revoked else {
            throw BridgeProductSessionError.invalidAdmissionToken
        }
        let waitKind = operationWaitKind(for: pendingControl.request)
        guard operationTable.hasCapacity(for: waitKind) else {
            throw BridgeProductSessionError.resultCapacityExhausted
        }
        let operationId = UUIDv7.generate().uuidString
        let response = BridgeProductOperationAdmittedResponse(
            correlation: pendingControl.request.correlation,
            operationId: operationId,
            waitKind: waitKind
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let responseBytes = try encoder.encode(response)
        try controlReplay.complete(token: token, exactResponseBytes: responseBytes)
        operationTable.admit(
            operationId: operationId,
            waitKind: waitKind,
            admission: pendingControl
        )
        // Provider work must start off this session actor's executor.
        // swiftlint:disable:next no_task_detached
        let executionTask = Task.detached { [self] in
            await execute(operationId)
            await finishOperationExecution(operationId: operationId)
        }
        let deadlineTask: Task<Void, Never>?
        switch waitKind {
        case .human:
            deadlineTask = nil
        case .ordinary:
            deadlineTask = Task { [self] in
                do {
                    try await operationDelay.wait(
                        AppPolicies.Bridge.productOperationSettlementDeadline
                    )
                    expireOperation(operationId: operationId)
                } catch is CancellationError {
                    // A settled operation cancelled its deadline.
                } catch {
                    expireOperation(operationId: operationId)
                }
            }
        }
        operationTable.registerTasks(
            operationId: operationId,
            executionTask: executionTask,
            deadlineTask: deadlineTask
        )
        self.pendingControl = nil
        return (operationId, responseBytes, waitKind)
    }

    func completeEscapeControl(
        token: BridgeProductControlAdmissionToken,
        response: BridgeProductControlResponse
    ) throws -> BridgeProductSessionCompletionEffect {
        guard let pendingControl, pendingControl.token == token,
            pendingControl.request.isSlotFreeEscape,
            lifecycle == .active
        else { throw BridgeProductSessionError.invalidAdmissionToken }
        try BridgeProductSessionControlTransitionBuilder.validateResponseShape(
            request: pendingControl.request,
            response: response
        )
        let transition = try BridgeProductSessionControlTransitionBuilder.prepare(
            request: pendingControl.request,
            response: response,
            subscriptionState: subscriptionState,
            resyncEpochs: pendingControl.deferredResyncEpochs,
            currentEpochs: workerDerivationEpochBySurface,
            snapshotRequiredSubscriptionIds: []
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let responseBytes = try encoder.encode(response)
        try admitRequiredProtocolLifecycleFrame(for: transition.effect)
        try controlReplay.complete(token: token, exactResponseBytes: responseBytes)
        subscriptionState = transition.subscriptionState
        self.pendingControl = nil
        return transition.effect
    }

    func waitForOperationExecution(operationId: String) async {
        let executionTask = operationTable.executionTasksById[operationId]
        await executionTask?.value
    }

    func waitForOutstandingOperationExecutions() async {
        let tasks = Array(operationTable.executionTasksById.values)
        for task in tasks {
            await task.value
        }
    }

    func finishOperationExecution(operationId: String) {
        operationTable.finishExecution(operationId: operationId)
    }

    func beginEscapeEffect() -> UUID? {
        guard lifecycle == .active else { return nil }
        let effectId = UUIDv7.generate()
        activeEscapeEffectIds.insert(effectId)
        return effectId
    }

    func attachEscapeEffect(_ task: Task<Void, Never>, effectId: UUID) {
        guard activeEscapeEffectIds.contains(effectId), lifecycle != .revoked else {
            task.cancel()
            return
        }
        escapeEffectTasksById[effectId] = task
    }

    func finishEscapeEffect(effectId: UUID) {
        activeEscapeEffectIds.remove(effectId)
        escapeEffectTasksById.removeValue(forKey: effectId)
    }

    func waitForOutstandingEscapeEffects() async {
        let tasks = Array(escapeEffectTasksById.values)
        for task in tasks {
            await task.value
        }
    }

    private func expireOperation(operationId: String) {
        guard let entry = operationTable.entriesById[operationId], entry.settlement == nil else {
            return
        }
        let outcome: BridgeProductOperationSettlement =
            entry.admission.request.kind == "product.call" ? .outcomeUnknown : .failed
        guard
            operationTable.settle(
                .init(operationId: operationId, outcome: outcome)
            )
        else { return }
        entry.executionTask?.cancel()
    }

    func readOperationResult(
        _ request: BridgeProductOperationResultRequest,
        productAdmission: BridgeProductAdmissionContext
    ) async -> BridgeProductOperationResultResponse? {
        guard request.paneSessionId == paneSessionId,
            request.workerInstanceId == workerInstanceId,
            productAdmission.withValidAdmission({ true }) == true
        else { return nil }
        let waiterId = UUIDv7.generate()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                if Task.isCancelled {
                    continuation.resume(returning: nil)
                } else {
                    let didPark = operationTable.observeResult(
                        operationId: request.operationId,
                        waiterId: waiterId,
                        continuation: continuation
                    )
                    if didPark {
                        resultWaiterRegistrationObserver?(request.operationId)
                    }
                }
            }
        } onCancel: {
            Task {
                await self.cancelOperationResultWaiter(
                    operationId: request.operationId,
                    waiterId: waiterId
                )
            }
        }
    }

    private func cancelOperationResultWaiter(operationId: String, waiterId: UUID) {
        operationTable.cancelResultWaiter(operationId: operationId, waiterId: waiterId)
    }

    func acknowledgeOperationResult(
        _ request: BridgeProductOperationResultAcknowledgement,
        exactRequestBytes: Data,
        productAdmission: BridgeProductAdmissionContext
    ) -> Data? {
        guard request.correlation.paneSessionId == paneSessionId,
            request.correlation.workerInstanceId == workerInstanceId,
            productAdmission.withValidAdmission({ true }) == true
        else { return nil }
        switch controlReplay.begin(
            requestSequence: request.correlation.requestSequence,
            exactRequestBytes: exactRequestBytes
        ) {
        case .replay(let exactResponseBytes):
            return exactResponseBytes
        case .rejected:
            return nil
        case .execute(let token):
            guard operationTable.entriesById[request.operationId]?.settlement != nil else {
                try? controlReplay.abandon(token: token)
                return nil
            }
            let response = BridgeProductOperationResultAcknowledgedResponse(
                correlation: request.correlation,
                operationId: request.operationId
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            guard let bytes = try? encoder.encode(response),
                (try? controlReplay.complete(token: token, exactResponseBytes: bytes)) != nil
            else {
                try? controlReplay.abandon(token: token)
                return nil
            }
            _ = operationTable.acknowledge(operationId: request.operationId)
            return bytes
        }
    }

    func settleOperation(
        operationId: String,
        response: BridgeProductControlResponse
    ) {
        let outcome: BridgeProductOperationSettlement
        let failureCode: BridgeProductRequestErrorCode?
        switch response {
        case .requestError(let error):
            outcome = .refused
            failureCode = error.code
        default:
            outcome = .succeeded
            failureCode = nil
        }
        let encodedResponse = try? JSONEncoder().encode(response)
        let result = encodedResponse.flatMap {
            try? JSONDecoder().decode(BridgeProductJSONValue.self, from: $0)
        }
        _ = operationTable.settle(
            .init(
                failureCode: failureCode,
                operationId: operationId,
                outcome: outcome,
                result: outcome == .succeeded ? result : nil
            )
        )
    }

}

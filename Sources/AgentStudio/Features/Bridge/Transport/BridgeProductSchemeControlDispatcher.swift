import Foundation

enum BridgeProductSchemeControlDispatchResult: Equatable, Sendable {
    case rejected(BridgeProductSessionControlRejection)
    case response(Data)
}

struct BridgeProductSchemeControlDispatcher: Sendable {
    let session: BridgeProductSession
    let provider: any BridgeProductSchemeProvider

    func dispatch(
        exactRequestBytes: Data,
        presentedCapability: String
    ) async throws -> BridgeProductSchemeControlDispatchResult {
        let admission = await session.beginControl(
            exactRequestBytes: exactRequestBytes,
            presentedCapability: presentedCapability
        )
        switch admission {
        case .rejected(let rejection):
            guard let request = rejection.request else {
                return .rejected(rejection.reason)
            }
            return .response(
                try Self.encode(
                    Self.requestError(for: rejection.reason, request: request)
                )
            )
        case .replay(let exactResponseBytes):
            return .response(exactResponseBytes)
        case .execute(let token, let request):
            if Task.isCancelled {
                try await session.abandonControl(token: token)
                throw CancellationError()
            }
            guard await session.claimControlProviderDispatch(token: token) else {
                throw CancellationError()
            }

            // Provider dispatch is the replay boundary. Once it starts, this unstructured
            // task must finish and cache one exact response even if the URL task closes.
            let completion = Task { [provider, session] in
                do {
                    let providerResponse = await provider.response(for: request)
                    let authoritativeResponse = try await session.authoritativeControlResponse(
                        token: token,
                        providerResponse: providerResponse
                    )
                    let response = try await Self.completeControl(
                        providerResponse: authoritativeResponse,
                        request: request,
                        token: token,
                        session: session,
                        provider: provider
                    )
                    await session.settleControlProviderDispatch(token: token)
                    return response
                } catch {
                    await session.settleControlProviderDispatch(token: token)
                    throw error
                }
            }
            let exactResponseBytes = try await completion.value
            return .response(exactResponseBytes)
        }
    }

    private static func completeControl(
        providerResponse: BridgeProductControlResponse,
        request: BridgeProductControlRequest,
        token: BridgeProductControlAdmissionToken,
        session: BridgeProductSession,
        provider: any BridgeProductSchemeProvider
    ) async throws -> Data {
        let providerResponseBytes = try encode(providerResponse)
        do {
            let completionEffect = try await session.completeControl(
                token: token,
                exactResponseBytes: providerResponseBytes
            )
            await applyCommittedEffect(
                completionEffect,
                request: request,
                provider: provider
            )
            return providerResponseBytes
        } catch {
            let internalError = try BridgeProductControlResponse.requestError(
                correlating: request,
                code: .internal,
                nextExpectedRequestSequence: request.requestSequence + 1,
                retryAfterMilliseconds: nil,
                retryable: false,
                safeMessage: nil
            )
            let internalErrorBytes = try encode(internalError)
            let completionEffect = try await session.completeControl(
                token: token,
                exactResponseBytes: internalErrorBytes
            )
            await applyCommittedEffect(
                completionEffect,
                request: request,
                provider: provider
            )
            return internalErrorBytes
        }
    }

    private static func applyCommittedEffect(
        _ effect: BridgeProductSessionCompletionEffect,
        request: BridgeProductControlRequest,
        provider: any BridgeProductSchemeProvider
    ) async {
        guard effect != .noEffect else { return }
        await provider.applyCommittedControlEffect(effect, for: request)
    }

    private static func encode(_ response: BridgeProductControlResponse) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(response)
    }

    private static func requestError(
        for rejection: BridgeProductSessionControlRejection,
        request: BridgeProductControlRequest
    ) throws -> BridgeProductControlResponse {
        let code: BridgeProductRequestErrorCode
        let nextExpectedRequestSequence: Int?
        let retryable: Bool
        switch rejection {
        case .inactiveSession:
            code = .resyncRequired
            nextExpectedRequestSequence = nil
            retryable = true
        case .invalidRequest:
            code = .invalidRequest
            nextExpectedRequestSequence = nil
            retryable = false
        case .payloadTooLarge:
            code = .payloadTooLarge
            nextExpectedRequestSequence = nil
            retryable = false
        case .requestInFlight(let nextExpected):
            code = .sequenceConflict
            nextExpectedRequestSequence = nextExpected
            retryable = true
        case .revoked, .staleWorker:
            code = .staleWorker
            nextExpectedRequestSequence = nil
            retryable = false
        case .sequenceExhausted(let nextExpected),
            .sequenceConflict(let nextExpected):
            code = .sequenceConflict
            nextExpectedRequestSequence = nextExpected
            retryable = true
        case .staleDerivationEpoch, .streamSequenceConflict:
            code = .resyncRequired
            nextExpectedRequestSequence = nil
            retryable = true
        case .unauthorized:
            code = .unauthorized
            nextExpectedRequestSequence = nil
            retryable = false
        }
        return try .requestError(
            correlating: request,
            code: code,
            nextExpectedRequestSequence: nextExpectedRequestSequence,
            retryAfterMilliseconds: nil,
            retryable: retryable,
            safeMessage: nil
        )
    }
}

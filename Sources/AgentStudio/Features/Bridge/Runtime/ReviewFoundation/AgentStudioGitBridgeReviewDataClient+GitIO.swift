import AgentStudioGit
import CryptoKit
import Foundation

extension AgentStudioGitBridgeReviewDataClient {
    func loadGitDiff(
        _ request: GitDiffRequest,
        freshnessKey: BridgeGitReadFreshnessKey
    ) async throws -> GitDiffSnapshot {
        let client = self.client
        do {
            return try await scheduledGitRead(
                operationClass: .reviewMetadata,
                coalescingKey: try gitReadCoalescingKey(domain: "diff", request: request),
                freshnessKey: freshnessKey
            ) {
                try await client.diff(request)
            }
        } catch BridgeGitReadSchedulerError.timedOut {
            throw BridgeProviderFailure.providerFailed(message: BridgeGitReadFailure.timeoutMessage)
        } catch BridgeGitReadSchedulerError.capacityReached {
            throw BridgeProviderFailure.providerFailed(message: BridgeGitReadFailure.capacityMessage)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as GitDataPlaneError {
            throw bridgeFailure(for: error)
        } catch {
            throw BridgeProviderFailure.providerFailed(message: unexpectedGitDataPlaneErrorMessage(error))
        }
    }

    func loadGitStatus(
        _ options: GitStatusOptions,
        freshnessKey: BridgeGitReadFreshnessKey
    ) async throws -> GitStatusSnapshot {
        let client = self.client
        do {
            return try await scheduledGitRead(
                operationClass: .reviewMetadata,
                coalescingKey: try gitReadCoalescingKey(domain: "status", request: options),
                freshnessKey: freshnessKey
            ) {
                try await client.status(for: self.repositoryPath, options: options)
            }
        } catch BridgeGitReadSchedulerError.timedOut {
            throw BridgeProviderFailure.providerFailed(message: BridgeGitReadFailure.timeoutMessage)
        } catch BridgeGitReadSchedulerError.capacityReached {
            throw BridgeProviderFailure.providerFailed(message: BridgeGitReadFailure.capacityMessage)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as GitDataPlaneError {
            throw bridgeFailure(for: error)
        } catch {
            throw BridgeProviderFailure.providerFailed(message: unexpectedGitDataPlaneErrorMessage(error))
        }
    }

    func loadGitTree(
        _ request: GitTreeReadRequest,
        freshnessKey: BridgeGitReadFreshnessKey
    ) async throws -> GitTreeSnapshot {
        let client = self.client
        do {
            return try await scheduledGitRead(
                operationClass: .reviewMetadata,
                coalescingKey: try gitReadCoalescingKey(domain: "tree", request: request),
                freshnessKey: freshnessKey
            ) {
                try await client.readTree(request)
            }
        } catch BridgeGitReadSchedulerError.timedOut {
            throw BridgeProviderFailure.providerFailed(message: BridgeGitReadFailure.timeoutMessage)
        } catch BridgeGitReadSchedulerError.capacityReached {
            throw BridgeProviderFailure.providerFailed(message: BridgeGitReadFailure.capacityMessage)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as GitDataPlaneError {
            throw bridgeFailure(for: error)
        } catch {
            throw BridgeProviderFailure.providerFailed(message: unexpectedGitDataPlaneErrorMessage(error))
        }
    }

    func loadGitContent(
        _ request: GitContentRequest,
        handle: BridgeContentHandle?,
        freshnessKey: BridgeGitReadFreshnessKey
    ) async throws -> GitContentPayload {
        do {
            return try await loadGitContentPayload(
                request,
                operationClass: .selectedVisibleContent,
                freshnessKey: freshnessKey
            )
        } catch BridgeGitReadSchedulerError.timedOut {
            throw BridgeProviderFailure.providerFailed(message: BridgeGitReadFailure.timeoutMessage)
        } catch BridgeGitReadSchedulerError.capacityReached {
            throw BridgeProviderFailure.providerFailed(message: BridgeGitReadFailure.capacityMessage)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as GitDataPlaneError {
            throw bridgeFailure(for: error, handle: handle)
        } catch {
            throw BridgeProviderFailure.providerFailed(message: unexpectedGitDataPlaneErrorMessage(error))
        }
    }

    func loadGitContentPayload(
        _ request: GitContentRequest,
        operationClass: BridgeGitReadOperationClass = .reviewMetadata,
        freshnessKey: BridgeGitReadFreshnessKey
    ) async throws -> GitContentPayload {
        let client = self.client
        return try await scheduledGitRead(
            operationClass: operationClass,
            coalescingKey: try gitReadCoalescingKey(domain: "content", request: request),
            freshnessKey: freshnessKey
        ) {
            try await client.content(request)
        }
    }

    private func scheduledGitRead<ReturnValue: Sendable>(
        operationClass: BridgeGitReadOperationClass,
        coalescingKey: BridgeGitReadCoalescingKey,
        freshnessKey: BridgeGitReadFreshnessKey,
        operation: @escaping @Sendable () async throws -> ReturnValue
    ) async throws -> ReturnValue {
        try await gitReadContext.scheduler.read(
            request: BridgeGitReadRequest(
                worktreeKey: gitReadContext.worktreeKey,
                operationClass: operationClass,
                coalescingKey: coalescingKey,
                freshnessKey: freshnessKey,
                deadline: gitDataPlaneReadTimeout
            ),
            operation: operation
        )
    }

    private func gitReadCoalescingKey<Request: Encodable>(
        domain: String,
        request: Request
    ) throws -> BridgeGitReadCoalescingKey {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let requestData = try encoder.encode(request)
        var hasher = SHA256()
        hasher.update(data: Data("agentstudio-bridge-git-read-v1:\(domain):".utf8))
        hasher.update(data: requestData)
        return BridgeGitReadCoalescingKey(
            token: hasher.finalize().map { String(format: "%02x", $0) }.joined()
        )
    }

    func gitReadFreshnessKey(
        for reviewGeneration: BridgeReviewGeneration
    ) -> BridgeGitReadFreshnessKey {
        BridgeGitReadFreshnessKey(
            token: "\(gitReadContext.scopeKey.token):review-generation-\(reviewGeneration.rawValue)"
        )
    }

    func bridgeFailure(
        for error: GitDataPlaneError,
        handle: BridgeContentHandle? = nil
    ) -> BridgeProviderFailure {
        switch error {
        case .repositoryNotFound:
            return .providerUnavailable
        case .contentTooLarge(_, let sizeBytes, _):
            if let handle {
                return .oversizedContent(handleId: handle.handleId, sizeBytes: byteCount(sizeBytes))
            }
            return .providerFailed(message: "gitDataPlane:contentTooLarge:sizeBytes=\(sizeBytes)")
        case .pathEscapesRepository:
            return .providerFailed(message: "gitDataPlane:pathEscapesRepository")
        case .libgit2Failure(let code, let klass, let message):
            return .providerFailed(
                message:
                    "gitDataPlane:libgit2Failure:code=\(code):klass=\(klass):reason=\(libGit2FailureReason(message))"
            )
        case .unsupported(let message), .locked(let message):
            return .providerFailed(message: message)
        case .worktreeNotFound:
            return .providerFailed(message: "gitDataPlane:worktreeNotFound")
        case .worktreeNotPrunable:
            return .providerFailed(message: "gitDataPlane:worktreeNotPrunable")
        case .unsafeWorktreeRemoval:
            return .providerFailed(message: "gitDataPlane:unsafeWorktreeRemoval")
        case .processFailed:
            return .providerFailed(message: "gitDataPlane:processFailed")
        case .processTimedOut:
            return .providerFailed(message: "gitDataPlane:processTimedOut")
        case .processCancelled:
            return .providerFailed(message: "gitDataPlane:processCancelled")
        case .processOutputTooLarge:
            return .providerFailed(message: "gitDataPlane:processOutputTooLarge")
        }
    }

    func unexpectedGitDataPlaneErrorMessage(_ error: Error) -> String {
        "gitDataPlane:unexpected:\(String(describing: type(of: error)))"
    }
}

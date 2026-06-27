import AgentStudioGit
import Foundation

extension AgentStudioGitBridgeReviewDataClient {
    func loadGitDiff(_ request: GitDiffRequest) async throws -> GitDiffSnapshot {
        let client = self.client
        do {
            return try await BridgeGitDataPlaneTimeout.readWithHardTimeout(
                gitDataPlaneReadTimeout,
                timeoutScheduler: timeoutScheduler
            ) {
                try await client.diff(request)
            }
        } catch BridgeGitDataPlaneTimeoutError.timedOut {
            throw BridgeProviderFailure.providerFailed(message: BridgeGitDataPlaneTimeoutFailure.message)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as GitDataPlaneError {
            throw bridgeFailure(for: error)
        } catch {
            throw BridgeProviderFailure.providerFailed(message: unexpectedGitDataPlaneErrorMessage(error))
        }
    }

    func loadGitStatus(_ options: GitStatusOptions) async throws -> GitStatusSnapshot {
        let client = self.client
        do {
            return try await BridgeGitDataPlaneTimeout.readWithHardTimeout(
                gitDataPlaneReadTimeout,
                timeoutScheduler: timeoutScheduler
            ) {
                try await client.status(for: self.repositoryPath, options: options)
            }
        } catch BridgeGitDataPlaneTimeoutError.timedOut {
            throw BridgeProviderFailure.providerFailed(message: BridgeGitDataPlaneTimeoutFailure.message)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as GitDataPlaneError {
            throw bridgeFailure(for: error)
        } catch {
            throw BridgeProviderFailure.providerFailed(message: unexpectedGitDataPlaneErrorMessage(error))
        }
    }

    func loadGitTree(_ request: GitTreeReadRequest) async throws -> GitTreeSnapshot {
        let client = self.client
        do {
            return try await BridgeGitDataPlaneTimeout.readWithHardTimeout(
                gitDataPlaneReadTimeout,
                timeoutScheduler: timeoutScheduler
            ) {
                try await client.readTree(request)
            }
        } catch BridgeGitDataPlaneTimeoutError.timedOut {
            throw BridgeProviderFailure.providerFailed(message: BridgeGitDataPlaneTimeoutFailure.message)
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
        handle: BridgeContentHandle?
    ) async throws -> GitContentPayload {
        do {
            return try await loadGitContentPayload(request)
        } catch BridgeGitDataPlaneTimeoutError.timedOut {
            throw BridgeProviderFailure.providerFailed(message: BridgeGitDataPlaneTimeoutFailure.message)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as GitDataPlaneError {
            throw bridgeFailure(for: error, handle: handle)
        } catch {
            throw BridgeProviderFailure.providerFailed(message: unexpectedGitDataPlaneErrorMessage(error))
        }
    }

    func loadGitContentPayload(_ request: GitContentRequest) async throws -> GitContentPayload {
        let client = self.client
        return try await BridgeGitDataPlaneTimeout.readWithHardTimeout(
            gitDataPlaneReadTimeout,
            timeoutScheduler: timeoutScheduler
        ) {
            try await client.content(request)
        }
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

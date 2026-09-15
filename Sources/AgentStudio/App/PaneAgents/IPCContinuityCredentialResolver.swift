import AgentStudioAppIPC
import CryptoKit
import Foundation

actor IPCContinuityCredentialResolver: AgentStudioIPCCredentialResolving {
    private let repository: IPCContinuityRepository

    init(repository: IPCContinuityRepository) {
        self.repository = repository
    }

    func resolveCredential(
        _ credential: AgentStudioIPCSubjectToken,
        serverRuntimeID: UUID
    ) async throws -> AgentStudioIPCCredentialResolution {
        let verifier = Data(SHA256.hash(data: Data(credential.rawValue.utf8)))
        let resolved: IPCContinuityResolvedCredential?
        do {
            resolved = try await repository.credential(matchingVerifier: verifier)
        } catch IPCContinuityRepositoryError.ambiguousVerifier {
            throw AgentStudioIPCAuthenticationError(reason: .unauthenticated)
        }
        guard let resolved else {
            throw AgentStudioIPCAuthenticationError(reason: .unauthenticated)
        }
        switch resolved {
        case .pane(let paneCredential):
            let status: AgentStudioIPCCredentialStatus
            switch paneCredential.status {
            case .active: status = .active
            case .superseded: status = .superseded
            case .prepared, .revoked: throw AgentStudioIPCAuthenticationError(reason: .unauthenticated)
            }
            return .init(
                namespace: .pane(paneID: paneCredential.paneID, workspaceID: paneCredential.workspaceID),
                generationID: paneCredential.generation, status: status)
        case .diagnostic(let runtimeID, let generation, _, let credentialStatus):
            guard runtimeID == serverRuntimeID, credentialStatus == .active else {
                throw AgentStudioIPCAuthenticationError(
                    reason: runtimeID == serverRuntimeID ? .unauthenticated : .runtimeMismatch)
            }
            return .init(namespace: .diagnostic(runtimeID: runtimeID), generationID: generation, status: .active)
        }
    }
}

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
            guard paneCredential.status == .registered else {
                throw AgentStudioIPCAuthenticationError(reason: .unauthenticated)
            }
            return .pane(
                paneID: paneCredential.paneID,
                workspaceID: paneCredential.workspaceID,
                credentialRecordID: paneCredential.credentialRecordID,
                status: .registered
            )
        case .diagnostic(let runtimeID, let generationID, _, let credentialStatus):
            guard runtimeID == serverRuntimeID, credentialStatus == .active else {
                throw AgentStudioIPCAuthenticationError(
                    reason: runtimeID == serverRuntimeID ? .unauthenticated : .runtimeMismatch)
            }
            return .diagnostic(
                runtimeID: runtimeID,
                generationID: generationID,
                status: .active
            )
        }
    }
}

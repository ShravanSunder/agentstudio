import AgentStudioAppIPC
import CryptoKit
import Foundation

/// Durable rows carry pane verifiers only. The reusable debug credential lives
/// in the principal registry's memory, so it never reaches this resolver.
actor IPCContinuityCredentialResolver: AgentStudioIPCCredentialResolving {
    private let repository: IPCContinuityRepository

    init(repository: IPCContinuityRepository) {
        self.repository = repository
    }

    func resolveCredential(
        _ credential: AgentStudioIPCSubjectToken,
        serverRuntimeID _: UUID
    ) async throws -> AgentStudioIPCCredentialResolution {
        let verifier = Data(SHA256.hash(data: Data(credential.rawValue.utf8)))
        let resolved: IPCPaneCredential?
        do {
            resolved = try await repository.credential(matchingVerifier: verifier)
        } catch IPCContinuityRepositoryError.ambiguousVerifier {
            throw AgentStudioIPCAuthenticationError(reason: .unauthenticated)
        }
        guard let resolved, resolved.status == .registered else {
            throw AgentStudioIPCAuthenticationError(reason: .unauthenticated)
        }
        return .pane(
            paneID: resolved.paneID,
            workspaceID: resolved.workspaceID,
            credentialRecordID: resolved.credentialRecordID,
            status: .registered
        )
    }
}

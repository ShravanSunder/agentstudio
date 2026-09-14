import Foundation

enum IPCContinuityCredentialStatus: String, Sendable {
    case prepared
    case active
    case superseded
    case revoked
}

struct IPCContinuityCredential: Sendable {
    let paneID: UUID
    let workspaceID: UUID
    let generation: UUID
    let verifier: Data
    let status: IPCContinuityCredentialStatus
}

enum IPCContinuityRepositoryError: Error, Equatable {
    case invalidVerifierLength
    case conflictingPreparedCredential
    case cannotActivateRevokedCredential
    case cannotActivateCredential
}

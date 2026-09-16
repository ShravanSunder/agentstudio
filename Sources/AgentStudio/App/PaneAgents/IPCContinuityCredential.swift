import Foundation

enum IPCPaneCredentialStatus: String, Sendable {
    case registered
    case revoked
}

enum IPCDiagnosticCredentialStatus: String, Sendable {
    case prepared
    case active
    case revoked
}

struct IPCPaneCredential: Sendable, Equatable {
    let paneID: UUID
    let workspaceID: UUID
    let credentialRecordID: UUID
    let verifierSHA256: Data
    let status: IPCPaneCredentialStatus
}

enum IPCContinuityResolvedCredential: Sendable, Equatable {
    case pane(IPCPaneCredential)
    case diagnostic(
        runtimeID: UUID,
        generationID: UUID,
        verifierSHA256: Data,
        status: IPCDiagnosticCredentialStatus
    )
}

enum IPCContinuityRepositoryError: Error, Equatable {
    case invalidVerifierLength
    case conflictingCredentialRecord
    case ambiguousVerifier
    case cannotTransitionDiagnosticCredential
}

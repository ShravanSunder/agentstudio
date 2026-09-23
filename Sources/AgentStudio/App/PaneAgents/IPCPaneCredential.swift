import Foundation

enum IPCPaneCredentialStatus: String, Sendable {
    case registered
    case revoked
}

struct IPCPaneCredential: Sendable, Equatable {
    let paneID: UUID
    let workspaceID: UUID
    let credentialRecordID: UUID
    let verifierSHA256: Data
    let status: IPCPaneCredentialStatus
}

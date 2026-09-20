import Foundation

/// The debug app hands its reusable credential to an unrelated shell through one
/// owner-only file whose path the launcher names. The app writes this shape and
/// the CLI reads it, so the field spellings and the variable that names the file
/// live here once rather than in both processes.
public struct IPCDebugCredentialEscrowDocument: Codable, Equatable, Sendable {
    public static let environmentVariableName = "AGENTSTUDIO_IPC_DEBUG_TOKEN_ESCROW"

    public let runtimeId: UUID
    public let socketPath: String
    public let token: String

    public init(runtimeId: UUID, socketPath: String, token: String) {
        self.runtimeId = runtimeId
        self.socketPath = socketPath
        self.token = token
    }
}

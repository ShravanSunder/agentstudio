import AgentStudioIPCTransport
import AgentStudioProgrammaticControl
import Foundation

public protocol AppIPCRuntimePort: Sendable {
    func sendInput(_ input: String) async throws
}

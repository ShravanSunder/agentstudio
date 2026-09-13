import AgentStudioProgrammaticControl
import Foundation

package struct IPCDescriptorClientResponse: Sendable {
    package let descriptor: IPCAnyMethodDescriptor
    package let requestID: Int
    package let normalizedResult: Data
}

package enum IPCDescriptorClientCallResult: Sendable {
    case success(IPCDescriptorClientResponse)
    case remoteFailure(IPCDescriptorRemoteFailure)
}

package enum IPCDescriptorClientStreamFrame: Sendable {
    case initialResponse(IPCDescriptorClientResponse)
    case notification(String)
    case remoteFailure(IPCDescriptorRemoteFailure)
}

package struct IPCDescriptorRemoteFailure: Error, Sendable {
    package let code: Int
    package let documentedReason: String?
    package let correction: IPCSchemaValidationError?
}

package struct IPCDescriptorClientFailure: Error, Equatable, Sendable {
    package enum Disposition: Equatable, Sendable {
        case notSubmitted
        case endpointUnavailableBeforeSubmission
        case authenticationRejected
        case deliveryUncertain
    }

    package enum Reason: Equatable, Sendable {
        case socketNotFound
        case endpointConnectFailed(errnoCode: Int32)
        case localRequestEncoding
        case authenticationTransport
        case authenticationResponse
        case commandWrite
        case commandResponseMissing
        case responseIDMismatch
        case invalidResponse
        case invalidTypedResult
    }

    package let disposition: Disposition
    package let reason: Reason
}

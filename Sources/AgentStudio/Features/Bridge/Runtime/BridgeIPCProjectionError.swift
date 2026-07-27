import Foundation

package struct BridgeIPCProjectionError: Error, Equatable, Sendable {
    package enum Reason: String, Equatable, Sendable {
        case packageUnavailable
        case itemNotFound
        case contentUnavailable
        case payloadTooLarge
        case validationRejected
    }

    package let reason: Reason
}

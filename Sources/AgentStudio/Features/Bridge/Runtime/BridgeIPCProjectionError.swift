import Foundation

struct BridgeIPCProjectionError: Error, Equatable, Sendable {
    enum Reason: String, Equatable, Sendable {
        case packageUnavailable
        case itemNotFound
        case contentUnavailable
        case payloadTooLarge
        case validationRejected
    }

    let reason: Reason
}

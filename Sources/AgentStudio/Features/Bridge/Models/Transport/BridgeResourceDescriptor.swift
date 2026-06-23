import Foundation

struct BridgeIntegrityDescriptor: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Equatable, Sendable {
        case wholeHash
        case chunkManifest
        case previewOnly
    }

    let kind: Kind
    let algorithm: String?
    let value: String?
    let manifestResourceId: String?
}

struct BridgeResourceIdentity: Codable, Equatable, Sendable {
    let paneId: String
    let protocolId: String
    let sourceId: String?
    let packageId: String?
    let generation: Int?
    let revision: Int?
    let streamId: String?
    let cursor: String?

    enum CodingKeys: String, CodingKey {
        case paneId
        case protocolId = "protocol"
        case sourceId
        case packageId
        case generation
        case revision
        case streamId
        case cursor
    }
}

struct BridgeResourceContentDescriptor: Codable, Equatable, Sendable {
    enum Encoding: String, Codable, Equatable, Sendable {
        case utf8 = "utf-8"
        case binary
    }

    let mediaType: String
    let encoding: Encoding?
    let expectedBytes: Int?
    let maxBytes: Int
    let integrity: BridgeIntegrityDescriptor?
}

struct BridgeResourceWindowDescriptor: Codable, Equatable, Sendable {
    let start: Int?
    let count: Int?
    let maxCount: Int
}

struct BridgeResourceDescriptor: Codable, Equatable, Sendable {
    let descriptorId: String
    let protocolId: String
    let resourceKind: String
    let resourceUrl: String
    let identity: BridgeResourceIdentity
    let content: BridgeResourceContentDescriptor
    let window: BridgeResourceWindowDescriptor?

    enum CodingKeys: String, CodingKey {
        case descriptorId
        case protocolId = "protocol"
        case resourceKind
        case resourceUrl
        case identity
        case content
        case window
    }
}

struct BridgeDescriptorRef: Codable, Equatable, Sendable {
    let descriptorId: String
    let expectedProtocol: String
    let expectedResourceKind: String
    let expectedIdentity: BridgeResourceIdentity
}

struct BridgeAttachedResourceDescriptor: Codable, Equatable, Sendable {
    let ref: BridgeDescriptorRef
    let descriptor: BridgeResourceDescriptor
}

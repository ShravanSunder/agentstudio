import Foundation

package enum BridgeLinkIdentityError: Error, Equatable, Sendable {
    case emptyValue
    case valueTooLong
    case invalidEncoding
    case invalidPullRequestNumber
    case invalidRelativePath
    case invalidLine
}

package struct BridgeAgentProviderName: Hashable, Sendable, Codable {
    package let value: String

    package init(_ value: String) throws {
        guard !value.isEmpty else { throw BridgeLinkIdentityError.emptyValue }
        guard value.utf8.count <= 128 else { throw BridgeLinkIdentityError.valueTooLong }
        guard value.utf8.allSatisfy({ ($0 >= 97 && $0 <= 122) || ($0 >= 48 && $0 <= 57) || $0 == 45 })
        else { throw BridgeLinkIdentityError.invalidEncoding }
        self.value = value
    }

    package init(from decoder: Decoder) throws {
        try self.init(decoder.singleValueContainer().decode(String.self))
    }

    package func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}

package struct BridgeAgentSessionRef: Hashable, Sendable, Codable {
    package let value: String

    package init(_ value: String) throws {
        guard !value.isEmpty else { throw BridgeLinkIdentityError.emptyValue }
        guard value.utf8.count <= 512 else { throw BridgeLinkIdentityError.valueTooLong }
        self.value = value
    }

    package init(from decoder: Decoder) throws {
        try self.init(decoder.singleValueContainer().decode(String.self))
    }

    package func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}

package struct BridgeAgentContributorIdentity: Hashable, Sendable, Codable {
    package let provider: BridgeAgentProviderName
    package let sessionRef: BridgeAgentSessionRef

    package init(provider: BridgeAgentProviderName, sessionRef: BridgeAgentSessionRef) {
        self.provider = provider
        self.sessionRef = sessionRef
    }

    package init(from decoder: Decoder) throws {
        let container = try BridgeContractWire.decodeFields(
            decoder, required: ["provider", "sessionRef"]
        )
        self.init(
            provider: try container.decode(BridgeAgentProviderName.self, forKey: .provider),
            sessionRef: try container.decode(BridgeAgentSessionRef.self, forKey: .sessionRef)
        )
    }

    package func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: BridgeContractWire.Key.self)
        try container.encode(provider, forKey: .provider)
        try container.encode(sessionRef, forKey: .sessionRef)
    }
}

package enum BridgeLinkContributor: Hashable, Sendable, Codable {
    case app
    case person
    case agent(BridgeAgentContributorIdentity)

    package init(from decoder: Decoder) throws {
        let container = try BridgeContractWire.decode(
            decoder,
            fieldsByKind: [
                "app": [],
                "person": [],
                "agent": ["provider", "sessionRef"],
            ]
        )
        switch try container.decode(String.self, forKey: .kind) {
        case "app": self = .app
        case "person": self = .person
        case "agent":
            self = .agent(
                BridgeAgentContributorIdentity(
                    provider: try container.decode(BridgeAgentProviderName.self, forKey: .provider),
                    sessionRef: try container.decode(BridgeAgentSessionRef.self, forKey: .sessionRef)
                ))
        default: throw BridgeContractWire.invalidKind(decoder)
        }
    }

    package func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: BridgeContractWire.Key.self)
        switch self {
        case .app: try container.encode("app", forKey: .kind)
        case .person: try container.encode("person", forKey: .kind)
        case .agent(let identity):
            try container.encode("agent", forKey: .kind)
            try container.encode(identity.provider, forKey: .provider)
            try container.encode(identity.sessionRef, forKey: .sessionRef)
        }
    }
}

/// The single canonical persisted key codec for link contributors. Percent
/// encoding operates on UTF-8 bytes, so an opaque session reference cannot
/// collide with the provider separator or another contributor.
package enum BridgeLinkContributorKeyCodec {
    package static func encode(_ contributor: BridgeLinkContributor) -> String {
        switch contributor {
        case .app: "app"
        case .person: "person"
        case .agent(let identity):
            "agent:\(identity.provider.value):\(percentEncode(identity.sessionRef.value))"
        }
    }

    package static func decode(_ key: String) throws -> BridgeLinkContributor {
        switch key {
        case "app": return .app
        case "person": return .person
        default:
            let parts = key.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false)
            guard parts.count == 3, parts[0] == "agent" else { throw BridgeLinkIdentityError.invalidEncoding }
            let provider = try BridgeAgentProviderName(String(parts[1]))
            let sessionRef = try BridgeAgentSessionRef(percentDecode(String(parts[2])))
            let contributor = BridgeLinkContributor.agent(
                BridgeAgentContributorIdentity(provider: provider, sessionRef: sessionRef)
            )
            guard encode(contributor) == key else { throw BridgeLinkIdentityError.invalidEncoding }
            return contributor
        }
    }

    private static func percentEncode(_ value: String) -> String {
        var result = ""
        for byte in value.utf8 {
            if (byte >= 65 && byte <= 90) || (byte >= 97 && byte <= 122)
                || (byte >= 48 && byte <= 57) || byte == 45 || byte == 46 || byte == 95 || byte == 126
            {
                result.append(Character(UnicodeScalar(byte)))
            } else {
                result += String(format: "%%%02X", byte)
            }
        }
        return result
    }

    private static func percentDecode(_ value: String) throws -> String {
        let bytes = Array(value.utf8)
        var decoded: [UInt8] = []
        var index = 0
        while index < bytes.count {
            if bytes[index] == 37 {
                guard index + 2 < bytes.count,
                    let high = hex(bytes[index + 1]), let low = hex(bytes[index + 2])
                else { throw BridgeLinkIdentityError.invalidEncoding }
                decoded.append(high * 16 + low)
                index += 3
            } else {
                decoded.append(bytes[index])
                index += 1
            }
        }
        guard let result = String(bytes: decoded, encoding: .utf8) else {
            throw BridgeLinkIdentityError.invalidEncoding
        }
        return result
    }

    private static func hex(_ byte: UInt8) -> UInt8? {
        switch byte {
        case 48...57: byte - 48
        case 65...70: byte - 55
        default: nil
        }
    }
}

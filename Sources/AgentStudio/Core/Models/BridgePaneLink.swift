import Foundation

package struct BridgeLinkContribution: Hashable, Sendable {
    package let addedBy: BridgeLinkContributor
    package let addedAt: Date

    package init(addedBy: BridgeLinkContributor, addedAt: Date) {
        self.addedBy = addedBy
        self.addedAt = addedAt
    }
}

package struct BridgeMemberLink: Hashable, Sendable {
    package let worktreeId: UUID
    package var contributions: [BridgeLinkContribution]

    package init(worktreeId: UUID, contributions: [BridgeLinkContribution]) {
        self.worktreeId = worktreeId
        self.contributions = contributions
    }
}

package struct BridgePullRequestLink: Hashable, Sendable {
    package let identity: ForgePullRequestIdentity
    package var contributions: [BridgeLinkContribution]

    package init(identity: ForgePullRequestIdentity, contributions: [BridgeLinkContribution]) {
        self.identity = identity
        self.contributions = contributions
    }
}

/// A lossless length-prefixed key avoids delimiter collisions in forge names.
package enum BridgePaneLinkItemKeyCodec {
    package static func member(_ worktreeId: UUID) -> String { "member:\(worktreeId.uuidString.lowercased())" }

    package static func decodeMember(_ key: String) throws -> UUID {
        guard key.hasPrefix("member:"), let id = UUID(uuidString: String(key.dropFirst(7))),
            member(id) == key
        else { throw BridgeLinkIdentityError.invalidEncoding }
        return id
    }

    package static func pullRequest(_ identity: ForgePullRequestIdentity) -> String {
        let fields = [identity.host, identity.owner, identity.repository, String(identity.number)]
        return "pr:" + fields.map { "\($0.utf8.count):\($0)" }.joined()
    }

    package static func decodePullRequest(_ key: String) throws -> ForgePullRequestIdentity {
        guard key.hasPrefix("pr:") else { throw BridgeLinkIdentityError.invalidEncoding }
        let bytes = Array(key.dropFirst(3).utf8)
        var position = 0
        var fields: [String] = []
        for _ in 0..<4 {
            let lengthStart = position
            while position < bytes.count, bytes[position] >= 48, bytes[position] <= 57 {
                position += 1
            }
            guard position > lengthStart, position < bytes.count, bytes[position] == 58,
                let lengthText = String(bytes: bytes[lengthStart..<position], encoding: .utf8),
                let length = Int(lengthText),
                length <= bytes.count - position - 1
            else { throw BridgeLinkIdentityError.invalidEncoding }
            position += 1
            guard let field = String(bytes: bytes[position..<(position + length)], encoding: .utf8) else {
                throw BridgeLinkIdentityError.invalidEncoding
            }
            fields.append(field)
            position += length
        }
        guard position == bytes.count, let number = Int(fields[3]) else {
            throw BridgeLinkIdentityError.invalidEncoding
        }
        let identity = try ForgePullRequestIdentity(
            host: fields[0], owner: fields[1], repository: fields[2], number: number
        )
        guard pullRequest(identity) == key else { throw BridgeLinkIdentityError.invalidEncoding }
        return identity
    }
}

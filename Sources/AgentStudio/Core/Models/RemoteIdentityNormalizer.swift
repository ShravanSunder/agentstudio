import Foundation

struct RemoteIdentityNormalizer {
    static func normalize(_ remoteURL: String) -> RepoIdentity? {
        guard let remoteSlug = extractSlug(remoteURL) else { return nil }
        let slugParts = remoteSlug.split(separator: "/", maxSplits: 1).map(String.init)

        let organizationName: String?
        let displayName: String
        if slugParts.count >= 2 {
            organizationName = slugParts[0]
            displayName = slugParts[1]
        } else {
            organizationName = nil
            displayName = remoteSlug
        }

        return RepoIdentity(
            groupKey: "remote:\(remoteSlug)",
            remoteSlug: remoteSlug,
            organizationName: organizationName,
            displayName: displayName
        )
    }

    static func extractSlug(_ remoteURL: String) -> String? {
        let normalized = remoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }

        let rawSlug: String?
        if normalized.hasPrefix("git@github.com:") {
            rawSlug = String(normalized.dropFirst("git@github.com:".count))
        } else if normalized.hasPrefix("ssh://git@github.com/") {
            rawSlug = String(normalized.dropFirst("ssh://git@github.com/".count))
        } else if normalized.hasPrefix("https://github.com/") {
            rawSlug = String(normalized.dropFirst("https://github.com/".count))
        } else if normalized.hasPrefix("http://github.com/") {
            rawSlug = String(normalized.dropFirst("http://github.com/".count))
        } else {
            rawSlug = nil
        }

        guard var trimmedSlug = rawSlug?.trimmingCharacters(in: CharacterSet(charactersIn: "/")) else {
            return nil
        }
        guard !trimmedSlug.isEmpty else { return nil }
        if trimmedSlug.hasSuffix(".git") {
            trimmedSlug = String(trimmedSlug.dropLast(4))
        }
        return trimmedSlug.isEmpty ? nil : trimmedSlug
    }

    static func localIdentity(repoName: String) -> RepoIdentity {
        RepoIdentity(
            groupKey: "local:\(repoName)",
            remoteSlug: nil,
            organizationName: nil,
            displayName: repoName
        )
    }
}

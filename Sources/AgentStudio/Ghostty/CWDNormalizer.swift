import Foundation

/// Pure normalization of raw PWD strings from Ghostty's OSC 7 into file URLs.
/// Ghostty's Zig layer validates the OSC 7 URI before reaching here,
/// but we apply defense-in-depth checks.
enum CWDNormalizer {
    /// Normalize a raw pwd string to a standardized file URL.
    /// - nil → nil
    /// - "" → nil
    /// - non-absolute path → nil (defense-in-depth)
    /// - "/path" → URL(fileURLWithPath:).standardizedFileURL
    static func normalize(_ rawPwd: String?) -> URL? {
        guard let pwd = rawPwd, !pwd.isEmpty else { return nil }
        guard pwd.hasPrefix("/") else { return nil }
        return URL(fileURLWithPath: pwd).standardizedFileURL
    }
}

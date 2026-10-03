import Foundation

/// A reported end always prevents automatic resume. Its reason is display
/// evidence only; the closed case is safe for telemetry, unlike provider text.
package enum ProviderEndReason: String, Codable, Equatable, Sendable {
    case personExit
    case providerOther
    case notGiven
    case unrecognized

    package static func parse(providerIdentifier: String, rawReason: String?) -> Self {
        guard let rawReason else { return .notGiven }
        switch (providerIdentifier, rawReason) {
        case ("claude-code", "prompt_input_exit"), ("codex", "exit"):
            return .personExit
        case ("claude-code", "clear"), ("claude-code", "logout"), ("claude-code", "other"), ("codex", "other"):
            return .providerOther
        default:
            return .unrecognized
        }
    }
}

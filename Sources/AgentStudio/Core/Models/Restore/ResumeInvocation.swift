import Foundation

// S3 RED stand-in: the closed provider vocabulary has no provider admission yet.
package enum ResumeProvider: Equatable, Sendable {
    case claudeCode, codex

    package init?(providerIdentifier: String) { nil }
}

// S3 RED stand-in: keep the input without validating its UUID shape.
package struct ProviderSessionId: Equatable, Hashable, Sendable {
    package let rawValue: String

    package init(rawValue: String) throws { self.rawValue = rawValue }
    fileprivate init(unvalidatedRawValue: String) { rawValue = unvalidatedRawValue }
}

// The agent-resume argv run before the fresh login shell's interactive handoff.
// S3 RED stand-in: typed invocations produce no command; the existing R1 argv oracle remains unchanged.
package struct ResumeInvocation: Equatable, Sendable {
    /// The command line the shell runs before the interactive handoff.
    package let argv: [String]
    package let provider: ResumeProvider
    package let sessionId: ProviderSessionId

    package init(provider: ResumeProvider, sessionId: ProviderSessionId) {
        self.provider = provider
        self.sessionId = sessionId
        argv = []
    }

    package init(argv: [String]) {
        self.argv = argv
        provider = .codex
        sessionId = ProviderSessionId(unvalidatedRawValue: argv.last ?? "")
    }
}

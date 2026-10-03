import Testing

@testable import AgentStudioCore

@Suite("Provider end reason")
struct ProviderEndReasonTests {
    @Test(
        "provider reasons parse into closed cases without guessing across providers",
        arguments: [
            ("claude-code", "prompt_input_exit", ProviderEndReason.personExit),
            ("claude-code", "clear", .providerOther),
            ("claude-code", "logout", .providerOther),
            ("claude-code", "other", .providerOther),
            ("codex", "exit", .personExit),
            ("codex", "other", .providerOther),
            ("claude-code", "exit", .unrecognized),
            ("codex", "prompt_input_exit", .unrecognized),
            ("codex", "future-provider-reason", .unrecognized),
            ("claude-code", "", .unrecognized),
        ]
    )
    func parsesProviderReason(
        providerIdentifier: String,
        rawReason: String,
        expected: ProviderEndReason
    ) {
        #expect(
            ProviderEndReason.parse(providerIdentifier: providerIdentifier, rawReason: rawReason)
                == expected
        )
    }

    @Test("a missing reason is notGiven for either provider", arguments: ["claude-code", "codex"])
    func missingReasonIsNotGiven(providerIdentifier: String) {
        #expect(ProviderEndReason.parse(providerIdentifier: providerIdentifier, rawReason: nil) == .notGiven)
    }
}

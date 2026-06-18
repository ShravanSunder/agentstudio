import Testing

@testable import AgentStudio

@Suite("InboxNotificationTextPolicy")
struct InboxNotificationTextPolicyTests {
    @Test("bounded text caps UTF-8 bytes for combining mark payloads")
    func boundedTextCapsUTF8BytesForCombiningMarkPayloads() {
        let title = "T" + String(repeating: "\u{0301}", count: AppPolicies.InboxNotification.maxTitleCharacters * 20)
        let body = "B" + String(repeating: "\u{0301}", count: AppPolicies.InboxNotification.maxBodyCharacters * 2)

        let boundedText = InboxNotificationTextPolicy.bounded(title: title, body: body)

        #expect(boundedText.title.utf8.count <= AppPolicies.InboxNotification.maxTitleCharacters)
        #expect(boundedText.body?.utf8.count ?? 0 <= AppPolicies.InboxNotification.maxBodyCharacters)
        #expect(boundedText.title.unicodeScalars.first == "T")
        #expect(boundedText.body?.unicodeScalars.first == "B")
    }

    @Test("approval summary does not persist raw request summary")
    func approvalSummaryDoesNotPersistRawRequestSummary() {
        let rawSummary = "Run sudo cat /Users/shravan/.ssh/id_rsa"

        let summary = InboxNotificationTextPolicy.approvalSummary(requestSummary: rawSummary)

        #expect(summary != rawSummary)
        #expect(summary.contains("/Users/shravan") == false)
        #expect(summary.contains("id_rsa") == false)
        #expect(summary == "Approval is required for a privileged action")
    }

    @Test("security summaries do not persist raw path secret or command")
    func securitySummariesDoNotPersistRawPathSecretOrCommand() {
        let filesystemSummary = InboxNotificationTextPolicy.securitySummary(
            kind: .filesystemAccessDenied(operation: "WRITE /Users/shravan/private.txt")
        )
        let secretSummary = InboxNotificationTextPolicy.securitySummary(kind: .secretAccessed)
        let processSummary = InboxNotificationTextPolicy.securitySummary(kind: .processSpawnBlocked)

        #expect(filesystemSummary == "Filesystem access was blocked by policy")
        #expect(filesystemSummary.contains("/Users/shravan") == false)
        #expect(secretSummary == "A secret access event was reported")
        #expect(processSummary == "Process launch was blocked by policy")
    }
}

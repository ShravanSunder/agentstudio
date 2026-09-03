import Testing

@testable import AgentStudioBridge

@Suite("Worktree annotation domain policy")
struct WorktreeAnnotationDomainPolicyTests {
    @Test("new durable identities are UUIDv7")
    func newDurableIdentitiesAreUUIDv7() {
        let identities = [
            WorktreeAnnotationSessionID.generate().rawValue,
            WorktreeAnnotationThreadID.generate().rawValue,
            WorktreeAnnotationMessageID.generate().rawValue,
            WorktreeAnnotationOutputAttemptID.generate().rawValue,
            WorktreeAnnotationOutputEventID.generate().rawValue,
        ]

        #expect(identities.allSatisfy { $0.uuidString.lowercased().split(separator: "-")[2].first == "7" })
    }

    @Test("message admission accepts ordinary Markdown and the exact UTF-8 limit")
    func messageAdmissionAcceptsOrdinaryMarkdownAndExactUTF8Limit() throws {
        let richMarkdown = """
            ## Review note

            - Keep the list
            - Keep **emphasis** and a [safe link](https://example.com/review)

            | input | result |
            | --- | --- |
            | `value` | accepted |

            ```html
            <h1>Code, not raw HTML</h1>
            ```
            """
        let exactLimit = String(repeating: "é", count: WorktreeAnnotationMessagePolicy.maximumBodyUTF8Bytes / 2)

        #expect(try WorktreeAnnotationMessagePolicy.validate(richMarkdown) == richMarkdown)
        #expect(try WorktreeAnnotationMessagePolicy.validate(exactLimit) == exactLimit)
    }

    @Test("message admission rejects bodies beyond the UTF-8 limit")
    func messageAdmissionRejectsBodiesBeyondUTF8Limit() {
        let oversized = String(repeating: "é", count: WorktreeAnnotationMessagePolicy.maximumBodyUTF8Bytes / 2 + 1)

        #expect(throws: WorktreeAnnotationMessagePolicyError.self) {
            try WorktreeAnnotationMessagePolicy.validate(oversized)
        }
    }

    @Test(arguments: [
        "# Level one",
        "Level one\n=========",
        "<script>alert('no')</script>",
        "[unsafe](javascript:alert(1))",
        "[relative](../other.md)",
    ])
    func messageAdmissionRejectsUnsafeMarkdown(body: String) {
        #expect(throws: WorktreeAnnotationMessagePolicyError.self) {
            try WorktreeAnnotationMessagePolicy.validate(body)
        }
    }

    @Test("H1 and HTML-looking text in inline code remain ordinary code")
    func markupInsideInlineCodeRemainsOrdinaryCode() throws {
        let body = "Use `# title` and `<section>` as literal values."

        #expect(try WorktreeAnnotationMessagePolicy.validate(body) == body)
    }
}

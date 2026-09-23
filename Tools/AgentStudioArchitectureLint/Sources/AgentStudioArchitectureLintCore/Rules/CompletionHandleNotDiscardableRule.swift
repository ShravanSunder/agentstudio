import SwiftSyntax

/// A function that returns a `Task` hands its caller the only proof that the
/// operation finished. Two shapes throw that proof away without anyone
/// deciding to:
///
/// - `@discardableResult` on a task-returning declaration lets every caller
///   drop the handle silently, so a synchronous caller can report success for
///   work that has not happened yet.
/// - `_ = f()` where `f` returns a task is an explicit discard. It is allowed
///   only when the call site says why no one needs the outcome, with a
///   `// fire-and-forget: <reason>` comment on the discard line or directly
///   above it.
///
/// Compile enforcement (`treatAllWarnings(as: .error)`) already rejects a bare,
/// unused non-discardable result; this rule covers what the compiler accepts.
///
/// Limits (syntax only, no type resolution): the explicit-discard predicate
/// resolves callees by base name against an index of task-returning function
/// declarations across every linted file. A base name that is also declared
/// anywhere with a non-task result (for example a second `submit` or a
/// `Void` `teardown`) is ambiguous and is not checked; the compiler still
/// rejects a bare discard of those. `_ = await …` is never flagged, because the
/// discarded value there is the awaited outcome, not the task.
struct CompletionHandleNotDiscardableRule: ArchitectureRule {
    let id = "agentstudio_completion_handle_not_discardable"
    let severity = ArchitectureSeverity.error
    let message = "A completion handle (Task) must not be discarded silently"

    static let discardableDeclarationMessage =
        "@discardableResult on a Task-returning declaration lets callers drop the completion handle; remove it and resolve each call site (await .value, store, or `_ = f() // fire-and-forget: <reason>`)"

    static let reasonlessDiscardMessage =
        "Discarding a Task-returning call needs `// fire-and-forget: <why no one needs the outcome>`; otherwise await .value or store the handle"

    static let fireAndForgetMarker = "// fire-and-forget:"

    private let taskReturningFunctionNames: Set<String>

    init() {
        self.init(taskReturningFunctionNames: [])
    }

    private init(taskReturningFunctionNames: Set<String>) {
        self.taskReturningFunctionNames = taskReturningFunctionNames
    }

    func prepared(for contexts: [ArchitectureLintContext]) -> any ArchitectureRule {
        let collector = FunctionResultKindCollector()
        for context in contexts {
            collector.walk(context.sourceFile)
        }
        return Self(
            taskReturningFunctionNames: collector.taskReturningNames.subtracting(collector.otherResultNames)
        )
    }

    func validate(context: ArchitectureLintContext) -> [ArchitectureDiagnostic] {
        let visitor = CompletionHandleDiscardVisitor(taskReturningFunctionNames: taskReturningFunctionNames)
        visitor.walk(context.sourceFile)
        return visitor.violations.map {
            diagnostic(context: context, position: $0.position, message: $0.message)
        }
    }

    fileprivate static func hasFireAndForgetReason(
        discardToken: TokenSyntax,
        lastToken: TokenSyntax?
    ) -> Bool {
        let trailingComments = lastToken?.lineCommentsThroughEndOfLine ?? []
        let leadingComments = discardToken.leadingTrivia.lineCommentDirectlyAbove.map { [$0] } ?? []
        return (trailingComments + leadingComments).contains { comment in
            comment.hasPrefix(fireAndForgetMarker)
                && !comment.dropFirst(fireAndForgetMarker.count).allSatisfy(\.isWhitespace)
        }
    }
}

/// Indexes function base names by whether any declaration returns a task.
private final class FunctionResultKindCollector: SyntaxVisitor {
    private(set) var taskReturningNames: Set<String> = []
    private(set) var otherResultNames: Set<String> = []

    init() {
        super.init(viewMode: .sourceAccurate)
    }

    override func visitPost(_ node: FunctionDeclSyntax) {
        let name = node.name.text
        if node.signature.returnClause?.type.isTaskResultType == true {
            taskReturningNames.insert(name)
        } else {
            otherResultNames.insert(name)
        }
    }
}

private final class CompletionHandleDiscardVisitor: SyntaxVisitor {
    private(set) var violations: [ArchitectureViolation] = []
    private let taskReturningFunctionNames: Set<String>

    init(taskReturningFunctionNames: Set<String>) {
        self.taskReturningFunctionNames = taskReturningFunctionNames
        super.init(viewMode: .sourceAccurate)
    }

    override func visitPost(_ node: FunctionDeclSyntax) {
        guard node.signature.returnClause?.type.isTaskResultType == true,
            let attribute = node.attributes.discardableResultAttribute
        else {
            return
        }
        violations.append(
            ArchitectureViolation(
                position: attribute.positionAfterSkippingLeadingTrivia,
                message: CompletionHandleNotDiscardableRule.discardableDeclarationMessage
            )
        )
    }

    override func visitPost(_ node: SequenceExprSyntax) {
        let elements = Array(node.elements)
        guard elements.count == 3,
            let discard = elements[0].as(DiscardAssignmentExprSyntax.self),
            elements[1].is(AssignmentExprSyntax.self),
            let call = elements[2].as(FunctionCallExprSyntax.self),
            let calleeName = call.calledExpression.directCalleeBaseName,
            taskReturningFunctionNames.contains(calleeName)
        else {
            return
        }
        guard
            !CompletionHandleNotDiscardableRule.hasFireAndForgetReason(
                discardToken: discard.wildcard,
                lastToken: node.lastToken(viewMode: .sourceAccurate)
            )
        else {
            return
        }
        violations.append(
            ArchitectureViolation(
                position: node.positionAfterSkippingLeadingTrivia,
                message: CompletionHandleNotDiscardableRule.reasonlessDiscardMessage
            )
        )
    }
}

extension ExprSyntax {
    /// The base name of a direct call's callee: `f(...)`, `x.f(...)`,
    /// `x?.f(...)`, or `f { ... }`. `nil` for any other callee shape.
    fileprivate var directCalleeBaseName: String? {
        if let reference = self.as(DeclReferenceExprSyntax.self) {
            return reference.baseName.text
        }
        if let memberAccess = self.as(MemberAccessExprSyntax.self), memberAccess.base != nil {
            return memberAccess.declName.baseName.text
        }
        return nil
    }
}

extension TypeSyntax {
    /// `Task<…>`, `Swift.Task<…>`, `_Concurrency.Task<…>`, or any of those
    /// wrapped in `?`.
    fileprivate var isTaskResultType: Bool {
        if let optional = self.as(OptionalTypeSyntax.self) {
            return optional.wrappedType.isTaskResultType
        }
        if let identifier = self.as(IdentifierTypeSyntax.self) {
            return identifier.name.text == "Task"
        }
        if let member = self.as(MemberTypeSyntax.self) {
            let moduleName = member.baseType.as(IdentifierTypeSyntax.self)?.name.text
            return member.name.text == "Task" && (moduleName == "Swift" || moduleName == "_Concurrency")
        }
        return false
    }
}

extension TokenSyntax {
    /// Line comments trailing this token or any later token on the same line,
    /// so `defer { _ = f() }  // fire-and-forget: …` carries its reason.
    fileprivate var lineCommentsThroughEndOfLine: [String] {
        var comments: [String] = []
        var token: TokenSyntax? = self
        while let current = token {
            comments.append(contentsOf: current.trailingTrivia.lineComments)
            guard let next = current.nextToken(viewMode: .sourceAccurate),
                !next.leadingTrivia.contains(where: \.isNewline)
            else {
                break
            }
            token = next
        }
        return comments
    }
}

extension AttributeListSyntax {
    fileprivate var discardableResultAttribute: AttributeSyntax? {
        for element in self {
            if let attribute = element.as(AttributeSyntax.self),
                attribute.attributeName.trimmedDescription == "discardableResult"
            {
                return attribute
            }
        }
        return nil
    }
}

extension Trivia {
    fileprivate var lineComments: [String] {
        compactMap { piece in
            if case .lineComment(let text) = piece {
                return text
            }
            return nil
        }
    }

    /// The line comment on the line directly above the token, if the only
    /// thing between them is one line break and indentation.
    fileprivate var lineCommentDirectlyAbove: String? {
        var sawSingleLineBreak = false
        for piece in reversed() {
            switch piece {
            case .spaces, .tabs:
                continue
            case .newlines(1), .carriageReturnLineFeeds(1):
                guard !sawSingleLineBreak else { return nil }
                sawSingleLineBreak = true
            case .lineComment(let text):
                return sawSingleLineBreak ? text : nil
            default:
                return nil
            }
        }
        return nil
    }
}

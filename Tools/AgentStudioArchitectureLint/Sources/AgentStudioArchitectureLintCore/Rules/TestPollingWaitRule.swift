import SwiftSyntax

/// A polling wait is a loop that repeats around a scheduler yield, a sleep, or a
/// clock deadline until a condition holds. Its verdict is a function of how fast
/// the machine is: the same loop that clears in three turns on a sixteen-core
/// developer Mac can still be in flight when the budget expires on a three-core
/// runner, where the cooperative pool has three threads and the work the loop is
/// waiting for is queued behind the loop itself.
///
/// The shape is what makes it wrong, not the helper's name, so this rule matches
/// the shape: a `while`, `for`, or `repeat` whose own condition or body contains
/// a yield, a `sleep` call, or a wall-clock read. `for await` over a stream is
/// not a poll — it suspends on delivery — and a loop with none of those signals
/// is just a loop.
///
/// The permitted forms are in
/// `docs/architecture/testing/testing_architecture.md#how-a-test-may-wait`.
struct TestPollingWaitRule: ArchitectureRule {
    let id = "agentstudio_no_polling_wait_in_tests"
    let severity = ArchitectureSeverity.error
    let message =
        "Polling wait: a loop around a yield, sleep, or clock deadline decides a test by machine speed"

    static let staleBaselineMessage =
        "File no longer polls; remove it from ArchitectureAllowlists.pollingWaitKnownDebt (baseline is shrink-only)"

    /// What the rule does with a file once its loops have been inspected.
    ///
    /// Split out as a pure function because the baseline is a compile-time
    /// constant: this is the seam where the shrink-only behaviour is provable
    /// without injecting an allowlist.
    enum Outcome: Equatable {
        /// Not baselined, nothing found.
        case clean
        /// Not baselined, and these loops poll.
        case report([ArchitectureViolation])
        /// Baselined and still polling: known debt, no diagnostic.
        case suppressedByBaseline
        /// Baselined but no longer polling: the entry must go.
        case staleBaselineEntry
    }

    static func pollingWaitOutcome(
        violations: [ArchitectureViolation],
        isBaselined: Bool
    ) -> Outcome {
        guard isBaselined else {
            return violations.isEmpty ? .clean : .report(violations)
        }
        return violations.isEmpty ? .staleBaselineEntry : .suppressedByBaseline
    }

    func validate(context: ArchitectureLintContext) -> [ArchitectureDiagnostic] {
        guard let targetPath = Self.targetPath(for: context),
            targetPath.contains("/Tests/"), targetPath.hasSuffix(".swift")
        else {
            return []
        }

        let visitor = TestPollingWaitVisitor()
        visitor.walk(context.sourceFile)
        let isBaselined = ArchitectureAllowlists.pollingWaitKnownDebt.contains(where: targetPath.hasSuffix)

        switch Self.pollingWaitOutcome(violations: visitor.violations, isBaselined: isBaselined) {
        case .clean, .suppressedByBaseline:
            return []
        case .report(let violations):
            return violations.map {
                diagnostic(context: context, position: $0.position, message: $0.message)
            }
        case .staleBaselineEntry:
            return [
                diagnostic(
                    context: context,
                    position: AbsolutePosition(utf8Offset: 0),
                    message: Self.staleBaselineMessage
                )
            ]
        }
    }

    private static func targetPath(for context: ArchitectureLintContext) -> String? {
        let normalizedPath = context.normalizedPath
        let pathForFixtureMatching = normalizedPath.hasPrefix("/") ? normalizedPath : "/\(normalizedPath)"
        for marker in ["/Fixtures/Bad/", "/Fixtures/Good/"] {
            if let range = pathForFixtureMatching.range(of: marker) {
                return "/\(pathForFixtureMatching[range.upperBound...])"
            }
        }
        guard let relativePath = context.workspaceRelativePath else {
            return nil
        }
        return relativePath.hasPrefix("/") ? relativePath : "/\(relativePath)"
    }
}

/// Finds loops that own a polling signal at their own nesting level.
///
/// Nested loops are each judged on their own: the signal search stops at a
/// nested loop, so an outer `for` over panes is not blamed for the inner `while`
/// that actually polls, and the inner loop still gets its own diagnostic.
private final class TestPollingWaitVisitor: SyntaxVisitor {
    private(set) var violations: [ArchitectureViolation] = []

    override init(viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(viewMode: viewMode)
    }

    override func visit(_ node: WhileStmtSyntax) -> SyntaxVisitorContinueKind {
        // A `while` repeats until its condition holds, so any of the three
        // signals anywhere inside it is the wait.
        recordIfPolling(
            keyword: node.whileKeyword,
            signals: PollingSignalVisitor.signals(in: [Syntax(node.conditions), Syntax(node.body)])
        )
        return .visitChildren
    }

    override func visit(_ node: ForStmtSyntax) -> SyntaxVisitorContinueKind {
        // `for await` suspends until the stream delivers; that is the permitted
        // form, not a poll.
        guard node.awaitKeyword == nil else {
            return .visitChildren
        }
        // A `for` already ends on its own. It is a wait only when the body
        // yields or sleeps each turn, or when its own control expressions read
        // a clock — a `for` body that stamps a fixture with `ContinuousClock().now`
        // is building data, not waiting.
        var controlExpressions: [Syntax] = [Syntax(node.sequence)]
        if let whereClause = node.whereClause {
            controlExpressions.append(Syntax(whereClause))
        }
        var signals = PollingSignalVisitor.signals(in: controlExpressions)
        signals.formUnion(
            PollingSignalVisitor.signals(in: [Syntax(node.body)]).subtracting([.clockRead])
        )
        recordIfPolling(keyword: node.forKeyword, signals: signals)
        return .visitChildren
    }

    override func visit(_ node: RepeatStmtSyntax) -> SyntaxVisitorContinueKind {
        recordIfPolling(
            keyword: node.repeatKeyword,
            signals: PollingSignalVisitor.signals(in: [Syntax(node.body), Syntax(node.condition)])
        )
        return .visitChildren
    }

    private func recordIfPolling(keyword: TokenSyntax, signals: Set<PollingSignal>) {
        guard !signals.isEmpty else {
            return
        }
        violations.append(
            ArchitectureViolation(
                position: keyword.positionAfterSkippingLeadingTrivia,
                message:
                    "Polling wait: a loop around a yield, sleep, or clock deadline decides a test by "
                    + "machine speed. Await the event, state, or quiescence seam instead — "
                    + "docs/architecture/testing/testing_architecture.md#how-a-test-may-wait"
            )
        )
    }
}

private enum PollingSignal {
    case yield
    case sleep
    case clockRead
}

/// Collects the polling signals present in the searched syntax, without
/// descending into a nested loop — each loop is judged on what it owns itself.
private final class PollingSignalVisitor: SyntaxVisitor {
    private(set) var signals: Set<PollingSignal> = []

    static func signals(in searched: [Syntax]) -> Set<PollingSignal> {
        var found: Set<PollingSignal> = []
        for syntax in searched {
            let visitor = PollingSignalVisitor()
            visitor.walk(syntax)
            found.formUnion(visitor.signals)
        }
        return found
    }

    override init(viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(viewMode: viewMode)
    }

    override func visit(_ node: WhileStmtSyntax) -> SyntaxVisitorContinueKind { .skipChildren }
    override func visit(_ node: ForStmtSyntax) -> SyntaxVisitorContinueKind { .skipChildren }
    override func visit(_ node: RepeatStmtSyntax) -> SyntaxVisitorContinueKind { .skipChildren }

    override func visitPost(_ node: FunctionCallExprSyntax) {
        if let memberAccess = node.calledExpression.as(MemberAccessExprSyntax.self) {
            let calleeName = memberAccess.declName.baseName.text
            if calleeName == "sleep" {
                signals.insert(.sleep)
                return
            }
            if calleeName == "yield", memberAccess.base?.isTaskTypeReference == true {
                signals.insert(.yield)
                return
            }
            return
        }
        guard let reference = node.calledExpression.as(DeclReferenceExprSyntax.self) else {
            return
        }
        if reference.baseName.text == "sleep" || reference.baseName.text == "usleep" {
            signals.insert(.sleep)
            return
        }
        if reference.baseName.text == "CFAbsoluteTimeGetCurrent" {
            signals.insert(.clockRead)
            return
        }
        // Bare `Date()` reads the wall clock. `Date(timeIntervalSince1970:)` and
        // every other argument form builds a fixed instant, which is a fixture
        // value, not a deadline.
        if reference.baseName.text == "Date", node.arguments.isEmpty, node.trailingClosure == nil {
            signals.insert(.clockRead)
        }
    }

    override func visitPost(_ node: MemberAccessExprSyntax) {
        if node.declName.baseName.text == "systemUptime" {
            signals.insert(.clockRead)
            return
        }
        guard node.declName.baseName.text == "now", node.base?.namesAClock == true else {
            return
        }
        signals.insert(.clockRead)
    }
}

extension ExprSyntax {
    /// The expression names something a wall-clock instant can be read from:
    /// a concrete clock type, `DispatchTime`, or a binding whose name says clock.
    fileprivate var namesAClock: Bool {
        if let reference = self.as(DeclReferenceExprSyntax.self) {
            let name = reference.baseName.text
            return name == "ContinuousClock" || name == "SuspendingClock" || name == "DispatchTime"
                || name.localizedCaseInsensitiveContains("clock")
        }
        if let call = self.as(FunctionCallExprSyntax.self) {
            return call.calledExpression.namesAClock
        }
        if let memberAccess = self.as(MemberAccessExprSyntax.self) {
            return memberAccess.declName.baseName.text.localizedCaseInsensitiveContains("clock")
                || memberAccess.base?.namesAClock == true
        }
        return false
    }
}

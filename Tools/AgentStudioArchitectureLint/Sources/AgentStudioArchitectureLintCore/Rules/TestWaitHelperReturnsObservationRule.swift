import SwiftSyntax

/// A wait helper returns what satisfied it, so the test asserts on the read
/// the wait matched rather than on a second read that may already see a
/// later state. A helper that returns nothing invites exactly that second
/// read.
///
/// Shape: in `Tests/`, outside the harness, an `async` function named
/// `wait…`, `require…`, `await…`, `waitUntil…` or `expect…Eventually` with no
/// return type. `@Test` functions are not helpers. Existing helpers are frozen
/// per file in the debt ledger.
struct TestWaitHelperReturnsObservationRule: ArchitectureRule {
    let id = "agentstudio_test_wait_helper_returns_observation"
    let severity = ArchitectureSeverity.error
    let message =
        "Wait helpers return the observed value that satisfied them; assert on that value, not on a later read"

    func validate(context: ArchitectureLintContext) -> [ArchitectureDiagnostic] {
        guard context.isTestSourceOutsideHarness else {
            return []
        }
        let visitor = VoidWaitHelperVisitor()
        visitor.walk(context.sourceFile)
        return visitor.positions.map { diagnostic(context: context, position: $0) }
    }

    static func isWaitHelperName(_ name: String) -> Bool {
        if name.hasPrefix("expect"), name.hasSuffix("Eventually") {
            return true
        }
        return ["wait", "require", "await"].contains { prefix in
            guard name.hasPrefix(prefix) else {
                return false
            }
            let rest = name.dropFirst(prefix.count)
            return rest.isEmpty || rest.first?.isUppercase == true
        }
    }
}

private final class VoidWaitHelperVisitor: SyntaxVisitor {
    private(set) var positions: [AbsolutePosition] = []

    init() {
        super.init(viewMode: .sourceAccurate)
    }

    override func visitPost(_ node: FunctionDeclSyntax) {
        guard node.signature.effectSpecifiers?.asyncSpecifier != nil,
            node.signature.returnClause == nil,
            TestWaitHelperReturnsObservationRule.isWaitHelperName(node.name.text),
            !node.attributes.contains(where: { $0.trimmedDescription.hasPrefix("@Test") })
        else {
            return
        }
        positions.append(node.name.positionAfterSkippingLeadingTrivia)
    }
}

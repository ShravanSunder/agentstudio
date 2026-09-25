import SwiftSyntax

/// A test that holds work at a step does it with the shared harness's
/// `HeldStep` (`Tests/AgentStudioTestHarness/`), whose release, failure,
/// retirement and cancellation are reviewed once. A hand-written gate type is
/// a private copy of that mechanism: 15 of today's relay their resume through
/// a detached task, and duplicates drift apart.
///
/// Shape: in `Tests/`, outside the harness, a type named `*Gate`, `*Latch`,
/// `*Barrier`, `*Blocker` or `*Hold` that stores (itself or in a nested type)
/// a continuation, a collection of them, a `DispatchSemaphore` or an
/// `NSCondition`. Existing gates are frozen per file in the debt ledger and
/// migrate onto `HeldStep`.
struct TestAdHocGateRule: ArchitectureRule {
    static let gateNameSuffixes = ["Gate", "Latch", "Barrier", "Blocker", "Hold"]

    let id = "agentstudio_test_ad_hoc_gate"
    let severity = ArchitectureSeverity.error
    let message =
        "Ad-hoc test gate: hold work with HeldStep from AgentStudioTestHarness instead of a private "
        + "continuation, semaphore or condition"

    func validate(context: ArchitectureLintContext) -> [ArchitectureDiagnostic] {
        guard context.isTestSourceOutsideHarness else {
            return []
        }
        let visitor = AdHocGateVisitor()
        visitor.walk(context.sourceFile)
        return visitor.positions.map { diagnostic(context: context, position: $0) }
    }
}

private final class AdHocGateVisitor: SyntaxVisitor {
    private(set) var positions: [AbsolutePosition] = []

    init() {
        super.init(viewMode: .sourceAccurate)
    }

    override func visitPost(_ node: ClassDeclSyntax) {
        record(name: node.name, members: node.memberBlock)
    }

    override func visitPost(_ node: StructDeclSyntax) {
        record(name: node.name, members: node.memberBlock)
    }

    override func visitPost(_ node: ActorDeclSyntax) {
        record(name: node.name, members: node.memberBlock)
    }

    override func visitPost(_ node: EnumDeclSyntax) {
        record(name: node.name, members: node.memberBlock)
    }

    private func record(name: TokenSyntax, members: MemberBlockSyntax) {
        guard TestAdHocGateRule.gateNameSuffixes.contains(where: name.text.hasSuffix) else {
            return
        }
        let storage = SuspensionStorageVisitor()
        storage.walk(members)
        if storage.storesSuspension {
            positions.append(name.positionAfterSkippingLeadingTrivia)
        }
    }
}

/// Stored properties (with no accessor block) whose declared type or
/// initializer names a continuation, `DispatchSemaphore` or `NSCondition`.
private final class SuspensionStorageVisitor: SyntaxVisitor {
    private(set) var storesSuspension = false

    init() {
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind { .skipChildren }
    override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind { .skipChildren }

    override func visitPost(_ node: PatternBindingSyntax) {
        guard node.accessorBlock == nil else {
            return
        }
        let declared = [
            node.typeAnnotation?.type.trimmedDescription,
            node.initializer?.value.trimmedDescription,
        ]
        .compactMap { $0 }
        if declared.contains(where: Self.namesSuspensionStorage) {
            storesSuspension = true
        }
    }

    private static func namesSuspensionStorage(_ text: String) -> Bool {
        text.contains("Continuation") || text.contains("DispatchSemaphore") || text.contains("NSCondition")
    }
}

extension ArchitectureLintContext {
    /// A test source that is not the shared causal-test harness, which owns
    /// the one sanctioned hold and wait mechanism.
    var isTestSourceOutsideHarness: Bool {
        let path = "/\(normalizedPath)"
        return path.contains("/Tests/") && !path.contains("/Tests/AgentStudioTestHarness/")
            && path.hasSuffix(".swift")
    }
}

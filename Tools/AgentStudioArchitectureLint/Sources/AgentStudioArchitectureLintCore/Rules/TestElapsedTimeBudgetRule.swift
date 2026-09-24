import Foundation
import SwiftSyntax

/// A test's verdict is a function of program logic, never of machine speed. The
/// only elapsed-time bound a test may carry is the runner-owned lane hang bound.
///
/// A per-test timeout picked on a sixteen-core developer Mac expires on a
/// three-core CI runner while the awaited work is still correct and in flight:
/// script runs under `DefaultProcessExecutor(timeout: 10)`, a strict-startup
/// subprocess behind `semaphore.wait(timeout: .now() + 20)`, and a launcher
/// fixture behind `waitForFile(timeoutSeconds: 5)` each failed pull requests
/// that way. This rule matches those shapes in `Tests/`:
///
/// - any `DefaultProcessExecutor(...)` construction, because the executor always
///   carries a timeout (15 seconds when none is passed); tests run subprocesses
///   through `runCommandToExit` or `runProcessToExit` in `AgentStudioTestSupport`,
///   or inject the `RunToExitProcessExecutor` adapter built on them;
/// - `.wait(timeout:)` and `.wait(wallTimeout:)` on a name bound to a
///   `DispatchSemaphore` or `DispatchGroup` in the file (an initializer, a type
///   annotation, or a parameter type), or on a direct construction;
/// - `asyncAfter(...)`, which in a test is always a real-time deadline or delay;
/// - a `timeout:` or `timeoutSeconds:` argument to a named file-wait helper.
///
/// Files that own a budget on purpose are named in
/// `ArchitectureAllowlists.elapsedTimeBudgetOwners`; remaining sites are frozen
/// per file in the debt ledger. The permitted forms are in
/// `docs/architecture/testing/testing_architecture.md#how-a-test-may-wait`.
struct TestElapsedTimeBudgetRule: ArchitectureRule {
    let id = "agentstudio_no_test_elapsed_time_budget"
    let severity = ArchitectureSeverity.error
    let message =
        "Per-test elapsed-time budget: a timeout decides the test by machine speed; the lane hang bound is the "
        + "only permitted bound"

    private let owners: [ElapsedTimeBudgetOwner]
    private let ownerProblems: [ArchitectureDiagnostic]

    init(owners: [ElapsedTimeBudgetOwner] = ArchitectureAllowlists.elapsedTimeBudgetOwners) {
        self.owners = owners
        self.ownerProblems = []
    }

    private init(owners: [ElapsedTimeBudgetOwner], ownerProblems: [ArchitectureDiagnostic]) {
        self.owners = owners
        self.ownerProblems = ownerProblems
    }

    /// Owner paths are repository paths, so they are checked when the corpus
    /// is the repository (its root holds this lint tool), not a fixture tree.
    func prepared(for contexts: [ArchitectureLintContext]) -> any ArchitectureRule {
        guard let rootPath = contexts.first?.workspaceRootPath,
            FileManager.default.fileExists(atPath: "\(rootPath)/Tools/AgentStudioArchitectureLint/Package.swift")
        else {
            return self
        }
        return Self(owners: owners, ownerProblems: ownerProblems(for: contexts))
    }

    func configurationDiagnostics() -> [ArchitectureDiagnostic] {
        ownerProblems
    }

    /// An owner whose file is not in the corpus is gone; an owner whose file no
    /// longer carries a budget no longer needs to be one.
    func ownerProblems(for contexts: [ArchitectureLintContext]) -> [ArchitectureDiagnostic] {
        var contextsByRelativePath: [String: ArchitectureLintContext] = [:]
        for context in contexts {
            if let relativePath = context.workspaceRelativePath {
                contextsByRelativePath[relativePath] = context
            }
        }
        return owners.compactMap { owner in
            guard let context = contextsByRelativePath[owner.path] else {
                return ArchitectureDiagnostic(
                    path: owner.path,
                    line: 1,
                    column: 1,
                    severity: severity,
                    ruleID: id,
                    message:
                        "Elapsed-time budget owner \(owner.path) (\(owner.owner)) no longer exists; remove it from "
                        + "ArchitectureAllowlists.elapsedTimeBudgetOwners"
                )
            }
            guard Self.budgets(in: context).isEmpty else {
                return nil
            }
            return ArchitectureDiagnostic(
                path: context.path,
                line: 1,
                column: 1,
                severity: severity,
                ruleID: id,
                message:
                    "Elapsed-time budget owner (\(owner.owner)) no longer carries a budget; remove it from "
                    + "ArchitectureAllowlists.elapsedTimeBudgetOwners"
            )
        }
    }

    func validate(context: ArchitectureLintContext) -> [ArchitectureDiagnostic] {
        guard let targetPath = Self.targetPath(for: context),
            targetPath.contains("/Tests/"), targetPath.hasSuffix(".swift"),
            !owners.contains(where: { targetPath.hasSuffix("/\($0.path)") })
        else {
            return []
        }
        return Self.budgets(in: context).map {
            diagnostic(context: context, position: $0.position, message: $0.message)
        }
    }

    private static func budgets(in context: ArchitectureLintContext) -> [ArchitectureViolation] {
        let visitor = ElapsedTimeBudgetVisitor(
            dispatchWaitableNames: DispatchWaitableBindingCollector.names(in: context.sourceFile)
        )
        visitor.walk(context.sourceFile)
        return visitor.violations
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

private enum DispatchWaitableType {
    static let names: Set<String> = ["DispatchSemaphore", "DispatchGroup"]
}

/// Names bound to a `DispatchSemaphore` or `DispatchGroup` in this file: by an
/// initializer, a type annotation, or a function or closure parameter type.
/// A syntactic rule cannot resolve types, so a `wait(timeout:)` on any other
/// receiver is left alone.
private enum DispatchWaitableBindingCollector {
    static func names(in sourceFile: SourceFileSyntax) -> Set<String> {
        let collector = DispatchWaitableBindingVisitor()
        collector.walk(sourceFile)
        return collector.names
    }
}

private final class DispatchWaitableBindingVisitor: SyntaxVisitor {
    private(set) var names: Set<String> = []

    init() {
        super.init(viewMode: .sourceAccurate)
    }

    override func visitPost(_ node: PatternBindingSyntax) {
        guard let identifier = node.pattern.as(IdentifierPatternSyntax.self)?.identifier.text else {
            return
        }
        if node.initializer?.value.isDispatchWaitableConstruction == true
            || node.typeAnnotation?.type.namesDispatchWaitable == true
        {
            names.insert(identifier)
        }
    }

    override func visitPost(_ node: FunctionParameterSyntax) {
        let localName = node.secondName?.text ?? node.firstName.text
        if localName != "_", node.type.namesDispatchWaitable {
            names.insert(localName)
        }
    }

    override func visitPost(_ node: ClosureParameterSyntax) {
        let localName = node.secondName?.text ?? node.firstName.text
        if localName != "_", node.type?.namesDispatchWaitable == true {
            names.insert(localName)
        }
    }
}

private final class ElapsedTimeBudgetVisitor: SyntaxVisitor {
    private static let deadlineWaitLabels: Set<String> = ["timeout", "wallTimeout"]
    private static let fileWaitHelperNames: Set<String> = ["waitForFile"]
    private static let fileWaitBudgetLabels: Set<String> = ["timeout", "timeoutSeconds"]

    private let dispatchWaitableNames: Set<String>
    private(set) var violations: [ArchitectureViolation] = []

    init(dispatchWaitableNames: Set<String>) {
        self.dispatchWaitableNames = dispatchWaitableNames
        super.init(viewMode: .sourceAccurate)
    }

    override func visitPost(_ node: FunctionCallExprSyntax) {
        if let reference = node.calledExpression.as(DeclReferenceExprSyntax.self) {
            recordProcessExecutor(named: reference.baseName.text, node: node)
            recordFileWaitBudget(named: reference.baseName.text, node: node)
            return
        }
        guard let memberAccess = node.calledExpression.as(MemberAccessExprSyntax.self) else {
            return
        }
        let calleeName = memberAccess.declName.baseName.text
        recordProcessExecutor(named: calleeName, node: node)
        recordFileWaitBudget(named: calleeName, node: node)
        if calleeName == "asyncAfter" {
            record(
                memberAccess,
                message:
                    "asyncAfter in a test waits on the wall clock. Await the event or state instead, or drive "
                    + "time through TestPushClock — docs/architecture/testing/testing_architecture.md#how-a-test-may-wait"
            )
            return
        }
        guard calleeName == "wait",
            let label = node.arguments.first?.label?.text,
            Self.deadlineWaitLabels.contains(label),
            let receiver = memberAccess.base,
            receiver.isDispatchWaitableConstruction || isDispatchWaitableBinding(receiver)
        else {
            return
        }
        record(
            memberAccess,
            message:
                "wait(\(label):) fails a correct test whenever the awaited work runs late. Wait untimed off the "
                + "cooperative pool, or await the owner's event — "
                + "docs/architecture/testing/testing_architecture.md#how-a-test-may-wait"
        )
    }

    private func recordProcessExecutor(named calleeName: String, node: FunctionCallExprSyntax) {
        guard calleeName == "DefaultProcessExecutor" else {
            return
        }
        record(
            node.calledExpression,
            message:
                "DefaultProcessExecutor always carries a per-call timeout (15 s by default). Run test subprocesses "
                + "with runCommandToExit or runProcessToExit (AgentStudioTestSupport), or inject "
                + "RunToExitProcessExecutor; they wait for exit with no budget"
        )
    }

    private func recordFileWaitBudget(named calleeName: String, node: FunctionCallExprSyntax) {
        guard Self.fileWaitHelperNames.contains(calleeName),
            let budgetArgument = node.arguments.first(where: {
                $0.label.map { Self.fileWaitBudgetLabels.contains($0.text) } ?? false
            })
        else {
            return
        }
        record(
            budgetArgument,
            message:
                "\(calleeName) with a time budget fails a correct test whenever the file is written late. Wait for "
                + "the filesystem event with no deadline"
        )
    }

    /// `semaphore` or `self.semaphore`, where the name is a Dispatch waitable binding.
    private func isDispatchWaitableBinding(_ receiver: ExprSyntax) -> Bool {
        if let reference = receiver.as(DeclReferenceExprSyntax.self) {
            return dispatchWaitableNames.contains(reference.baseName.text)
        }
        if let member = receiver.as(MemberAccessExprSyntax.self),
            member.base?.as(DeclReferenceExprSyntax.self)?.baseName.text == "self"
        {
            return dispatchWaitableNames.contains(member.declName.baseName.text)
        }
        return false
    }

    private func record(_ syntax: some SyntaxProtocol, message: String) {
        violations.append(
            ArchitectureViolation(position: syntax.positionAfterSkippingLeadingTrivia, message: message)
        )
    }
}

extension ExprSyntax {
    /// `DispatchSemaphore(value: 0)` or `DispatchGroup()`, optionally module-qualified.
    fileprivate var isDispatchWaitableConstruction: Bool {
        guard let call = self.as(FunctionCallExprSyntax.self) else {
            return false
        }
        if let reference = call.calledExpression.as(DeclReferenceExprSyntax.self) {
            return DispatchWaitableType.names.contains(reference.baseName.text)
        }
        if let memberAccess = call.calledExpression.as(MemberAccessExprSyntax.self) {
            return DispatchWaitableType.names.contains(memberAccess.declName.baseName.text)
        }
        return false
    }
}

extension TypeSyntax {
    /// `DispatchSemaphore`, `DispatchGroup`, `Dispatch.DispatchSemaphore`, or an
    /// optional of one.
    fileprivate var namesDispatchWaitable: Bool {
        if let identifier = self.as(IdentifierTypeSyntax.self) {
            return DispatchWaitableType.names.contains(identifier.name.text)
        }
        if let member = self.as(MemberTypeSyntax.self) {
            return DispatchWaitableType.names.contains(member.name.text)
        }
        if let optional = self.as(OptionalTypeSyntax.self) {
            return optional.wrappedType.namesDispatchWaitable
        }
        if let unwrapped = self.as(ImplicitlyUnwrappedOptionalTypeSyntax.self) {
            return unwrapped.wrappedType.namesDispatchWaitable
        }
        return false
    }
}

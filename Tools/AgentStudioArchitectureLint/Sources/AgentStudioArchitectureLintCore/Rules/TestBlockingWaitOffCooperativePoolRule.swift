import SwiftSyntax

/// Swift Testing runs each test body as a task on the cooperative executor,
/// whose width is the machine's core count, and `AgentStudioAppIPCServer`
/// answers every accepted connection from a `Task` on that same pool. A test
/// that parks a cooperative thread in a socket read, a semaphore wait, or a
/// process wait is starving work on that same pool: on a three-core CI runner
/// three blocking tests at once deadlocked the whole fast lane, with no failure
/// message, only a ten-minute silence.
///
/// The blocking primitives are allowed in the few support files that own them
/// and document where the block lands. Everywhere else in `Tests/` the wait
/// goes through `withoutBlockingCooperativePool` or one of the
/// `WithoutBlockingMainActor` helpers built on the same hop.
struct TestBlockingWaitOffCooperativePoolRule: ArchitectureRule {
    let id = "agentstudio_test_blocking_wait_off_cooperative_pool"
    let severity = ArchitectureSeverity.error
    let message = "Blocking waits in tests must run off the cooperative pool"

    func validate(context: ArchitectureLintContext) -> [ArchitectureDiagnostic] {
        guard let targetPath = Self.targetPath(for: context),
            targetPath.contains("/Tests/"), targetPath.hasSuffix(".swift"),
            !ArchitectureAllowlists.blockingTestWaitAllowedPathSuffixes.contains(where: targetPath.hasSuffix)
        else {
            return []
        }

        let semaphoreNames = DispatchSemaphoreBindingCollector.names(in: context.sourceFile)
        let visitor = TestBlockingWaitVisitor(semaphoreNames: semaphoreNames)
        visitor.walk(context.sourceFile)
        return visitor.violations.map {
            diagnostic(context: context, position: $0.position, message: $0.message)
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

/// Names bound to a `DispatchSemaphore` in this file.
///
/// A syntactic rule cannot resolve types, so `.wait()` is only a blocking
/// semaphore wait when the receiver was initialized from `DispatchSemaphore`
/// here. That keeps the rule off unrelated `wait()` methods.
private enum DispatchSemaphoreBindingCollector {
    static func names(in sourceFile: SourceFileSyntax) -> Set<String> {
        let collector = DispatchSemaphoreBindingVisitor()
        collector.walk(sourceFile)
        return collector.names
    }
}

private final class DispatchSemaphoreBindingVisitor: SyntaxVisitor {
    private(set) var names: Set<String> = []

    override init(viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(viewMode: viewMode)
    }

    override func visitPost(_ node: PatternBindingSyntax) {
        guard let identifier = node.pattern.as(IdentifierPatternSyntax.self)?.identifier.text,
            node.initializer?.value.isDispatchSemaphoreConstruction == true
        else {
            return
        }
        names.insert(identifier)
    }
}

private final class TestBlockingWaitVisitor: SyntaxVisitor {
    private(set) var violations: [ArchitectureViolation] = []
    private let semaphoreNames: Set<String>
    private var processBindingScopes: [[String: Bool]] = [[:]]

    init(semaphoreNames: Set<String>) {
        self.semaphoreNames = semaphoreNames
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: CodeBlockSyntax) -> SyntaxVisitorContinueKind {
        var bindings: [String: Bool] = [:]
        if let function = node.parent?.as(FunctionDeclSyntax.self) {
            for parameter in function.signature.parameterClause.parameters {
                let localName = parameter.secondName?.text ?? parameter.firstName.text
                if localName != "_" {
                    bindings[localName] = parameter.type.isFoundationProcessType
                }
            }
        }
        processBindingScopes.append(bindings)
        return .visitChildren
    }

    override func visitPost(_: CodeBlockSyntax) {
        processBindingScopes.removeLast()
    }

    override func visit(_ node: ClosureExprSyntax) -> SyntaxVisitorContinueKind {
        var bindings: [String: Bool] = [:]
        if let parameterClause = node.signature?.parameterClause {
            switch parameterClause {
            case .simpleInput(let parameters):
                for parameter in parameters where parameter.name.text != "_" {
                    bindings[parameter.name.text] = false
                }
            case .parameterClause(let clause):
                for parameter in clause.parameters {
                    let localName = parameter.secondName?.text ?? parameter.firstName.text
                    if localName != "_" {
                        bindings[localName] = parameter.type?.isFoundationProcessType == true
                    }
                }
            }
        }
        processBindingScopes.append(bindings)
        return .visitChildren
    }

    override func visitPost(_: ClosureExprSyntax) {
        processBindingScopes.removeLast()
    }

    override func visitPost(_ node: PatternBindingSyntax) {
        guard let identifier = node.pattern.as(IdentifierPatternSyntax.self)?.identifier.text else {
            return
        }
        processBindingScopes[processBindingScopes.index(before: processBindingScopes.endIndex)][identifier] =
            node.initializer?.value.isFoundationProcessConstruction == true
    }

    /// A blocking call is only a problem on a cooperative thread. Inside the
    /// wrapper, or already inside a `DispatchQueue` block or a thread of its
    /// own, the block lands on libdispatch and the body is not searched.
    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        node.isCooperativePoolOffloadCall ? .skipChildren : .visitChildren
    }

    override func visitPost(_ node: FunctionCallExprSyntax) {
        guard !node.isCooperativePoolOffloadCall,
            let memberAccess = node.calledExpression.as(MemberAccessExprSyntax.self)
        else {
            return
        }
        if memberAccess.declName.baseName.text == "receive",
            node.arguments.first?.label?.text == "maxBytes"
        {
            violations.append(
                ArchitectureViolation(
                    position: memberAccess.positionAfterSkippingLeadingTrivia,
                    message:
                        "Wrap this socket receive in withoutBlockingCooperativePool, or use a "
                        + "WithoutBlockingMainActor helper, so it does not park a cooperative thread"
                )
            )
            return
        }
        if memberAccess.declName.baseName.text == "waitUntilExit",
            let base = memberAccess.base
        {
            let isProcessWait =
                base.isFoundationProcessConstruction
                || (base.as(DeclReferenceExprSyntax.self).map {
                    isFoundationProcessBinding(named: $0.baseName.text)
                } ?? false)
            guard isProcessWait else { return }
            violations.append(
                ArchitectureViolation(
                    position: memberAccess.positionAfterSkippingLeadingTrivia,
                    message:
                        "Wrap this Process.waitUntilExit call in withoutBlockingCooperativePool so it does not "
                        + "park a cooperative thread"
                )
            )
            return
        }
        guard memberAccess.declName.baseName.text == "wait", let base = memberAccess.base else {
            return
        }
        let isSemaphoreWait =
            base.isDispatchSemaphoreConstruction
            || (base.as(DeclReferenceExprSyntax.self).map { semaphoreNames.contains($0.baseName.text) } ?? false)
        guard isSemaphoreWait else { return }
        violations.append(
            ArchitectureViolation(
                position: memberAccess.positionAfterSkippingLeadingTrivia,
                message:
                    "Wrap this semaphore wait in withoutBlockingCooperativePool so it does not park "
                    + "a cooperative thread the IPC server needs"
            )
        )
    }

    private func isFoundationProcessBinding(named name: String) -> Bool {
        for scope in processBindingScopes.reversed() {
            if let isProcess = scope[name] {
                return isProcess
            }
        }
        return false
    }
}

extension TypeSyntax {
    fileprivate var isFoundationProcessType: Bool {
        if let identifier = self.as(IdentifierTypeSyntax.self) {
            return identifier.name.text == "Process"
        }
        guard let member = self.as(MemberTypeSyntax.self), member.name.text == "Process",
            let base = member.baseType.as(IdentifierTypeSyntax.self)
        else {
            return false
        }
        return base.name.text == "Foundation"
    }
}

extension FunctionCallExprSyntax {
    /// The call already moved this work off the cooperative executor: the shared
    /// wrapper, a `DispatchQueue` submission, or a thread of its own. A socket
    /// listener hands its handler such a queue too, so those bodies are fine.
    fileprivate var isCooperativePoolOffloadCall: Bool {
        if calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text == "withoutBlockingCooperativePool" {
            return true
        }
        guard let memberAccess = calledExpression.as(MemberAccessExprSyntax.self) else { return false }
        let submissionNames: Set<String> = ["async", "sync", "asyncAfter", "detachNewThread"]
        guard submissionNames.contains(memberAccess.declName.baseName.text) else { return false }
        return memberAccess.base?.namesADispatchTarget == true
    }
}

extension ExprSyntax {
    /// `DispatchQueue.global()`, `DispatchQueue.main`, a stored queue named for
    /// one, or `Thread`.
    fileprivate var namesADispatchTarget: Bool {
        if let reference = self.as(DeclReferenceExprSyntax.self) {
            let name = reference.baseName.text
            return name == "Thread" || name.containsIgnoringASCIICase("queue")
        }
        if let call = self.as(FunctionCallExprSyntax.self) {
            return call.calledExpression.namesADispatchTarget
        }
        if let memberAccess = self.as(MemberAccessExprSyntax.self) {
            return memberAccess.base?.namesADispatchTarget == true
                || memberAccess.declName.baseName.text.containsIgnoringASCIICase("queue")
        }
        return false
    }
}

extension ExprSyntax {
    fileprivate var isFoundationProcessConstruction: Bool {
        guard let call = self.as(FunctionCallExprSyntax.self) else { return false }
        if let reference = call.calledExpression.as(DeclReferenceExprSyntax.self) {
            return reference.baseName.text == "Process"
        }
        guard let memberAccess = call.calledExpression.as(MemberAccessExprSyntax.self),
            memberAccess.declName.baseName.text == "Process",
            let baseReference = memberAccess.base?.as(DeclReferenceExprSyntax.self)
        else {
            return false
        }
        return baseReference.baseName.text == "Foundation"
    }

    fileprivate var isDispatchSemaphoreConstruction: Bool {
        guard let call = self.as(FunctionCallExprSyntax.self) else { return false }
        if let reference = call.calledExpression.as(DeclReferenceExprSyntax.self) {
            return reference.baseName.text == "DispatchSemaphore"
        }
        if let memberAccess = call.calledExpression.as(MemberAccessExprSyntax.self) {
            return memberAccess.declName.baseName.text == "DispatchSemaphore"
        }
        return false
    }
}

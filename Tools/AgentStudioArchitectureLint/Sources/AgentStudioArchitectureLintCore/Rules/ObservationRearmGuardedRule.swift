import SwiftSyntax

/// A `withObservationTracking` whose `onChange` re-invokes the method that
/// armed it must show, in that method, what stops a second live tracking.
/// Without one, any second arm path leaves two trackings alive, and every
/// change after that fans out into more refreshes (the #323 storm: ~1,400
/// refreshes per second from one pane switch).
///
/// Accepted guards, both of which must control the re-arm:
/// - generation fence: `guard stored == captured else { return }` before the
///   re-arm, or the re-arm nested in `if stored == captured`, where `captured`
///   is a `let` or parameter of the arming method;
/// - arm latch: `guard !flag` in the arming method, `flag = true` when it
///   arms, and `flag = false` in `onChange`.
///
/// A comparison whose result does not decide whether the re-arm runs is not a
/// guard. One-shot trackings that never re-arm are outside the shape, and so
/// are tests: the shape is a product runtime hazard.
struct ObservationRearmGuardedRule: ArchitectureRule {
    let id = "agentstudio_observation_rearm_guarded"
    let severity = ArchitectureSeverity.error
    let message =
        "withObservationTracking re-arms from onChange without a generation fence or arm latch that controls "
        + "the re-arm; a second arm path leaves two live trackings"

    func validate(context: ArchitectureLintContext) -> [ArchitectureDiagnostic] {
        guard context.isUnderSourcesDirectory else {
            return []
        }
        let visitor = ObservationRearmVisitor()
        visitor.walk(context.sourceFile)
        return visitor.positions.map { diagnostic(context: context, position: $0) }
    }
}

private final class ObservationRearmVisitor: SyntaxVisitor {
    private(set) var positions: [AbsolutePosition] = []

    init() {
        super.init(viewMode: .sourceAccurate)
    }

    override func visitPost(_ node: FunctionCallExprSyntax) {
        guard node.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text == "withObservationTracking",
            let onChange = node.onChangeClosure,
            let armingFunction = node.enclosingFunction
        else {
            return
        }
        let armingName = armingFunction.name.text
        let rearmCalls = FunctionCallCollector.calls(in: Syntax(onChange)).filter { $0.calleeName == armingName }
        guard !rearmCalls.isEmpty else {
            return
        }
        if ArmLatch.guards(armingFunction: armingFunction, trackingCall: node, onChange: onChange) {
            return
        }
        let capturedNames = CapturedNames.of(armingFunction, excluding: Syntax(node))
        let unguarded = rearmCalls.contains { rearm in
            !GenerationFence.controls(rearm: Syntax(rearm), within: Syntax(onChange), capturedNames: capturedNames)
        }
        if unguarded {
            positions.append(node.positionAfterSkippingLeadingTrivia)
        }
    }
}

extension FunctionCallExprSyntax {
    /// `onChange:` passed either as a labeled argument or as the labeled
    /// trailing closure of `withObservationTracking { … } onChange: { … }`.
    fileprivate var onChangeClosure: ClosureExprSyntax? {
        if let argument = arguments.first(where: { $0.label?.text == "onChange" }) {
            return argument.expression.as(ClosureExprSyntax.self)
        }
        return additionalTrailingClosures.first { $0.label.text == "onChange" }?.closure
    }

    /// The name this call invokes: `f()`, `self.f()`, `self?.f()`, `x.f()`.
    var calleeName: String? {
        if let reference = calledExpression.as(DeclReferenceExprSyntax.self) {
            return reference.baseName.text
        }
        if let member = calledExpression.as(MemberAccessExprSyntax.self) {
            return member.declName.baseName.text
        }
        return nil
    }
}

extension SyntaxProtocol {
    /// The nearest enclosing `func`, if the node is inside one.
    var enclosingFunction: FunctionDeclSyntax? {
        var current = parent
        while let node = current {
            if let function = node.as(FunctionDeclSyntax.self) {
                return function
            }
            current = node.parent
        }
        return nil
    }
}

final class FunctionCallCollector: SyntaxVisitor {
    private(set) var calls: [FunctionCallExprSyntax] = []

    static func calls(in syntax: Syntax) -> [FunctionCallExprSyntax] {
        let collector = FunctionCallCollector(viewMode: .sourceAccurate)
        collector.walk(syntax)
        return collector.calls
    }

    override func visitPost(_ node: FunctionCallExprSyntax) {
        calls.append(node)
    }
}

/// `let` bindings and parameters of the arming method, outside the tracking
/// call itself: the values an `onChange` closure captures from its arm.
private enum CapturedNames {
    static func of(_ function: FunctionDeclSyntax, excluding trackingCall: Syntax) -> Set<String> {
        var names = Set(
            function.signature.parameterClause.parameters.map { ($0.secondName ?? $0.firstName).text }
        )
        if let body = function.body {
            let collector = LetBindingCollector(excluding: trackingCall)
            collector.walk(body)
            names.formUnion(collector.names)
        }
        return names
    }
}

private final class LetBindingCollector: SyntaxVisitor {
    private(set) var names: Set<String> = []
    private let excluded: Syntax

    init(excluding excluded: Syntax) {
        self.excluded = excluded
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        Syntax(node) == excluded ? .skipChildren : .visitChildren
    }

    override func visitPost(_ node: PatternBindingSyntax) {
        guard node.parent?.parent?.as(VariableDeclSyntax.self)?.bindingSpecifier.tokenKind == .keyword(.let),
            let name = node.pattern.as(IdentifierPatternSyntax.self)?.identifier.text
        else {
            return
        }
        names.insert(name)
    }
}

/// A generation comparison that decides whether the re-arm runs.
private enum GenerationFence {
    /// Walks from the re-arm up to the `onChange` closure. At each level the
    /// re-arm is controlled by an earlier statement in the same block —
    /// `guard stored == captured else { exit }` or
    /// `if stored != captured { exit }` — or by an enclosing
    /// `if stored == captured` whose body holds the re-arm. `stored` must be
    /// stored state (see `readsStoredState`), not a literal or a local.
    static func controls(rearm: Syntax, within onChange: Syntax, capturedNames: Set<String>) -> Bool {
        let localNames = capturedNames.union(LocalBindingNameCollector.names(in: onChange))
        var child = rearm
        var current = rearm.parent
        while let node = current, node != onChange {
            if let item = child.as(CodeBlockItemSyntax.self), let block = node.as(CodeBlockItemListSyntax.self) {
                for sibling in block {
                    if sibling == item {
                        break
                    }
                    if let guardStatement = sibling.item.as(GuardStmtSyntax.self),
                        guardStatement.body.exitsScope,
                        comparesCaptured(
                            guardStatement.conditions, operator: "==", capturedNames: capturedNames,
                            localNames: localNames)
                    {
                        return true
                    }
                    if let ifExpression = sibling.ifExpression, ifExpression.body.exitsScope,
                        comparesCaptured(
                            ifExpression.conditions, operator: "!=", capturedNames: capturedNames,
                            localNames: localNames)
                    {
                        return true
                    }
                }
            }
            if let ifExpression = node.as(IfExprSyntax.self),
                Syntax(ifExpression.body) == child,
                comparesCaptured(
                    ifExpression.conditions, operator: "==", capturedNames: capturedNames, localNames: localNames)
            {
                return true
            }
            child = node
            current = node.parent
        }
        return false
    }

    /// Some condition compares a captured value with stored state.
    private static func comparesCaptured(
        _ conditions: ConditionElementListSyntax,
        operator operatorText: String,
        capturedNames: Set<String>,
        localNames: Set<String>
    ) -> Bool {
        conditions.contains { element in
            guard let condition = element.condition.as(ExprSyntax.self) else {
                return false
            }
            return condition.binaryOperands(operator: operatorText).contains { comparison in
                let isCaptured = { (operand: ExprSyntax) -> Bool in
                    guard let reference = operand.as(DeclReferenceExprSyntax.self) else {
                        return false
                    }
                    return capturedNames.contains(reference.baseName.text)
                }
                return
                    (isCaptured(comparison.left)
                    && comparison.right.readsStoredState(excludingLocalNames: localNames))
                    || (isCaptured(comparison.right)
                        && comparison.left.readsStoredState(excludingLocalNames: localNames))
            }
        }
    }
}

/// `guard !flag` and `flag = true` in the arming method, `flag = false` in
/// `onChange`: arming is refused while a tracking is live.
private enum ArmLatch {
    /// On the arming method's straight-line path — its top-level statements
    /// before the one that arms — a `guard … !flag … else` refuses a second
    /// arm and `flag = true` records the live tracking; `onChange` clears it.
    static func guards(
        armingFunction: FunctionDeclSyntax,
        trackingCall: FunctionCallExprSyntax,
        onChange: ClosureExprSyntax
    ) -> Bool {
        guard let body = armingFunction.body,
            let armingIndex = body.statements.firstIndex(where: { statement in
                statement.position <= trackingCall.position && trackingCall.endPosition <= statement.endPosition
            })
        else {
            return false
        }
        let beforeArming = body.statements[..<armingIndex]
        let refusedFlags = Set(
            beforeArming.compactMap { $0.item.as(GuardStmtSyntax.self) }.flatMap { guardStatement in
                guardStatement.conditions.compactMap { element -> String? in
                    guard let prefix = element.condition.as(PrefixOperatorExprSyntax.self),
                        prefix.operator.text == "!"
                    else {
                        return nil
                    }
                    return prefix.expression.referencedPropertyName
                }
            }
        )
        let setBeforeArming = Set(
            beforeArming.compactMap { statement -> String? in
                guard let assignment = statement.item.as(ExprSyntax.self)?.assignment,
                    assignment.value.as(BooleanLiteralExprSyntax.self)?.literal.text == "true"
                else {
                    return nil
                }
                return assignment.target.referencedPropertyName
            }
        )
        let clearedOnChange = BooleanAssignmentCollector.flags(assigned: "false", in: Syntax(onChange))
        return !refusedFlags.intersection(setBeforeArming).isDisjoint(with: clearedOnChange)
    }
}

private final class BooleanAssignmentCollector: SyntaxVisitor {
    private(set) var flags: Set<String> = []
    private let value: String

    static func flags(assigned value: String, in syntax: Syntax) -> Set<String> {
        let collector = BooleanAssignmentCollector(value: value)
        collector.walk(syntax)
        return collector.flags
    }

    private init(value: String) {
        self.value = value
        super.init(viewMode: .sourceAccurate)
    }

    override func visitPost(_ node: SequenceExprSyntax) {
        guard let assignment = ExprSyntax(node).assignment,
            assignment.value.as(BooleanLiteralExprSyntax.self)?.literal.text == value,
            let name = assignment.target.referencedPropertyName
        else {
            return
        }
        flags.insert(name)
    }
}

extension ExprSyntax {
    /// `flag`, `self.flag` or `self?.flag` as the bare property name.
    var referencedPropertyName: String? {
        if let reference = self.as(DeclReferenceExprSyntax.self) {
            return reference.baseName.text
        }
        if let member = self.as(MemberAccessExprSyntax.self) {
            return member.declName.baseName.text
        }
        return nil
    }
}

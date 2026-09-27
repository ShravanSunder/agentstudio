import SwiftSyntax

/// SwiftUI evaluates `body` on every render, on MainActor. Command validation,
/// fuzzy scoring and collection-wide sort/filter/reduce/grouping there repeat
/// per render and per row; they belong in a derived projection computed off
/// the render path.
///
/// Walks `var body: some View` and the same-file methods and computed
/// properties it reaches through them (a body's builders are render path
/// however deep they nest). Flags `canDispatch` on a dispatcher, `snapshot(state:)`,
/// `fuzzyMatch`/`score*`, `.sorted`/`.sort`/`.filter`/`.reduce`, any
/// `grouping:` call, and calls to `Type.member` or `Type(...)` resolvers that
/// the prepared index shows calling `canDispatch` in another file.
///
/// Not flagged: `Optional.map`/`compactMap`/`flatMap` (almost always a single
/// optional), `canDispatch` on a precomputed capability set rather than a
/// dispatcher, and closures SwiftUI runs later rather than during the render:
/// `action:`/`perform:` arguments, any `on…:` handler argument, and trailing
/// closures of `Button`, `.task` and `.on…` modifiers.
struct SwiftUIBodyDerivationRule: ArchitectureRule {
    let id = "agentstudio_swiftui_body_derivation"
    let severity = ArchitectureSeverity.error
    let message =
        "Command validation, fuzzy scoring, or collection-wide derivation inside a SwiftUI body runs on every "
        + "render; derive it off the render path and read the result"

    private let commandValidatingResolvers: Set<String>

    init() {
        self.init(commandValidatingResolvers: [])
    }

    private init(commandValidatingResolvers: Set<String>) {
        self.commandValidatingResolvers = commandValidatingResolvers
    }

    func prepared(for contexts: [ArchitectureLintContext]) -> any ArchitectureRule {
        var resolvers: Set<String> = []
        for context in contexts where context.normalizedPath.contains("/Sources/") {
            let collector = CommandValidatingResolverCollector()
            collector.walk(context.sourceFile)
            resolvers.formUnion(collector.resolvers)
        }
        return Self(commandValidatingResolvers: resolvers)
    }

    func validate(context: ArchitectureLintContext) -> [ArchitectureDiagnostic] {
        guard context.isUnderSourcesDirectory else {
            return []
        }
        let declarations = SameFileMemberCollector()
        declarations.walk(context.sourceFile)
        guard !declarations.bodies.isEmpty else {
            return []
        }

        var positions: Set<AbsolutePosition> = []
        var pending = declarations.bodies
        var visitedHelpers: Set<SameFileMember> = []
        while let renderPath = pending.popLast() {
            let visitor = RenderPathVisitor(commandValidatingResolvers: commandValidatingResolvers)
            visitor.walk(renderPath.syntax)
            positions.formUnion(visitor.positions)
            for helperName in visitor.referencedNames {
                // A name resolves to a member of the body's own type, or else
                // to a file-scope function; never to another type's member.
                let ownMember = SameFileMember(typeName: renderPath.typeName, name: helperName)
                let fileMember = SameFileMember(typeName: "", name: helperName)
                let member = declarations.helpers[ownMember] == nil ? fileMember : ownMember
                guard let helpers = declarations.helpers[member], visitedHelpers.insert(member).inserted else {
                    continue
                }
                pending.append(contentsOf: helpers)
            }
        }
        return positions.sorted { $0.utf8Offset < $1.utf8Offset }.map { diagnostic(context: context, position: $0) }
    }
}

/// The file's `body: some View` accessors and its methods and computed
/// properties by name — the helpers a body can reach.
private struct SameFileMember: Hashable {
    /// The enclosing type or extended type; empty at file scope.
    let typeName: String
    let name: String
}

private struct RenderPathSyntax {
    let typeName: String
    let syntax: Syntax
}

private final class SameFileMemberCollector: SyntaxVisitor {
    private(set) var bodies: [RenderPathSyntax] = []
    private(set) var helpers: [SameFileMember: [RenderPathSyntax]] = [:]
    private var typeNames: [String] = []

    init() {
        super.init(viewMode: .sourceAccurate)
    }

    private var typeName: String {
        typeNames.last ?? ""
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        typeNames.append(node.name.text)
        return .visitChildren
    }

    override func visitPost(_ node: StructDeclSyntax) {
        typeNames.removeLast()
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        typeNames.append(node.name.text)
        return .visitChildren
    }

    override func visitPost(_ node: ClassDeclSyntax) {
        typeNames.removeLast()
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        typeNames.append(node.name.text)
        return .visitChildren
    }

    override func visitPost(_ node: EnumDeclSyntax) {
        typeNames.removeLast()
    }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        typeNames.append(node.name.text)
        return .visitChildren
    }

    override func visitPost(_ node: ActorDeclSyntax) {
        typeNames.removeLast()
    }

    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        typeNames.append(node.extendedType.trimmedDescription)
        return .visitChildren
    }

    override func visitPost(_ node: ExtensionDeclSyntax) {
        typeNames.removeLast()
    }

    override func visitPost(_ node: FunctionDeclSyntax) {
        if let body = node.body {
            record(name: node.name.text, syntax: Syntax(body))
        }
    }

    override func visitPost(_ node: PatternBindingSyntax) {
        guard let name = node.pattern.as(IdentifierPatternSyntax.self)?.identifier.text,
            let accessors = node.accessorBlock
        else {
            return
        }
        let isViewBody =
            name == "body"
            && node.typeAnnotation?.type.trimmedDescription == "some View"
        if isViewBody {
            bodies.append(RenderPathSyntax(typeName: typeName, syntax: Syntax(accessors)))
        } else {
            record(name: name, syntax: Syntax(accessors))
        }
    }

    private func record(name: String, syntax: Syntax) {
        helpers[SameFileMember(typeName: typeName, name: name), default: []]
            .append(RenderPathSyntax(typeName: typeName, syntax: syntax))
    }
}

private final class RenderPathVisitor: SyntaxVisitor {
    private static let collectionDerivationNames: Set<String> = ["sorted", "sort", "filter", "reduce"]
    /// Closure arguments SwiftUI stores and runs later, besides any `on…:`
    /// handler label.
    private static let deferredClosureLabels: Set<String> = ["action", "perform", "canDispatchCommand"]
    /// Calls whose trailing closure runs later, besides any `.on…` modifier.
    private static let deferredTrailingClosureCallees: Set<String> = ["Button", "task"]

    private(set) var positions: [AbsolutePosition] = []
    private(set) var referencedNames: Set<String> = []
    private let commandValidatingResolvers: Set<String>

    init(commandValidatingResolvers: Set<String>) {
        self.commandValidatingResolvers = commandValidatingResolvers
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: ClosureExprSyntax) -> SyntaxVisitorContinueKind {
        Self.isDeferred(node) ? .skipChildren : .visitChildren
    }

    override func visitPost(_ node: DeclReferenceExprSyntax) {
        // `helper` and `self.helper` name a same-file member; `other.helper`
        // does not. A bare name as a member access base (`helper.padding()`)
        // still names the helper.
        if let member = node.parent?.as(MemberAccessExprSyntax.self), member.declName == node,
            member.base?.as(DeclReferenceExprSyntax.self)?.baseName.tokenKind != .keyword(.self)
        {
            return
        }
        referencedNames.insert(node.baseName.text)
    }

    override func visitPost(_ node: FunctionCallExprSyntax) {
        if isRenderPathDerivation(node) {
            positions.append(node.positionAfterSkippingLeadingTrivia)
        }
    }

    private func isRenderPathDerivation(_ call: FunctionCallExprSyntax) -> Bool {
        guard let calleeName = call.calleeName else {
            return false
        }
        if calleeName == "canDispatch" {
            return call.isDispatcherCanDispatch
        }
        if calleeName == "fuzzyMatch" || calleeName.isScoringName {
            return true
        }
        if calleeName == "snapshot", call.arguments.first?.label?.text == "state" {
            return true
        }
        if call.arguments.contains(where: { $0.label?.text == "grouping" }) {
            return true
        }
        if let member = call.calledExpression.as(MemberAccessExprSyntax.self) {
            if Self.collectionDerivationNames.contains(calleeName) {
                return true
            }
            if let typeName = member.base?.as(DeclReferenceExprSyntax.self)?.baseName.text,
                commandValidatingResolvers.contains("\(typeName).\(calleeName)")
            {
                return true
            }
        }
        if call.calledExpression.is(DeclReferenceExprSyntax.self),
            commandValidatingResolvers.contains("\(calleeName).init")
        {
            return true
        }
        return false
    }

    private static func isDeferred(_ closure: ClosureExprSyntax) -> Bool {
        if let argument = closure.parent?.as(LabeledExprSyntax.self),
            let label = argument.label?.text
        {
            return deferredClosureLabels.contains(label) || label.isEventHandlerName
        }
        if let trailing = closure.parent?.as(MultipleTrailingClosureElementSyntax.self) {
            let label = trailing.label.text
            return deferredClosureLabels.contains(label) || label.isEventHandlerName
        }
        if let call = closure.parent?.as(FunctionCallExprSyntax.self), call.trailingClosure == closure,
            let calleeName = call.calleeName
        {
            return deferredTrailingClosureCallees.contains(calleeName) || calleeName.isEventHandlerName
        }
        return false
    }
}

/// `Type.member` functions and `Type.init` initializers whose bodies call
/// `canDispatch`, across every source file.
private final class CommandValidatingResolverCollector: SyntaxVisitor {
    private(set) var resolvers: Set<String> = []
    private var typeNames: [String] = []

    init() {
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        typeNames.append(node.name.text)
        return .visitChildren
    }

    override func visitPost(_ node: StructDeclSyntax) {
        typeNames.removeLast()
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        typeNames.append(node.name.text)
        return .visitChildren
    }

    override func visitPost(_ node: ClassDeclSyntax) {
        typeNames.removeLast()
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        typeNames.append(node.name.text)
        return .visitChildren
    }

    override func visitPost(_ node: EnumDeclSyntax) {
        typeNames.removeLast()
    }

    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        typeNames.append(node.extendedType.trimmedDescription)
        return .visitChildren
    }

    override func visitPost(_ node: ExtensionDeclSyntax) {
        typeNames.removeLast()
    }

    override func visitPost(_ node: FunctionDeclSyntax) {
        guard let typeName = typeNames.last, let body = node.body, Self.callsCanDispatch(Syntax(body)) else {
            return
        }
        resolvers.insert("\(typeName).\(node.name.text)")
    }

    override func visitPost(_ node: InitializerDeclSyntax) {
        guard let typeName = typeNames.last, let body = node.body, Self.callsCanDispatch(Syntax(body)) else {
            return
        }
        resolvers.insert("\(typeName).init")
    }

    private static func callsCanDispatch(_ body: Syntax) -> Bool {
        FunctionCallCollector.calls(in: body).contains { $0.calleeName == "canDispatch" && $0.isDispatcherCanDispatch }
    }
}

extension String {
    /// `score`, `scoreMatch`, `scored` — not `scoreboard` style words that
    /// merely start with the letters.
    fileprivate var isScoringName: Bool {
        guard hasPrefix("score") else {
            return false
        }
        let rest = dropFirst("score".count)
        return rest.isEmpty || rest == "d" || rest.first?.isUppercase == true
    }

    /// `onTapGesture`, `onArrowUp`, `onEnter`: a SwiftUI event handler.
    fileprivate var isEventHandlerName: Bool {
        guard hasPrefix("on"), count > 2 else {
            return false
        }
        return self[index(startIndex, offsetBy: 2)].isUppercase
    }
}

extension FunctionCallExprSyntax {
    /// `canDispatch` asked of a command dispatcher (`dispatcher`,
    /// `commandDispatcher`, `AppCommandDispatcher.shared`), which validates the
    /// command. The same name on a precomputed capability set is a lookup.
    fileprivate var isDispatcherCanDispatch: Bool {
        guard let receiver = calledExpression.as(MemberAccessExprSyntax.self)?.base else {
            return false
        }
        let receiverName =
            receiver.as(MemberAccessExprSyntax.self).map { member in
                member.declName.baseName.text == "shared"
                    ? member.base?.trimmedDescription ?? "" : member.declName.baseName.text
            }
            ?? receiver.trimmedDescription
        return receiverName.lowercased().hasSuffix("dispatcher")
    }
}

import SwiftSyntax

struct TooltipSourceRule: ArchitectureRule {
    let id = "agentstudio_toolbar_tooltip_source"
    let severity = ArchitectureSeverity.error
    let message = "Dense control tooltips must flow through typed tooltip sources and render values"

    private let commandSemanticDeniedReferences = Set([
        "AppCommand",
        "AppCommandSpec",
        "AppCommandIPCExposure",
        "IPCCommandExecuteParams",
        "IPCCommandExecuteResult",
        "IPCCommandIdentifier",
        "IPCCommandListEntry",
        "IPCCommandListResult",
        "IPCPrivilegeClass",
    ])

    private let sharedComponentsDeniedReferences = Set([
        "ActionSpec",
        "AppCommand",
        "AppCommandSpec",
        "CommandDisplayDescriptor",
        "ControlTooltipSource",
        "IPCCommandExecuteParams",
        "IPCCommandExecuteResult",
        "IPCCommandIdentifier",
        "IPCCommandListEntry",
        "IPCCommandListResult",
        "IPCPrivilegeClass",
        "LocalActionSpec",
    ])

    private let migratedDenseTooltipSuffixes = [
        "/Sources/AgentStudio/Core/Views/Drawer/DrawerIconBar.swift",
        "/Sources/AgentStudio/App/Windows/MainWindowController.swift",
        "/Sources/AgentStudio/Features/InboxNotification/Views/InboxSidebarComponents.swift",
        "/Sources/AgentStudio/Features/InboxNotification/Views/PaneInboxNotificationPopover.swift",
    ]

    private let coreTooltipContractSuffixes = [
        "/Sources/AgentStudio/Core/Actions/ControlTooltipSource.swift",
        "/Sources/AgentStudio/Core/Actions/UIActionPresentation.swift",
    ]

    func validate(context: ArchitectureLintContext) -> [ArchitectureDiagnostic] {
        var diagnostics: [ArchitectureDiagnostic] = []

        if isCoreTooltipContractPath(context.normalizedPath) {
            let visitor = DeniedReferenceVisitor(
                deniedReferences: commandSemanticDeniedReferences,
                message: "Core/Actions tooltip contracts must not reference app commands or IPC DTOs"
            )
            visitor.walk(context.sourceFile)
            diagnostics.append(
                contentsOf: visitor.violations.map {
                    diagnostic(context: context, position: $0.position, message: $0.message)
                })
        }

        if pathContains(context.normalizedPath, "Sources/AgentStudio/Infrastructure/") {
            let visitor = DeniedReferenceVisitor(
                deniedReferences: commandSemanticDeniedReferences,
                message: "Infrastructure tooltip render values must not reference app commands or IPC DTOs"
            )
            visitor.walk(context.sourceFile)
            diagnostics.append(
                contentsOf: visitor.violations.map {
                    diagnostic(context: context, position: $0.position, message: $0.message)
                })
        }

        if pathContains(context.normalizedPath, "Sources/AgentStudio/SharedComponents/") {
            let visitor = DeniedReferenceVisitor(
                deniedReferences: sharedComponentsDeniedReferences,
                message:
                    "SharedComponents may render ControlTooltipRenderValue but must not consume command specs, tooltip sources, or IPC DTOs"
            )
            visitor.walk(context.sourceFile)
            diagnostics.append(
                contentsOf: visitor.violations.map {
                    diagnostic(context: context, position: $0.position, message: $0.message)
                })
        }

        if isMigratedDenseTooltipPath(context.normalizedPath) {
            let visitor = DenseTooltipRenderAdapterVisitor()
            visitor.walk(context.sourceFile)
            diagnostics.append(
                contentsOf: visitor.violations.map {
                    diagnostic(context: context, position: $0.position, message: $0.message)
                })
        }

        return diagnostics
    }

    private func isMigratedDenseTooltipPath(_ path: String) -> Bool {
        migratedDenseTooltipSuffixes.contains { suffix in
            path.hasSuffix(suffix) || path.hasSuffix(String(suffix.dropFirst()))
        }
    }

    private func isCoreTooltipContractPath(_ path: String) -> Bool {
        coreTooltipContractSuffixes.contains { suffix in
            path.hasSuffix(suffix) || path.hasSuffix(String(suffix.dropFirst()))
        }
    }

    private func pathContains(_ path: String, _ component: String) -> Bool {
        path.contains("/\(component)") || path.contains(component)
    }
}

private final class DeniedReferenceVisitor: SyntaxVisitor {
    private(set) var violations: [ArchitectureViolation] = []
    private let deniedReferences: Set<String>
    private let message: String

    init(
        deniedReferences: Set<String>,
        message: String,
        viewMode: SyntaxTreeViewMode = .sourceAccurate
    ) {
        self.deniedReferences = deniedReferences
        self.message = message
        super.init(viewMode: viewMode)
    }

    override func visitPost(_ node: DeclReferenceExprSyntax) {
        guard deniedReferences.contains(node.baseName.text) else { return }
        violations.append(
            ArchitectureViolation(
                position: node.positionAfterSkippingLeadingTrivia,
                message: message
            )
        )
    }

    override func visitPost(_ node: IdentifierTypeSyntax) {
        guard deniedReferences.contains(node.name.text) else { return }
        violations.append(
            ArchitectureViolation(
                position: node.positionAfterSkippingLeadingTrivia,
                message: message
            )
        )
    }
}

private final class DenseTooltipRenderAdapterVisitor: SyntaxVisitor {
    private(set) var violations: [ArchitectureViolation] = []
    private let denseControlConstructors = Set([
        "Button",
        "Menu",
        "Picker",
        "Toggle",
    ])

    override init(viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(viewMode: viewMode)
    }

    override func visitPost(_ node: FunctionCallExprSyntax) {
        guard let memberAccess = node.calledExpression.as(MemberAccessExprSyntax.self),
            memberAccess.declName.baseName.text == "help"
        else {
            diagnoseHoverPresenterTooltipText(node)
            return
        }

        if isDenseControlChain(memberAccess.base) {
            violations.append(
                ArchitectureViolation(
                    position: memberAccess.positionAfterSkippingLeadingTrivia,
                    message:
                        "Migrated dense controls must use controlHelp with ControlTooltipRenderValue instead of raw .help"
                )
            )
        }

        diagnoseHoverPresenterTooltipText(node)
    }

    private func diagnoseHoverPresenterTooltipText(_ node: FunctionCallExprSyntax) {
        guard node.calledExpression.trimmedDescription == "FloatingHoverTooltipPresenter" else {
            return
        }
        guard let tooltipTextArgument = node.arguments.first(where: { $0.label?.text == "tooltipText" }) else {
            return
        }
        violations.append(
            ArchitectureViolation(
                position: tooltipTextArgument.positionAfterSkippingLeadingTrivia,
                message: "FloatingHoverTooltipPresenter must receive ControlTooltipRenderValue through tooltipValue"
            )
        )
    }

    override func visitPost(_ node: MemberAccessExprSyntax) {
        guard node.declName.baseName.text == "toolTip" else { return }
        guard isAssignmentTarget(node) else { return }
        violations.append(
            ArchitectureViolation(
                position: node.positionAfterSkippingLeadingTrivia,
                message: "Migrated AppKit controls must use applyControlTooltip with ControlTooltipRenderValue"
            )
        )
    }

    private func isDenseControlChain(_ expression: ExprSyntax?) -> Bool {
        guard let expression else { return false }
        if let functionCall = expression.as(FunctionCallExprSyntax.self) {
            if denseControlConstructors.contains(functionCall.calledExpression.trimmedDescription) {
                return true
            }
            if let memberAccess = functionCall.calledExpression.as(MemberAccessExprSyntax.self) {
                return isDenseControlChain(memberAccess.base)
            }
        }
        if let memberAccess = expression.as(MemberAccessExprSyntax.self) {
            return isDenseControlChain(memberAccess.base)
        }
        return false
    }

    private func isAssignmentTarget(_ node: MemberAccessExprSyntax) -> Bool {
        var ancestor = node.parent
        while let currentAncestor = ancestor {
            if let sequence = currentAncestor.as(SequenceExprSyntax.self),
                sequence.trimmedDescription.contains("\(node.trimmedDescription) =")
            {
                return true
            }
            ancestor = currentAncestor.parent
        }
        return false
    }
}

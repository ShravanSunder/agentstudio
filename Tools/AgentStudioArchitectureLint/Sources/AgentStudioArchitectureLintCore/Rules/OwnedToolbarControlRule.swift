import SwiftSyntax

struct OwnedToolbarControlRule: ArchitectureRule {
    let id = "agentstudio_drawer_toolbar_owned_controls"
    let severity = ArchitectureSeverity.error
    let message =
        "Drawer toolbar actions must use ToolbarActionButton; raw Button rendering belongs only to the owned control"

    func validate(context: ArchitectureLintContext) -> [ArchitectureDiagnostic] {
        guard context.normalizedPath.hasSuffix("/Core/Views/Drawer/DrawerIconBar.swift") else { return [] }
        let visitor = OwnedToolbarControlVisitor()
        visitor.walk(context.sourceFile)
        return visitor.positions.map { diagnostic(context: context, position: $0) }
    }
}

private final class OwnedToolbarControlVisitor: SyntaxVisitor {
    var positions: [AbsolutePosition] = []

    init() {
        super.init(viewMode: .sourceAccurate)
    }

    override func visitPost(_ node: FunctionCallExprSyntax) {
        let callee = node.calledExpression.trimmedDescription
        if callee == "Button" || callee == "SwiftUI.Button"
            || callee == "Button.init" || callee == "SwiftUI.Button.init"
            || callee.hasPrefix("Button<") || callee.hasPrefix("SwiftUI.Button<")
        {
            positions.append(node.positionAfterSkippingLeadingTrivia)
        }
    }
}

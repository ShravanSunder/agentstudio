import SwiftSyntax

struct HotPaneSnapshotReadsRule: ArchitectureRule {
    let id = "agentstudio_hot_pane_snapshot_reads"
    let severity = ArchitectureSeverity.error
    let message = "Hot tab/sidebar command presentation must use pane membership plus keyed structural reads"

    private let hotPathSuffixes = [
        "/Sources/AgentStudio/App/Panes/PaneTabViewController.swift",
        "/Sources/AgentStudio/App/Panes/TabBar/TabBarAdapter.swift",
        "/Sources/AgentStudio/App/Windows/SidebarSurfaceHost.swift",
        "/Sources/AgentStudio/App/Windows/RepoExplorerCommandPresentationBatch.swift",
        "/Sources/AgentStudio/Features/RepoExplorer/RepoExplorerCommandPresentation.swift",
        "/Sources/AgentStudio/Features/RepoExplorer/RepoExplorerView.swift",
        "/Sources/AgentStudio/Features/RepoExplorer/RepoExplorerView+ProjectionHelpers.swift",
    ]

    func validate(context: ArchitectureLintContext) -> [ArchitectureDiagnostic] {
        guard hotPathSuffixes.contains(where: context.normalizedPath.hasSuffix) else { return [] }
        let visitor = BulkPaneReadVisitor()
        visitor.walk(context.sourceFile)
        return visitor.positions.map { position in
            diagnostic(context: context, position: position)
        }
    }
}

private final class BulkPaneReadVisitor: SyntaxVisitor {
    private(set) var positions: [AbsolutePosition] = []

    override init(viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(viewMode: viewMode)
    }

    override func visitPost(_ node: FunctionCallExprSyntax) {
        guard let memberAccess = node.calledExpression.as(MemberAccessExprSyntax.self) else { return }
        let functionName = memberAccess.declName.baseName.text
        let argumentLabels = node.arguments.map { $0.label?.text }
        let isProhibitedCall =
            ((functionName == "paneSnapshot" || functionName == "paneStateSnapshot")
                && argumentLabels.isEmpty)
            || (functionName == "panes" && argumentLabels == ["for"])
            || (functionName == "isWorktreeActive" && argumentLabels == [nil])
            || (functionName == "orphanedPanes" && argumentLabels == ["excluding"])
        guard isProhibitedCall else { return }
        positions.append(memberAccess.positionAfterSkippingLeadingTrivia)
    }
}

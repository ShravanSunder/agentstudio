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
        let visitor = BulkPaneSnapshotVisitor()
        visitor.walk(context.sourceFile)
        return visitor.positions.map { position in
            diagnostic(context: context, position: position)
        }
    }
}

private final class BulkPaneSnapshotVisitor: SyntaxVisitor {
    private(set) var positions: [AbsolutePosition] = []

    override init(viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(viewMode: viewMode)
    }

    override func visitPost(_ node: MemberAccessExprSyntax) {
        guard
            node.declName.baseName.text == "paneSnapshot"
                || node.declName.baseName.text == "paneStateSnapshot"
        else {
            return
        }
        positions.append(node.positionAfterSkippingLeadingTrivia)
    }
}

import AgentStudioCore
import AgentStudioInfrastructure
import AgentStudioSharedComponents
import Foundation

struct RepoExplorerMaterializedGroupHeaderPresentation: Equatable, Sendable {
    let groupID: String
    let icon: AppEntityIcon
    let title: String
    let organizationName: String?
    let colorHex: String?
    let isExpanded: Bool
    let repoIDs: [UUID]
    let semanticRepoPath: URL?
    let paneDestinations: [RepoExplorerPaneDestination]
}

struct RepoExplorerMaterializedWorktreePresentation: Equatable, Sendable {
    let rowID: RepoExplorerRowID
    let groupID: String
    let repo: RepoPresentationItem
    let worktree: Worktree
    let checkoutTitle: String
    let isMainCheckout: Bool
    let checkoutColorHex: String
    let placementText: String
    let branchStatus: GitBranchStatus
    let branchName: String
    let bridgeCommandResolution: BridgePaneCommandResolution
    let paneDestinations: [RepoExplorerPaneDestination]

    /// Equality covers only values consumed by the materialized row. The full
    /// source models are retained for rendering actions, but dormant metadata
    /// must not turn into a native table update.
    static func == (
        lhs: Self,
        rhs: Self
    ) -> Bool {
        lhs.rowID == rhs.rowID
            && lhs.groupID == rhs.groupID
            && lhs.repo.id == rhs.repo.id
            && lhs.worktree.id == rhs.worktree.id
            && lhs.worktree.path == rhs.worktree.path
            && lhs.worktree.isMainWorktree == rhs.worktree.isMainWorktree
            && lhs.checkoutTitle == rhs.checkoutTitle
            && lhs.isMainCheckout == rhs.isMainCheckout
            && lhs.checkoutColorHex == rhs.checkoutColorHex
            && lhs.placementText == rhs.placementText
            && lhs.branchStatus == rhs.branchStatus
            && lhs.branchName == rhs.branchName
            && lhs.bridgeCommandResolution == rhs.bridgeCommandResolution
            && lhs.paneDestinations == rhs.paneDestinations
    }
}

struct RepoExplorerUnassociatedPanePresentation: Equatable, Sendable {
    let destination: RepoExplorerUnassociatedPaneDestination
    let primaryText: String
    let secondaryLine: RepoExplorerPaneSecondaryLine?
    let recencyText: String
    let recencyTier: RepoExplorerPaneRecencyTier
    let isActive: Bool
    let isDrawerPane: Bool
}

enum RepoExplorerMaterializedRowPresentation: Equatable, Sendable {
    case sectionHeader(kind: RepoExplorerSidebarSectionKind, isFirstRow: Bool)
    case loadingSectionHeader(
        kind: RepoExplorerSidebarSectionKind,
        state: RepoExplorerLoadingSectionState
    )
    case loadingRepository(
        section: RepoExplorerSidebarSectionKind,
        repoID: UUID,
        name: String,
        isStatusUnavailable: Bool
    )
    case groupHeader(RepoExplorerMaterializedGroupHeaderPresentation)
    case worktree(RepoExplorerMaterializedWorktreePresentation)
    case pane(RepoExplorerProjectedPaneRow)
    case unassociatedPane(RepoExplorerUnassociatedPanePresentation)
    case topologyFault(RepoExplorerTopologyFault)
    case unresolved(RepoExplorerRowID)
}

struct RepoExplorerRowContentRevision: Equatable, Sendable {
    let presentation: RepoExplorerMaterializedRowPresentation
}

enum RepoExplorerRowLayoutClass: Equatable, Sendable {
    case sectionHeader
    case loadingSectionHeader
    case loadingRepository
    case groupHeader
    case worktree
    case pane
    case fault
}

struct RepoExplorerRowLayoutMetrics: Equatable, Sendable {
    let primaryLineHeight: CGFloat
    let metadataLineHeight: CGFloat
    let chipLineHeight: CGFloat
    let contentSpacing: CGFloat
    let verticalInset: CGFloat
    let leadingInset: CGFloat
    let trailingInset: CGFloat
    let minimumHeight: CGFloat
    let fallbackHeight: CGFloat
}

struct RepoExplorerRowLayout: Equatable, Sendable {
    let rowClass: RepoExplorerRowLayoutClass
    let metrics: RepoExplorerRowLayoutMetrics
    let requiresVisibleWidthMeasurement: Bool

    private struct Facts {
        let rowClass: RepoExplorerRowLayoutClass
        let primaryLineHeight: CGFloat
        var leadingInset: CGFloat = 0
        var trailingInset: CGFloat = 0
        var metadataLineHeight = AppStyles.Shell.Sidebar.nativeMetadataTextLineHeight
        var metadataLineCount: CGFloat = 0
        var chipLineCount: CGFloat = 0
        var verticalInset: CGFloat = 0
        var additionalVerticalPadding: CGFloat = 0
        var requiresVisibleWidthMeasurement = false
    }

    static func make(for presentation: RepoExplorerMaterializedRowPresentation) -> Self {
        let facts = facts(for: presentation)
        return Self(
            rowClass: facts.rowClass,
            metrics: metrics(facts),
            requiresVisibleWidthMeasurement: facts.requiresVisibleWidthMeasurement
        )
    }

    private static func facts(for presentation: RepoExplorerMaterializedRowPresentation) -> Facts {
        switch presentation {
        case .sectionHeader(_, let isFirstRow):
            var facts = Facts(
                rowClass: .sectionHeader,
                primaryLineHeight: AppStyles.Shell.Sidebar.nativePrimaryTextLineHeight
            )
            facts.additionalVerticalPadding =
                (isFirstRow ? 0 : AppStyles.Components.SectionSubheading.topPadding)
                + AppStyles.Components.SectionSubheading.bottomPadding
            return facts
        case .loadingSectionHeader:
            var facts = Facts(
                rowClass: .loadingSectionHeader,
                primaryLineHeight: AppStyles.Shell.Sidebar.nativeLoadingSectionContentHeight
            )
            facts.metadataLineHeight = AppStyles.Shell.Sidebar.nativeLoadingCaptionLineHeight
            facts.additionalVerticalPadding =
                AppStyles.General.Spacing.standard + AppStyles.General.Spacing.tight
            return facts
        case .loadingRepository(_, _, _, let isStatusUnavailable):
            var facts = Facts(
                rowClass: .loadingRepository,
                primaryLineHeight: AppStyles.Shell.Sidebar.nativePrimaryTextLineHeight
            )
            facts.leadingInset = AppStyles.Shell.Sidebar.nativeGroupChildRowLeadingInset
            facts.trailingInset = AppStyles.General.Spacing.loose
            facts.metadataLineHeight = AppStyles.Shell.Sidebar.nativeLoadingCaptionLineHeight
            facts.metadataLineCount = isStatusUnavailable ? 1 : 0
            facts.verticalInset = AppStyles.Shell.Sidebar.nativeRowVerticalInset
            return facts
        case .groupHeader:
            var facts = Facts(
                rowClass: .groupHeader,
                primaryLineHeight: AppStyles.Shell.Sidebar.nativeGroupTitleLineHeight
            )
            facts.verticalInset = AppStyles.Shell.Sidebar.groupRowVerticalPadding
            facts.additionalVerticalPadding =
                AppStyles.Shell.Sidebar.nativeGroupHeaderTopPadding
                + AppStyles.Shell.Sidebar.nativeGroupHeaderBottomPadding
            return facts
        case .worktree(let worktree):
            var facts = Facts(
                rowClass: .worktree,
                primaryLineHeight:
                    worktree.isMainCheckout
                    ? AppStyles.Shell.Sidebar.nativeInlineControlLineHeight
                    : AppStyles.Shell.Sidebar.nativePrimaryTextLineHeight
            )
            facts.leadingInset = AppStyles.Shell.Sidebar.nativeGroupChildRowLeadingInset
            facts.metadataLineCount = worktree.placementText.isEmpty ? 1 : 2
            facts.chipLineCount =
                SidebarGitStatusChips.hasContent(
                    branchStatus: worktree.branchStatus
                ) ? 1 : 0
            facts.verticalInset = AppStyles.Shell.Sidebar.nativeRowVerticalInset
            return facts
        case .pane(let pane):
            var facts = Facts(
                rowClass: .pane,
                primaryLineHeight: AppStyles.Shell.Sidebar.nativePrimaryTextLineHeight
            )
            facts.leadingInset = AppStyles.Shell.Sidebar.nativeGroupChildRowLeadingInset
            facts.metadataLineCount =
                (pane.secondaryLine == nil ? 0 : 1)
                + (pane.branchContextText == nil ? 0 : 1)
            facts.chipLineCount = 1
            facts.verticalInset = AppStyles.Shell.Sidebar.nativeRowVerticalInset
            return facts
        case .unassociatedPane(let pane):
            var facts = Facts(
                rowClass: .pane,
                primaryLineHeight: AppStyles.Shell.Sidebar.nativePrimaryTextLineHeight
            )
            facts.leadingInset = AppStyles.Shell.Sidebar.nativeGroupChildRowLeadingInset
            facts.metadataLineCount = pane.secondaryLine == nil ? 0 : 1
            facts.chipLineCount = 1
            facts.verticalInset = AppStyles.Shell.Sidebar.nativeRowVerticalInset
            return facts
        case .topologyFault, .unresolved:
            var facts = Facts(
                rowClass: .fault,
                primaryLineHeight: AppStyles.Shell.Sidebar.nativePrimaryTextLineHeight
            )
            facts.leadingInset = AppStyles.Shell.Sidebar.nativeGroupChildRowLeadingInset
            facts.trailingInset = AppStyles.General.Spacing.standard
            facts.metadataLineCount = 2
            facts.verticalInset = AppStyles.Shell.Sidebar.nativeRowVerticalInset
            facts.requiresVisibleWidthMeasurement = true
            return facts
        }
    }

    private static func metrics(_ facts: Facts) -> RepoExplorerRowLayoutMetrics {
        let chipLineHeight = AppStyles.Shell.Sidebar.chipLineHeight
        let contentSpacing = AppStyles.Shell.Sidebar.rowContentSpacing
        let fallbackChildSpacingCount = facts.metadataLineCount + facts.chipLineCount
        let fallbackHeight =
            facts.primaryLineHeight
            + facts.metadataLineHeight * facts.metadataLineCount
            + chipLineHeight * facts.chipLineCount
            + contentSpacing * fallbackChildSpacingCount
            + facts.verticalInset * 2
            + facts.additionalVerticalPadding

        return RepoExplorerRowLayoutMetrics(
            primaryLineHeight: facts.primaryLineHeight,
            metadataLineHeight: facts.metadataLineHeight,
            chipLineHeight: chipLineHeight,
            contentSpacing: contentSpacing,
            verticalInset: facts.verticalInset,
            leadingInset: facts.leadingInset,
            trailingInset: facts.trailingInset,
            minimumHeight: fallbackHeight,
            fallbackHeight: fallbackHeight
        )
    }
}

struct RepoExplorerMaterializedRow: Equatable, Sendable {
    let id: RepoExplorerRowID
    let contentRevision: RepoExplorerRowContentRevision
    let layout: RepoExplorerRowLayout
    let representedRepoID: UUID?
    let representedWorktreeID: UUID?

    var presentation: RepoExplorerMaterializedRowPresentation {
        contentRevision.presentation
    }
}

struct RepoExplorerMaterializationInputs: Sendable {
    let snapshot: RepoExplorerSnapshot
    let projection: RepoExplorerSidebarProjection
    let branchStatusByWorktreeID: [UUID: GitBranchStatus]
    let branchNameByWorktreeID: [UUID: String]
    let bridgeCommandResolutionByWorktreeID: [UUID: BridgePaneCommandResolution]
    let paneRowFactsByPaneID: [UUID: RepoExplorerPaneRowFacts]
}

struct RepoExplorerMaterializationSnapshot: Equatable, Sendable {
    let rows: [RepoExplorerMaterializedRow]
    let fallbackContentHeight: CGFloat
    let rowIndexByID: [RepoExplorerRowID: Int]
    let rowIDsByWorktreeID: [UUID: [RepoExplorerRowID]]
    let rowIDsByRepoID: [UUID: [RepoExplorerRowID]]

    static let empty = Self(rows: [])

    init(rows: [RepoExplorerMaterializedRow]) {
        var rowIndexByID: [RepoExplorerRowID: Int] = [:]
        var rowIDsByWorktreeID: [UUID: [RepoExplorerRowID]] = [:]
        var rowIDsByRepoID: [UUID: [RepoExplorerRowID]] = [:]
        rowIndexByID.reserveCapacity(rows.count)

        for (index, row) in rows.enumerated() {
            precondition(rowIndexByID.updateValue(index, forKey: row.id) == nil)
            if let worktreeID = row.representedWorktreeID {
                rowIDsByWorktreeID[worktreeID, default: []].append(row.id)
            }
            if let repoID = row.representedRepoID {
                rowIDsByRepoID[repoID, default: []].append(row.id)
            }
            if case .groupHeader(let group) = row.presentation {
                for repoID in group.repoIDs {
                    rowIDsByRepoID[repoID, default: []].append(row.id)
                }
            }
        }

        self.rows = rows
        fallbackContentHeight = rows.reduce(into: 0) { totalHeight, row in
            totalHeight += row.layout.metrics.fallbackHeight
        }
        self.rowIndexByID = rowIndexByID
        self.rowIDsByWorktreeID = rowIDsByWorktreeID
        self.rowIDsByRepoID = rowIDsByRepoID
    }

    func row(id: RepoExplorerRowID) -> RepoExplorerMaterializedRow? {
        rowIndexByID[id].map { rows[$0] }
    }

    static func build(
        rowIndex: RepoExplorerRowIndex,
        inputs: RepoExplorerMaterializationInputs
    ) -> Self {
        let rows = rowIndex.entries.enumerated().map { index, entry in
            let presentation = presentation(
                for: entry,
                index: index,
                rowIndex: rowIndex,
                inputs: inputs
            )
            let representedIdentities = representedIdentities(for: presentation)
            return RepoExplorerMaterializedRow(
                id: entry.id,
                contentRevision: RepoExplorerRowContentRevision(presentation: presentation),
                layout: RepoExplorerRowLayout.make(for: presentation),
                representedRepoID: representedIdentities.repoID,
                representedWorktreeID: representedIdentities.worktreeID
            )
        }
        return Self(rows: rows)
    }
}

extension RepoExplorerMaterializationSnapshot {
    private static func presentation(
        for entry: RepoExplorerListEntry,
        index: Int,
        rowIndex: RepoExplorerRowIndex,
        inputs: RepoExplorerMaterializationInputs
    ) -> RepoExplorerMaterializedRowPresentation {
        switch entry {
        case .sectionHeader(let kind):
            return .sectionHeader(kind: kind, isFirstRow: index == 0)
        case .loadingSectionHeader(let kind):
            let state =
                inputs.projection.sections.first(where: { $0.kind == kind })?
                .loadingState(enrichmentByRepoId: inputs.snapshot.repoEnrichmentSnapshotByRepoId)
                ?? .scanning
            return .loadingSectionHeader(kind: kind, state: state)
        case .loadingRepoRow(let section, let repo):
            let isStatusUnavailable: Bool
            if case .statusUnavailable = inputs.snapshot.repoEnrichmentSnapshotByRepoId[repo.id] {
                isStatusUnavailable = true
            } else {
                isStatusUnavailable = false
            }
            return .loadingRepository(
                section: section,
                repoID: repo.id,
                name: repo.name,
                isStatusUnavailable: isStatusUnavailable
            )
        case .resolvedGroupHeader(let group):
            let semanticRepo = semanticRepo(for: group, groupingMode: inputs.snapshot.groupingMode)
            let paneDestinations =
                inputs.snapshot.groupingMode != .tab && group.repos.count == 1
                ? inputs.projection.paneDestinationsByRepoId[group.repos[0].id] ?? []
                : []
            return .groupHeader(
                RepoExplorerMaterializedGroupHeaderPresentation(
                    groupID: group.id,
                    icon: inputs.snapshot.groupingMode == .tab ? .tabGroup : .repo,
                    title: group.repoTitle,
                    organizationName: group.organizationName,
                    colorHex: RepoPresentationColoring.sourceGroupColorHex(for: group),
                    isExpanded: rowIndex.isGroupExpanded(group.id),
                    repoIDs: group.repos.map(\.id),
                    semanticRepoPath: semanticRepo?.repoPath,
                    paneDestinations: paneDestinations
                )
            )
        case .resolvedWorktreeRow(let groupID, let repoID, let worktreeID, let rowID):
            guard
                let context = rowIndex.resolve(
                    groupId: groupID,
                    repoId: repoID,
                    worktreeId: worktreeID,
                    rowId: rowID
                )
            else { return .unresolved(entry.id) }
            return .worktree(
                RepoExplorerMaterializedWorktreePresentation(
                    rowID: rowID,
                    groupID: groupID,
                    repo: context.repo,
                    worktree: context.worktree,
                    checkoutTitle: checkoutTitle(for: context.worktree, in: context.repo),
                    isMainCheckout: isMainCheckout(context.worktree, in: context.repo),
                    checkoutColorHex: context.checkoutColorHex,
                    placementText: context.placementContext?.displayText ?? "",
                    branchStatus: inputs.branchStatusByWorktreeID[worktreeID] ?? .unknown,
                    branchName: inputs.branchNameByWorktreeID[worktreeID] ?? "detached HEAD",
                    bridgeCommandResolution: inputs.bridgeCommandResolutionByWorktreeID[worktreeID]
                        ?? .create,
                    paneDestinations: inputs.projection.paneDestinationsByWorktreeId[worktreeID] ?? []
                )
            )
        case .resolvedPaneRow(let groupID, let identity, let rowID):
            guard
                let context = rowIndex.resolvePane(
                    groupId: groupID,
                    repoId: identity.repoId,
                    paneId: identity.paneId,
                    rowId: rowID
                )
            else { return .unresolved(entry.id) }
            return .pane(context.row)
        case .unassociatedPaneRow(let destination):
            let paneFacts = inputs.paneRowFactsByPaneID[destination.paneId]
            return .unassociatedPane(
                RepoExplorerUnassociatedPanePresentation(
                    destination: destination,
                    primaryText:
                        "Pane \(destination.paneIndexInTab + 1) · "
                        + (paneFacts?.sidebarTerminalTitle ?? "zsh"),
                    secondaryLine: paneFacts?.secondaryLine,
                    recencyText: paneFacts?.recencyText ?? "Now",
                    recencyTier: paneFacts?.recencyTier ?? .strongBlue,
                    isActive: paneFacts?.isActive ?? false,
                    isDrawerPane: paneFacts?.isDrawerPane ?? false
                )
            )
        case .topologyFault(let fault):
            return .topologyFault(fault)
        }
    }

    private static func representedIdentities(
        for presentation: RepoExplorerMaterializedRowPresentation
    ) -> (repoID: UUID?, worktreeID: UUID?) {
        switch presentation {
        case .loadingRepository(_, let repoID, _, _):
            return (repoID, nil)
        case .worktree(let worktree):
            return (worktree.repo.id, worktree.worktree.id)
        case .pane(let pane):
            return (pane.repoId, pane.worktreeId)
        case .sectionHeader, .loadingSectionHeader, .groupHeader, .unassociatedPane,
            .topologyFault, .unresolved:
            return (nil, nil)
        }
    }

    private static func semanticRepo(
        for group: RepoPresentationGroup,
        groupingMode: RepoExplorerGroupingMode
    ) -> RepoPresentationItem? {
        guard groupingMode == .repo || groupingMode == .pane, group.repos.count == 1 else {
            return nil
        }
        return group.repos[0]
    }

    private static func checkoutTitle(
        for worktree: Worktree,
        in repo: RepoPresentationItem
    ) -> String {
        let folderName = worktree.path.lastPathComponent
        return folderName.isEmpty ? repo.name : folderName
    }

    private static func isMainCheckout(
        _ worktree: Worktree,
        in repo: RepoPresentationItem
    ) -> Bool {
        worktree.isMainWorktree
            || worktree.path.standardizedFileURL.path == repo.repoPath.standardizedFileURL.path
    }
}

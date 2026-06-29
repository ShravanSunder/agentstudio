import SwiftUI

struct SidebarHeaderLayoutPolicy: Equatable {
    let rowSpacing: CGFloat
    let searchActionSpacing: CGFloat
    let contentPadding: CGFloat

    static let standard = Self(
        rowSpacing: AppStyles.General.Spacing.tight,
        searchActionSpacing: AppStyles.General.Spacing.standard,
        contentPadding: AppStyles.Shell.Sidebar.Header.contentPadding
    )
}

struct SidebarHeaderLayout<SearchRow: View, PrimaryAction: View, ToolbarRow: View, StatusRow: View>: View {
    static var policy: SidebarHeaderLayoutPolicy {
        .standard
    }

    private let searchRow: SearchRow
    private let primaryAction: PrimaryAction
    private let toolbarRow: ToolbarRow
    private let statusRow: StatusRow
    private let showsToolbarRow: Bool
    private let showsStatusRow: Bool

    init(
        @ViewBuilder searchRow: () -> SearchRow,
        @ViewBuilder primaryAction: () -> PrimaryAction,
        @ViewBuilder toolbarRow: () -> ToolbarRow,
        @ViewBuilder statusRow: () -> StatusRow,
        showsToolbarRow: Bool = true,
        showsStatusRow: Bool = true
    ) {
        self.searchRow = searchRow()
        self.primaryAction = primaryAction()
        self.toolbarRow = toolbarRow()
        self.statusRow = statusRow()
        self.showsToolbarRow = showsToolbarRow
        self.showsStatusRow = showsStatusRow
    }

    var body: some View {
        let policy = Self.policy
        VStack(alignment: .leading, spacing: policy.rowSpacing) {
            HStack(spacing: policy.searchActionSpacing) {
                searchRow
                    .layoutPriority(0)

                primaryAction
                    .fixedSize()
                    .layoutPriority(1)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)

            if showsToolbarRow {
                toolbarRow
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }

            if showsStatusRow {
                statusRow
            }
        }
        .padding(policy.contentPadding)
    }
}

extension SidebarHeaderLayout where PrimaryAction == EmptyView {
    init(
        @ViewBuilder searchRow: () -> SearchRow,
        @ViewBuilder toolbarRow: () -> ToolbarRow,
        @ViewBuilder statusRow: () -> StatusRow
    ) {
        self.init(
            searchRow: searchRow,
            primaryAction: { EmptyView() },
            toolbarRow: toolbarRow,
            statusRow: statusRow
        )
    }
}

extension SidebarHeaderLayout where ToolbarRow == EmptyView, StatusRow == EmptyView {
    init(
        @ViewBuilder searchRow: () -> SearchRow,
        @ViewBuilder primaryAction: () -> PrimaryAction
    ) {
        self.init(
            searchRow: searchRow,
            primaryAction: primaryAction,
            toolbarRow: { EmptyView() },
            statusRow: { EmptyView() },
            showsToolbarRow: false,
            showsStatusRow: false
        )
    }
}

extension SidebarHeaderLayout where PrimaryAction == EmptyView, ToolbarRow == EmptyView, StatusRow == EmptyView {
    init(@ViewBuilder searchRow: () -> SearchRow) {
        self.init(
            searchRow: searchRow,
            primaryAction: { EmptyView() },
            toolbarRow: { EmptyView() },
            statusRow: { EmptyView() },
            showsToolbarRow: false,
            showsStatusRow: false
        )
    }
}

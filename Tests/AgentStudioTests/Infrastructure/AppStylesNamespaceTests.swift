import SwiftUI
import Testing

@testable import AgentStudio

@Suite("AppStyles namespace")
struct AppStylesNamespaceTests {
    @Test("general namespace keeps shared spacing, typography, and pane geometry tokens")
    func generalNamespaceKeepsSharedTokens() {
        #expect(AppStyles.General.Spacing.tight == 4)
        #expect(AppStyles.General.Spacing.loose == 8)
        #expect(AppStyles.General.Typography.textBase == 13)
        #expect(AppStyles.General.Layout.paneGap == 1)
    }

    @Test("shell namespace owns sidebar, pane chrome, and management layer tokens")
    func shellNamespaceOwnsSidebarPaneChromeAndManagementLayerTokens() {
        #expect(AppStyles.Shell.Sidebar.rowVerticalInset == 6)
        #expect(AppStyles.Shell.Sidebar.groupIconSize == 14)
        #expect(AppStyles.Shell.Sidebar.groupIconColumnWidth == 18)
        #expect(AppStyles.Shell.Sidebar.groupIconTitleSpacing == 6)
        #expect(AppStyles.Shell.Sidebar.sectionHeaderChevronColumnWidth == 13)
        #expect(AppStyles.Shell.Sidebar.sectionHeaderChevronLabelSpacing == 4)
        #expect(AppStyles.Shell.PaneChrome.inactivePaneDimmingDepth == 120)
        #expect(AppStyles.Shell.ManagementLayer.actionSize == 28)
    }

    @Test("shell namespace owns compact titlebar density tokens")
    func shellNamespaceOwnsCompactTitlebarDensityTokens() {
        #expect(AppStyles.Shell.TabBar.height == 40)
        #expect(AppStyles.Shell.TabBar.tabPillHeight == 32)
        #expect(AppStyles.Shell.Chrome.windowDragRegionHeight == 8)
        #expect(AppStyles.Shell.Chrome.ToolbarButton.size == 28)
        #expect(AppStyles.Shell.Chrome.ToolbarButton.iconSize == 12)
        #expect(AppStyles.Shell.Titlebar.iconSize == 14)
        #expect(AppStyles.Shell.Titlebar.buttonSize == 28)
        #expect(AppStyles.Shell.Titlebar.buttonSpacing == 4)
    }

    @Test("workspace focus namespaces own content-specific transient surfaces")
    func workspaceFocusNamespacesOwnContentSpecificTokens() {
        #expect(AppStyles.WorkspaceFocus.Terminal.startupOverlayPadding == 28)
        #expect(AppStyles.WorkspaceFocus.Terminal.errorOverlayCornerRadius == 12)
        #expect(AppStyles.WorkspaceFocus.Webview.navigationFieldCornerRadius == 6)
    }

    @Test("command bar namespace owns panel chrome and row styling")
    func commandBarNamespaceOwnsPanelChromeAndRowStyling() {
        #expect(AppStyles.CommandBar.Footer.separatorOpacity == 0.15)
        #expect(AppStyles.CommandBar.Footer.rowHeight == 16)
        #expect(AppStyles.CommandBar.Rows.groupHeaderFontSize == AppStyles.General.Typography.textBase)
        #expect(AppStyles.CommandBar.Rows.groupHeaderOpacity == 0.70)
        #expect(AppStyles.CommandBar.Rows.selectedRowTitleOpacity == 0.95)
        #expect(AppStyles.CommandBar.Rows.trailingMetadataOpacity == 0.68)
        #expect(AppStyles.CommandBar.Rows.scopePillFontSize == AppStyles.General.Typography.textXs)
        #expect(AppStyles.CommandBar.Rows.statusContextOpacity == 0.50)
        #expect(AppStyles.CommandBar.Rows.selectedRowCornerRadius == 6)
        #expect(AppStyles.CommandBar.Panel.horizontalPadding == 12)
    }
}

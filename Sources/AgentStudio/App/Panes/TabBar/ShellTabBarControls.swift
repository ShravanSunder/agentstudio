import AgentStudioCore
import AgentStudioInboxNotification
import AgentStudioInfrastructure
import AgentStudioSharedComponents
import SwiftUI

struct ShellTabBarCommandPresentation: Equatable {
    let command: AppCommand
    let controlToolTip: String
    let isEnabled: Bool

    private let dispatcher: any AppCommandDispatching

    @MainActor
    init?(
        command: AppCommand,
        commandContext: CommandContext,
        dispatcher: any AppCommandDispatching = AppCommandDispatcher.shared
    ) {
        self.init(
            definition: AppCommandDispatcher.shared.definition(for: command),
            commandContext: commandContext,
            dispatcher: dispatcher
        )
    }

    @MainActor
    init?(
        definition: AppCommandSpec,
        commandContext: CommandContext,
        dispatcher: any AppCommandDispatching = AppCommandDispatcher.shared
    ) {
        guard
            definition.shouldPresent(
                AppCommandPresentationQuery(
                    surface: .toolbar(.app),
                    subject: .contextual(commandContext)
                )
            )
        else {
            return nil
        }

        self.command = definition.command
        self.controlToolTip = definition.controlToolTip
        self.isEnabled = dispatcher.canDispatch(definition.command)
        self.dispatcher = dispatcher
    }

    @MainActor
    func perform() {
        guard dispatcher.canDispatch(command) else { return }
        dispatcher.dispatch(command)
    }

    static func == (
        lhs: Self,
        rhs: Self
    ) -> Bool {
        lhs.command == rhs.command
            && lhs.controlToolTip == rhs.controlToolTip
            && lhs.isEnabled == rhs.isEnabled
    }
}

@MainActor
enum ShellTabBarCommandContext {
    static func current() -> CommandContext {
        let workspaceTab = atom(\.workspaceTab)
        let workspacePane = atom(\.workspacePane)
        let focusedPane = atom(\.workspaceFocusedPane).resolve(
            workspaceTab: workspaceTab,
            workspacePane: workspacePane,
            requestedOwner: atom(\.workspaceFocusOwner).owner
        )
        return atom(\.commandContext).currentContext(
            workspaceTab: workspaceTab,
            workspacePane: workspacePane,
            focusedPane: focusedPane,
            workspacePanePresentation: atom(\.workspacePanePresentation)
        )
    }
}

struct SidebarSurfaceTabBarControls: View {
    let inboxAtom: InboxNotificationAtom

    private var sidebarState: WorkspaceSidebarState {
        atom(\.workspaceSidebarState)
    }

    private var isSidebarOpen: Bool {
        !sidebarState.sidebarCollapsed
    }

    var body: some View {
        let commandContext = ShellTabBarCommandContext.current()

        HStack(spacing: AppStyles.Shell.Chrome.SidebarNav.iconSpacing) {
            if let presentation = ShellTabBarCommandPresentation(
                command: .showWorktreeSidebar,
                commandContext: commandContext
            ) {
                SidebarSurfaceTabBarButton(
                    presentation: presentation,
                    symbolName: "square.stack.3d.down.right",
                    selectedSymbolName: "square.stack.3d.down.right.fill",
                    isSelected: isSidebarOpen && sidebarState.sidebarSurface == .repos
                )
            }

            if let presentation = ShellTabBarCommandPresentation(
                command: .showInboxNotifications,
                commandContext: commandContext
            ) {
                SidebarSurfaceTabBarButton(
                    presentation: presentation,
                    symbolName: "bell",
                    selectedSymbolName: "bell.fill",
                    isSelected: isSidebarOpen && sidebarState.sidebarSurface == .inbox,
                    badgeCount: inboxAtom.globalRollUpAlertCount
                )
            }
        }
    }
}

private struct SidebarSurfaceTabBarButton: View {
    let presentation: ShellTabBarCommandPresentation
    let symbolName: String
    let selectedSymbolName: String
    let isSelected: Bool
    var badgeCount = 0

    @State private var isHovered = false

    private var command: AppCommand {
        presentation.command
    }

    var body: some View {
        Button {
            presentation.perform()
        } label: {
            ChromeToolbarButtonLabel(
                symbolName: symbolName,
                selectedSymbolName: selectedSymbolName,
                isSelected: isSelected,
                isHovered: isHovered,
                badgeText: badgeCount > 0 ? InboxToolbarUnreadBadgeText.text(for: badgeCount) : nil,
                showsBackground: false
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .disabled(!presentation.isEnabled)
        .help(presentation.controlToolTip)
    }
}

struct WatchFolderTabBarMenu: View {
    @State private var isHovered = false

    @ViewBuilder
    var body: some View {
        if let presentation = ShellTabBarCommandPresentation(
            command: .watchFolder,
            commandContext: ShellTabBarCommandContext.current()
        ) {
            Button {
                presentation.perform()
            } label: {
                ChromeToolbarButtonLabel(
                    symbolName: "folder.badge.plus",
                    isHovered: isHovered
                )
            }
            .buttonStyle(.plain)
            .onHover { isHovered = $0 }
            .disabled(!presentation.isEnabled)
            .help(presentation.controlToolTip)
        }
    }
}

/// Management layer toggle in the tab bar. Blue accent when active, standard hover otherwise.
struct TabBarManagementLayerButton: View {
    private var isManagementLayerActive: Bool {
        atom(\.managementLayer).isActive
    }
    @State private var isHovered = false

    @ViewBuilder
    var body: some View {
        if let presentation = ShellTabBarCommandPresentation(
            command: .toggleManagementLayer,
            commandContext: ShellTabBarCommandContext.current()
        ) {
            Button(action: presentation.perform) {
                ChromeToolbarButtonLabel(
                    symbolName: "rectangle.split.2x2",
                    selectedSymbolName: "rectangle.split.2x2.fill",
                    isSelected: isManagementLayerActive,
                    isHovered: isHovered
                )
            }
            .buttonStyle(.plain)
            .onHover { isHovered = $0 }
            .disabled(!presentation.isEnabled)
            .help(presentation.controlToolTip)
        }
    }
}

/// Circular "+" button for creating a new tab.
/// Click = empty terminal (existing behavior). Right-click = menu with options.
struct NewTabButton: View {
    let onAdd: () -> Void
    let onOpenRepoInTab: (() -> Void)?
    @State private var isHovered = false

    @ViewBuilder
    var body: some View {
        if let presentation = ShellTabBarCommandPresentation(
            command: .newTab,
            commandContext: ShellTabBarCommandContext.current()
        ) {
            Button(action: presentation.perform) {
                ChromeToolbarButtonLabel(
                    symbolName: "plus",
                    isHovered: isHovered
                )
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button(LocalActionSpec.emptyTerminal.actionSpec.label) { onAdd() }
                Divider()
                if let onOpenRepoInTab {
                    Button(LocalActionSpec.openRepoWorktree.actionSpec.label) {
                        onOpenRepoInTab()
                    }
                }
            }
            .onHover { isHovered = $0 }
            .disabled(!presentation.isEnabled)
            .help(presentation.controlToolTip)
        }
    }
}

struct SidebarNavDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(AppStyles.General.Fill.hover))
            .frame(width: 1, height: AppStyles.Shell.Chrome.dividerHeight)
            .padding(.leading, AppStyles.Shell.Chrome.SidebarNav.dividerLeadingPadding)
            .padding(.trailing, AppStyles.Shell.Chrome.SidebarNav.dividerTrailingPadding)
    }
}

struct TabBarDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(AppStyles.General.Fill.hover))
            .frame(width: 1, height: AppStyles.Shell.Chrome.dividerHeight)
            .padding(.horizontal, AppStyles.Shell.Chrome.dividerHorizontalPadding)
    }
}

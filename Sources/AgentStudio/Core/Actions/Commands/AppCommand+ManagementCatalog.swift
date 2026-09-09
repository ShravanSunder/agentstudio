extension AppCommand {
    func toggleManagementLayerDefinition() -> AppCommandSpec {
        windowDefinition(
            shortcut: .toggleManagementLayer,
            label: "Manage Workspace",
            icon: .system(.rectangleSplit2x2),
            helpText: "Toggle workspace management mode",
            surfacePolicy: .exposed([.commandBar, .toolbar(.app)]),
            targeting: .contextual
        )
    }

    func managementLayerFocusLeftDefinition() -> AppCommandSpec {
        managementDefinition(
            shortcut: .managementLayerFocusLeft,
            label: "Management Focus Left",
            icon: .system(.arrowLeft),
            helpText: "Move focus left in management mode"
        )
    }

    func managementLayerFocusRightDefinition() -> AppCommandSpec {
        managementDefinition(
            shortcut: .managementLayerFocusRight,
            label: "Management Focus Right",
            icon: .system(.arrowRight),
            helpText: "Move focus right in management mode"
        )
    }

    func managementLayerEnterDrawerDefinition() -> AppCommandSpec {
        managementDefinition(
            shortcut: .managementLayerEnterDrawer,
            label: "Management Enter Drawer",
            icon: .system(.arrowDown),
            helpText: "Enter or expand the current drawer in management mode"
        )
    }

    func managementLayerExitDrawerDefinition() -> AppCommandSpec {
        managementDefinition(
            shortcut: .managementLayerExitDrawer,
            label: "Management Exit Drawer",
            icon: .system(.arrowUp),
            helpText: "Collapse the current drawer in management mode"
        )
    }

    func managementLayerOpenDrawerDefinition() -> AppCommandSpec {
        managementDefinition(
            shortcut: .managementLayerOpenDrawer,
            label: "Management Open Drawer",
            icon: .system(.rectangleExpandVertical),
            helpText: "Open the current drawer in management mode"
        )
    }

    func managementLayerCreateTerminalDefinition() -> AppCommandSpec {
        managementDefinition(
            shortcut: .managementLayerCreateTerminal,
            label: "Management Create Terminal",
            icon: .system(.plusSquare),
            helpText: "Create a terminal in the current management-mode context"
        )
    }

    func managementLayerCreateBrowserDefinition() -> AppCommandSpec {
        managementDefinition(
            shortcut: .managementLayerCreateBrowser,
            label: "Management Create Browser",
            icon: .system(.globe),
            helpText: "Create a browser in the current management-mode context"
        )
    }

    func managementLayerExitDefinition() -> AppCommandSpec {
        managementDefinition(
            shortcut: .managementLayerExit,
            label: "Management Exit Mode",
            icon: .system(.rectangleSplit2x2Fill),
            helpText: "Exit management mode"
        )
    }
}

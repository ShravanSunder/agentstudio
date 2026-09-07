extension AppCommand {
    func showInboxNotificationsDefinition() -> AppCommandSpec {
        retiredGlobalInboxDefinition()
    }

    func toggleInboxNotificationSortDefinition() -> AppCommandSpec {
        retiredInboxDefinition(
            label: "Toggle Inbox Sort Order",
            icon: .system(.arrowUp),
            helpText: "The notification inbox is retired"
        )
    }

    func clearReadInboxNotificationsDefinition() -> AppCommandSpec {
        retiredInboxDefinition(
            label: "Clear Read Inbox Notifications",
            icon: .system(.deleteLeft),
            helpText: "The notification inbox is retired"
        )
    }

    func clearAllInboxNotificationsDefinition() -> AppCommandSpec {
        retiredInboxDefinition(
            label: "Clear All Inbox Notifications",
            icon: .system(.deleteLeft),
            helpText: "The notification inbox is retired"
        )
    }

    func showPaneInboxNotificationsDefinition() -> AppCommandSpec {
        retiredInboxDefinition(
            label: "Toggle Pane Inbox",
            icon: .system(.bellBadge),
            helpText: "The pane notification inbox is retired"
        )
    }

    func clearPaneInboxNotificationsDefinition() -> AppCommandSpec {
        retiredInboxDefinition(
            label: "Clear Pane Inbox",
            icon: .system(.deleteLeft),
            helpText: "The pane notification inbox is retired"
        )
    }

    func setInboxGroupingTabDefinition() -> AppCommandSpec {
        retiredInboxDefinition(
            label: "Tab",
            icon: .system(.rectangleStack),
            helpText: "The notification inbox is retired"
        )
    }

    func setInboxGroupingRepoDefinition() -> AppCommandSpec {
        retiredInboxDefinition(
            label: "Repo",
            icon: .system(.folder),
            helpText: "The notification inbox is retired"
        )
    }

    func setInboxGroupingPaneDefinition() -> AppCommandSpec {
        retiredInboxDefinition(
            label: "Pane",
            icon: .system(.rectangleSplit2x1),
            helpText: "The notification inbox is retired"
        )
    }

    func setInboxGroupingNoneDefinition() -> AppCommandSpec {
        retiredInboxDefinition(
            label: "None",
            icon: .system(.line3Horizontal),
            helpText: "The notification inbox is retired"
        )
    }

    func setInboxRowStateFilterDefinition() -> AppCommandSpec {
        retiredInboxDefinition(
            label: "Set Inbox Row Filter",
            icon: .system(.line3Horizontal),
            helpText: "The notification inbox is retired"
        )
    }

    func setInboxContentModeDefinition() -> AppCommandSpec {
        retiredInboxDefinition(
            label: "Set Inbox Content Mode",
            icon: .system(.line3Horizontal),
            helpText: "The notification inbox is retired"
        )
    }
}

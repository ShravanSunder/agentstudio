import Foundation

enum IPCCommandArgumentSchemas {
    static let workspaceWindow = IPCObjectField(
        name: "workspaceWindowId",
        description: "Explicit owning workspace window UUID",
        schema: IPCSchemaScalars.uuid
    )

    static func object(
        kind: IPCCommandArgumentVariant,
        fields: [IPCObjectField] = []
    ) -> IPCJSONSchema {
        .object(fields: [kindField(kind)] + fields)
    }

    static func uuid(_ name: String, description: String) -> IPCObjectField {
        .init(name: name, description: description, schema: IPCSchemaScalars.uuid)
    }

    static func paneSelector(_ name: String, description: String) -> IPCObjectField {
        .init(name: name, description: description, schema: IPCRequestSchemaFields.paneSelector)
    }

    static func string(_ name: String, description: String) -> IPCObjectField {
        .init(name: name, description: description, schema: .string())
    }

    static func optionalString(_ name: String, description: String) -> IPCObjectField {
        .optional(name, description: description, schema: .string())
    }

    private static func kindField(_ kind: IPCCommandArgumentVariant) -> IPCObjectField {
        .init(
            name: "kind",
            description: "Closed command argument variant",
            schema: .string(allowedValues: [kind.rawValue])
        )
    }
}

extension IPCWorkspaceWindowCommandArguments {
    static func argumentSchema() throws -> IPCJSONSchema {
        IPCCommandArgumentSchemas.object(kind: .workspaceWindow, fields: [IPCCommandArgumentSchemas.workspaceWindow])
    }
}

extension IPCTabCommandArguments {
    static func argumentSchema() throws -> IPCJSONSchema {
        IPCCommandArgumentSchemas.object(
            kind: .tab,
            fields: [
                IPCCommandArgumentSchemas.workspaceWindow,
                IPCCommandArgumentSchemas.uuid("tabId", description: "Explicit target tab UUID"),
            ])
    }
}

extension IPCRenamedTabCommandArguments {
    static func argumentSchema() throws -> IPCJSONSchema {
        IPCCommandArgumentSchemas.object(
            kind: .renamedTab,
            fields: [
                IPCCommandArgumentSchemas.workspaceWindow,
                IPCCommandArgumentSchemas.uuid("tabId", description: "Tab UUID to rename"),
                IPCCommandArgumentSchemas.string("name", description: "Requested tab name"),
            ])
    }
}

extension IPCNewTabCommandArguments {
    static func argumentSchema() throws -> IPCJSONSchema {
        IPCCommandArgumentSchemas.object(
            kind: .newTab,
            fields: [
                IPCCommandArgumentSchemas.workspaceWindow,
                IPCCommandArgumentSchemas.optionalString(
                    "launchDirectory",
                    description: "Explicit launch directory; omission uses first watched folder then home"
                ),
            ])
    }
}

extension IPCTabAnchorCommandArguments {
    static func argumentSchema() throws -> IPCJSONSchema {
        IPCCommandArgumentSchemas.object(
            kind: .tabAnchor,
            fields: [
                IPCCommandArgumentSchemas.workspaceWindow,
                IPCCommandArgumentSchemas.uuid("anchorTabId", description: "Source tab UUID for relative selection"),
            ])
    }
}

extension IPCPaneCommandArguments {
    static func argumentSchema() throws -> IPCJSONSchema {
        IPCCommandArgumentSchemas.object(
            kind: .pane,
            fields: [
                IPCCommandArgumentSchemas.workspaceWindow,
                IPCCommandArgumentSchemas.paneSelector("paneSelector", description: "Target pane selector"),
            ])
    }
}

extension IPCSourcePaneCommandArguments {
    static func argumentSchema() throws -> IPCJSONSchema {
        IPCCommandArgumentSchemas.object(
            kind: .sourcePane,
            fields: [
                IPCCommandArgumentSchemas.workspaceWindow,
                IPCCommandArgumentSchemas.paneSelector(
                    "sourcePaneSelector",
                    description: "Source pane selector for relative focus"
                ),
            ])
    }
}

extension IPCMovePaneToTabCommandArguments {
    static func argumentSchema() throws -> IPCJSONSchema {
        IPCCommandArgumentSchemas.object(
            kind: .movePaneToTab,
            fields: [
                IPCCommandArgumentSchemas.workspaceWindow,
                IPCCommandArgumentSchemas.paneSelector("sourcePaneSelector", description: "Pane selector to move"),
                IPCCommandArgumentSchemas.uuid("destinationTabId", description: "Destination tab UUID"),
            ])
    }
}

extension IPCArrangementCommandArguments {
    static func argumentSchema() throws -> IPCJSONSchema {
        IPCCommandArgumentSchemas.object(
            kind: .arrangement,
            fields: [
                IPCCommandArgumentSchemas.workspaceWindow,
                IPCCommandArgumentSchemas.uuid("tabId", description: "Tab UUID owning the arrangement"),
                IPCCommandArgumentSchemas.uuid("arrangementId", description: "Target arrangement UUID"),
            ])
    }
}

extension IPCNewArrangementCommandArguments {
    static func argumentSchema() throws -> IPCJSONSchema {
        IPCCommandArgumentSchemas.object(
            kind: .newArrangement,
            fields: [
                IPCCommandArgumentSchemas.workspaceWindow,
                IPCCommandArgumentSchemas.uuid("tabId", description: "Tab UUID receiving the arrangement"),
                IPCCommandArgumentSchemas.string("name", description: "Requested arrangement name"),
            ])
    }
}

extension IPCRenamedArrangementCommandArguments {
    static func argumentSchema() throws -> IPCJSONSchema {
        IPCCommandArgumentSchemas.object(
            kind: .renamedArrangement,
            fields: [
                IPCCommandArgumentSchemas.workspaceWindow,
                IPCCommandArgumentSchemas.uuid("tabId", description: "Tab UUID owning the arrangement"),
                IPCCommandArgumentSchemas.uuid("arrangementId", description: "Arrangement UUID to rename"),
                IPCCommandArgumentSchemas.string("name", description: "Requested arrangement name"),
            ])
    }
}

extension IPCDrawerParentCommandArguments {
    static func argumentSchema() throws -> IPCJSONSchema {
        IPCCommandArgumentSchemas.object(
            kind: .drawerParent,
            fields: [
                IPCCommandArgumentSchemas.workspaceWindow,
                IPCCommandArgumentSchemas.paneSelector(
                    "parentPaneSelector",
                    description: "Main pane selector owning the drawer"
                ),
            ])
    }
}

extension IPCDrawerSourcePaneCommandArguments {
    static func argumentSchema() throws -> IPCJSONSchema {
        IPCCommandArgumentSchemas.object(
            kind: .drawerSourcePane,
            fields: [
                IPCCommandArgumentSchemas.workspaceWindow,
                IPCCommandArgumentSchemas.paneSelector(
                    "parentPaneSelector",
                    description: "Main pane selector owning the drawer"
                ),
                IPCCommandArgumentSchemas.paneSelector(
                    "sourceDrawerPaneSelector",
                    description: "Source drawer pane selector for relative focus"
                ),
            ])
    }
}

extension IPCDrawerPaneCommandArguments {
    static func argumentSchema() throws -> IPCJSONSchema {
        IPCCommandArgumentSchemas.object(
            kind: .drawerPane,
            fields: [
                IPCCommandArgumentSchemas.workspaceWindow,
                IPCCommandArgumentSchemas.paneSelector(
                    "parentPaneSelector",
                    description: "Main pane selector owning the drawer"
                ),
                IPCCommandArgumentSchemas.paneSelector(
                    "drawerPaneSelector", description: "Target drawer pane selector"),
            ])
    }
}

extension IPCDetachedDrawerPaneCommandArguments {
    static func argumentSchema() throws -> IPCJSONSchema {
        IPCCommandArgumentSchemas.object(
            kind: .detachedDrawerPane,
            fields: [
                IPCCommandArgumentSchemas.workspaceWindow,
                IPCCommandArgumentSchemas.paneSelector(
                    "drawerPaneSelector", description: "Drawer pane selector to detach"),
            ])
    }
}

extension IPCDirectoryCommandArguments {
    static func argumentSchema() throws -> IPCJSONSchema {
        IPCCommandArgumentSchemas.object(
            kind: .directory,
            fields: [
                IPCCommandArgumentSchemas.workspaceWindow,
                IPCCommandArgumentSchemas.string("directoryPath", description: "Directory path to watch"),
            ])
    }
}

extension IPCRepositoryCommandArguments {
    static func argumentSchema() throws -> IPCJSONSchema {
        IPCCommandArgumentSchemas.object(
            kind: .repository,
            fields: [
                IPCCommandArgumentSchemas.uuid("repoId", description: "Target repository UUID")
            ])
    }
}

extension IPCStandalonePaneCommandArguments {
    static func argumentSchema() throws -> IPCJSONSchema {
        IPCCommandArgumentSchemas.object(
            kind: .standalonePane,
            fields: [
                IPCCommandArgumentSchemas.paneSelector("paneSelector", description: "Target pane selector")
            ])
    }
}

extension IPCWorktreeCommandArguments {
    static func argumentSchema() throws -> IPCJSONSchema {
        IPCCommandArgumentSchemas.object(
            kind: .worktree,
            fields: [
                IPCCommandArgumentSchemas.workspaceWindow,
                IPCCommandArgumentSchemas.uuid("worktreeId", description: "Target worktree UUID"),
            ])
    }
}

extension IPCWorktreeInPaneCommandArguments {
    static func argumentSchema() throws -> IPCJSONSchema {
        IPCCommandArgumentSchemas.object(
            kind: .worktreeInPane,
            fields: [
                IPCCommandArgumentSchemas.workspaceWindow,
                IPCCommandArgumentSchemas.uuid("worktreeId", description: "Worktree UUID to open"),
                IPCCommandArgumentSchemas.paneSelector(
                    "targetPaneSelector",
                    description: "Pane selector providing the split anchor"
                ),
            ])
    }
}

extension IPCTerminalFromWorktreeCommandArguments {
    static func argumentSchema() throws -> IPCJSONSchema {
        IPCCommandArgumentSchemas.object(
            kind: .terminalFromWorktree,
            fields: [
                IPCCommandArgumentSchemas.workspaceWindow,
                IPCCommandArgumentSchemas.uuid("worktreeId", description: "Source worktree UUID"),
                IPCCommandArgumentSchemas.optionalString(
                    "launchDirectory",
                    description: "CWD override; omission uses the selected worktree path"
                ),
                IPCCommandArgumentSchemas.optionalString(
                    "title",
                    description: "Title override; omission lets the creation owner derive the title"
                ),
            ])
    }
}

extension IPCTerminalFromPaneCommandArguments {
    static func argumentSchema() throws -> IPCJSONSchema {
        IPCCommandArgumentSchemas.object(
            kind: .terminalFromPane,
            fields: [
                IPCCommandArgumentSchemas.workspaceWindow,
                IPCCommandArgumentSchemas.paneSelector(
                    "sourcePaneSelector",
                    description: "Source pane selector providing location context"
                ),
                IPCCommandArgumentSchemas.optionalString(
                    "launchDirectory",
                    description: "CWD override; omission uses the source pane admitted location"
                ),
                IPCCommandArgumentSchemas.optionalString(
                    "title",
                    description: "Title override; omission lets the creation owner derive the title"
                ),
            ])
    }
}

extension IPCManagementFromMainPaneCommandArguments {
    static func argumentSchema() throws -> IPCJSONSchema {
        IPCCommandArgumentSchemas.object(
            kind: .managementFromMainPane,
            fields: [
                IPCCommandArgumentSchemas.workspaceWindow,
                IPCCommandArgumentSchemas.paneSelector(
                    "mainPaneSelector",
                    description: "Main pane source selector for the relative management command"
                ),
            ])
    }
}

extension IPCManagementFromDrawerPaneCommandArguments {
    static func argumentSchema() throws -> IPCJSONSchema {
        IPCCommandArgumentSchemas.object(
            kind: .managementFromDrawerPane,
            fields: [
                IPCCommandArgumentSchemas.workspaceWindow,
                IPCCommandArgumentSchemas.paneSelector(
                    "parentPaneSelector",
                    description: "Main pane selector owning the source drawer"
                ),
                IPCCommandArgumentSchemas.paneSelector(
                    "drawerPaneSelector",
                    description: "Drawer pane source selector for the relative management command"
                ),
            ])
    }
}

extension IPCFloatingTerminalCommandArguments {
    static func argumentSchema() throws -> IPCJSONSchema {
        IPCCommandArgumentSchemas.object(
            kind: .floatingTerminal,
            fields: [
                IPCCommandArgumentSchemas.workspaceWindow,
                IPCCommandArgumentSchemas.optionalString(
                    "launchDirectory",
                    description: "Launch directory override; omission uses the user's home directory"
                ),
                IPCCommandArgumentSchemas.optionalString(
                    "title",
                    description: "Title override; omission lets the creation owner derive the title"
                ),
            ])
    }
}

extension IPCWebviewCommandArguments {
    static func argumentSchema() throws -> IPCJSONSchema {
        IPCCommandArgumentSchemas.object(
            kind: .webview,
            fields: [
                IPCCommandArgumentSchemas.workspaceWindow,
                .init(
                    name: "url",
                    description: "Webview URL; omission opens GitHub",
                    schema: .string(),
                    presence: try .defaulted("https://github.com")
                ),
            ])
    }
}

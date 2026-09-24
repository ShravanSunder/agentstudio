import Foundation

/// One typed command-argument value. Command identity remains an open string
/// owned by App; this union describes only reusable wire data shapes.
package enum IPCCommandArguments: IPCSchemaProviding, Equatable, Sendable {
    case noArguments
    case workspaceWindow(IPCWorkspaceWindowCommandArguments)
    case tab(IPCTabCommandArguments)
    case renamedTab(IPCRenamedTabCommandArguments)
    case newTab(IPCNewTabCommandArguments)
    case tabAnchor(IPCTabAnchorCommandArguments)
    case pane(IPCPaneCommandArguments)
    case sourcePane(IPCSourcePaneCommandArguments)
    case movePaneToTab(IPCMovePaneToTabCommandArguments)
    case arrangement(IPCArrangementCommandArguments)
    case newArrangement(IPCNewArrangementCommandArguments)
    case renamedArrangement(IPCRenamedArrangementCommandArguments)
    case drawerParent(IPCDrawerParentCommandArguments)
    case drawerSourcePane(IPCDrawerSourcePaneCommandArguments)
    case drawerPane(IPCDrawerPaneCommandArguments)
    case detachedDrawerPane(IPCDetachedDrawerPaneCommandArguments)
    case directory(IPCDirectoryCommandArguments)
    case repository(IPCRepositoryCommandArguments)
    case standalonePane(IPCStandalonePaneCommandArguments)
    case worktree(IPCWorktreeCommandArguments)
    case worktreeInPane(IPCWorktreeInPaneCommandArguments)
    case bridgeDocumentInPane(IPCBridgeDocumentInPaneCommandArguments)
    case terminalFromWorktree(IPCTerminalFromWorktreeCommandArguments)
    case terminalFromPane(IPCTerminalFromPaneCommandArguments)
    case managementFromMainPane(IPCManagementFromMainPaneCommandArguments)
    case managementFromDrawerPane(IPCManagementFromDrawerPaneCommandArguments)
    case floatingTerminal(IPCFloatingTerminalCommandArguments)
    case webview(IPCWebviewCommandArguments)

    package var variant: IPCCommandArgumentVariant {
        switch self {
        case .noArguments: .noArguments
        case .workspaceWindow: .workspaceWindow
        case .tab: .tab
        case .renamedTab: .renamedTab
        case .newTab: .newTab
        case .tabAnchor: .tabAnchor
        case .pane: .pane
        case .sourcePane: .sourcePane
        case .movePaneToTab: .movePaneToTab
        case .arrangement: .arrangement
        case .newArrangement: .newArrangement
        case .renamedArrangement: .renamedArrangement
        case .drawerParent: .drawerParent
        case .drawerSourcePane: .drawerSourcePane
        case .drawerPane: .drawerPane
        case .detachedDrawerPane: .detachedDrawerPane
        case .directory: .directory
        case .repository: .repository
        case .standalonePane: .standalonePane
        case .worktree: .worktree
        case .worktreeInPane: .worktreeInPane
        case .bridgeDocumentInPane: .bridgeDocumentInPane
        case .terminalFromWorktree: .terminalFromWorktree
        case .terminalFromPane: .terminalFromPane
        case .managementFromMainPane: .managementFromMainPane
        case .managementFromDrawerPane: .managementFromDrawerPane
        case .floatingTerminal: .floatingTerminal
        case .webview: .webview
        }
    }

    package static func ipcSchema(
        allowing variants: some Collection<IPCCommandArgumentVariant>
    ) throws -> IPCJSONSchema {
        let variants = Array(variants)
        guard !variants.isEmpty, Set(variants).count == variants.count else {
            throw IPCSchemaValidationError(
                fieldPath: "$",
                reason: .invalidDefinition,
                expected: "at least one unique command argument variant"
            )
        }
        if variants.count == 1, let variant = variants.first {
            return try variant.schema
        }
        return try .oneOf(variants.map { try $0.schema })
    }

    package static func ipcSchema() throws -> IPCJSONSchema {
        try ipcSchema(allowing: IPCCommandArgumentVariant.allCases)
    }

    private enum CodingKeys: String, CodingKey {
        case kind
    }

    package init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let variant = try container.decode(IPCCommandArgumentVariant.self, forKey: .kind)
        if let layoutArguments = try Self.decodeLayoutArguments(variant, from: decoder) {
            self = layoutArguments
            return
        }
        switch variant {
        case .drawerSourcePane:
            self = .drawerSourcePane(try IPCDrawerSourcePaneCommandArguments(from: decoder))
        case .drawerPane:
            self = .drawerPane(try IPCDrawerPaneCommandArguments(from: decoder))
        case .detachedDrawerPane:
            self = .detachedDrawerPane(try IPCDetachedDrawerPaneCommandArguments(from: decoder))
        case .directory:
            self = .directory(try IPCDirectoryCommandArguments(from: decoder))
        case .repository:
            self = .repository(try IPCRepositoryCommandArguments(from: decoder))
        case .standalonePane:
            self = .standalonePane(try IPCStandalonePaneCommandArguments(from: decoder))
        case .worktree:
            self = .worktree(try IPCWorktreeCommandArguments(from: decoder))
        case .worktreeInPane:
            self = .worktreeInPane(try IPCWorktreeInPaneCommandArguments(from: decoder))
        case .bridgeDocumentInPane:
            self = .bridgeDocumentInPane(try IPCBridgeDocumentInPaneCommandArguments(from: decoder))
        case .terminalFromWorktree:
            self = .terminalFromWorktree(try IPCTerminalFromWorktreeCommandArguments(from: decoder))
        case .terminalFromPane:
            self = .terminalFromPane(try IPCTerminalFromPaneCommandArguments(from: decoder))
        case .managementFromMainPane:
            self = .managementFromMainPane(try IPCManagementFromMainPaneCommandArguments(from: decoder))
        case .managementFromDrawerPane:
            self = .managementFromDrawerPane(try IPCManagementFromDrawerPaneCommandArguments(from: decoder))
        case .floatingTerminal:
            self = .floatingTerminal(try IPCFloatingTerminalCommandArguments(from: decoder))
        case .webview:
            self = .webview(try IPCWebviewCommandArguments(from: decoder))
        case .noArguments, .workspaceWindow, .tab, .renamedTab, .newTab, .tabAnchor, .pane, .sourcePane, .movePaneToTab,
            .arrangement, .newArrangement, .renamedArrangement, .drawerParent:
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Invalid argument family"))
        }
    }

    private static func decodeLayoutArguments(
        _ variant: IPCCommandArgumentVariant, from decoder: any Decoder
    ) throws -> Self? {
        switch variant {
        case .noArguments:
            return .noArguments
        case .workspaceWindow:
            return .workspaceWindow(try IPCWorkspaceWindowCommandArguments(from: decoder))
        case .tab:
            return .tab(try IPCTabCommandArguments(from: decoder))
        case .renamedTab:
            return .renamedTab(try IPCRenamedTabCommandArguments(from: decoder))
        case .newTab:
            return .newTab(try IPCNewTabCommandArguments(from: decoder))
        case .tabAnchor:
            return .tabAnchor(try IPCTabAnchorCommandArguments(from: decoder))
        case .pane:
            return .pane(try IPCPaneCommandArguments(from: decoder))
        case .sourcePane:
            return .sourcePane(try IPCSourcePaneCommandArguments(from: decoder))
        case .movePaneToTab:
            return .movePaneToTab(try IPCMovePaneToTabCommandArguments(from: decoder))
        case .arrangement:
            return .arrangement(try IPCArrangementCommandArguments(from: decoder))
        case .newArrangement:
            return .newArrangement(try IPCNewArrangementCommandArguments(from: decoder))
        case .renamedArrangement:
            return .renamedArrangement(try IPCRenamedArrangementCommandArguments(from: decoder))
        case .drawerParent:
            return .drawerParent(try IPCDrawerParentCommandArguments(from: decoder))
        default: return nil
        }
    }

    package func encode(to encoder: any Encoder) throws {
        if try encodeLayoutArguments(to: encoder) { return }
        switch self {
        case .drawerSourcePane(let arguments): try encode(arguments, to: encoder)
        case .drawerPane(let arguments): try encode(arguments, to: encoder)
        case .detachedDrawerPane(let arguments): try encode(arguments, to: encoder)
        case .directory(let arguments): try encode(arguments, to: encoder)
        case .repository(let arguments): try encode(arguments, to: encoder)
        case .standalonePane(let arguments): try encode(arguments, to: encoder)
        case .worktree(let arguments): try encode(arguments, to: encoder)
        case .worktreeInPane(let arguments): try encode(arguments, to: encoder)
        case .bridgeDocumentInPane(let arguments): try encode(arguments, to: encoder)
        case .terminalFromWorktree(let arguments): try encode(arguments, to: encoder)
        case .terminalFromPane(let arguments): try encode(arguments, to: encoder)
        case .managementFromMainPane(let arguments): try encode(arguments, to: encoder)
        case .managementFromDrawerPane(let arguments): try encode(arguments, to: encoder)
        case .floatingTerminal(let arguments): try encode(arguments, to: encoder)
        case .webview(let arguments): try encode(arguments, to: encoder)
        case .noArguments, .workspaceWindow, .tab, .renamedTab, .newTab, .tabAnchor, .pane, .sourcePane, .movePaneToTab,
            .arrangement, .newArrangement, .renamedArrangement, .drawerParent:
            throw EncodingError.invalidValue(
                variant, .init(codingPath: encoder.codingPath, debugDescription: "Invalid argument family"))
        }
    }

    private func encodeLayoutArguments(to encoder: any Encoder) throws -> Bool {
        switch self {
        case .noArguments:
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(variant, forKey: .kind)
        case .workspaceWindow(let arguments): try encode(arguments, to: encoder)
        case .tab(let arguments): try encode(arguments, to: encoder)
        case .renamedTab(let arguments): try encode(arguments, to: encoder)
        case .newTab(let arguments): try encode(arguments, to: encoder)
        case .tabAnchor(let arguments): try encode(arguments, to: encoder)
        case .pane(let arguments): try encode(arguments, to: encoder)
        case .sourcePane(let arguments): try encode(arguments, to: encoder)
        case .movePaneToTab(let arguments): try encode(arguments, to: encoder)
        case .arrangement(let arguments): try encode(arguments, to: encoder)
        case .newArrangement(let arguments): try encode(arguments, to: encoder)
        case .renamedArrangement(let arguments): try encode(arguments, to: encoder)
        case .drawerParent(let arguments): try encode(arguments, to: encoder)
        default: return false
        }
        return true
    }

    private func encode<Arguments: Encodable>(
        _ arguments: Arguments,
        to encoder: any Encoder
    ) throws {
        try arguments.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(variant, forKey: .kind)
    }
}

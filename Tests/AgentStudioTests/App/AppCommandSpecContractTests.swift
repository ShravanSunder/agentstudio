import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("Command spec contracts")
struct CommandSpecContractTests {
    init() {
        installTestAtomRegistryIfNeeded()
    }

    @Test("every shortcut maps to a command definition that declares that shortcut")
    func everyShortcutMapsToACommandDefinitionThatDeclaresThatShortcut() {
        for shortcut in AppShortcut.allCases {
            let command = shortcut.command
            let definition = AppCommandDispatcher.shared.definition(for: command)

            #expect(
                definition.shortcut == shortcut,
                "\(shortcut.rawValue) maps to \(command.rawValue), but its AppCommandSpec declares \(String(describing: definition.shortcut))"
            )
        }
    }

    @Test("shortcut triggers are unique within each routing context")
    func shortcutTriggersAreUniqueWithinEachRoutingContext() {
        var seenShortcuts: [ShortcutRouteKey: AppShortcut] = [:]

        for shortcut in AppShortcut.allCases {
            for context in shortcut.contexts {
                let routeKey = ShortcutRouteKey(context: context, trigger: shortcut.trigger)
                if let existingShortcut = seenShortcuts[routeKey] {
                    Issue.record(
                        """
                        \(shortcut.rawValue) and \(existingShortcut.rawValue) both use \
                        \(shortcut.trigger.displayDescription) in \(context)
                        """
                    )
                } else {
                    seenShortcuts[routeKey] = shortcut
                }
            }
        }
    }

    @Test("commands scope mirrors visible AppCommandSpec metadata")
    func commandsScopeMirrorsVisibleCommandSpecMetadata() throws {
        let store = makeCommandRichStore()
        let focus = WorkspacePaneFocus(
            activeTabId: UUID(),
            activePaneId: UUID(),
            paneContentType: .terminal,
            satisfiedRequirements: Set(FocusRequirement.allCases)
        )

        let items = CommandBarDataSource.items(
            scope: .commands,
            store: store,
            repoCache: RepoCacheAtom(),
            dispatcher: .shared,
            focus: focus
        )
        let itemsByCommand = Dictionary(
            uniqueKeysWithValues: items.compactMap { item in
                item.command.map { ($0, item) }
            })
        let expectedDefinitions = AppCommandDispatcher.shared.definitions.values.filter {
            !$0.isHiddenInCommandBar && $0.isVisible(in: focus)
        }

        #expect(itemsByCommand.count == expectedDefinitions.count)

        for definition in expectedDefinitions {
            let item = try #require(
                itemsByCommand[definition.command],
                "Missing command bar row for \(definition.command.rawValue)"
            )

            #expect(item.id == "cmd-\(definition.command.rawValue)")
            #expect(item.title == definition.label)
            #expect(item.icon == definition.icon)
            #expect(item.group == definition.commandBarGroupName)
            #expect(item.groupPriority == definition.commandBarGroupPriority)
            #expect(item.shortcutTrigger == definition.commandBarShortcutTrigger)
            #expect(item.command == definition.command)
        }
    }

    @Test("app command specs project typed tooltip descriptors")
    func appCommandSpecsProjectTypedTooltipDescriptors() {
        let definition = AppCommand.openPaneLocationInEditorMenu.definition

        let descriptor = definition.commandDisplayDescriptor(compactTooltipText: "Open in Editor")

        #expect(descriptor.provenance == .appCommand(rawValue: "openPaneLocationInEditorMenu"))
        #expect(descriptor.label == definition.label)
        #expect(descriptor.helpText == definition.helpText)
        #expect(descriptor.compactTooltipText == "Open in Editor")
        #expect(descriptor.shortcutDisplayText == ShortcutDisplayText(value: "⌘⌥O"))
        #expect(
            ControlTooltipResolver.resolve(.display(descriptor))
                == definition.controlTooltipRenderValue(textOverride: "Open in Editor")
        )
        #expect(definition.controlToolTip(textOverride: "Open in Editor") == "Open in Editor (⌘⌥O)")
    }

    @Test("app command tooltip source preserves help-text fallback without shortcut")
    func appCommandTooltipSourcePreservesHelpTextFallbackWithoutShortcut() {
        let definition = AppCommandSpec(
            command: .renameArrangement,
            label: "Rename Arrangement",
            icon: .system(.pencil),
            helpText: "Rename the current arrangement"
        )

        let renderValue = ControlTooltipResolver.resolve(definition.controlTooltipSource())

        #expect(renderValue.text == "Rename the current arrangement")
        #expect(renderValue.shortcutDisplayText == nil)
    }

    private func makeCommandRichStore() -> WorkspaceStore {
        let store = WorkspaceStore(
            workspacePersistenceRevisionOwner: WorkspacePersistenceRevisionOwner(),
        )
        let repo = store.addRepo(at: URL(filePath: "/tmp/command-spec-contracts"))
        let worktree = Worktree(
            repoId: repo.id,
            name: "feature-command-contracts",
            path: URL(filePath: "/tmp/command-spec-contracts/feature-command-contracts")
        )
        store.reconcileDiscoveredWorktrees(repo.id, worktrees: [worktree])

        let primaryPane = store.createPane(
            launchDirectory: worktree.path,
            title: "Primary",
            facets: PaneContextFacets(repoId: repo.id, worktreeId: worktree.id, cwd: worktree.path),
        )
        let secondaryPane = store.createPane()
        var tab = Tab(paneId: primaryPane.id)
        tab.arrangements.append(
            PaneArrangement(
                name: "Review",
                isDefault: false,
                layout: tab.layout
            )
        )
        store.appendTab(tab)
        store.setActiveTab(tab.id)
        store.insertPane(
            secondaryPane.id,
            inTab: tab.id,
            at: primaryPane.id,
            direction: .horizontal,
            position: .after,
            sizingMode: .halveTarget
        )
        _ = store.addDrawerPane(to: primaryPane.id)

        return store
    }
}

private struct ShortcutRouteKey: Hashable {
    let context: ShortcutContext
    let trigger: ShortcutTrigger
}

extension ShortcutTrigger {
    fileprivate var displayDescription: String {
        let modifierPrefix =
            modifiers
            .sorted { $0.rawValue < $1.rawValue }
            .map(\.rawValue)
            .joined(separator: "+")
        guard !modifierPrefix.isEmpty else { return key.displayString }
        return "\(modifierPrefix)+\(key.displayString)"
    }
}

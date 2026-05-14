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
            let definition = CommandDispatcher.shared.definition(for: command)

            #expect(
                definition.shortcut == shortcut,
                "\(shortcut.rawValue) maps to \(command.rawValue), but its CommandSpec declares \(String(describing: definition.shortcut))"
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

    @Test("commands scope mirrors visible CommandSpec metadata")
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
        let expectedDefinitions = CommandDispatcher.shared.definitions.values.filter {
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

    private func makeCommandRichStore() -> WorkspaceStore {
        let store = WorkspaceStore()
        let repo = store.addRepo(at: URL(filePath: "/tmp/command-spec-contracts"))
        let worktree = Worktree(
            repoId: repo.id,
            name: "feature-command-contracts",
            path: URL(filePath: "/tmp/command-spec-contracts/feature-command-contracts")
        )
        store.reconcileDiscoveredWorktrees(repo.id, worktrees: [worktree])

        let primaryPane = store.createPane(
            source: .worktree(worktreeId: worktree.id, repoId: repo.id, launchDirectory: worktree.path),
            title: "Primary"
        )
        let secondaryPane = store.createPane(source: .floating(launchDirectory: nil, title: "Secondary"))
        var tab = Tab(paneId: primaryPane.id)
        tab.arrangements.append(
            PaneArrangement(
                name: "Review",
                isDefault: false,
                layout: tab.layout,
                visiblePaneIds: Set(tab.activePaneIds)
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

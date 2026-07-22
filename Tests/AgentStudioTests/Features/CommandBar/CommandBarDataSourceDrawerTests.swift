import Foundation
import Testing

@testable import AgentStudio

extension CommandBarDataSourceTests {
    @Test
    func test_commandsScope_includesDrawerCommands() {
        let store = makeRichCommandStore()

        let items = CommandBarDataSource.items(
            scope: .commands,
            store: store,
            repoCache: RepoCacheAtom(),
            dispatcher: dispatcher
        )

        let ids = items.map(\.id)
        #expect(ids.contains("cmd-addDrawerPane"))
        #expect(ids.contains("cmd-toggleDrawer"))
        #expect(ids.contains("cmd-navigateDrawerPane"))
        #expect(ids.contains("cmd-closeDrawerPane"))
    }

    @Test
    func test_commandsScope_drawerCommandsInPaneGroup() {
        let store = makeRichCommandStore()

        let items = CommandBarDataSource.items(
            scope: .commands,
            store: store,
            repoCache: RepoCacheAtom(),
            dispatcher: dispatcher
        )

        let drawerItems = items.filter {
            $0.id == "cmd-addDrawerPane"
                || $0.id == "cmd-toggleDrawer"
                || $0.id == "cmd-navigateDrawerPane"
                || $0.id == "cmd-closeDrawerPane"
        }
        #expect(drawerItems.count == 4)
        #expect(drawerItems.allSatisfy { $0.group == "Pane" })
    }

    @Test
    func test_commandsScope_navigateDrawerPaneIsTargetable() {
        let store = makeStore()
        let pane = store.createPane()
        let tab = Tab(paneId: pane.id)
        store.appendTab(tab)
        store.setActiveTab(tab.id)

        store.addDrawerPane(to: pane.id)

        let items = CommandBarDataSource.items(
            scope: .commands,
            store: store,
            repoCache: RepoCacheAtom(),
            dispatcher: dispatcher
        )

        let navigateItem = items.first { $0.id == "cmd-navigateDrawerPane" }
        #expect(navigateItem != nil)
        #expect((navigateItem?.hasChildren ?? false) == true)
    }

    @Test
    func test_navigateDrawerPane_targetLevel_listsDrawerPanes() {
        let store = makeStore()
        let pane = store.createPane()
        let tab = Tab(paneId: pane.id)
        store.appendTab(tab)
        store.setActiveTab(tab.id)

        let drawer1 = store.addDrawerPane(to: pane.id)
        let drawer2 = store.addDrawerPane(to: pane.id)
        #expect(drawer1 != nil)
        #expect(drawer2 != nil)

        let items = CommandBarDataSource.items(
            scope: .commands,
            store: store,
            repoCache: RepoCacheAtom(),
            dispatcher: dispatcher
        )
        let navigateItem = items.first { $0.id == "cmd-navigateDrawerPane" }
        #expect(navigateItem != nil)

        guard case .navigate(let level) = navigateItem?.action else {
            Issue.record(
                "navigateDrawerPane action should be .navigate, got \(String(describing: navigateItem?.action))"
            )
            return
        }

        #expect(level.items.count == 2)
        #expect(level.id == "level-navigateDrawerPane")

        let levelTitles = level.items.map(\.title)
        #expect(levelTitles.allSatisfy { $0 == "Drawer" })

        let levelIds = level.items.map(\.id)
        #expect(levelIds.contains("target-drawer-\(drawer1!.id.uuidString)"))
        #expect(levelIds.contains("target-drawer-\(drawer2!.id.uuidString)"))

        let activeItem = level.items.first { $0.id == "target-drawer-\(drawer2!.id.uuidString)" }
        #expect(activeItem?.subtitle == "Active")
    }
}

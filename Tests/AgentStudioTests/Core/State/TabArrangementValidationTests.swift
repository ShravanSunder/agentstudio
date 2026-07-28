import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
struct TabArrangementValidationTests {
    @Test
    func validate_removesDuplicatePaneIdsFromLaterTabsAndMinimizedSets() {
        let sharedPane = UUID()
        let uniquePane = UUID()
        let firstArrangement = PaneArrangement(
            name: "Default",
            isDefault: true,
            layout: Layout(paneId: sharedPane)
        )
        let first = TabArrangementState(
            tabId: UUID(),
            allPaneIds: [sharedPane],
            arrangements: [firstArrangement],
            activeArrangementId: firstArrangement.id,
            activePaneId: sharedPane
        )
        let secondArrangement = PaneArrangement(
            name: "Default",
            isDefault: true,
            layout: Layout(paneId: sharedPane)
                .inserting(
                    paneId: uniquePane, at: sharedPane, direction: .horizontal, position: .after,
                    sizingMode: .halveTarget)!,
            minimizedPaneIds: [sharedPane]
        )
        let second = TabArrangementState(
            tabId: UUID(),
            allPaneIds: [sharedPane, uniquePane],
            arrangements: [secondArrangement],
            activeArrangementId: secondArrangement.id,
            activePaneId: sharedPane
        )

        let validated = TabArrangementValidation.validating([first, second])

        #expect(validated.count == 2)
        #expect(validated[1].allPaneIds == [uniquePane])
        #expect(validated[1].arrangements[0].layout.paneIds == [uniquePane])
        #expect(validated[1].arrangements[0].minimizedPaneIds.isEmpty)
    }

    @Test
    func pruningInvalidPaneIds_removesInvalidDrawerViewPaneReferences() {
        let parentPane = UUID()
        let validDrawerPane = UUID()
        let invalidDrawerPane = UUID()
        let drawerId = UUID()
        let drawerLayout = DrawerGridLayout(
            topRow: Layout(paneId: validDrawerPane)
                .inserting(
                    paneId: invalidDrawerPane,
                    at: validDrawerPane,
                    direction: .horizontal,
                    position: .after,
                    sizingMode: .halveTarget
                )!)
        let arrangement = PaneArrangement(
            name: "Default",
            isDefault: true,
            layout: Layout(paneId: parentPane),
            drawerViews: [
                drawerId: DrawerView(
                    layout: drawerLayout,
                    activeChildId: invalidDrawerPane,
                    minimizedPaneIds: [invalidDrawerPane]
                )
            ]
        )
        let state = TabArrangementState(
            tabId: UUID(),
            allPaneIds: [parentPane, validDrawerPane, invalidDrawerPane],
            arrangements: [arrangement],
            activeArrangementId: arrangement.id,
            activePaneId: parentPane
        )

        let validated = TabArrangementValidation.pruningInvalidPaneIds(
            validPaneIds: [parentPane, validDrawerPane],
            from: [state]
        )

        let drawerView = validated[0].arrangements[0].drawerViews[drawerId]
        #expect(drawerView?.layout.paneIds == [validDrawerPane])
        #expect(drawerView?.activeChildId == validDrawerPane)
        #expect(drawerView?.minimizedPaneIds.isEmpty == true)
    }

    @Test
    func validate_keepsDrawerPaneIdsInTabPaneMembership() {
        let parentPane = UUID()
        let drawerPane = UUID()
        let drawerId = UUID()
        let arrangement = PaneArrangement(
            name: "Default",
            isDefault: true,
            layout: Layout(paneId: parentPane),
            drawerViews: [
                drawerId: DrawerView(layout: DrawerGridLayout(topRow: Layout(paneId: drawerPane)))
            ]
        )
        let state = TabArrangementState(
            tabId: UUID(),
            allPaneIds: [parentPane, drawerPane],
            arrangements: [arrangement],
            activeArrangementId: arrangement.id,
            activePaneId: parentPane
        )

        let validated = TabArrangementValidation.validating([state])

        #expect(Set(validated[0].allPaneIds) == Set([parentPane, drawerPane]))
        #expect(validated[0].arrangements[0].drawerViews[drawerId]?.layout.paneIds == [drawerPane])
    }

    @Test
    func validate_doesNotPromoteOrphanedDrawerChildIntoDefaultMainLayout() {
        let removedParentPane = UUID()
        let survivingDrawerPane = UUID()
        let drawerId = UUID()
        let defaultArrangement = PaneArrangement(
            name: "Default",
            isDefault: true,
            layout: Layout(paneId: removedParentPane),
            drawerViews: [
                drawerId: DrawerView(
                    layout: DrawerGridLayout(topRow: Layout(paneId: survivingDrawerPane))
                )
            ]
        )
        let state = TabArrangementState(
            tabId: UUID(),
            allPaneIds: [removedParentPane, survivingDrawerPane],
            arrangements: [defaultArrangement],
            activeArrangementId: defaultArrangement.id,
            activePaneId: removedParentPane
        )

        let validated = TabArrangementValidation.pruningInvalidPaneIds(
            validPaneIds: [survivingDrawerPane],
            from: [state],
            drawerParentPaneIdByDrawerId: [drawerId: removedParentPane]
        )

        #expect(
            validated.allSatisfy { state in
                state.arrangements.allSatisfy { !$0.layout.contains(survivingDrawerPane) }
            }
        )
    }

    @Test
    func validate_normalizesScrambledDrawerMembershipToReferencedOrder() {
        let parentPane = UUID()
        let firstDrawerPane = UUID()
        let secondDrawerPane = UUID()
        let drawerId = UUID()
        let drawerLayout = DrawerGridLayout(
            topRow: Layout(paneId: firstDrawerPane)
                .inserting(
                    paneId: secondDrawerPane,
                    at: firstDrawerPane,
                    direction: .horizontal,
                    position: .after,
                    sizingMode: .halveTarget
                )!)
        let arrangement = PaneArrangement(
            name: "Default",
            isDefault: true,
            layout: Layout(paneId: parentPane),
            drawerViews: [
                drawerId: DrawerView(layout: drawerLayout)
            ]
        )
        let state = TabArrangementState(
            tabId: UUID(),
            allPaneIds: [secondDrawerPane, firstDrawerPane, parentPane],
            arrangements: [arrangement],
            activeArrangementId: arrangement.id,
            activePaneId: parentPane
        )

        let validated = TabArrangementValidation.validating([state])

        #expect(validated[0].allPaneIds == [parentPane, firstDrawerPane, secondDrawerPane])
    }

    @Test
    func validate_normalizesDefaultToAllMainPanesWithoutMinimizedPanes() throws {
        let paneA = UUID()
        let paneB = UUID()
        var defaultArrangement = PaneArrangement(
            name: "Default",
            isDefault: true,
            layout: Layout(paneId: paneA)
        )
        defaultArrangement.minimizedPaneIds = [paneA]
        let userLayout = PaneArrangement(
            name: "Layout 1",
            isDefault: false,
            layout: Layout.autoTiled([paneB, paneA]),
            minimizedPaneIds: [paneB]
        )
        let state = TabArrangementState(
            tabId: UUID(),
            allPaneIds: [paneA, paneB],
            arrangements: [defaultArrangement, userLayout],
            activeArrangementId: userLayout.id,
            activePaneId: paneA
        )

        let validatedState = try #require(TabArrangementValidation.validating([state]).first)
        let validatedDefault = try #require(validatedState.arrangements.first(where: { $0.isDefault }))
        let validatedUserLayout = try #require(validatedState.arrangements.first(where: { !$0.isDefault }))

        #expect(validatedDefault.layout.paneIds == [paneA, paneB])
        #expect(validatedDefault.minimizedPaneIds.isEmpty)
        #expect(validatedUserLayout.layout.paneIds == [paneB, paneA])
        #expect(validatedUserLayout.minimizedPaneIds == Set([paneB]))
    }

    @Test
    func validate_preservesUnreferencedDurableMembershipAndAddsItToDefault() throws {
        let paneA = UUID()
        let paneB = UUID()
        let defaultArrangement = PaneArrangement(
            name: "Default",
            isDefault: true,
            layout: Layout(paneId: paneA)
        )
        let state = TabArrangementState(
            tabId: UUID(),
            allPaneIds: [paneA, paneB],
            arrangements: [defaultArrangement],
            activeArrangementId: defaultArrangement.id,
            activePaneId: paneA
        )

        let validatedState = try #require(TabArrangementValidation.validating([state]).first)
        let validatedDefault = try #require(validatedState.arrangements.first(where: { $0.isDefault }))

        #expect(validatedState.allPaneIds == [paneA, paneB])
        #expect(validatedDefault.layout.paneIds == [paneA, paneB])
    }

    @Test
    func validate_removesDuplicateUnreferencedMembershipFromLaterTab() throws {
        let sharedPane = UUID()
        let laterPane = UUID()
        let firstDefault = PaneArrangement(
            name: "Default",
            isDefault: true,
            layout: Layout(paneId: sharedPane)
        )
        let laterDefault = PaneArrangement(
            name: "Default",
            isDefault: true,
            layout: Layout(paneId: laterPane)
        )
        let firstState = TabArrangementState(
            tabId: UUID(),
            allPaneIds: [sharedPane],
            arrangements: [firstDefault],
            activeArrangementId: firstDefault.id,
            activePaneId: sharedPane
        )
        let laterState = TabArrangementState(
            tabId: UUID(),
            allPaneIds: [sharedPane, laterPane],
            arrangements: [laterDefault],
            activeArrangementId: laterDefault.id,
            activePaneId: laterPane
        )

        let validatedStates = TabArrangementValidation.validating([firstState, laterState])
        let validatedLaterState = try #require(validatedStates.last)
        let validatedLaterDefault = try #require(
            validatedLaterState.arrangements.first(where: { $0.isDefault })
        )

        #expect(validatedLaterState.allPaneIds == [laterPane])
        #expect(validatedLaterDefault.layout.paneIds == [laterPane])
    }
}

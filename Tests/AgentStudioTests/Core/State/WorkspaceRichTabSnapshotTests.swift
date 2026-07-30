import Foundation
import Testing

@testable import AgentStudioCore
@testable import AgentStudioInfrastructure

@MainActor
@Suite(.serialized)
struct WorkspaceRichTabSnapshotTests {
    @Test("tab shell revision advances only for accepted semantic changes")
    func tabShellRevisionTracksAcceptedChanges() throws {
        let shell = TabShell(id: UUID(), name: "One")
        let atom = WorkspaceTabShellAtom()

        #expect(atom.tabShellRevision == 0)

        atom.appendTabShell(shell)
        #expect(atom.tabShellRevision == 1)

        atom.appendTabShell(shell)
        #expect(atom.tabShellRevision == 1)

        atom.renameTab(shell.id, name: "Renamed")
        #expect(atom.tabShellRevision == 2)

        atom.renameTab(shell.id, name: "Renamed")
        #expect(atom.tabShellRevision == 2)

        try atom.setTabColorHex("#AABBCC", tabId: shell.id)
        #expect(atom.tabShellRevision == 3)

        try atom.setTabColorHex("#aabbcc", tabId: shell.id)
        #expect(atom.tabShellRevision == 3)
    }

    @Test("tab graph revision advances only when graph content changes")
    func tabGraphRevisionTracksAcceptedChanges() {
        let state = TabGraphState(
            tabId: UUID(),
            allPaneIds: [UUID()],
            arrangements: []
        )
        let atom = WorkspaceTabGraphAtom()

        #expect(atom.tabGraphRevision == 0)

        atom.replaceStates([state])
        #expect(atom.tabGraphRevision == 1)

        atom.replaceStates([state])
        #expect(atom.tabGraphRevision == 1)

        atom.replaceStates([])
        #expect(atom.tabGraphRevision == 2)
    }

    @Test("each arrangement cursor collection has an independent semantic revision")
    func arrangementCursorRevisionsTrackIndependentCollections() {
        let tabId = UUID()
        let firstArrangementId = UUID()
        let secondArrangementId = UUID()
        let firstPaneId = UUID()
        let secondPaneId = UUID()
        let drawerId = UUID()
        let firstDrawerPaneId = UUID()
        let secondDrawerPaneId = UUID()
        let atom = WorkspaceArrangementCursorAtom()

        atom.replaceCursors(
            activeArrangementIdsByTabId: [tabId: firstArrangementId],
            paneCursorsByArrangementId: [
                firstArrangementId: .init(activePaneId: firstPaneId)
            ],
            drawerCursorsByKey: [
                .init(arrangementId: firstArrangementId, drawerId: drawerId):
                    .init(activeChildId: firstDrawerPaneId)
            ]
        )
        #expect(atom.activeArrangementRevision == 1)
        #expect(atom.activePaneRevision == 1)
        #expect(atom.drawerChildRevision == 1)

        atom.replaceCursors(
            activeArrangementIdsByTabId: [tabId: secondArrangementId],
            paneCursorsByArrangementId: [
                firstArrangementId: .init(activePaneId: firstPaneId)
            ],
            drawerCursorsByKey: [
                .init(arrangementId: firstArrangementId, drawerId: drawerId):
                    .init(activeChildId: firstDrawerPaneId)
            ]
        )
        #expect(atom.activeArrangementRevision == 2)
        #expect(atom.activePaneRevision == 1)
        #expect(atom.drawerChildRevision == 1)

        atom.replaceCursors(
            activeArrangementIdsByTabId: [tabId: secondArrangementId],
            paneCursorsByArrangementId: [
                firstArrangementId: .init(activePaneId: secondPaneId)
            ],
            drawerCursorsByKey: [
                .init(arrangementId: firstArrangementId, drawerId: drawerId):
                    .init(activeChildId: firstDrawerPaneId)
            ]
        )
        #expect(atom.activeArrangementRevision == 2)
        #expect(atom.activePaneRevision == 2)
        #expect(atom.drawerChildRevision == 1)

        atom.replaceCursors(
            activeArrangementIdsByTabId: [tabId: secondArrangementId],
            paneCursorsByArrangementId: [
                firstArrangementId: .init(activePaneId: secondPaneId)
            ],
            drawerCursorsByKey: [
                .init(arrangementId: firstArrangementId, drawerId: drawerId):
                    .init(activeChildId: secondDrawerPaneId)
            ]
        )
        #expect(atom.activeArrangementRevision == 2)
        #expect(atom.activePaneRevision == 2)
        #expect(atom.drawerChildRevision == 2)

        atom.replaceCursors(
            activeArrangementIdsByTabId: [tabId: secondArrangementId],
            paneCursorsByArrangementId: [
                firstArrangementId: .init(activePaneId: secondPaneId)
            ],
            drawerCursorsByKey: [
                .init(arrangementId: firstArrangementId, drawerId: drawerId):
                    .init(activeChildId: secondDrawerPaneId)
            ]
        )
        #expect(atom.activeArrangementRevision == 2)
        #expect(atom.activePaneRevision == 2)
        #expect(atom.drawerChildRevision == 2)
    }

    @Test("rich snapshot preserves shell order and invalidates after compound replacement")
    func richSnapshotMatchesCanonicalAssemblyAfterCompoundReplacement() {
        let firstPaneId = UUID()
        let secondPaneId = UUID()
        let firstTab = Tab(paneId: firstPaneId, name: "First")
        let secondTab = Tab(paneId: secondPaneId, name: "Second")
        let atom = WorkspaceTabLayoutAtom()

        atom.replaceTabs(
            [secondTab, firstTab],
            activeTabId: firstTab.id,
            validPaneIds: [firstPaneId, secondPaneId]
        )

        let firstSnapshot = atom.richTabSnapshot
        let directFirstAssembly = WorkspaceTabLayoutDerived(
            shellAtom: atom.shellAtom,
            arrangementAtom: atom.arrangementAtom
        ).tabs
        #expect(firstSnapshot.orderedTabs == directFirstAssembly)
        #expect(firstSnapshot.orderedTabs.map(\.id) == [secondTab.id, firstTab.id])

        let renamedFirstTab = Tab(
            id: firstTab.id,
            name: "First Renamed",
            allPaneIds: firstTab.allPaneIds,
            arrangements: firstTab.arrangements,
            activeArrangementId: firstTab.activeArrangementId
        )
        atom.replaceTabs(
            [renamedFirstTab],
            activeTabId: renamedFirstTab.id,
            validPaneIds: [firstPaneId]
        )

        let secondSnapshot = atom.richTabSnapshot
        let directSecondAssembly = WorkspaceTabLayoutDerived(
            shellAtom: atom.shellAtom,
            arrangementAtom: atom.arrangementAtom
        ).tabs
        #expect(secondSnapshot.orderedTabs == directSecondAssembly)
        #expect(secondSnapshot.orderedTabs.map(\.name) == ["First Renamed"])
    }

    @Test("production snapshot recomputes for every declared revision family")
    func productionSnapshotMutationMatrix() async throws {
        let (traceRuntime, traceDirectory) = makeTraceRuntime()
        defer { try? FileManager.default.removeItem(at: traceDirectory) }
        AtomPerformanceTelemetry.shared.configure(traceRuntime: traceRuntime)
        defer { AtomPerformanceTelemetry.shared.resetForTests() }

        let fixture = makeProductionSnapshotFixture()
        let atom = fixture.atom
        let tab = fixture.initialTab

        func expectedCanonicalTabs() -> [Tab] {
            WorkspaceTabLayoutDerived(
                shellAtom: atom.shellAtom,
                arrangementAtom: atom.arrangementAtom
            ).tabs
        }

        #expect(atom.richTabSnapshot.orderedTabs == expectedCanonicalTabs())
        #expect(atom.richTabSnapshot.orderedTabs == expectedCanonicalTabs())

        atom.renameTab(tab.id, name: "Renamed")
        #expect(atom.richTabSnapshot.orderedTabs == expectedCanonicalTabs())
        atom.renameTab(tab.id, name: "Renamed")
        #expect(atom.richTabSnapshot.orderedTabs == expectedCanonicalTabs())

        atom.renameArrangement(fixture.defaultArrangement.id, name: "Default Renamed", inTab: tab.id)
        #expect(atom.richTabSnapshot.orderedTabs == expectedCanonicalTabs())
        atom.renameArrangement(fixture.defaultArrangement.id, name: "Default Renamed", inTab: tab.id)
        #expect(atom.richTabSnapshot.orderedTabs == expectedCanonicalTabs())

        atom.switchArrangement(to: fixture.focusedArrangement.id, inTab: tab.id)
        #expect(atom.richTabSnapshot.orderedTabs == expectedCanonicalTabs())
        atom.switchArrangement(to: fixture.focusedArrangement.id, inTab: tab.id)
        #expect(atom.richTabSnapshot.orderedTabs == expectedCanonicalTabs())

        atom.setActivePane(fixture.firstPaneId, inTab: tab.id)
        #expect(atom.richTabSnapshot.orderedTabs == expectedCanonicalTabs())
        atom.setActivePane(fixture.firstPaneId, inTab: tab.id)
        #expect(atom.richTabSnapshot.orderedTabs == expectedCanonicalTabs())

        atom.arrangementAtom.setActiveDrawerPane(
            fixture.secondDrawerPaneId,
            drawerId: fixture.drawerId,
            inTab: tab.id
        )
        #expect(atom.richTabSnapshot.orderedTabs == expectedCanonicalTabs())
        atom.arrangementAtom.setActiveDrawerPane(
            fixture.secondDrawerPaneId,
            drawerId: fixture.drawerId,
            inTab: tab.id
        )
        #expect(atom.richTabSnapshot.orderedTabs == expectedCanonicalTabs())

        let restoredTab = fixture.restoredTab
        atom.replaceTabs(
            [restoredTab],
            activeTabId: restoredTab.id,
            validPaneIds: Set(restoredTab.allPaneIds)
        )
        #expect(atom.richTabSnapshot.orderedTabs == expectedCanonicalTabs())
        atom.replaceTabs(
            [restoredTab],
            activeTabId: restoredTab.id,
            validPaneIds: Set(restoredTab.allPaneIds)
        )
        #expect(atom.richTabSnapshot.orderedTabs == expectedCanonicalTabs())

        atom.setActivePane(UUID(), inTab: restoredTab.id)
        #expect(atom.richTabSnapshot.orderedTabs == expectedCanonicalTabs())
        atom.arrangementAtom.setActiveDrawerPane(UUID(), drawerId: fixture.drawerId, inTab: restoredTab.id)
        #expect(atom.richTabSnapshot.orderedTabs == expectedCanonicalTabs())

        try await AtomPerformanceTelemetry.shared.drainForTests()
        let operationCounts = try derivedOperationCounts(traceRuntime: traceRuntime)
        #expect(operationCounts.compute == 7)
        #expect(operationCounts.cacheHit == 9)
    }

    private func makeTraceRuntime() -> (AgentStudioTraceRuntime, URL) {
        let traceDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("rich-tab-snapshot-telemetry-\(UUID().uuidString)", isDirectory: true)
        let traceRuntime = AgentStudioTraceRuntime(
            configuration: AgentStudioTraceConfiguration.from(environment: [
                "AGENTSTUDIO_TRACE_BACKEND": "jsonl",
                "AGENTSTUDIO_TRACE_DIR": traceDirectory.path,
                "AGENTSTUDIO_TRACE_NAME": "rich-tab-snapshot-telemetry",
                "AGENTSTUDIO_TRACE_TAGS": "atoms",
            ]),
            processIdentifier: 919,
            timeUnixNano: { 779 }
        )
        return (traceRuntime, traceDirectory)
    }

    private func makeProductionSnapshotFixture() -> ProductionSnapshotFixture {
        let firstPaneId = UUID()
        let secondPaneId = UUID()
        let firstDrawerPaneId = UUID()
        let secondDrawerPaneId = UUID()
        let drawerId = UUID()
        let defaultArrangement = PaneArrangement(
            name: "Default",
            isDefault: true,
            layout: Layout.autoTiled([firstPaneId, secondPaneId]),
            activePaneId: firstPaneId,
            drawerViews: [
                drawerId: DrawerView(
                    layout: DrawerGridLayout(
                        topRow: Layout.autoTiled([firstDrawerPaneId, secondDrawerPaneId])
                    ),
                    activeChildId: firstDrawerPaneId
                )
            ]
        )
        let focusedArrangement = PaneArrangement(
            name: "Focused",
            isDefault: false,
            layout: Layout.autoTiled([firstPaneId, secondPaneId]),
            activePaneId: secondPaneId,
            drawerViews: defaultArrangement.drawerViews
        )
        let initialTab = Tab(
            name: "Initial",
            allPaneIds: [firstPaneId, secondPaneId, firstDrawerPaneId, secondDrawerPaneId],
            arrangements: [defaultArrangement, focusedArrangement],
            activeArrangementId: defaultArrangement.id
        )
        let restoredTab = Tab(
            id: initialTab.id,
            name: "Restored",
            allPaneIds: initialTab.allPaneIds,
            arrangements: [defaultArrangement],
            activeArrangementId: defaultArrangement.id
        )
        let atom = WorkspaceTabLayoutAtom()
        atom.replaceTabs(
            [initialTab],
            activeTabId: initialTab.id,
            validPaneIds: Set(initialTab.allPaneIds)
        )
        return ProductionSnapshotFixture(
            atom: atom,
            initialTab: initialTab,
            restoredTab: restoredTab,
            defaultArrangement: defaultArrangement,
            focusedArrangement: focusedArrangement,
            firstPaneId: firstPaneId,
            secondDrawerPaneId: secondDrawerPaneId,
            drawerId: drawerId
        )
    }

    private func derivedOperationCounts(
        traceRuntime: AgentStudioTraceRuntime
    ) throws -> (compute: Int, cacheHit: Int) {
        let outputFileURL = try #require(traceRuntime.outputFileURL)
        let contents = try String(contentsOf: outputFileURL, encoding: .utf8)
        let derivedLines = contents.split(separator: "\n").filter {
            $0.contains("\"body\":\"performance.atom.derived\"")
        }
        return (
            compute: derivedLines.count {
                $0.contains("\"agentstudio.performance.atom.operation\":\"compute\"")
            },
            cacheHit: derivedLines.count {
                $0.contains("\"agentstudio.performance.atom.operation\":\"cache_hit\"")
            }
        )
    }

    private struct ProductionSnapshotFixture {
        let atom: WorkspaceTabLayoutAtom
        let initialTab: Tab
        let restoredTab: Tab
        let defaultArrangement: PaneArrangement
        let focusedArrangement: PaneArrangement
        let firstPaneId: UUID
        let secondDrawerPaneId: UUID
        let drawerId: UUID
    }
}

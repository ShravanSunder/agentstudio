import Foundation
import Testing

@testable import AgentStudio
@testable import AgentStudioBridge
@testable import AgentStudioCore
@testable import AgentStudioEditorChooser
@testable import AgentStudioInboxNotification
@testable import AgentStudioInfrastructure
@testable import AgentStudioTestSupport

@MainActor
@Suite("AtomRegistry")
struct AtomRegistryTests {
    @Test("default initializer constructs the complete App root")
    func defaultInitializerConstructsCompleteAppRoot() {
        let atomRegistry = AtomRegistry()

        #expect(atomRegistry.core.workspacePane.graphAtom === atomRegistry.core.workspacePaneGraph)
        #expect(atomRegistry.repoExplorerSidebarPrefs.groupingMode == .repo)
        #expect(atomRegistry.terminalActivity.snapshotsByPaneId.isEmpty)
        #expect(atomRegistry.editorChooser.bookmarkedEditorId == nil)
        #expect(atomRegistry.inboxNotification.notifications.isEmpty)
        #expect(atomRegistry.inboxSidebarState.collapsedGroups.isEmpty)
        #expect(atomRegistry.bridgePaneAttendance.ordinalByPaneId.isEmpty)
    }

    @Test("injected Core graph is retained by exact identity")
    func injectedCoreGraphIsRetainedByExactIdentity() {
        let coreAtoms = makeInstalledTestCoreAtoms()

        let atomRegistry = AtomRegistry(core: coreAtoms)

        #expect(atomRegistry.core === coreAtoms)
    }

    @Test("Feature facades use the exact stored backing atoms")
    func featureFacadesUseExactStoredBackingAtoms() {
        let editorPreference = EditorPreferenceAtom()
        let editorChooserRuntime = EditorChooserRuntimeAtom()
        let inboxSidebarMemory = InboxSidebarMemoryAtom()
        let inboxSidebarRuntime = InboxSidebarRuntimeAtom()
        let atomRegistry = AtomRegistry(
            editorPreference: editorPreference,
            editorChooserRuntime: editorChooserRuntime,
            inboxSidebarMemory: inboxSidebarMemory,
            inboxSidebarRuntime: inboxSidebarRuntime
        )

        editorPreference.setBookmarkedEditor(ExternalEditorTarget.cursor.id)
        let paneId = UUID()
        editorChooserRuntime.setOpenEditorPane(paneId)
        let groupKey = InboxNotificationGroupKey("repo:atom-registry")
        inboxSidebarMemory.setGroupCollapsed(groupKey, isCollapsed: true)
        let filter = InboxFilter.repo(id: UUID())
        inboxSidebarRuntime.setPendingFilter(filter)

        #expect(atomRegistry.editorPreference === editorPreference)
        #expect(atomRegistry.editorChooserRuntime === editorChooserRuntime)
        #expect(atomRegistry.editorChooser.bookmarkedEditorId == ExternalEditorTarget.cursor.id)
        #expect(atomRegistry.editorChooser.openForPaneId == paneId)
        #expect(atomRegistry.inboxSidebarMemory === inboxSidebarMemory)
        #expect(atomRegistry.inboxSidebarRuntime === inboxSidebarRuntime)
        #expect(atomRegistry.inboxSidebarState.collapsedGroups.contains(groupKey))
        #expect(atomRegistry.inboxSidebarState.pendingFilter == filter)
    }
}

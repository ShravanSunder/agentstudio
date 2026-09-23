import Foundation
import Testing

@testable import AgentStudioCore

@MainActor
@Suite("WorkspaceDrawerCursorAtom")
struct WorkspaceDrawerCursorAtomTests {
    @Test("replacement stores one expanded drawer or no expanded drawer")
    func replacementStoresOneExpandedDrawerOrNoExpandedDrawer() {
        let atom = WorkspaceDrawerCursorAtom()
        let firstDrawerID = UUID()
        let secondDrawerID = UUID()

        atom.replaceExpandedDrawer(firstDrawerID)
        #expect(atom.expandedDrawerId == firstDrawerID)

        atom.replaceExpandedDrawer(secondDrawerID)
        #expect(atom.expandedDrawerId == secondDrawerID)

        atom.replaceExpandedDrawer(nil)
        #expect(atom.expandedDrawerId == nil)
    }

    @Test("missing owners read defaults without inserting a preference")
    func missingOwnerReadsDefault() {
        let atom = WorkspaceDrawerCursorAtom()
        let ownerPaneId = UUID()

        #expect(atom.presentationPreference(forOwner: ownerPaneId) == .default)
        atom.setPresentationPreference(.default, forOwner: ownerPaneId)

        #expect(atom.presentationPreferencesByOwnerPaneId.isEmpty)
        #expect(atom.presentationPreferenceRevision == 0)
    }

    @Test("owners keep independent heights and sides")
    func ownersKeepIndependentPreferences() {
        let atom = WorkspaceDrawerCursorAtom()
        let paneA = UUID()
        let paneB = UUID()

        atom.setPresentationPreference(
            DrawerPresentationPreference(normalHeightRatio: 0.4, zoomSide: .bridge),
            forOwner: paneA
        )
        atom.setPresentationPreference(
            DrawerPresentationPreference(normalHeightRatio: 0.6, zoomSide: .terminal),
            forOwner: paneB
        )

        #expect(atom.presentationPreference(forOwner: paneA).normalHeightRatio == 0.4)
        #expect(atom.presentationPreference(forOwner: paneA).zoomSide == .bridge)
        #expect(atom.presentationPreference(forOwner: paneB).normalHeightRatio == 0.6)
        #expect(atom.presentationPreference(forOwner: paneB).zoomSide == .terminal)
    }

    @Test("equal writes are suppressed and do not bump the preference revision")
    func equalWritesAreSuppressed() {
        let atom = WorkspaceDrawerCursorAtom()
        let ownerPaneId = UUID()
        let preference = DrawerPresentationPreference(normalHeightRatio: 0.5, zoomSide: .bridge)

        atom.setPresentationPreference(preference, forOwner: ownerPaneId)
        let revisionAfterFirstWrite = atom.presentationPreferenceRevision
        atom.setPresentationPreference(preference, forOwner: ownerPaneId)

        #expect(revisionAfterFirstWrite == 1)
        #expect(atom.presentationPreferenceRevision == revisionAfterFirstWrite)
    }

    @Test("replacement installs the hydrated map and drops owners not in it")
    func replacementInstallsHydratedMap() {
        let atom = WorkspaceDrawerCursorAtom()
        let stale = UUID()
        let restored = UUID()
        atom.setPresentationPreference(
            DrawerPresentationPreference(normalHeightRatio: 0.3, zoomSide: .terminal),
            forOwner: stale
        )

        atom.replacePresentationPreferences([
            restored: DrawerPresentationPreference(normalHeightRatio: 0.7, zoomSide: .bridge)
        ])

        #expect(atom.presentationPreference(forOwner: stale) == .default)
        #expect(atom.presentationPreference(forOwner: restored).zoomSide == .bridge)
    }
}

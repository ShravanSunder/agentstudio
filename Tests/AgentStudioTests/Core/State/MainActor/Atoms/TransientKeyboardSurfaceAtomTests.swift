import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("TransientKeyboardSurfaceAtom")
struct TransientKeyboardSurfaceAtomTests {
    @Test("surfaces are exposed as a token-scoped stack")
    func surfacesAreTokenScopedStack() {
        let atom = TransientKeyboardSurfaceAtom()
        let workspaceWindowId = UUID()
        let firstTabId = UUID()
        let secondTabId = UUID()

        let firstToken = atom.present(.tabRename(tabId: firstTabId), workspaceWindowId: workspaceWindowId)
        let secondToken = atom.present(.tabRename(tabId: secondTabId), workspaceWindowId: workspaceWindowId)

        #expect(atom.surfaces.map(\.token) == [firstToken, secondToken])
        #expect(atom.topAnySurface?.kind == .tabRename(tabId: secondTabId))
        #expect(atom.topSurface(for: workspaceWindowId)?.kind == .tabRename(tabId: secondTabId))

        atom.dismiss(firstToken)

        #expect(atom.surfaces.map(\.token) == [secondToken])
        #expect(atom.topSurface(for: workspaceWindowId)?.kind == .tabRename(tabId: secondTabId))

        atom.dismiss(secondToken)

        #expect(atom.surfaces.isEmpty)
        #expect(atom.topAnySurface == nil)
    }

    @Test("window scoped lookup ignores transients from other workspace windows")
    func windowScopedLookupIgnoresOtherWorkspaceWindows() {
        let atom = TransientKeyboardSurfaceAtom()
        let firstWindowId = UUID()
        let secondWindowId = UUID()
        let firstTabId = UUID()
        let secondTabId = UUID()

        _ = atom.present(.tabRename(tabId: firstTabId), workspaceWindowId: firstWindowId)
        _ = atom.present(.tabRename(tabId: secondTabId), workspaceWindowId: secondWindowId)

        #expect(atom.topAnySurface?.kind == .tabRename(tabId: secondTabId))
        #expect(atom.topSurface(for: firstWindowId)?.kind == .tabRename(tabId: firstTabId))
        #expect(atom.topSurface(for: UUID()) == nil)
    }

    @Test("replace updates kind atomically while preserving token and stack order")
    func replaceUpdatesKindAtomicallyWhilePreservingTokenAndStackOrder() {
        let atom = TransientKeyboardSurfaceAtom()
        let workspaceWindowId = UUID()
        let tabId = UUID()
        let arrangementId = UUID()
        let firstToken = atom.present(.tabRename(tabId: UUID()), workspaceWindowId: workspaceWindowId)
        let secondToken = atom.present(.arrangementPanel(tabId: tabId), workspaceWindowId: workspaceWindowId)

        atom.replace(
            secondToken,
            with: .arrangementRename(tabId: tabId, arrangementId: arrangementId),
            workspaceWindowId: workspaceWindowId
        )

        #expect(atom.surfaces.map(\.token) == [firstToken, secondToken])
        #expect(
            atom.topSurface(for: workspaceWindowId)?.kind
                == .arrangementRename(tabId: tabId, arrangementId: arrangementId))
    }

    @Test("replace ignores stale tokens instead of appending leaked surfaces")
    func replaceIgnoresStaleTokensInsteadOfAppendingLeakedSurfaces() {
        let atom = TransientKeyboardSurfaceAtom()
        let workspaceWindowId = UUID()
        let existingToken = atom.present(.tabRename(tabId: UUID()), workspaceWindowId: workspaceWindowId)
        let replacementKind = TransientKeyboardSurfaceKind.arrangementPanel(tabId: UUID())

        atom.replace(
            TransientKeyboardSurfaceToken(),
            with: replacementKind,
            workspaceWindowId: workspaceWindowId
        )

        #expect(atom.surfaces.map(\.token) == [existingToken])
        #expect(atom.topSurface(for: workspaceWindowId)?.kind != replacementKind)
    }

    @Test("surfaces preserve dismiss policy through present and replace")
    func surfacesPreserveDismissPolicyThroughPresentAndReplace() {
        let atom = TransientKeyboardSurfaceAtom()
        let workspaceWindowId = UUID()
        let tabId = UUID()
        let arrangementId = UUID()
        let panelPolicy = TransientKeyboardSurfacePolicy.dismissable(
            dismissTriggers: [ShortcutTrigger(key: .character(.i), modifiers: [.command, .option])]
        )
        let renamePolicy = TransientKeyboardSurfacePolicy.dismissable(
            dismissTriggers: [ShortcutTrigger(key: .character(.i), modifiers: [.command, .option])],
            consumesEscape: false
        )

        let token = atom.present(
            .arrangementPanel(tabId: tabId),
            workspaceWindowId: workspaceWindowId,
            policy: panelPolicy
        )
        atom.replace(
            token,
            with: .arrangementRename(tabId: tabId, arrangementId: arrangementId),
            workspaceWindowId: workspaceWindowId,
            policy: renamePolicy
        )

        #expect(atom.topSurface(for: workspaceWindowId)?.policy == renamePolicy)
    }

    @Test("mixed transient kinds remain token scoped and window scoped")
    func mixedTransientKindsRemainTokenScopedAndWindowScoped() {
        let atom = TransientKeyboardSurfaceAtom()
        let firstWindowId = UUID()
        let secondWindowId = UUID()
        let tabId = UUID()
        let arrangementId = UUID()
        let parentPaneId = UUID()
        let editorPaneId = UUID()

        let arrangementToken = atom.present(.arrangementPanel(tabId: tabId), workspaceWindowId: firstWindowId)
        let renameToken = atom.present(
            .arrangementRename(tabId: tabId, arrangementId: arrangementId),
            workspaceWindowId: firstWindowId
        )
        let inboxToken = atom.present(.paneInbox(parentPaneId: parentPaneId), workspaceWindowId: secondWindowId)
        let editorToken = atom.present(.editorChooser(paneId: editorPaneId), workspaceWindowId: firstWindowId)

        #expect(atom.surfaces.map(\.token) == [arrangementToken, renameToken, inboxToken, editorToken])
        #expect(atom.topAnySurface?.kind == .editorChooser(paneId: editorPaneId))
        #expect(atom.topSurface(for: firstWindowId)?.kind == .editorChooser(paneId: editorPaneId))
        #expect(atom.topSurface(for: secondWindowId)?.kind == .paneInbox(parentPaneId: parentPaneId))

        atom.dismiss(editorToken)

        #expect(
            atom.topSurface(for: firstWindowId)?.kind
                == .arrangementRename(
                    tabId: tabId,
                    arrangementId: arrangementId
                ))
    }
}

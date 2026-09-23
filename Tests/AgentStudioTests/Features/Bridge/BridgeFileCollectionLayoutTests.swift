import AgentStudioCore
import AgentStudioInfrastructure
import Foundation
import Testing

@testable import AgentStudioBridge

struct BridgeFileCollectionLayoutTests {
    @Test("equal worktree folder names get distinct group keys that resolve back to their member")
    func equalFolderNamesResolveToTheirOwnMembers() {
        // Arrange
        let first = member("/work/a/app")
        let second = member("/work/b/app")

        // Act
        let layout = BridgeFileCollectionLayout.empty.updating(members: [first, second], openedDocuments: [])

        // Assert
        #expect(layout.memberGroups.map(\.groupPath) == ["app", "app (2)"])
        #expect(
            layout.resolve(displayPath: "app/src/main.ts")
                == .memberPath(worktreeId: first.worktreeId, relativePath: "src/main.ts")
        )
        #expect(
            layout.resolve(displayPath: "app (2)/src/main.ts")
                == .memberPath(worktreeId: second.worktreeId, relativePath: "src/main.ts")
        )
        #expect(layout.resolve(displayPath: "app (2)") == .memberGroup(worktreeId: second.worktreeId))
        #expect(layout.resolve(displayPath: "elsewhere/main.ts") == nil)
    }

    @Test("membership changes never re-key a surviving member or document")
    func surviveMembershipChangesWithTheirKeys() throws {
        // Arrange
        let first = member("/work/a/app")
        let second = member("/work/b/app")
        let notes = try #require(BridgeDocumentLocation(canonicalPath: "/tmp/one/notes.md"))
        let layout = BridgeFileCollectionLayout.empty.updating(
            members: [first, second],
            openedDocuments: [notes]
        )

        // Act
        let afterRemoval = layout.updating(members: [second], openedDocuments: [notes])
        let afterReAdd = afterRemoval.updating(members: [second, first], openedDocuments: [notes])

        // Assert
        #expect(afterRemoval.memberGroups.map(\.groupPath) == ["app (2)"])
        #expect(afterReAdd.memberGroups.map(\.groupPath) == ["app (2)", "app"])
        #expect(afterReAdd.openedDocuments.map(\.displayPath) == ["Open Files/notes.md"])
    }

    @Test("a nested member owns its subtree and the outer member never lists it")
    func nestedMemberOwnsItsSubtree() {
        // Arrange
        let outer = member("/work/repo")
        let nested = member("/work/repo/.worktrees/feature")

        // Act
        let layout = BridgeFileCollectionLayout.empty.updating(members: [outer, nested], openedDocuments: [])

        // Assert
        #expect(layout.displayPath(worktreeId: outer.worktreeId, relativePath: "src/a.ts") == "repo/src/a.ts")
        #expect(layout.displayPath(worktreeId: outer.worktreeId, relativePath: ".worktrees/feature/a.ts") == nil)
        #expect(layout.displayPath(worktreeId: outer.worktreeId, relativePath: ".worktrees/other/a.ts") != nil)
        #expect(layout.displayPath(worktreeId: nested.worktreeId, relativePath: "a.ts") == "feature/a.ts")
        #expect(layout.resolve(displayPath: "repo/.worktrees/feature/a.ts") == nil)
    }

    @Test("opened documents outside members are listed by location; members keep their own files")
    func openedDocumentsAreGroupedByLocation() throws {
        // Arrange
        let worktree = member("/work/app")
        let inside = try #require(BridgeDocumentLocation(canonicalPath: "/work/app/README.md"))
        let first = try #require(BridgeDocumentLocation(canonicalPath: "/tmp/one/notes.md"))
        let second = try #require(BridgeDocumentLocation(canonicalPath: "/tmp/two/notes.md"))

        // Act
        let layout = BridgeFileCollectionLayout.empty.updating(
            members: [worktree],
            openedDocuments: [inside, first, second]
        )

        // Assert
        #expect(layout.openedDocuments.map(\.location) == [first, second])
        #expect(layout.openedDocuments.map(\.displayPath) == ["Open Files/notes.md", "Open Files/notes (2).md"])
        #expect(layout.resolve(displayPath: "Open Files/notes (2).md") == .openedDocument(second))
        #expect(layout.resolve(displayPath: "Open Files") == .openedDocumentsGroup)
    }

    @Test("equal member roots leave a contained document listed by location, never guessed")
    func ambiguousEqualRootsKeepDocumentLoose() throws {
        // Arrange
        let first = member("/work/app")
        let second = member("/work/app")
        let document = try #require(BridgeDocumentLocation(canonicalPath: "/work/app/notes.md"))

        // Act
        let layout = BridgeFileCollectionLayout.empty.updating(members: [first, second], openedDocuments: [document])

        // Assert
        #expect(layout.openedDocuments.map(\.location) == [document])
    }

    @Test("a worktree folder named like the opened-documents group gets its own key")
    func reservedGroupNameIsNeverShared() {
        // Act
        let layout = BridgeFileCollectionLayout.empty.updating(
            members: [member("/work/Open Files")],
            openedDocuments: []
        )

        // Assert
        #expect(layout.memberGroups.map(\.groupPath) == ["Open Files (2)"])
    }

    private func member(_ root: String) -> BridgeFileCollectionMember {
        BridgeFileCollectionMember(worktreeId: UUIDv7.generate(), canonicalRootPath: root)
    }
}

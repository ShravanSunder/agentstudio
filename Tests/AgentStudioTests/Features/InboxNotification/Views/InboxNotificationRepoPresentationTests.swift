import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("InboxNotification repo presentation", .serialized)
struct InboxNotificationRepoPresentationTests {

    @Test("resolver matches repo explorer title owner and color inputs")
    func resolverMatchesRepoExplorerInputs() throws {
        let repoId = UUID()
        let worktree = Worktree(
            id: UUID(),
            repoId: repoId,
            name: "notification-inbox-redesign",
            path: URL(fileURLWithPath: "/tmp/agent-studio.notification-inbox-redesign"),
            isMainWorktree: false
        )
        let repo = Repo(
            id: repoId,
            name: "agent-studio.notification-inbox-redesign",
            repoPath: URL(fileURLWithPath: "/tmp/agent-studio"),
            worktrees: [worktree]
        )
        let identity = RepoIdentity(
            groupKey: "github:ShravanSunder/agent-studio",
            remoteSlug: "ShravanSunder/agent-studio",
            organizationName: "ShravanSunder",
            displayName: "agent-studio"
        )

        let presentations = InboxNotificationSidebarView.repoPresentationByRepoId(
            repos: [repo],
            repoEnrichmentByRepoId: [
                repoId: .resolvedRemote(
                    repoId: repoId,
                    raw: RawRepoOrigin(
                        origin: "git@github.com:ShravanSunder/agent-studio.git",
                        upstream: nil
                    ),
                    identity: identity,
                    updatedAt: Date(timeIntervalSince1970: 100)
                )
            ],
            checkoutColors: [SidebarCheckoutColorKey(repoId.uuidString): "#EAC54F"]
        )
        let presentation = try #require(presentations[repoId])
        let expectedAccentColorHex = RepoPresentationColoring.checkoutColorHex(
            for: RepoPresentationItem(repo: repo),
            in: RepoPresentationGroup(
                id: identity.groupKey,
                repoTitle: identity.displayName,
                organizationName: identity.organizationName,
                repos: [RepoPresentationItem(repo: repo)]
            ),
            checkoutColorOverrides: [repoId.uuidString: "#EAC54F"]
        )

        #expect(presentation.groupId == "github:ShravanSunder/agent-studio")
        #expect(presentation.title == "agent-studio")
        #expect(presentation.organizationName == "ShravanSunder")
        #expect(presentation.accentColorHex == expectedAccentColorHex)
    }

    @Test("resolver gives shared group id and color to collapsed repo family")
    func resolverGivesSharedGroupIdAndColorToCollapsedRepoFamily() throws {
        let mainRepoId = UUID()
        let forkRepoId = UUID()
        let mainRepo = Repo(
            id: mainRepoId,
            name: "agent-studio",
            repoPath: URL(fileURLWithPath: "/tmp/agent-studio"),
            worktrees: [
                Worktree(
                    repoId: mainRepoId,
                    name: "main",
                    path: URL(fileURLWithPath: "/tmp/agent-studio"),
                    isMainWorktree: true
                )
            ]
        )
        let forkRepo = Repo(
            id: forkRepoId,
            name: "agent-studio.notification-inbox-redesign",
            repoPath: URL(fileURLWithPath: "/tmp/agent-studio.notification-inbox-redesign"),
            worktrees: [
                Worktree(
                    repoId: forkRepoId,
                    name: "notification-inbox-redesign",
                    path: URL(fileURLWithPath: "/tmp/agent-studio.notification-inbox-redesign")
                )
            ]
        )
        let identity = RepoIdentity(
            groupKey: "github:ShravanSunder/agent-studio",
            remoteSlug: "ShravanSunder/agent-studio",
            organizationName: "ShravanSunder",
            displayName: "agent-studio"
        )

        let presentations = InboxNotificationSidebarView.repoPresentationByRepoId(
            repos: [forkRepo, mainRepo],
            repoEnrichmentByRepoId: [
                mainRepoId: .resolvedRemote(
                    repoId: mainRepoId,
                    raw: RawRepoOrigin(
                        origin: "git@github.com:ShravanSunder/agent-studio.git",
                        upstream: nil
                    ),
                    identity: identity,
                    updatedAt: Date(timeIntervalSince1970: 100)
                ),
                forkRepoId: .resolvedRemote(
                    repoId: forkRepoId,
                    raw: RawRepoOrigin(
                        origin: "git@github.com:ShravanSunder/agent-studio.git",
                        upstream: nil
                    ),
                    identity: identity,
                    updatedAt: Date(timeIntervalSince1970: 100)
                ),
            ],
            checkoutColors: [SidebarCheckoutColorKey(mainRepoId.uuidString): "#EAC54F"]
        )
        let mainPresentation = try #require(presentations[mainRepoId])
        let forkPresentation = try #require(presentations[forkRepoId])

        #expect(mainPresentation.groupId == "github:ShravanSunder/agent-studio")
        #expect(forkPresentation.groupId == "github:ShravanSunder/agent-studio")
        #expect(mainPresentation.title == "agent-studio")
        #expect(forkPresentation.title == "agent-studio")
        #expect(mainPresentation.organizationName == "ShravanSunder")
        #expect(forkPresentation.organizationName == "ShravanSunder")
        #expect(mainPresentation.accentColorHex == forkPresentation.accentColorHex)
    }

    @Test("resolver assigns shared family presentation to deduped repo ids")
    func resolverAssignsSharedFamilyPresentationToDedupedRepoIds() throws {
        let sharedPath = URL(fileURLWithPath: "/tmp/acme/feature-x")
        let ownerRepoId = UUID()
        let duplicateRepoId = UUID()
        let ownerRepo = Repo(
            id: ownerRepoId,
            name: "acme-main",
            repoPath: URL(fileURLWithPath: "/tmp/acme/main"),
            worktrees: [
                Worktree(
                    repoId: ownerRepoId,
                    name: "main",
                    path: URL(fileURLWithPath: "/tmp/acme/main"),
                    isMainWorktree: true
                ),
                Worktree(
                    repoId: ownerRepoId,
                    name: "feature-x",
                    path: sharedPath
                ),
                Worktree(
                    repoId: ownerRepoId,
                    name: "hotfix",
                    path: URL(fileURLWithPath: "/tmp/acme/hotfix")
                ),
            ]
        )
        let duplicateRepo = Repo(
            id: duplicateRepoId,
            name: "acme-feature-x-standalone",
            repoPath: sharedPath,
            worktrees: [
                Worktree(
                    repoId: duplicateRepoId,
                    name: "feature-x",
                    path: sharedPath
                )
            ]
        )
        let identity = RepoIdentity(
            groupKey: "github:acme/acme-main",
            remoteSlug: "acme/acme-main",
            organizationName: "acme",
            displayName: "acme-main"
        )

        let presentations = InboxNotificationSidebarView.repoPresentationByRepoId(
            repos: [ownerRepo, duplicateRepo],
            repoEnrichmentByRepoId: [
                ownerRepoId: .resolvedRemote(
                    repoId: ownerRepoId,
                    raw: RawRepoOrigin(
                        origin: "git@github.com:acme/acme-main.git",
                        upstream: nil
                    ),
                    identity: identity,
                    updatedAt: Date(timeIntervalSince1970: 100)
                ),
                duplicateRepoId: .resolvedRemote(
                    repoId: duplicateRepoId,
                    raw: RawRepoOrigin(
                        origin: "git@github.com:acme/acme-main.git",
                        upstream: nil
                    ),
                    identity: identity,
                    updatedAt: Date(timeIntervalSince1970: 100)
                ),
            ],
            checkoutColors: [SidebarCheckoutColorKey(ownerRepoId.uuidString): "#EAC54F"]
        )
        let ownerPresentation = try #require(presentations[ownerRepoId])
        let duplicatePresentation = try #require(presentations[duplicateRepoId])

        #expect(duplicatePresentation.groupId == ownerPresentation.groupId)
        #expect(duplicatePresentation.title == ownerPresentation.title)
        #expect(duplicatePresentation.organizationName == ownerPresentation.organizationName)
        #expect(duplicatePresentation.accentColorHex == ownerPresentation.accentColorHex)
    }
}

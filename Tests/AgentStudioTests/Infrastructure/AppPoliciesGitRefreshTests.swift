import Foundation
import Testing

@testable import AgentStudioInfrastructure

@Suite("AppPolicies GitRefresh")
struct AppPoliciesGitRefreshTests {
    @Test("default policy captures active background budget and retry constants")
    func defaultPolicyCapturesRefreshConstants() {
        let policy = AppPolicies.GitRefresh.defaultPolicy

        #expect(policy.activePaneCadence == .seconds(15))
        #expect(policy.visibleSidebarCadence == .seconds(60))
        #expect(policy.openPaneCadence == .seconds(180))
        #expect(policy.backgroundCadence == .seconds(240))
        #expect(
            policy.backgroundCadence
                == Self.scaled(policy.activePaneCadence, by: policy.backgroundStripeCount)
        )
        #expect(policy.maxConcurrentStatusComputes == 4)
        #expect(policy.activePaneMaxConcurrent == 1)
        #expect(policy.visibleSidebarMaxConcurrent == 2)
        #expect(policy.openPaneMaxConcurrent == 1)
        #expect(policy.backgroundMaxConcurrent == 1)
        #expect(policy.visibleSidebarStripeSize == 8)
        #expect(policy.suppressedWorktreeTombstoneLimit == 1024)
        #expect(policy.lineDetailFreshnessInterval == .seconds(960))
        #expect(policy.minimumAutomaticStartInterval == .milliseconds(300))
        #expect(AppPolicies.GitRefresh.defaultStatusReadTimeout == .seconds(1))
        #expect(AppPolicies.GitRefresh.defaultDiscoveryReadTimeout == .seconds(2))
        #expect(AppPolicies.GitRefresh.defaultDetachedStatusReadLimit == 4)
        #expect(AppPolicies.GitRefresh.filesystemDebounceWindow == .milliseconds(500))
        #expect(AppPolicies.GitRefresh.filesystemMaxFlushLatency == .seconds(10))
        #expect(AppPolicies.GitRefresh.filesystemDerivedCoalescingWindow == .milliseconds(500))
        #expect(AppPolicies.GitRefresh.visibilityChangeCoalescingWindow == .milliseconds(200))
        #expect(
            AppPolicies.FilesystemIngress.maximumRetainedActivityOverflowParticipantScopes
                == 256
        )
        #expect(
            RepoScanner.AgentStudioGitRepositoryDiscoveryProvider.defaultTimeout
                == AppPolicies.GitRefresh.defaultDiscoveryReadTimeout
        )
        #expect(
            RepoScanner.AgentStudioGitRepositoryDiscoveryProvider.defaultTimeout
                != AppPolicies.GitRefresh.defaultStatusReadTimeout
        )
    }

    @Test("default policy stripes background work deterministically")
    func defaultPolicyStripesBackgroundWorkDeterministically() {
        let policy = AppPolicies.GitRefresh.defaultPolicy
        let firstWorktreeId = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let secondWorktreeId = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!

        let firstStripe = policy.backgroundStripe(for: firstWorktreeId)
        let repeatedStripe = policy.backgroundStripe(for: firstWorktreeId)
        let secondStripe = policy.backgroundStripe(for: secondWorktreeId)

        #expect(policy.backgroundStripeCount == 16)
        #expect(firstStripe == repeatedStripe)
        #expect((0..<policy.backgroundStripeCount).contains(firstStripe))
        #expect((0..<policy.backgroundStripeCount).contains(secondStripe))
    }

    @Test("background registration phase is deterministic and inside the finite cadence")
    func backgroundRegistrationPhaseIsDeterministicAndBounded() {
        let policy = AppPolicies.GitRefresh.defaultPolicy
        let worktreeId = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!
        let firstDelay = policy.backgroundRegistrationDelay(for: worktreeId)
        let repeatedDelay = policy.backgroundRegistrationDelay(for: worktreeId)

        #expect(firstDelay == repeatedDelay)
        #expect(firstDelay > .zero)
        #expect(firstDelay <= policy.backgroundCadence)
    }

    private static func scaled(_ duration: Duration, by multiplier: Int) -> Duration {
        var scaledDuration = Duration.zero
        for _ in 0..<multiplier {
            scaledDuration += duration
        }
        return scaledDuration
    }
}

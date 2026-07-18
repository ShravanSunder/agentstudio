import Foundation
import Testing

@testable import AgentStudio

@Suite("AppPolicies GitRefresh")
struct AppPoliciesGitRefreshTests {
    @Test("default policy captures active background budget and retry constants")
    func defaultPolicyCapturesRefreshConstants() {
        let policy = AppPolicies.GitRefresh.defaultPolicy

        #expect(policy.activeCadence == .seconds(15))
        #expect(policy.backgroundCadence == .seconds(240))
        #expect(
            policy.backgroundCadence
                == Self.scaled(policy.activeCadence, by: policy.backgroundStripeCount)
        )
        #expect(policy.maxConcurrentStatusComputes == 4)
        #expect(policy.oldestStaleReservedSlots == 1)
        #expect(policy.suppressedWorktreeTombstoneLimit == 1024)
        #expect(policy.maxNilStatusRetries == 1)
        #expect(policy.nilStatusRetryDelay > .zero)
        #expect(AppPolicies.GitRefresh.defaultStatusReadTimeout == .seconds(1))
        #expect(AppPolicies.GitRefresh.defaultDiscoveryReadTimeout == .seconds(2))
        #expect(AppPolicies.GitRefresh.defaultDetachedStatusReadLimit == 4)
        #expect(AppPolicies.GitRefresh.filesystemDebounceWindow == .milliseconds(500))
        #expect(AppPolicies.GitRefresh.filesystemMaxFlushLatency == .seconds(10))
        #expect(AppPolicies.GitRefresh.filesystemDerivedCoalescingWindow == .milliseconds(500))
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

    @Test("background due check admits only the matching stripe")
    func backgroundDueCheckAdmitsOnlyMatchingStripe() {
        let policy = AppPolicies.GitRefresh.defaultPolicy
        let worktreeId = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!
        let stripe = policy.backgroundStripe(for: worktreeId)

        #expect(policy.isBackgroundWorktreeDue(worktreeId, tick: UInt64(stripe)))
        #expect(!policy.isBackgroundWorktreeDue(worktreeId, tick: UInt64((stripe + 1) % policy.backgroundStripeCount)))
        #expect(policy.isBackgroundWorktreeDue(worktreeId, tick: UInt64(stripe + policy.backgroundStripeCount)))
    }

    private static func scaled(_ duration: Duration, by multiplier: Int) -> Duration {
        var scaledDuration = Duration.zero
        for _ in 0..<multiplier {
            scaledDuration += duration
        }
        return scaledDuration
    }
}

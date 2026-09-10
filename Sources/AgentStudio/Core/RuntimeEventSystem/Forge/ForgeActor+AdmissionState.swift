import AgentStudioInfrastructure
import Foundation

extension ForgeActor {
    struct RepositoryRefreshState {
        var origin: String?
        var generation: UInt64 = 0
        var lastSuccessfulRefreshAt: Duration?
        var lastAttemptAt: Duration?
        var backoffUntil: Duration?
        var activeRequestId: UInt64?
        var activeRequestSignature: ProviderRequestSignature?
        var pendingFollowUp = false
        var pendingFollowUpRequiresRefresh = false
        var pendingFollowUpHasUnconfirmedScopeChange = false
        var pendingFollowUpEligibleAt: Duration?
        var consecutiveFailureCount = 0
        var stablePresentation: PullRequestStablePresentation = .unknown
        var acceptedProjection: PullRequestRepositoryProjection = .stable(.unknown)
        /// Consecutive non-`.complete` provider outcomes (truncated, rate
        /// limited, or failed), independent of `consecutiveFailureCount`
        /// which drives `.failed`-specific backoff timing. Crossing
        /// `AppPolicies.Forge.consecutiveFailureHonestyThreshold` resolves
        /// this repository to terminal-unavailable.
        var consecutiveUnsuccessfulAttempts = 0
        /// True once the terminal unavailable projection has been accepted
        /// for the repository's current origin generation. Cleared whenever
        /// a fresh origin arrives or a query succeeds.
        var hasEmittedUnavailable = false
    }

    struct ProviderRequest: Sendable {
        let id: UInt64
        let repoId: UUID
        let origin: String
        let generation: UInt64
        let demandedBranches: Set<String>
        let trigger: RefreshTrigger
        let correlationId: UUID?
        let explicitAttemptIds: Set<UUID>

        var signature: ProviderRequestSignature {
            ProviderRequestSignature(origin: origin, demandedBranches: demandedBranches)
        }
    }

    struct ExplicitRepositoryUpdateAttempt {
        let repoId: UUID
        let generation: UInt64
        let origin: String
        var branches: Set<String>
        let settlement: RepositoryFactSourceUpdateSettlement
    }

    struct ProviderRequestSignature: Equatable, Sendable {
        let origin: String
        let demandedBranches: Set<String>
    }

    enum RefreshTrigger {
        case automatic
        case manual
        case manualFollowUp
        case scopeChanged
        case followUp

        var bypassesFreshness: Bool {
            switch self {
            case .automatic, .followUp: false
            case .manual, .manualFollowUp, .scopeChanged: true
            }
        }

        var requiresFollowUpRefresh: Bool {
            switch self {
            case .manual: true
            case .automatic, .manualFollowUp, .scopeChanged, .followUp: false
            }
        }

        var hasUnconfirmedScopeChange: Bool {
            if case .scopeChanged = self { return true }
            return false
        }

        var performanceInput: ForgePerformanceInput {
            switch self {
            case .automatic: .automatic
            case .manual: .manual
            case .manualFollowUp, .scopeChanged, .followUp: .followUp
            }
        }

        var usesAutomaticFailureFloor: Bool {
            switch self {
            case .automatic, .scopeChanged, .followUp: true
            case .manual, .manualFollowUp: false
            }
        }
    }
}

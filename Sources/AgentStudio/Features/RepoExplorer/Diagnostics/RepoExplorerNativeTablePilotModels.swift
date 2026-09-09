import Foundation

package struct RepoExplorerNativeTablePilotResult: Equatable, Sendable {
    package enum FailureReason: String, Error, Equatable, Sendable {
        case completionTimeout = "completion_timeout"
        case cancelled
        case fixtureInvalid = "fixture_invalid"
        case transactionInvalid = "transaction_invalid"
        case measurementCountMismatch = "measurement_count_mismatch"
        case membershipP95Exceeded = "membership_p95_exceeded"
        case doubledGrowthExceeded = "doubled_growth_exceeded"
    }

    package static let resultVersion = 1

    package let policyID: String
    package let policyVersion: Int
    package let scaleCount: Int
    package let livenessProjectionCount: Int
    package let drainedScaleCount: Int
    package let templatePairCount: Int
    package let warmupTransactionCountPerScale: Int
    package let measuredTransactionCountPerScale: Int
    package let baselineMeasurementCount: Int
    package let doubledMeasurementCount: Int
    package let baselineMembershipP95Milliseconds: Double
    package let doubledMembershipP95Milliseconds: Double
    package let doubledOffscreenGrowthPercent: Double
    package let exactness: Bool
    package let completed: Bool
    package let passed: Bool
    package let failureReason: FailureReason?
}

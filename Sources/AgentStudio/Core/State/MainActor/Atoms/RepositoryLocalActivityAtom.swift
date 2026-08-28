import AgentStudioInfrastructure
import Observation

package enum RepositoryLocalActivityHydrationDisposition: Equatable, Sendable {
    case pending
    case authoritative
    case unavailable
}

@MainActor
@Observable
package final class RepositoryLocalActivityAtom {
    package private(set) var hydrationDisposition: RepositoryLocalActivityHydrationDisposition = .pending
    package private(set) var acceptedRevision = 0

    @ObservationIgnored private let activityFamily = AtomFamily<String, RepositoryLocalActivity>(
        telemetryLabel: "repository_local_activity",
        isContentEqual: ==
    )
    @ObservationIgnored private let acceptedMutationRevision = AtomRevision()
    @ObservationIgnored private var acceptedActivityByRepositoryStableKey: [String: RepositoryLocalActivity] = [:]

    package init() {}

    package func activity(for repositoryStableKey: String) -> RepositoryLocalActivity? {
        activityFamily.value(for: repositoryStableKey)
    }

    package func snapshot() -> [String: RepositoryLocalActivity] {
        acceptedActivityByRepositoryStableKey
    }

    package func publishAuthoritative(_ snapshot: RepositoryLocalActivitySnapshot) {
        publish(
            activityByRepositoryStableKey: snapshot.activityByRepositoryStableKey,
            disposition: .authoritative
        )
    }

    package func publishUnavailable() {
        publish(activityByRepositoryStableKey: [:], disposition: .unavailable)
    }

    private func publish(
        activityByRepositoryStableKey: [String: RepositoryLocalActivity],
        disposition: RepositoryLocalActivityHydrationDisposition
    ) {
        guard
            acceptedActivityByRepositoryStableKey != activityByRepositoryStableKey
                || hydrationDisposition != disposition
        else { return }
        let mutation = AtomMutationContext(aggregateRevision: acceptedMutationRevision)
        activityFamily.replaceAll(activityByRepositoryStableKey, mutation: mutation)
        mutation.commit()
        acceptedActivityByRepositoryStableKey = activityByRepositoryStableKey
        hydrationDisposition = disposition
        acceptedRevision &+= 1
    }
}

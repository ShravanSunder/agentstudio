import Foundation

@testable import AgentStudio

func constructContributionIdentityDirectly(
    binding: FilesystemObservationSlotBinding,
    value: UUID
) -> FilesystemObservationContributionIdentity {
    FilesystemObservationContributionIdentity(binding: binding, value: value)
}

@testable import AgentStudio

func invokeRemovedRawCallbackLeaseAdmissionSignature(
    lease: FSEventCallbackLease,
    controlBlockIdentity: FilesystemObservationControlBlockIdentity,
    registration: FSEventRegistrationToken,
    binding: FilesystemObservationSlotBinding,
    captureLimits: FSEventCaptureLimits
) {
    _ = lease.withOneShotCallbackAdmission(
        expectedControlBlockIdentity: controlBlockIdentity,
        expectedRegistration: registration,
        expectedBinding: binding,
        expectedCaptureLimits: captureLimits
    ) {}
}

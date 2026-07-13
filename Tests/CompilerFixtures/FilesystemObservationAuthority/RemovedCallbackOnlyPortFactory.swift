@testable import AgentStudio

func requestRemovedCallbackOnlyPortFactory(
    mailbox: FilesystemObservationMailbox,
    startingNativeLifetime: FilesystemObservationStartingNativeLifetime
) -> Any {
    mailbox.callbackAdmissionPort(for: startingNativeLifetime)
}

@testable import AgentStudio

func constructNativeLifecycleOperationDirectly() -> Any {
    FilesystemObservationNativeLifecycleOperation(
        startingNativeLifetime: fatalError("compiler-negative fixture"),
        callbackAdmissionPort: fatalError("compiler-negative fixture"),
        mailbox: fatalError("compiler-negative fixture")
    )
}

@testable import AgentStudio

func compilerNegativeCallbackAdmissionPortArgument<TArgument>() -> TArgument {
    fatalError("compiler-negative fixture")
}

func constructCallbackAdmissionPortDirectly() -> FilesystemObservationCallbackAdmissionPort {
    FilesystemObservationCallbackAdmissionPort(
        identity: compilerNegativeCallbackAdmissionPortArgument(),
        operation: compilerNegativeCallbackAdmissionPortArgument()
    )
}

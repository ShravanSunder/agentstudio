@testable import AgentStudio

func compilerNegativeCallbackLeaseArgument<TArgument>() -> TArgument {
    fatalError("compiler-negative fixture")
}

func constructCallbackLeaseDirectly() -> FSEventCallbackLease {
    FSEventCallbackLease(
        controlBlock: compilerNegativeCallbackLeaseArgument(),
        leaseID: 0
    )
}

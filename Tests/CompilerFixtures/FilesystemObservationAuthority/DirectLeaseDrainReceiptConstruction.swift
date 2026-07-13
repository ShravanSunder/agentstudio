@testable import AgentStudio

func compilerNegativeLeaseDrainReceiptArgument<TArgument>() -> TArgument {
    fatalError("compiler-negative fixture")
}

func constructLeaseDrainReceiptDirectly() -> DarwinFSEventRegistrationLeaseDrainReceipt {
    DarwinFSEventRegistrationLeaseDrainReceipt(
        binding: compilerNegativeLeaseDrainReceiptArgument(),
        nativeGenerationIdentity: compilerNegativeLeaseDrainReceiptArgument(),
        callbackContextCustody: compilerNegativeLeaseDrainReceiptArgument()
    )
}

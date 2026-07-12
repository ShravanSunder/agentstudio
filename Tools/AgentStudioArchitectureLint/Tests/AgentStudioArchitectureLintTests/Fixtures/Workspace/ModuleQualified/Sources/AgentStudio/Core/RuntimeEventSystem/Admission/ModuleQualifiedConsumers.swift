func consumeModuleQualifiedJournal(
    journal: AgentStudio.OrderedFactJournal<Int, String>,
    token: borrowing AdmissionProtectedRegionToken
) {
    _ = journal
    _ = token
}

struct ModuleQualifiedConsumers {
    init(
        journal: AgentStudio.OrderedFactJournal<Int, String>,
        token: borrowing AdmissionProtectedRegionToken
    ) {
        _ = journal
        _ = token
    }

    subscript(
        journal journal: AgentStudio.OrderedFactJournal<Int, String>,
        token token: borrowing AdmissionProtectedRegionToken
    ) -> Int {
        _ = journal
        _ = token
        return 0
    }
}

func retainOtherModuleJournal(
    journal: OtherModule.OrderedFactJournal<Int, String>,
    token: borrowing AdmissionProtectedRegionToken
) {
    _ = journal
    _ = token
}

enum ModuleQualifierShadow {
    typealias AgentStudio = OtherModule

    static func retainShadowedModuleJournal(
        journal: AgentStudio.OrderedFactJournal<Int, String>,
        token: borrowing AdmissionProtectedRegionToken
    ) {
        _ = journal
        _ = token
    }
}

extension AgentStudio.OrderedFactJournal {
    func exposeState(state: State) {
        _ = state
    }
}

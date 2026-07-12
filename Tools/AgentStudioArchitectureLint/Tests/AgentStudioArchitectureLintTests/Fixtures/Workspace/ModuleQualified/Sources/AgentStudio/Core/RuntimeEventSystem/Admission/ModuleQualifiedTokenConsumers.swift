func consumeModuleQualifiedToken(
    journal: OrderedFactJournal<Int, String>,
    token: borrowing AgentStudio.AdmissionProtectedRegionToken
) {
    _ = journal
    _ = token
}

struct ModuleQualifiedTokenConsumers {
    let escaped: (OrderedFactJournal<Int, String>, AgentStudio.AdmissionProtectedRegionToken)?

    init(
        journal: OrderedFactJournal<Int, String>,
        token: borrowing AgentStudio.AdmissionProtectedRegionToken
    ) {
        _ = journal
        _ = token
        escaped = nil
    }

    subscript(
        journal journal: OrderedFactJournal<Int, String>,
        token token: borrowing AgentStudio.AdmissionProtectedRegionToken
    ) -> Int {
        _ = journal
        _ = token
        return 0
    }
}

typealias ModuleQualifiedTokenAlias = AgentStudio.AdmissionProtectedRegionToken

func consumeModuleQualifiedTokenAlias(
    journal: OrderedFactJournal<Int, String>,
    token: borrowing ModuleQualifiedTokenAlias
) {
    _ = journal
    _ = token
}

extension OrderedFactJournal {
    func consumeModuleQualifiedToken(
        token: borrowing AgentStudio.AdmissionProtectedRegionToken
    ) {
        _ = token
    }
}

func retainOtherModuleToken(
    journal: OrderedFactJournal<Int, String>,
    token: borrowing OtherModule.AdmissionProtectedRegionToken
) {
    _ = journal
    _ = token
}

enum ModuleTokenQualifierShadow {
    typealias AgentStudio = OtherModule

    static func retainShadowedModuleToken(
        journal: OrderedFactJournal<Int, String>,
        token: borrowing AgentStudio.AdmissionProtectedRegionToken
    ) {
        _ = journal
        _ = token
    }
}

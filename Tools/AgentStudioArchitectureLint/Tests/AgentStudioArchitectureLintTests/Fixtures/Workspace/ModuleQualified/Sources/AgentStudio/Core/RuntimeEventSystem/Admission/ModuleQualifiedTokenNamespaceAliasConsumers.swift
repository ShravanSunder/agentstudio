enum AgentStudioTokenNamespace {
    typealias Token = AgentStudio.AdmissionProtectedRegionToken
}

typealias AgentStudioTokenNamespaceAlias = AgentStudioTokenNamespace

func consumeModuleQualifiedTokenThroughNamespaceAlias(
    journal: OrderedFactJournal<Int, String>,
    token: borrowing AgentStudioTokenNamespaceAlias.Token
) {
    _ = journal
    _ = token
}

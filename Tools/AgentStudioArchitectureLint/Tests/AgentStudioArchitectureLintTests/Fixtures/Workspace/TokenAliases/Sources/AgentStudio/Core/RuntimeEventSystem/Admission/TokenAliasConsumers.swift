func consumeTokenAlias(
    journal: OrderedFactJournal<Int, String>,
    token: borrowing ProtectedTokenAliasHop
) {
    _ = journal
    _ = token
}

struct TokenAliasConsumers {
    let escaped: (OrderedFactJournal<Int, String>, ProtectedTokenAlias)?

    init(
        journal: OrderedFactJournal<Int, String>,
        token: borrowing ProtectedTokenAlias
    ) {
        _ = journal
        _ = token
        escaped = nil
    }

    subscript(
        journal journal: OrderedFactJournal<Int, String>,
        token token: borrowing ProtectedTokenAliasHop
    ) -> Int {
        _ = journal
        _ = token
        return 0
    }
}

enum LocalTokenShadow {
    typealias AdmissionProtectedRegionToken = String

    static func retainShadowedToken(
        journal: OrderedFactJournal<Int, String>,
        token: borrowing AdmissionProtectedRegionToken
    ) {
        _ = journal
        _ = token
    }
}

func retainUnrelatedTokenAlias(
    journal: OrderedFactJournal<Int, String>,
    token: borrowing UnrelatedTokenNamespace.ProtectedTokenAlias
) {
    _ = journal
    _ = token
}

extension OrderedFactJournal {
    func consumeProtectedTokenAlias(token: borrowing ProtectedTokenAlias) {
        _ = token
    }
}

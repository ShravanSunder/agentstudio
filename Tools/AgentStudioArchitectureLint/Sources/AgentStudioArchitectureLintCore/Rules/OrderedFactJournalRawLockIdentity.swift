import SwiftSyntax

extension OrderedFactJournalDeclarationAliasIndex {
    static func resolveRawLockAliasIdentities(
        from declarationsByIdentity:
            [OrderedFactJournalTypeIdentity: [OrderedFactJournalAliasDeclaration]],
        namespaceAliasTargets: [OrderedFactJournalTypeIdentity: OrderedFactJournalTypeIdentity]
    ) -> Set<OrderedFactJournalTypeIdentity> {
        var rawLockAliases: Set<OrderedFactJournalTypeIdentity> = []
        var addedAlias = true
        while addedAlias {
            addedAlias = false
            for (identity, declarations) in declarationsByIdentity where declarations.count == 1 {
                guard let declaration = declarations.first else { continue }
                let resolvesToRawLock = declaration.targetReferences.contains { reference in
                    referenceResolvesToRawLock(
                        reference,
                        from: declaration.lexicalNamespace,
                        declarationsByIdentity: declarationsByIdentity,
                        namespaceAliasTargets: namespaceAliasTargets,
                        rawLockAliasIdentities: rawLockAliases
                    )
                }
                guard resolvesToRawLock else { continue }
                addedAlias = rawLockAliases.insert(identity).inserted || addedAlias
            }
        }
        return rawLockAliases
    }

    func referenceResolvesToRawLock(
        _ reference: OrderedFactJournalTypeIdentity,
        from lexicalNamespace: OrderedFactJournalTypeIdentity
    ) -> Bool {
        Self.referenceResolvesToRawLock(
            reference,
            from: lexicalNamespace,
            declarationsByIdentity: aliasDeclarationsByIdentity,
            namespaceAliasTargets: namespaceAliasTargets,
            rawLockAliasIdentities: rawLockAliasIdentities
        )
    }

    private static func referenceResolvesToRawLock(
        _ reference: OrderedFactJournalTypeIdentity,
        from lexicalNamespace: OrderedFactJournalTypeIdentity,
        declarationsByIdentity:
            [OrderedFactJournalTypeIdentity: [OrderedFactJournalAliasDeclaration]],
        namespaceAliasTargets: [OrderedFactJournalTypeIdentity: OrderedFactJournalTypeIdentity],
        rawLockAliasIdentities: Set<OrderedFactJournalTypeIdentity>
    ) -> Bool {
        let aliasLookup = lookupAliasReference(
            reference,
            from: lexicalNamespace,
            declarationsByIdentity: declarationsByIdentity,
            namespaceAliasTargets: namespaceAliasTargets
        )
        if reference.components == ["OSAllocatedUnfairLock"] {
            guard let aliasLookup else { return true }
            guard aliasLookup.declarationCount == 1 else { return false }
            return rawLockAliasIdentities.contains(aliasLookup.identity)
        }
        guard let aliasLookup, aliasLookup.declarationCount == 1 else { return false }
        return rawLockAliasIdentities.contains(aliasLookup.identity)
    }
}

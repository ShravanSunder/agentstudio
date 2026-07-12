import SwiftSyntax

struct OrderedFactJournalTypeIdentity: Hashable, Sendable {
    let components: [String]

    init(_ components: [String]) {
        self.components = components
    }

    func appending(_ component: String) -> Self {
        Self(components + [component])
    }

    var droppingLast: Self {
        Self(Array(components.dropLast()))
    }
}

struct OrderedFactJournalAliasDeclaration: Sendable {
    let identity: OrderedFactJournalTypeIdentity
    let lexicalNamespace: OrderedFactJournalTypeIdentity
    let targetReferences: [OrderedFactJournalTypeIdentity]
    let namespaceAliasTarget: OrderedFactJournalTypeIdentity?
}

struct OrderedFactJournalDeclarationAliasIndex: Sendable {
    let aliasDeclarationsByIdentity: [OrderedFactJournalTypeIdentity: [OrderedFactJournalAliasDeclaration]]
    let namespaceAliasTargets: [OrderedFactJournalTypeIdentity: OrderedFactJournalTypeIdentity]
    private let journalAliasIdentities: Set<OrderedFactJournalTypeIdentity>
    private let rawStateAliasIdentities: Set<OrderedFactJournalTypeIdentity>
    private let protectedTokenAliasIdentities: Set<OrderedFactJournalTypeIdentity>
    let rawLockAliasIdentities: Set<OrderedFactJournalTypeIdentity>
    private let additionalProductionOwnerPaths: Set<String>
    private let missingProductionOwnerDiagnosticPath: String?

    init(contexts: [ArchitectureLintContext]) {
        let contexts = Self.deduplicatedContexts(contexts)
        var aliasDeclarations: [OrderedFactJournalAliasDeclaration] = []
        for context in contexts where context.isProductionAdmissionSource {
            let aliasInventory = OrderedFactJournalAliasInventory(
                sourceIdentity: context.syntaxScopeSourceIdentity
            )
            aliasInventory.walk(context.sourceFile)
            aliasDeclarations.append(contentsOf: aliasInventory.declarations)
        }
        aliasDeclarationsByIdentity = Dictionary(
            grouping: aliasDeclarations,
            by: \.identity
        )
        namespaceAliasTargets = Self.resolveNamespaceAliasTargets(
            from: aliasDeclarationsByIdentity
        )
        journalAliasIdentities = Self.resolveJournalAliasIdentities(
            from: aliasDeclarationsByIdentity,
            namespaceAliasTargets: namespaceAliasTargets
        )
        rawStateAliasIdentities = Self.resolveRawStateAliasIdentities(
            from: aliasDeclarationsByIdentity,
            namespaceAliasTargets: namespaceAliasTargets,
            journalAliasIdentities: journalAliasIdentities
        )
        protectedTokenAliasIdentities = Self.resolveProtectedTokenAliasIdentities(
            from: aliasDeclarationsByIdentity,
            namespaceAliasTargets: namespaceAliasTargets
        )
        rawLockAliasIdentities = Self.resolveRawLockAliasIdentities(
            from: aliasDeclarationsByIdentity,
            namespaceAliasTargets: namespaceAliasTargets
        )
        let productionOwnerInventory = Self.productionOwnerInventory(
            contexts: contexts
        )
        additionalProductionOwnerPaths = Set(productionOwnerInventory.ownerPaths.dropFirst())
        missingProductionOwnerDiagnosticPath =
            productionOwnerInventory.ownerPaths.isEmpty
            ? productionOwnerInventory.sourcePaths.first
            : nil
    }

    init(sourceFile: SourceFileSyntax) {
        let aliasInventory = OrderedFactJournalAliasInventory(
            sourceIdentity: "<single-source>"
        )
        aliasInventory.walk(sourceFile)
        aliasDeclarationsByIdentity = Dictionary(
            grouping: aliasInventory.declarations,
            by: \.identity
        )
        namespaceAliasTargets = Self.resolveNamespaceAliasTargets(
            from: aliasDeclarationsByIdentity
        )
        journalAliasIdentities = Self.resolveJournalAliasIdentities(
            from: aliasDeclarationsByIdentity,
            namespaceAliasTargets: namespaceAliasTargets
        )
        rawStateAliasIdentities = Self.resolveRawStateAliasIdentities(
            from: aliasDeclarationsByIdentity,
            namespaceAliasTargets: namespaceAliasTargets,
            journalAliasIdentities: journalAliasIdentities
        )
        protectedTokenAliasIdentities = Self.resolveProtectedTokenAliasIdentities(
            from: aliasDeclarationsByIdentity,
            namespaceAliasTargets: namespaceAliasTargets
        )
        rawLockAliasIdentities = Self.resolveRawLockAliasIdentities(
            from: aliasDeclarationsByIdentity,
            namespaceAliasTargets: namespaceAliasTargets
        )
        additionalProductionOwnerPaths = []
        missingProductionOwnerDiagnosticPath = nil
    }

    func containsJournalType(
        in node: some SyntaxProtocol,
        lexicalNamespace: OrderedFactJournalTypeIdentity
    ) -> Bool {
        let genericParameterNames = orderedFactJournalVisibleGenericParameterNames(at: node)
        return typeReferences(in: node).contains {
            genericParameterNames.contains($0.components.first ?? "") == false
                && referenceResolvesToJournal($0, from: lexicalNamespace)
        }
    }

    func containsRawStateType(
        in node: some SyntaxProtocol,
        lexicalNamespace: OrderedFactJournalTypeIdentity
    ) -> Bool {
        let genericParameterNames = orderedFactJournalVisibleGenericParameterNames(at: node)
        return typeReferences(in: node).contains {
            genericParameterNames.contains($0.components.first ?? "") == false
                && referenceResolvesToRawState($0, from: lexicalNamespace)
        }
    }

    func containsProtectedTokenType(
        in node: some SyntaxProtocol,
        lexicalNamespace: OrderedFactJournalTypeIdentity
    ) -> Bool {
        let genericParameterNames = orderedFactJournalVisibleGenericParameterNames(at: node)
        return typeReferences(in: node).contains {
            genericParameterNames.contains($0.components.first ?? "") == false
                && referenceResolvesToProtectedToken($0, from: lexicalNamespace)
        }
    }

    func containsRawLockType(
        in node: some SyntaxProtocol,
        lexicalNamespace: OrderedFactJournalTypeIdentity
    ) -> Bool {
        let genericParameterNames = orderedFactJournalVisibleGenericParameterNames(at: node)
        return typeReferences(in: node).contains {
            genericParameterNames.contains($0.components.first ?? "") == false
                && referenceResolvesToRawLock($0, from: lexicalNamespace)
        }
    }

    func resolvedLexicalNamespace(
        _ lexicalNamespace: OrderedFactJournalTypeIdentity
    ) -> OrderedFactJournalTypeIdentity {
        Self.expandingNamespaceAliases(
            in: lexicalNamespace,
            namespaceAliasTargets: namespaceAliasTargets
        )
    }

    func isAdditionalProductionOwnerSource(path: String) -> Bool {
        additionalProductionOwnerPaths.contains(Self.normalized(path))
    }

    func isMissingProductionOwnerDiagnosticSource(path: String) -> Bool {
        missingProductionOwnerDiagnosticPath == Self.normalized(path)
    }

    private static func resolveNamespaceAliasTargets(
        from declarationsByIdentity:
            [OrderedFactJournalTypeIdentity: [OrderedFactJournalAliasDeclaration]]
    ) -> [OrderedFactJournalTypeIdentity: OrderedFactJournalTypeIdentity] {
        var resolvedTargets: [OrderedFactJournalTypeIdentity: OrderedFactJournalTypeIdentity] = [:]
        for _ in 0...declarationsByIdentity.count {
            var changed = false
            for (identity, declarations) in declarationsByIdentity where declarations.count == 1 {
                guard let declaration = declarations.first,
                    let target = declaration.namespaceAliasTarget
                else { continue }
                let resolvedTarget = resolvingNamespaceAliasTarget(
                    target,
                    from: declaration.lexicalNamespace,
                    namespaceAliasTargets: resolvedTargets
                )
                if resolvedTargets[identity] != resolvedTarget {
                    resolvedTargets[identity] = resolvedTarget
                    changed = true
                }
            }
            if changed == false { break }
        }
        return resolvedTargets
    }

    private static func resolvingNamespaceAliasTarget(
        _ target: OrderedFactJournalTypeIdentity,
        from lexicalNamespace: OrderedFactJournalTypeIdentity,
        namespaceAliasTargets: [OrderedFactJournalTypeIdentity: OrderedFactJournalTypeIdentity]
    ) -> OrderedFactJournalTypeIdentity {
        for namespaceDepth in stride(
            from: lexicalNamespace.components.count,
            through: 0,
            by: -1
        ) {
            let candidate = OrderedFactJournalTypeIdentity(
                Array(lexicalNamespace.components.prefix(namespaceDepth)) + target.components
            )
            if namespaceAliasTargets[candidate] != nil {
                return expandingNamespaceAliases(
                    in: candidate,
                    namespaceAliasTargets: namespaceAliasTargets
                )
            }
        }
        return expandingNamespaceAliases(
            in: target,
            namespaceAliasTargets: namespaceAliasTargets
        )
    }

    private static func expandingNamespaceAliases(
        in identity: OrderedFactJournalTypeIdentity,
        namespaceAliasTargets: [OrderedFactJournalTypeIdentity: OrderedFactJournalTypeIdentity]
    ) -> OrderedFactJournalTypeIdentity {
        var expandedIdentity = identity
        var remainingExpansions = namespaceAliasTargets.count + 1
        while remainingExpansions > 0 {
            remainingExpansions -= 1
            var replacement: OrderedFactJournalTypeIdentity?
            for prefixCount in stride(
                from: expandedIdentity.components.count,
                through: 1,
                by: -1
            ) {
                let prefix = OrderedFactJournalTypeIdentity(
                    Array(expandedIdentity.components.prefix(prefixCount))
                )
                guard let target = namespaceAliasTargets[prefix] else { continue }
                replacement = OrderedFactJournalTypeIdentity(
                    target.components + expandedIdentity.components.dropFirst(prefixCount)
                )
                break
            }
            guard let replacement, replacement != expandedIdentity else { break }
            expandedIdentity = replacement
        }
        return expandedIdentity
    }

    private static func resolveJournalAliasIdentities(
        from declarationsByIdentity:
            [OrderedFactJournalTypeIdentity: [OrderedFactJournalAliasDeclaration]],
        namespaceAliasTargets: [OrderedFactJournalTypeIdentity: OrderedFactJournalTypeIdentity]
    ) -> Set<OrderedFactJournalTypeIdentity> {
        var journalAliases: Set<OrderedFactJournalTypeIdentity> = []
        var addedAlias = true
        while addedAlias {
            addedAlias = false
            for (identity, declarations) in declarationsByIdentity where declarations.count == 1 {
                guard let declaration = declarations.first else { continue }
                let resolvesToJournal = declaration.targetReferences.contains { reference in
                    referenceResolvesToJournal(
                        reference,
                        from: declaration.lexicalNamespace,
                        declarationsByIdentity: declarationsByIdentity,
                        namespaceAliasTargets: namespaceAliasTargets,
                        journalAliasIdentities: journalAliases
                    )
                }
                guard resolvesToJournal else { continue }
                addedAlias = journalAliases.insert(identity).inserted || addedAlias
            }
        }
        return journalAliases
    }

    private static func resolveRawStateAliasIdentities(
        from declarationsByIdentity:
            [OrderedFactJournalTypeIdentity: [OrderedFactJournalAliasDeclaration]],
        namespaceAliasTargets: [OrderedFactJournalTypeIdentity: OrderedFactJournalTypeIdentity],
        journalAliasIdentities: Set<OrderedFactJournalTypeIdentity>
    ) -> Set<OrderedFactJournalTypeIdentity> {
        var rawStateAliases: Set<OrderedFactJournalTypeIdentity> = []
        var addedAlias = true
        while addedAlias {
            addedAlias = false
            for (identity, declarations) in declarationsByIdentity where declarations.count == 1 {
                guard let declaration = declarations.first else { continue }
                let resolvesToRawState = declaration.targetReferences.contains { reference in
                    referenceResolvesToRawState(
                        reference,
                        from: declaration.lexicalNamespace,
                        declarationsByIdentity: declarationsByIdentity,
                        namespaceAliasTargets: namespaceAliasTargets,
                        journalAliasIdentities: journalAliasIdentities,
                        rawStateAliasIdentities: rawStateAliases
                    )
                }
                guard resolvesToRawState else { continue }
                addedAlias = rawStateAliases.insert(identity).inserted || addedAlias
            }
        }
        return rawStateAliases
    }

    private static func resolveProtectedTokenAliasIdentities(
        from declarationsByIdentity:
            [OrderedFactJournalTypeIdentity: [OrderedFactJournalAliasDeclaration]],
        namespaceAliasTargets: [OrderedFactJournalTypeIdentity: OrderedFactJournalTypeIdentity]
    ) -> Set<OrderedFactJournalTypeIdentity> {
        var protectedTokenAliases: Set<OrderedFactJournalTypeIdentity> = []
        var addedAlias = true
        while addedAlias {
            addedAlias = false
            for (identity, declarations) in declarationsByIdentity where declarations.count == 1 {
                guard let declaration = declarations.first else { continue }
                let resolvesToToken = declaration.targetReferences.contains { reference in
                    referenceResolvesToProtectedToken(
                        reference,
                        from: declaration.lexicalNamespace,
                        declarationsByIdentity: declarationsByIdentity,
                        namespaceAliasTargets: namespaceAliasTargets,
                        protectedTokenAliasIdentities: protectedTokenAliases
                    )
                }
                guard resolvesToToken else { continue }
                addedAlias = protectedTokenAliases.insert(identity).inserted || addedAlias
            }
        }
        return protectedTokenAliases
    }

    private func referenceResolvesToJournal(
        _ reference: OrderedFactJournalTypeIdentity,
        from lexicalNamespace: OrderedFactJournalTypeIdentity
    ) -> Bool {
        Self.referenceResolvesToJournal(
            reference,
            from: lexicalNamespace,
            declarationsByIdentity: aliasDeclarationsByIdentity,
            namespaceAliasTargets: namespaceAliasTargets,
            journalAliasIdentities: journalAliasIdentities
        )
    }

    private static func referenceResolvesToJournal(
        _ reference: OrderedFactJournalTypeIdentity,
        from lexicalNamespace: OrderedFactJournalTypeIdentity,
        declarationsByIdentity:
            [OrderedFactJournalTypeIdentity: [OrderedFactJournalAliasDeclaration]],
        namespaceAliasTargets: [OrderedFactJournalTypeIdentity: OrderedFactJournalTypeIdentity],
        journalAliasIdentities: Set<OrderedFactJournalTypeIdentity>
    ) -> Bool {
        let aliasLookup = lookupAliasReference(
            reference,
            from: lexicalNamespace,
            declarationsByIdentity: declarationsByIdentity,
            namespaceAliasTargets: namespaceAliasTargets
        )
        if reference.components == ["OrderedFactJournal"] {
            guard let aliasLookup else { return true }
            guard aliasLookup.declarationCount == 1 else { return false }
            return journalAliasIdentities.contains(aliasLookup.identity)
        }
        if reference.components == ["AgentStudio", "OrderedFactJournal"] {
            if let aliasLookup {
                guard aliasLookup.declarationCount == 1 else { return false }
                return journalAliasIdentities.contains(aliasLookup.identity)
            }
            return namespaceResolvedReference(
                reference,
                from: lexicalNamespace,
                namespaceAliasTargets: namespaceAliasTargets
            ) == reference
        }
        guard let aliasLookup, aliasLookup.declarationCount == 1 else {
            return false
        }
        return journalAliasIdentities.contains(aliasLookup.identity)
    }

    private static func namespaceResolvedReference(
        _ reference: OrderedFactJournalTypeIdentity,
        from lexicalNamespace: OrderedFactJournalTypeIdentity,
        namespaceAliasTargets: [OrderedFactJournalTypeIdentity: OrderedFactJournalTypeIdentity]
    ) -> OrderedFactJournalTypeIdentity {
        for namespaceDepth in stride(
            from: lexicalNamespace.components.count,
            through: 1,
            by: -1
        ) {
            let candidate = OrderedFactJournalTypeIdentity(
                Array(lexicalNamespace.components.prefix(namespaceDepth))
                    + reference.components
            )
            let expandedCandidate = expandingNamespaceAliases(
                in: candidate,
                namespaceAliasTargets: namespaceAliasTargets
            )
            if expandedCandidate != candidate {
                return expandedCandidate
            }
        }
        return expandingNamespaceAliases(
            in: reference,
            namespaceAliasTargets: namespaceAliasTargets
        )
    }

    private func referenceResolvesToRawState(
        _ reference: OrderedFactJournalTypeIdentity,
        from lexicalNamespace: OrderedFactJournalTypeIdentity
    ) -> Bool {
        Self.referenceResolvesToRawState(
            reference,
            from: lexicalNamespace,
            declarationsByIdentity: aliasDeclarationsByIdentity,
            namespaceAliasTargets: namespaceAliasTargets,
            journalAliasIdentities: journalAliasIdentities,
            rawStateAliasIdentities: rawStateAliasIdentities
        )
    }

    private static func referenceResolvesToRawState(
        _ reference: OrderedFactJournalTypeIdentity,
        from lexicalNamespace: OrderedFactJournalTypeIdentity,
        declarationsByIdentity:
            [OrderedFactJournalTypeIdentity: [OrderedFactJournalAliasDeclaration]],
        namespaceAliasTargets: [OrderedFactJournalTypeIdentity: OrderedFactJournalTypeIdentity],
        journalAliasIdentities: Set<OrderedFactJournalTypeIdentity>,
        rawStateAliasIdentities: Set<OrderedFactJournalTypeIdentity>
    ) -> Bool {
        if reference.components == ["State"] {
            if let aliasLookup = lookupAliasReference(
                reference,
                from: lexicalNamespace,
                declarationsByIdentity: declarationsByIdentity,
                namespaceAliasTargets: namespaceAliasTargets
            ) {
                guard aliasLookup.declarationCount == 1 else { return false }
                return rawStateAliasIdentities.contains(aliasLookup.identity)
            }
            for prefixCount in stride(
                from: lexicalNamespace.components.count,
                through: 1,
                by: -1
            ) {
                let candidate = OrderedFactJournalTypeIdentity(
                    Array(lexicalNamespace.components.prefix(prefixCount))
                )
                if referenceResolvesToJournal(
                    candidate,
                    from: lexicalNamespace,
                    declarationsByIdentity: declarationsByIdentity,
                    namespaceAliasTargets: namespaceAliasTargets,
                    journalAliasIdentities: journalAliasIdentities
                ) {
                    return true
                }
            }
            return false
        }
        if reference.components.last == "State",
            reference.components.count > 1,
            referenceResolvesToJournal(
                reference.droppingLast,
                from: lexicalNamespace,
                declarationsByIdentity: declarationsByIdentity,
                namespaceAliasTargets: namespaceAliasTargets,
                journalAliasIdentities: journalAliasIdentities
            )
        {
            return true
        }
        guard
            let aliasLookup = lookupAliasReference(
                reference,
                from: lexicalNamespace,
                declarationsByIdentity: declarationsByIdentity,
                namespaceAliasTargets: namespaceAliasTargets
            ),
            aliasLookup.declarationCount == 1
        else {
            return false
        }
        return rawStateAliasIdentities.contains(aliasLookup.identity)
    }

    private func referenceResolvesToProtectedToken(
        _ reference: OrderedFactJournalTypeIdentity,
        from lexicalNamespace: OrderedFactJournalTypeIdentity
    ) -> Bool {
        Self.referenceResolvesToProtectedToken(
            reference,
            from: lexicalNamespace,
            declarationsByIdentity: aliasDeclarationsByIdentity,
            namespaceAliasTargets: namespaceAliasTargets,
            protectedTokenAliasIdentities: protectedTokenAliasIdentities
        )
    }

    private static func referenceResolvesToProtectedToken(
        _ reference: OrderedFactJournalTypeIdentity,
        from lexicalNamespace: OrderedFactJournalTypeIdentity,
        declarationsByIdentity:
            [OrderedFactJournalTypeIdentity: [OrderedFactJournalAliasDeclaration]],
        namespaceAliasTargets: [OrderedFactJournalTypeIdentity: OrderedFactJournalTypeIdentity],
        protectedTokenAliasIdentities: Set<OrderedFactJournalTypeIdentity>
    ) -> Bool {
        let aliasLookup = lookupAliasReference(
            reference,
            from: lexicalNamespace,
            declarationsByIdentity: declarationsByIdentity,
            namespaceAliasTargets: namespaceAliasTargets
        )
        if reference.components == ["AdmissionProtectedRegionToken"] {
            guard let aliasLookup else { return true }
            guard aliasLookup.declarationCount == 1 else { return false }
            return protectedTokenAliasIdentities.contains(aliasLookup.identity)
        }
        let canonicalModuleQualifiedToken = OrderedFactJournalTypeIdentity([
            "AgentStudio", "AdmissionProtectedRegionToken",
        ])
        if namespaceResolvedReference(
            reference,
            from: lexicalNamespace,
            namespaceAliasTargets: namespaceAliasTargets
        ) == canonicalModuleQualifiedToken {
            guard let aliasLookup else { return true }
            guard aliasLookup.declarationCount == 1 else { return false }
            return protectedTokenAliasIdentities.contains(aliasLookup.identity)
        }
        guard let aliasLookup, aliasLookup.declarationCount == 1 else { return false }
        return protectedTokenAliasIdentities.contains(aliasLookup.identity)
    }

    struct AliasReferenceLookup {
        let identity: OrderedFactJournalTypeIdentity
        let declarationCount: Int
    }

    static func lookupAliasReference(
        _ reference: OrderedFactJournalTypeIdentity,
        from lexicalNamespace: OrderedFactJournalTypeIdentity,
        declarationsByIdentity:
            [OrderedFactJournalTypeIdentity: [OrderedFactJournalAliasDeclaration]],
        namespaceAliasTargets: [OrderedFactJournalTypeIdentity: OrderedFactJournalTypeIdentity]
    ) -> AliasReferenceLookup? {
        guard let bareName = reference.components.last else { return nil }
        if reference.components.count > 1 {
            for namespaceDepth in stride(
                from: lexicalNamespace.components.count,
                through: 1,
                by: -1
            ) {
                let candidate = OrderedFactJournalTypeIdentity(
                    Array(lexicalNamespace.components.prefix(namespaceDepth))
                        + reference.components
                )
                if let declarations = declarationsByIdentity[candidate] {
                    return AliasReferenceLookup(
                        identity: candidate,
                        declarationCount: declarations.count
                    )
                }
                let expandedCandidate = expandingNamespaceAliases(
                    in: candidate,
                    namespaceAliasTargets: namespaceAliasTargets
                )
                guard let declarations = declarationsByIdentity[expandedCandidate] else { continue }
                return AliasReferenceLookup(
                    identity: expandedCandidate,
                    declarationCount: declarations.count
                )
            }
            if let declarations = declarationsByIdentity[reference] {
                return AliasReferenceLookup(
                    identity: reference,
                    declarationCount: declarations.count
                )
            }
            let expandedReference = expandingNamespaceAliases(
                in: reference,
                namespaceAliasTargets: namespaceAliasTargets
            )
            guard let declarations = declarationsByIdentity[expandedReference] else { return nil }
            return AliasReferenceLookup(
                identity: expandedReference,
                declarationCount: declarations.count
            )
        }

        for namespaceDepth in stride(
            from: lexicalNamespace.components.count,
            through: 0,
            by: -1
        ) {
            let candidate = OrderedFactJournalTypeIdentity(
                Array(lexicalNamespace.components.prefix(namespaceDepth)) + [bareName]
            )
            if let declarations = declarationsByIdentity[candidate] {
                return AliasReferenceLookup(
                    identity: candidate,
                    declarationCount: declarations.count
                )
            }
            let expandedCandidate = expandingNamespaceAliases(
                in: candidate,
                namespaceAliasTargets: namespaceAliasTargets
            )
            guard let declarations = declarationsByIdentity[expandedCandidate] else { continue }
            return AliasReferenceLookup(
                identity: expandedCandidate,
                declarationCount: declarations.count
            )
        }
        return nil
    }

    private static func productionOwnerInventory(
        contexts: [ArchitectureLintContext]
    ) -> (sourcePaths: [String], ownerPaths: [String]) {
        let productionContexts = contexts.filter { context in
            guard
                context.isProductionAdmissionSource,
                context.enforcesProductionAdmissionOwnerCardinality
            else {
                return false
            }
            return true
        }
        let sourcePaths = productionContexts.map { normalized($0.path) }.sorted()
        let ownerPaths = productionContexts.compactMap { context -> String? in
            let inventory = OrderedFactJournalDeclarationInventory()
            inventory.walk(context.sourceFile)
            return inventory.topLevelOwnerDeclarations.isEmpty
                ? nil
                : normalized(context.path)
        }.sorted()
        return (sourcePaths, ownerPaths)
    }

    private static func normalized(_ path: String) -> String {
        path.replacingOccurrences(of: "\\", with: "/")
    }

    private static func deduplicatedContexts(
        _ contexts: [ArchitectureLintContext]
    ) -> [ArchitectureLintContext] {
        var seenSourceIdentities: Set<String> = []
        return contexts.filter { context in
            seenSourceIdentities.insert(context.syntaxScopeSourceIdentity).inserted
        }
    }
}

struct OrderedFactJournalLexicalOwnershipClassifier {
    let violations: [ArchitectureViolation]

    static func containsTopLevelOwner(in sourceFile: SourceFileSyntax) -> Bool {
        let declarationInventory = OrderedFactJournalDeclarationInventory()
        declarationInventory.walk(sourceFile)
        return declarationInventory.topLevelOwnerDeclarations.isEmpty == false
    }

    init(
        path: String,
        sourceIdentity: String,
        sourceFile: SourceFileSyntax,
        declarationAliasIndex: OrderedFactJournalDeclarationAliasIndex,
        lexicalOwnershipMessage: String,
        ownerResponsibilityMessage: String
    ) {
        let declarationInventory = OrderedFactJournalDeclarationInventory()
        declarationInventory.walk(sourceFile)

        var findings: [ArchitectureViolation] = []
        if declarationInventory.topLevelOwnerDeclarations.isEmpty == false {
            let responsibilityVisitor = OrderedFactJournalOwnerResponsibilityVisitor(
                declarationAliasIndex: declarationAliasIndex,
                sourceIdentity: sourceIdentity,
                message: ownerResponsibilityMessage
            )
            responsibilityVisitor.walk(sourceFile)
            findings.append(contentsOf: responsibilityVisitor.violations)
        } else {
            let rawAccessVisitor = OrderedFactJournalRawAccessVisitor(
                declarationAliasIndex: declarationAliasIndex,
                sourceIdentity: sourceIdentity,
                message: lexicalOwnershipMessage
            )
            rawAccessVisitor.walk(sourceFile)
            findings.append(contentsOf: rawAccessVisitor.violations)
        }

        for invalidOwner in declarationInventory.nonTopLevelOrNonClassOwnerDeclarations {
            findings.append(
                ArchitectureViolation(
                    position: invalidOwner,
                    message: ownerResponsibilityMessage
                ))
        }
        if declarationInventory.topLevelOwnerDeclarations.count > 1 {
            findings.append(
                contentsOf: declarationInventory.topLevelOwnerDeclarations.dropFirst().map {
                    ArchitectureViolation(position: $0, message: ownerResponsibilityMessage)
                })
        }
        if declarationAliasIndex.isAdditionalProductionOwnerSource(path: path),
            let ownerPosition = declarationInventory.topLevelOwnerDeclarations.first
        {
            findings.append(
                ArchitectureViolation(
                    position: ownerPosition,
                    message: ownerResponsibilityMessage
                ))
        }
        if declarationAliasIndex.isMissingProductionOwnerDiagnosticSource(path: path) {
            findings.append(
                ArchitectureViolation(
                    position: sourceFile.positionAfterSkippingLeadingTrivia,
                    message: ownerResponsibilityMessage
                ))
        }
        violations = findings
    }

}

private final class OrderedFactJournalDeclarationInventory: SyntaxVisitor {
    private(set) var topLevelOwnerDeclarations: [AbsolutePosition] = []
    private(set) var nonTopLevelOrNonClassOwnerDeclarations: [AbsolutePosition] = []

    override init(viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(viewMode: viewMode)
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        guard node.name.text == "OrderedFactJournal" else { return .visitChildren }
        let position = node.name.positionAfterSkippingLeadingTrivia
        if isTopLevelDeclaration(node) {
            topLevelOwnerDeclarations.append(position)
        }
        return .visitChildren
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        recordTopLevelNonClassOwner(node)
        return .visitChildren
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        recordTopLevelNonClassOwner(node)
        return .visitChildren
    }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        recordTopLevelNonClassOwner(node)
        return .visitChildren
    }

    private func recordTopLevelNonClassOwner(_ node: some DeclSyntaxProtocol & NamedDeclSyntax) {
        guard node.name.text == "OrderedFactJournal", isTopLevelDeclaration(node) else { return }
        nonTopLevelOrNonClassOwnerDeclarations.append(
            node.name.positionAfterSkippingLeadingTrivia
        )
    }
}

private final class OrderedFactJournalOwnerResponsibilityVisitor: SyntaxVisitor {
    private(set) var violations: [ArchitectureViolation] = []
    private let declarationAliasIndex: OrderedFactJournalDeclarationAliasIndex
    private let sourceIdentity: String
    private let message: String

    init(
        declarationAliasIndex: OrderedFactJournalDeclarationAliasIndex,
        sourceIdentity: String,
        message: String,
        viewMode: SyntaxTreeViewMode = .sourceAccurate
    ) {
        self.declarationAliasIndex = declarationAliasIndex
        self.sourceIdentity = sourceIdentity
        self.message = message
        super.init(viewMode: viewMode)
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        guard isTopLevelDeclaration(node) else { return .visitChildren }
        if node.name.text != "OrderedFactJournal" {
            recordViolation(at: node.name.positionAfterSkippingLeadingTrivia)
        }
        return .visitChildren
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        recordTopLevelViolation(node, position: node.name.positionAfterSkippingLeadingTrivia)
        return .visitChildren
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        recordTopLevelViolation(node, position: node.name.positionAfterSkippingLeadingTrivia)
        return .visitChildren
    }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        recordTopLevelViolation(node, position: node.name.positionAfterSkippingLeadingTrivia)
        return .visitChildren
    }

    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        recordTopLevelViolation(node, position: node.name.positionAfterSkippingLeadingTrivia)
        return .visitChildren
    }

    override func visit(_ node: TypeAliasDeclSyntax) -> SyntaxVisitorContinueKind {
        recordTopLevelViolation(node, position: node.name.positionAfterSkippingLeadingTrivia)
        return .visitChildren
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        recordTopLevelViolation(node, position: node.name.positionAfterSkippingLeadingTrivia)
        return .visitChildren
    }

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        recordTopLevelViolation(node, position: node.bindingSpecifier.positionAfterSkippingLeadingTrivia)
        return .visitChildren
    }

    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        guard isTopLevelDeclaration(node) else { return .visitChildren }
        if declarationAliasIndex.containsJournalType(
            in: node.extendedType,
            lexicalNamespace: declarationAliasIndex.resolvedLexicalNamespace(
                orderedFactJournalLexicalNamespace(
                    of: node,
                    sourceIdentity: sourceIdentity
                )
            )
        ) == false {
            recordViolation(at: node.extensionKeyword.positionAfterSkippingLeadingTrivia)
        }
        return .visitChildren
    }

    private func recordTopLevelViolation(
        _ node: some SyntaxProtocol,
        position: AbsolutePosition
    ) {
        guard isTopLevelDeclaration(node) else { return }
        recordViolation(at: position)
    }

    private func recordViolation(at position: AbsolutePosition) {
        violations.append(ArchitectureViolation(position: position, message: message))
    }
}

private final class OrderedFactJournalTypeReferenceVisitor: SyntaxVisitor {
    private(set) var references: [OrderedFactJournalTypeIdentity] = []

    override init(viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(viewMode: viewMode)
    }

    override func visit(_ node: IdentifierTypeSyntax) -> SyntaxVisitorContinueKind {
        references.append(OrderedFactJournalTypeIdentity([node.name.text]))
        return .visitChildren
    }

    override func visit(_ node: MemberTypeSyntax) -> SyntaxVisitorContinueKind {
        if let identity = orderedFactJournalQualifiedTypeIdentity(node) {
            references.append(identity)
        }
        return .visitChildren
    }
}

func typeReferences(
    in node: some SyntaxProtocol
) -> [OrderedFactJournalTypeIdentity] {
    let visitor = OrderedFactJournalTypeReferenceVisitor()
    visitor.walk(node)
    return visitor.references
}

func orderedFactJournalQualifiedTypeIdentity(
    _ node: some TypeSyntaxProtocol
) -> OrderedFactJournalTypeIdentity? {
    if let identifierType = node.as(IdentifierTypeSyntax.self) {
        return OrderedFactJournalTypeIdentity([identifierType.name.text])
    }
    if let memberType = node.as(MemberTypeSyntax.self),
        let baseIdentity = orderedFactJournalQualifiedTypeIdentity(memberType.baseType)
    {
        return baseIdentity.appending(memberType.name.text)
    }
    return nil
}

private func isTopLevelDeclaration(_ node: some SyntaxProtocol) -> Bool {
    var ancestor = node.parent
    while let current = ancestor {
        if current.is(SourceFileSyntax.self) { return true }
        if current.is(ClassDeclSyntax.self)
            || current.is(StructDeclSyntax.self)
            || current.is(EnumDeclSyntax.self)
            || current.is(ActorDeclSyntax.self)
            || current.is(ProtocolDeclSyntax.self)
            || current.is(ExtensionDeclSyntax.self)
            || current.is(FunctionDeclSyntax.self)
        {
            return false
        }
        ancestor = current.parent
    }
    return false
}

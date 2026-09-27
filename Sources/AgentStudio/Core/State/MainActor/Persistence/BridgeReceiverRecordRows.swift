import Foundation

/// Translation between live navigation and normalized receiver rows. The
/// repository owns SQL; this codec owns the meaning and validation of columns.
enum BridgeReceiverRecordRows {
    static func states(_ record: BridgeNavigationRecord, receiver: BridgeReceiver, generation: Int)
        -> [BridgeReceiverStateRow]
    {
        func row(_ kind: String, _ key: String = BridgeReceiverStateKeyCodec.singleton) -> BridgeReceiverStateRow {
            BridgeReceiverStateRow(
                receiver: receiver, kind: kind, itemKey: key, generation: generation, isDeleted: false)
        }
        var result: [BridgeReceiverStateRow] = []
        var filter = row("filesFilter")
        switch record.filesFilter {
        case .allMembers: filter.textValue = "allMembers"
        case .openedDocuments: filter.textValue = "openedDocuments"
        case .member(let id):
            filter.textValue = "member"
            filter.worktreeID = id
        }
        result.append(filter)
        if let selected = record.selectedFilesDocument {
            var selection = row("selectedFilesDocument")
            selection.documentPath = selected.canonicalPath
            result.append(selection)
        }
        var review = row("reviewSelection")
        switch record.reviewSelection {
        case .unselected: review.textValue = "unselected"
        case .member(let id):
            review.textValue = "member"
            review.worktreeID = id
        case .importedUnavailable(let query):
            review.textValue = "importedUnavailable"
            review.importedVariant = query.variant.rawValue
            review.importedPayload = query.originalPayloadJSON
        }
        result.append(review)
        var surface = row("surface")
        surface.textValue = record.surface.rawValue
        result.append(surface)
        for (id, comparison) in record.reviewComparisonsByWorktreeId {
            var state = row("reviewComparison", BridgeReceiverStateKeyCodec.member(id))
            state.worktreeID = id
            switch comparison {
            case .localDefaultBranch(let branch, let basis):
                state.comparisonKind = "localDefaultBranch"
                state.comparisonBranch = branch
                state.comparisonBasis = basis.rawValue
            case .originDefaultBranch(let remote, let branch, let basis):
                state.comparisonKind = "originDefaultBranch"
                state.comparisonRemote = remote
                state.comparisonBranch = branch
                state.comparisonBasis = basis.rawValue
            case .branch(let name, let basis):
                state.comparisonKind = "branch"
                state.comparisonName = name
                state.comparisonBasis = basis.rawValue
            case .commit(let oid):
                state.comparisonKind = "commit"
                state.comparisonOID = oid
            case .ref(let name, let basis):
                state.comparisonKind = "ref"
                state.comparisonName = name
                state.comparisonBasis = basis.rawValue
            case .headMinusOne: state.comparisonKind = "headMinusOne"
            case .staged: state.comparisonKind = "staged"
            case .unstaged: state.comparisonKind = "unstaged"
            }
            result.append(state)
        }
        for (index, link) in record.committedMemberLinks.enumerated() {
            var order = row("itemOrder", BridgePaneLinkItemKeyCodec.member(link.worktreeId))
            order.textValue = "member"
            order.worktreeID = link.worktreeId
            order.ordinal = index
            result.append(order)
        }
        for (index, link) in record.pullRequestLinks.enumerated() {
            var order = row("itemOrder", BridgePaneLinkItemKeyCodec.pullRequest(link.identity))
            order.textValue = "prReference"
            order.ordinal = index
            order.forgeHost = link.identity.host
            order.forgeOwner = link.identity.owner
            order.forgeRepository = link.identity.repository
            order.forgeNumber = link.identity.number
            result.append(order)
        }
        for (index, document) in record.openedDocuments.enumerated() {
            var opened = row("openedDocument", BridgeReceiverStateKeyCodec.document(document.location))
            opened.documentPath = document.location.canonicalPath
            opened.ordinal = index
            opened.provenanceRepoID = document.provenance?.repoId
            opened.provenanceWorktreeID = document.provenance?.worktreeId
            opened.provenanceRelativePath = document.provenance?.relativePath
            result.append(opened)
        }
        return result
    }

    static func items(_ record: BridgeNavigationRecord, receiver: BridgeReceiver, generation: Int)
        -> [BridgeReceiverItemRow]
    {
        func contributionRow(kind: String, key: String, contribution: BridgeLinkContribution) -> BridgeReceiverItemRow {
            var row = BridgeReceiverItemRow(
                receiver: receiver, kind: kind, itemKey: key,
                contributorKey: BridgeLinkContributorKeyCodec.encode(contribution.addedBy), generation: generation,
                isDeleted: false)
            switch contribution.addedBy {
            case .app: row.contributorKind = "app"
            case .person: row.contributorKind = "person"
            case .agent(let identity):
                row.contributorKind = "agent"
                row.contributorProvider = identity.provider.value
                row.contributorSessionRef = identity.sessionRef.value
            }
            row.addedAt = contribution.addedAt
            return row
        }
        var result: [BridgeReceiverItemRow] = []
        for link in record.committedMemberLinks {
            for contribution in link.contributions {
                var row = contributionRow(
                    kind: "member", key: BridgePaneLinkItemKeyCodec.member(link.worktreeId),
                    contribution: contribution)
                row.worktreeID = link.worktreeId
                result.append(row)
            }
        }
        for link in record.pullRequestLinks {
            for contribution in link.contributions {
                var row = contributionRow(
                    kind: "prReference", key: BridgePaneLinkItemKeyCodec.pullRequest(link.identity),
                    contribution: contribution)
                row.forgeHost = link.identity.host
                row.forgeOwner = link.identity.owner
                row.forgeRepository = link.identity.repository
                row.forgeNumber = link.identity.number
                result.append(row)
            }
        }
        return result
    }

    static func record(states: [BridgeReceiverStateRow], items: [BridgeReceiverItemRow]) throws
        -> BridgeNavigationRecord
    {
        let (memberContributions, pullRequestContributions) = try decodeContributions(items)
        var decoded = DecodedState()
        for state in states { try decoded.apply(state) }
        guard Set(memberContributions.keys) == Set(decoded.memberOrder.keys),
            Set(pullRequestContributions.keys) == Set(decoded.pullRequestOrder.keys),
            Set(decoded.memberOrder.values).count == decoded.memberOrder.count,
            Set(decoded.pullRequestOrder.values).count == decoded.pullRequestOrder.count,
            Set(decoded.documentOrder.map(\.0)).count == decoded.documentOrder.count
        else { throw BridgeReceiverStorageError.malformedRow("missing item order") }
        decoded.record.committedMemberLinks = memberContributions.map {
            BridgeMemberLink(worktreeId: $0.key, contributions: $0.value)
        }.sorted { decoded.memberOrder[$0.worktreeId]! < decoded.memberOrder[$1.worktreeId]! }
        decoded.record.pullRequestLinks = pullRequestContributions.map {
            BridgePullRequestLink(identity: $0.key, contributions: $0.value)
        }.sorted { decoded.pullRequestOrder[$0.identity]! < decoded.pullRequestOrder[$1.identity]! }
        decoded.record.openedDocuments = decoded.documentOrder.sorted { $0.0 < $1.0 }.map(\.1)
        if let selected = decoded.record.selectedFilesDocument,
            !decoded.record.openedDocuments.contains(where: { $0.location == selected })
        {
            throw BridgeReceiverStorageError.malformedRow("selected document missing from inventory")
        }
        return decoded.record
    }

    private static func decodeContributions(_ items: [BridgeReceiverItemRow]) throws -> (
        [UUID: [BridgeLinkContribution]], [ForgePullRequestIdentity: [BridgeLinkContribution]]
    ) {
        var members: [UUID: [BridgeLinkContribution]] = [:]
        var pullRequests: [ForgePullRequestIdentity: [BridgeLinkContribution]] = [:]
        for item in items {
            try validateItemIdentity(item)
            let contributor = try BridgeLinkContributorKeyCodec.decode(item.contributorKey)
            try validateContributorColumns(item, contributor: contributor)
            if item.isDeleted { continue }
            guard let addedAt = item.addedAt else { throw BridgeReceiverStorageError.malformedRow("added_at") }
            let contribution = BridgeLinkContribution(addedBy: contributor, addedAt: addedAt)
            switch item.kind {
            case "member":
                guard let id = item.worktreeID else { throw BridgeReceiverStorageError.malformedRow("member identity") }
                members[id, default: []].append(contribution)
            case "prReference":
                guard let host = item.forgeHost, let owner = item.forgeOwner,
                    let repository = item.forgeRepository, let number = item.forgeNumber
                else {
                    throw BridgeReceiverStorageError.malformedRow("PR identity")
                }
                let identity = try ForgePullRequestIdentity(
                    host: host, owner: owner, repository: repository, number: number)
                pullRequests[identity, default: []].append(contribution)
            default: throw BridgeReceiverStorageError.malformedRow("item kind")
            }
        }
        return (members, pullRequests)
    }

    private static func validateContributorColumns(
        _ item: BridgeReceiverItemRow, contributor: BridgeLinkContributor
    ) throws {
        switch contributor {
        case .app:
            guard item.contributorKind == "app", item.contributorProvider == nil,
                item.contributorSessionRef == nil
            else {
                throw BridgeReceiverStorageError.malformedRow("contributor columns")
            }
        case .person:
            guard item.contributorKind == "person", item.contributorProvider == nil,
                item.contributorSessionRef == nil
            else {
                throw BridgeReceiverStorageError.malformedRow("contributor columns")
            }
        case .agent(let identity):
            guard item.contributorKind == "agent", item.contributorProvider == identity.provider.value,
                item.contributorSessionRef == identity.sessionRef.value
            else {
                throw BridgeReceiverStorageError.malformedRow("contributor columns")
            }
        }
    }

    private struct DecodedState {
        var record = BridgeNavigationRecord.empty
        var memberOrder: [UUID: Int] = [:]
        var pullRequestOrder: [ForgePullRequestIdentity: Int] = [:]
        var documentOrder: [(Int, BridgeOpenedDocument)] = []

        mutating func apply(_ state: BridgeReceiverStateRow) throws {
            try BridgeReceiverRecordRows.validateStateIdentity(state)
            if state.isDeleted { return }
            switch state.kind {
            case "filesFilter": record.filesFilter = try BridgeReceiverRecordRows.filesFilter(state)
            case "selectedFilesDocument":
                record.selectedFilesDocument = try BridgeReceiverRecordRows.selectedDocument(state)
            case "reviewSelection": record.reviewSelection = try BridgeReceiverRecordRows.reviewSelection(state)
            case "surface": record.surface = try BridgeReceiverRecordRows.surface(state)
            case "reviewComparison":
                guard let id = state.worktreeID else { throw BridgeReceiverStorageError.malformedRow("comparison key") }
                record.reviewComparisonsByWorktreeId[id] = try BridgeReceiverRecordRows.comparison(state)
            case "itemOrder": try applyItemOrder(state)
            case "openedDocument": documentOrder.append(try BridgeReceiverRecordRows.openedDocument(state))
            default: throw BridgeReceiverStorageError.malformedRow("state kind")
            }
        }

        private mutating func applyItemOrder(_ state: BridgeReceiverStateRow) throws {
            guard let ordinal = state.ordinal, ordinal >= 0 else {
                throw BridgeReceiverStorageError.malformedRow("item order")
            }
            switch state.textValue {
            case "member":
                guard let id = state.worktreeID else { throw BridgeReceiverStorageError.malformedRow("member order") }
                memberOrder[id] = ordinal
            case "prReference":
                guard let host = state.forgeHost, let owner = state.forgeOwner,
                    let repository = state.forgeRepository, let number = state.forgeNumber
                else {
                    throw BridgeReceiverStorageError.malformedRow("PR order")
                }
                let identity = try ForgePullRequestIdentity(
                    host: host, owner: owner, repository: repository, number: number)
                pullRequestOrder[identity] = ordinal
            default: throw BridgeReceiverStorageError.malformedRow("item order kind")
            }
        }
    }

    private static func filesFilter(_ state: BridgeReceiverStateRow) throws -> BridgeFilesFilter {
        switch state.textValue {
        case "allMembers":
            guard state.worktreeID == nil else { throw BridgeReceiverStorageError.malformedRow("filter") }
            return .allMembers
        case "openedDocuments":
            guard state.worktreeID == nil else { throw BridgeReceiverStorageError.malformedRow("filter") }
            return .openedDocuments
        case "member":
            guard let id = state.worktreeID else { throw BridgeReceiverStorageError.malformedRow("filter") }
            return .member(worktreeId: id)
        default: throw BridgeReceiverStorageError.malformedRow("filter")
        }
    }

    private static func selectedDocument(_ state: BridgeReceiverStateRow) throws -> BridgeDocumentLocation {
        guard let path = state.documentPath, let location = BridgeDocumentLocation(canonicalPath: path) else {
            throw BridgeReceiverStorageError.malformedRow("selection")
        }
        return location
    }

    private static func reviewSelection(_ state: BridgeReceiverStateRow) throws -> BridgeReviewSelection {
        switch state.textValue {
        case "unselected": return .unselected
        case "member":
            guard let id = state.worktreeID else { throw BridgeReceiverStorageError.malformedRow("review selection") }
            return .member(worktreeId: id)
        case "importedUnavailable":
            guard let variantRaw = state.importedVariant,
                let variant = BridgeImportedReviewQuery.Variant(rawValue: variantRaw),
                let payload = state.importedPayload
            else {
                throw BridgeReceiverStorageError.malformedRow("imported review")
            }
            return .importedUnavailable(.init(variant: variant, originalPayloadJSON: payload))
        default: throw BridgeReceiverStorageError.malformedRow("review selection")
        }
    }

    private static func surface(_ state: BridgeReceiverStateRow) throws -> BridgeNavigationSurface {
        guard let value = state.textValue, let surface = BridgeNavigationSurface(rawValue: value) else {
            throw BridgeReceiverStorageError.malformedRow("surface")
        }
        return surface
    }

    private static func openedDocument(_ state: BridgeReceiverStateRow) throws -> (Int, BridgeOpenedDocument) {
        guard let path = state.documentPath, let location = BridgeDocumentLocation(canonicalPath: path),
            let ordinal = state.ordinal, ordinal >= 0
        else {
            throw BridgeReceiverStorageError.malformedRow("opened document")
        }
        let provenance: BridgeKnownWorktreeProvenance?
        if let repo = state.provenanceRepoID, let worktree = state.provenanceWorktreeID,
            let relative = state.provenanceRelativePath
        {
            provenance = .init(repoId: repo, worktreeId: worktree, relativePath: relative)
        } else if state.provenanceRepoID == nil, state.provenanceWorktreeID == nil,
            state.provenanceRelativePath == nil
        {
            provenance = nil
        } else {
            throw BridgeReceiverStorageError.malformedRow("document provenance")
        }
        return (ordinal, .init(location: location, provenance: provenance))
    }

    private static func requireSingleton(_ state: BridgeReceiverStateRow) throws {
        guard state.itemKey == BridgeReceiverStateKeyCodec.singleton else {
            throw BridgeReceiverStorageError.malformedRow("singleton key")
        }
    }

    private static func validateStateIdentity(_ state: BridgeReceiverStateRow) throws {
        let presentColumns = Set(
            [
                state.textValue == nil ? nil : "textValue",
                state.worktreeID == nil ? nil : "worktreeID",
                state.forgeHost == nil ? nil : "forgeHost",
                state.forgeOwner == nil ? nil : "forgeOwner",
                state.forgeRepository == nil ? nil : "forgeRepository",
                state.forgeNumber == nil ? nil : "forgeNumber",
                state.documentPath == nil ? nil : "documentPath",
                state.provenanceRepoID == nil ? nil : "provenanceRepoID",
                state.provenanceWorktreeID == nil ? nil : "provenanceWorktreeID",
                state.provenanceRelativePath == nil ? nil : "provenanceRelativePath",
                state.comparisonKind == nil ? nil : "comparisonKind",
                state.comparisonBasis == nil ? nil : "comparisonBasis",
                state.comparisonName == nil ? nil : "comparisonName",
                state.comparisonBranch == nil ? nil : "comparisonBranch",
                state.comparisonRemote == nil ? nil : "comparisonRemote",
                state.comparisonOID == nil ? nil : "comparisonOID",
                state.ordinal == nil ? nil : "ordinal",
                state.importedVariant == nil ? nil : "importedVariant",
                state.importedPayload == nil ? nil : "importedPayload",
            ].compactMap { $0 })
        let allowedColumns: Set<String>
        switch state.kind {
        case "filesFilter": allowedColumns = ["textValue", "worktreeID"]
        case "selectedFilesDocument": allowedColumns = ["documentPath"]
        case "reviewSelection": allowedColumns = ["textValue", "worktreeID", "importedVariant", "importedPayload"]
        case "surface": allowedColumns = ["textValue"]
        case "reviewComparison":
            allowedColumns = [
                "worktreeID", "comparisonKind", "comparisonBasis", "comparisonName",
                "comparisonBranch", "comparisonRemote", "comparisonOID",
            ]
        case "itemOrder":
            allowedColumns = [
                "textValue", "worktreeID", "forgeHost", "forgeOwner",
                "forgeRepository", "forgeNumber", "ordinal",
            ]
        case "openedDocument":
            allowedColumns = [
                "documentPath", "provenanceRepoID", "provenanceWorktreeID",
                "provenanceRelativePath", "ordinal",
            ]
        default: throw BridgeReceiverStorageError.malformedRow("state kind")
        }
        guard presentColumns.isSubset(of: allowedColumns) else {
            throw BridgeReceiverStorageError.malformedRow("state kind columns")
        }
        switch state.kind {
        case "filesFilter", "selectedFilesDocument", "reviewSelection", "surface":
            try requireSingleton(state)
        case "reviewComparison":
            guard let id = state.worktreeID, BridgeReceiverStateKeyCodec.member(id) == state.itemKey else {
                throw BridgeReceiverStorageError.malformedRow("comparison identity")
            }
        case "openedDocument":
            guard let path = state.documentPath,
                let location = BridgeDocumentLocation(canonicalPath: path),
                BridgeReceiverStateKeyCodec.document(location) == state.itemKey
            else {
                throw BridgeReceiverStorageError.malformedRow("document identity")
            }
        case "itemOrder":
            switch state.textValue {
            case "member":
                guard let id = state.worktreeID, BridgePaneLinkItemKeyCodec.member(id) == state.itemKey,
                    state.forgeHost == nil, state.forgeOwner == nil,
                    state.forgeRepository == nil, state.forgeNumber == nil
                else {
                    throw BridgeReceiverStorageError.malformedRow("member order identity")
                }
            case "prReference":
                guard state.worktreeID == nil, let host = state.forgeHost,
                    let owner = state.forgeOwner, let repository = state.forgeRepository,
                    let number = state.forgeNumber
                else {
                    throw BridgeReceiverStorageError.malformedRow("PR order identity")
                }
                let identity = try ForgePullRequestIdentity(
                    host: host, owner: owner,
                    repository: repository, number: number)
                guard BridgePaneLinkItemKeyCodec.pullRequest(identity) == state.itemKey else {
                    throw BridgeReceiverStorageError.malformedRow("PR order identity")
                }
            default: throw BridgeReceiverStorageError.malformedRow("order kind")
            }
        default: throw BridgeReceiverStorageError.malformedRow("state kind")
        }
    }

    private static func validateItemIdentity(_ item: BridgeReceiverItemRow) throws {
        switch item.kind {
        case "member":
            guard let id = item.worktreeID, BridgePaneLinkItemKeyCodec.member(id) == item.itemKey,
                item.forgeHost == nil, item.forgeOwner == nil,
                item.forgeRepository == nil, item.forgeNumber == nil
            else {
                throw BridgeReceiverStorageError.malformedRow("member identity")
            }
        case "prReference":
            guard item.worktreeID == nil, let host = item.forgeHost,
                let owner = item.forgeOwner, let repository = item.forgeRepository,
                let number = item.forgeNumber
            else {
                throw BridgeReceiverStorageError.malformedRow("PR identity")
            }
            let identity = try ForgePullRequestIdentity(
                host: host, owner: owner,
                repository: repository, number: number)
            guard BridgePaneLinkItemKeyCodec.pullRequest(identity) == item.itemKey else {
                throw BridgeReceiverStorageError.malformedRow("PR key")
            }
        default: throw BridgeReceiverStorageError.malformedRow("item kind")
        }
    }

    private static func comparison(_ state: BridgeReceiverStateRow) throws -> WorkspaceBaseline {
        switch state.comparisonKind {
        case "localDefaultBranch":
            guard let branch = state.comparisonBranch, let basis = basis(state) else { break }
            return .localDefaultBranch(branchName: branch, basis: basis)
        case "originDefaultBranch":
            guard let remote = state.comparisonRemote, let branch = state.comparisonBranch,
                let basis = basis(state)
            else { break }
            return .originDefaultBranch(remoteName: remote, branchName: branch, basis: basis)
        case "branch":
            guard let name = state.comparisonName, let basis = basis(state) else { break }
            return .branch(name: name, basis: basis)
        case "commit":
            guard let oid = state.comparisonOID else { break }
            return .commit(oid: oid)
        case "ref":
            guard let name = state.comparisonName, let basis = basis(state) else { break }
            return .ref(name: name, basis: basis)
        case "headMinusOne": return .headMinusOne
        case "staged": return .staged
        case "unstaged": return .unstaged
        default: break
        }
        throw BridgeReceiverStorageError.malformedRow("comparison columns")
    }

    private static func basis(_ state: BridgeReceiverStateRow) -> WorkspaceReviewComparisonBasis? {
        guard let raw = state.comparisonBasis else { return nil }
        return WorkspaceReviewComparisonBasis(rawValue: raw)
    }
}

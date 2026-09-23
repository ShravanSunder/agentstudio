import AgentStudioCore
import CryptoKit
import Foundation

/// One member worktree of a receiver's Files collection.
struct BridgeFileCollectionMember: Equatable, Sendable {
    let worktreeId: UUID
    let canonicalRootPath: String
}

/// The presentation keys of one receiver's Files collection.
///
/// Every member worktree is listed under its own group directory and every
/// opened document outside all members under the opened-documents group. Group
/// paths are presentation keys only: they are never filesystem paths and never
/// grant read authority. A key resolves back to `(member, relative path)` or to
/// an exact opened document; basenames alone are never keys.
///
/// Keys are sticky. Updating the membership keeps every surviving member's and
/// document's key, so adding or removing one source never re-keys the rows,
/// selection or descriptors of another.
struct BridgeFileCollectionLayout: Equatable, Sendable {
    static let openedDocumentsGroupPath = "Open Files"

    struct MemberGroup: Equatable, Sendable {
        let worktreeId: UUID
        let canonicalRootPath: String
        let groupPath: String
        /// Member-relative roots of deeper member worktrees nested inside this
        /// one; their files belong to the deepest member, never to both.
        let nestedMemberRelativeRoots: [String]
        let identityPrefix: String
    }

    struct OpenedDocumentEntry: Equatable, Sendable {
        let location: BridgeDocumentLocation
        let displayPath: String
        let identityPrefix: String
    }

    enum Resolution: Equatable, Sendable {
        case memberGroup(worktreeId: UUID)
        case memberPath(worktreeId: UUID, relativePath: String)
        case openedDocumentsGroup
        case openedDocument(BridgeDocumentLocation)
    }

    static let empty = Self(memberGroups: [], openedDocuments: [])

    private(set) var memberGroups: [MemberGroup]
    private(set) var openedDocuments: [OpenedDocumentEntry]

    /// Lay out `members` in collection order plus the opened documents that fall
    /// outside every member. A document inside a member root is part of that
    /// member's tree, whichever way it was opened; equal-root ambiguity keeps
    /// the document listed by location instead of guessing its worktree.
    func updating(
        members: [BridgeFileCollectionMember],
        openedDocuments documents: [BridgeDocumentLocation]
    ) -> Self {
        let previousGroupPaths = Dictionary(
            uniqueKeysWithValues: memberGroups.map { ($0.worktreeId, $0.groupPath) }
        )
        var usedGroupPaths: Set<String> = [Self.openedDocumentsGroupPath]
        var groupPathByWorktreeId: [UUID: String] = [:]
        for member in members {
            guard let previous = previousGroupPaths[member.worktreeId] else { continue }
            groupPathByWorktreeId[member.worktreeId] = previous
            usedGroupPaths.insert(previous)
        }
        var nextGroups: [MemberGroup] = []
        for member in members {
            let groupPath =
                groupPathByWorktreeId[member.worktreeId]
                ?? Self.unusedName(
                    preferred: Self.groupName(forRootPath: member.canonicalRootPath),
                    in: &usedGroupPaths
                )
            nextGroups.append(
                MemberGroup(
                    worktreeId: member.worktreeId,
                    canonicalRootPath: member.canonicalRootPath,
                    groupPath: groupPath,
                    nestedMemberRelativeRoots: Self.nestedRelativeRoots(of: member, among: members),
                    identityPrefix: "m\(Self.shortDigest(member.canonicalRootPath))."
                )
            )
        }

        let memberIds = members.map(\.worktreeId)
        let rootsById = Dictionary(
            uniqueKeysWithValues: members.map { ($0.worktreeId, $0.canonicalRootPath) }
        )
        let previousDocumentPaths = Dictionary(
            uniqueKeysWithValues: openedDocuments.map { ($0.location, $0.displayPath) }
        )
        let looseDocuments = documents.filter { location in
            switch BridgeNavigationRules.grouping(
                of: location,
                memberWorktreeIds: memberIds,
                memberRootsByWorktreeId: rootsById
            ) {
            case .member: false
            case .loose, .ambiguous: true
            }
        }
        var usedDocumentPaths = Set(
            looseDocuments.compactMap { previousDocumentPaths[$0] }
        )
        let nextDocuments = looseDocuments.map { location in
            let displayPath =
                previousDocumentPaths[location]
                ?? "\(Self.openedDocumentsGroupPath)/"
                + Self.unusedDocumentName(for: location, in: &usedDocumentPaths)
            return OpenedDocumentEntry(
                location: location,
                displayPath: displayPath,
                identityPrefix: "d\(Self.shortDigest(location.canonicalPath))."
            )
        }
        return Self(memberGroups: nextGroups, openedDocuments: nextDocuments)
    }

    func memberGroup(for worktreeId: UUID) -> MemberGroup? {
        memberGroups.first { $0.worktreeId == worktreeId }
    }

    func openedDocument(at displayPath: String) -> OpenedDocumentEntry? {
        openedDocuments.first { $0.displayPath == displayPath }
    }

    func resolve(displayPath: String) -> Resolution? {
        if displayPath == Self.openedDocumentsGroupPath { return .openedDocumentsGroup }
        if let document = openedDocument(at: displayPath) { return .openedDocument(document.location) }
        for group in memberGroups {
            if displayPath == group.groupPath { return .memberGroup(worktreeId: group.worktreeId) }
            guard displayPath.hasPrefix(group.groupPath + "/") else { continue }
            let relativePath = String(displayPath.dropFirst(group.groupPath.count + 1))
            guard !group.belongsToNestedMember(relativePath) else { return nil }
            return .memberPath(worktreeId: group.worktreeId, relativePath: relativePath)
        }
        return nil
    }

    /// The collection key for a member's relative path, or nil when the path
    /// belongs to a deeper nested member.
    func displayPath(worktreeId: UUID, relativePath: String) -> String? {
        guard let group = memberGroup(for: worktreeId), !group.belongsToNestedMember(relativePath) else {
            return nil
        }
        return "\(group.groupPath)/\(relativePath)"
    }

    static func namespacedIdentifier(prefix: String, identifier: String) -> String {
        let candidate = prefix + identifier
        guard candidate.utf8.count > BridgeProductWireContract.maximumIdentifierByteLength else {
            return candidate
        }
        return prefix + digest(identifier).prefix(64)
    }

    private static func groupName(forRootPath canonicalRootPath: String) -> String {
        let name = (canonicalRootPath as NSString).lastPathComponent
        return name.isEmpty || name == "/" ? "root" : name
    }

    private static func unusedName(preferred: String, in used: inout Set<String>) -> String {
        var candidate = preferred
        var ordinal = 2
        while used.contains(candidate) {
            candidate = "\(preferred) (\(ordinal))"
            ordinal += 1
        }
        used.insert(candidate)
        return candidate
    }

    private static func unusedDocumentName(
        for location: BridgeDocumentLocation,
        in used: inout Set<String>
    ) -> String {
        let name = location.displayName
        let stem = (name as NSString).deletingPathExtension
        let pathExtension = (name as NSString).pathExtension
        var candidate = name
        var ordinal = 2
        while used.contains("\(openedDocumentsGroupPath)/\(candidate)") {
            candidate = pathExtension.isEmpty ? "\(stem) (\(ordinal))" : "\(stem) (\(ordinal)).\(pathExtension)"
            ordinal += 1
        }
        used.insert("\(openedDocumentsGroupPath)/\(candidate)")
        return candidate
    }

    private static func nestedRelativeRoots(
        of member: BridgeFileCollectionMember,
        among members: [BridgeFileCollectionMember]
    ) -> [String] {
        members.compactMap { other in
            guard other.worktreeId != member.worktreeId,
                let otherLocation = BridgeDocumentLocation(canonicalPath: other.canonicalRootPath)
            else { return nil }
            return otherLocation.relativePath(inCanonicalRoot: member.canonicalRootPath)
        }
    }

    private static func shortDigest(_ value: String) -> String {
        String(digest(value).prefix(12))
    }

    private static func digest(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

extension BridgeFileCollectionLayout.MemberGroup {
    func belongsToNestedMember(_ relativePath: String) -> Bool {
        nestedMemberRelativeRoots.contains { nestedRoot in
            relativePath == nestedRoot || relativePath.hasPrefix(nestedRoot + "/")
        }
    }
}

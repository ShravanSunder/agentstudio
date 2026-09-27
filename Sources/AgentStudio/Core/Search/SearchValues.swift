import Foundation

package struct SearchItemId: Hashable, Sendable {
    package let rawValue: String

    package init?(_ rawValue: String) {
        guard !rawValue.isEmpty else { return nil }
        self.rawValue = rawValue
    }
}

package enum SearchKind: String, CaseIterable, Sendable {
    case repo
    case worktree
    case pane
    case tab
    case command
    case other
}

package struct SearchDocument: Sendable {
    package let itemId: SearchItemId
    package let kind: SearchKind
    package let groupId: String
    package let title: String
    package let fields: [String]

    package init(itemId: SearchItemId, kind: SearchKind, groupId: String, title: String, fields: [String]) {
        self.itemId = itemId
        self.kind = kind
        self.groupId = groupId
        self.title = title
        self.fields = fields
    }
}

package struct SearchGroup: Sendable {
    package let id: String
    package let priority: Int

    package init(id: String, priority: Int) {
        self.id = id
        self.priority = priority
    }
}

package struct SearchDocumentGeneration: Hashable, Comparable, Sendable {
    package let value: UInt64

    package init(_ value: UInt64) {
        self.value = value
    }

    package static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.value < rhs.value
    }
}

package struct SearchDocumentSet: Sendable {
    package let generation: SearchDocumentGeneration
    package let groups: [SearchGroup]
    package let documents: [SearchDocument]

    package init(generation: SearchDocumentGeneration, groups: [SearchGroup], documents: [SearchDocument]) {
        self.generation = generation
        self.groups = groups
        self.documents = documents
    }
}

package struct SearchRequestSequence: Hashable, Comparable, Sendable {
    package let value: UInt64

    package init(_ value: UInt64) {
        self.value = value
    }

    package static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.value < rhs.value
    }
}

package struct SearchRequest: Sendable {
    package let sequence: SearchRequestSequence
    package let text: String
    package let recentItemIds: [SearchItemId]
    package let documentSet: SearchDocumentSet

    package init(
        sequence: SearchRequestSequence,
        text: String,
        recentItemIds: [SearchItemId],
        documentSet: SearchDocumentSet
    ) {
        self.sequence = sequence
        self.text = text
        self.recentItemIds = recentItemIds
        self.documentSet = documentSet
    }
}

package enum SearchDegradedReason: Equatable, Sendable {
    case databaseUnavailable
    case unreadableRow
}

package enum SearchResultOutcome: Equatable, Sendable {
    case answered
    case obsolete
    case degraded(SearchDegradedReason)
}

package struct SearchMatch: Sendable {
    package let itemId: SearchItemId
    package let titleMatch: Range<Int>?

    package init(itemId: SearchItemId, titleMatch: Range<Int>?) {
        self.itemId = itemId
        self.titleMatch = titleMatch
    }
}

package struct SearchResultGroup: Sendable {
    package let groupId: String
    package let matches: [SearchMatch]

    package init(groupId: String, matches: [SearchMatch]) {
        self.groupId = groupId
        self.matches = matches
    }
}

package struct SearchResultSet: Sendable {
    package let sequence: SearchRequestSequence
    package let generation: SearchDocumentGeneration
    package let groups: [SearchResultGroup]
    package let outcome: SearchResultOutcome

    package init(
        sequence: SearchRequestSequence,
        generation: SearchDocumentGeneration,
        groups: [SearchResultGroup],
        outcome: SearchResultOutcome
    ) {
        self.sequence = sequence
        self.generation = generation
        self.groups = groups
        self.outcome = outcome
    }
}

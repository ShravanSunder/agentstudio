import AgentStudioInfrastructure
import Foundation

struct WorktreeAnnotationIdentity<TIdentityScope>: Hashable, Sendable {
    let rawValue: UUID

    static func generate() -> Self {
        Self(rawValue: UUIDv7.generate())
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue == rhs.rawValue
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(rawValue)
    }
}

extension WorktreeAnnotationIdentity: Codable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(rawValue: try container.decode(UUID.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

enum WorktreeAnnotationSessionIdentityScope: Sendable {}
enum WorktreeAnnotationThreadIdentityScope: Sendable {}
enum WorktreeAnnotationMessageIdentityScope: Sendable {}
enum WorktreeAnnotationOutputAttemptIdentityScope: Sendable {}
enum WorktreeAnnotationOutputEventIdentityScope: Sendable {}
enum WorktreeAnnotationRecoveryProvenanceIdentityScope: Sendable {}

typealias WorktreeAnnotationSessionID = WorktreeAnnotationIdentity<WorktreeAnnotationSessionIdentityScope>
typealias WorktreeAnnotationThreadID = WorktreeAnnotationIdentity<WorktreeAnnotationThreadIdentityScope>
typealias WorktreeAnnotationMessageID = WorktreeAnnotationIdentity<WorktreeAnnotationMessageIdentityScope>
typealias WorktreeAnnotationOutputAttemptID = WorktreeAnnotationIdentity<WorktreeAnnotationOutputAttemptIdentityScope>
typealias WorktreeAnnotationOutputEventID = WorktreeAnnotationIdentity<WorktreeAnnotationOutputEventIdentityScope>
typealias WorktreeAnnotationRecoveryProvenanceID = WorktreeAnnotationIdentity<
    WorktreeAnnotationRecoveryProvenanceIdentityScope
>

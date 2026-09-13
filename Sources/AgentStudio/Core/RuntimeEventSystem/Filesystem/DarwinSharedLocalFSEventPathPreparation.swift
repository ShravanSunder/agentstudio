import Foundation

struct DarwinSharedLocalFSEventPreparedPath: Hashable, Sendable {
    let normalizedPath: String
    let descendantPrefix: String

    init(
        _ path: String,
        normalizePath: (String) -> String
    ) {
        normalizedPath = normalizePath(path)
        descendantPrefix = normalizedPath == "/" ? "/" : normalizedPath + "/"
    }

    func contains(_ candidatePath: String) -> Bool {
        candidatePath == normalizedPath || candidatePath.hasPrefix(descendantPrefix)
    }

    static func prepareDistinct(
        _ paths: [String],
        normalizePath: (String) -> String
    ) -> [Self] {
        distinct(
            paths.map { Self($0, normalizePath: normalizePath) }
        )
    }

    static func distinct(_ paths: [Self]) -> [Self] {
        Array(Set(paths)).sorted { $0.normalizedPath < $1.normalizedPath }
    }
}

struct DarwinSharedLocalFSEventPreparedRawEvent: @unchecked Sendable {
    let rawEvent: DarwinLocalFSEventRawEvent
    let path: DarwinSharedLocalFSEventPreparedPath
}

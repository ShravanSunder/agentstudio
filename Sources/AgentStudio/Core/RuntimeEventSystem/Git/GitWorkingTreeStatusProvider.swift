import Foundation

enum GitOriginResolution: Sendable, Equatable {
    case awaitingResolution
    case confirmedAbsent
    case resolved(String)
}

struct GitWorkingTreeStatus: Sendable, Equatable {
    let summary: GitWorkingTreeSummary
    let branch: String?
    let originResolution: GitOriginResolution

    init(
        summary: GitWorkingTreeSummary,
        branch: String?,
        originResolution: GitOriginResolution
    ) {
        self.summary = summary
        self.branch = branch
        self.originResolution = originResolution
    }

    init(
        summary: GitWorkingTreeSummary,
        branch: String?,
        origin: String?
    ) {
        self.init(
            summary: summary,
            branch: branch,
            originResolution: origin.map(GitOriginResolution.resolved) ?? .confirmedAbsent
        )
    }

    var origin: String? {
        switch originResolution {
        case .resolved(let origin):
            origin
        case .awaitingResolution, .confirmedAbsent:
            nil
        }
    }
}

protocol GitWorkingTreeStatusProvider: Sendable {
    func status(for rootPath: URL) async -> GitWorkingTreeStatus?
}

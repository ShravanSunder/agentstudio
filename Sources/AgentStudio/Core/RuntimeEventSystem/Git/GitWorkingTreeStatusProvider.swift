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

enum GitWorkingTreeStatusUnavailableReason: String, Sendable, Equatable {
    case providerReturnedNil = "provider_returned_nil"
    case timeout
    case readAlreadyInFlight = "read_already_in_flight"
    case cancelled
    case sdkError = "sdk_error"
}

struct GitWorkingTreeStatusUnavailable: Sendable, Equatable {
    let reason: GitWorkingTreeStatusUnavailableReason
}

enum GitWorkingTreeStatusResult: Sendable, Equatable {
    case available(GitWorkingTreeStatus)
    case unavailable(GitWorkingTreeStatusUnavailable)
}

protocol GitWorkingTreeStatusProvider: Sendable {
    func statusResult(for rootPath: URL) async -> GitWorkingTreeStatusResult
    func status(for rootPath: URL) async -> GitWorkingTreeStatus?
}

extension GitWorkingTreeStatusProvider {
    func statusResult(for rootPath: URL) async -> GitWorkingTreeStatusResult {
        guard let status = await status(for: rootPath) else {
            return .unavailable(GitWorkingTreeStatusUnavailable(reason: .providerReturnedNil))
        }
        return .available(status)
    }

    func status(for rootPath: URL) async -> GitWorkingTreeStatus? {
        switch await statusResult(for: rootPath) {
        case .available(let status):
            status
        case .unavailable:
            nil
        }
    }
}

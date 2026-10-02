import AgentStudioCore
import Foundation

/// Builds a `TerminalColdRestorePlan` from a pane and configuration
/// (SR3, SR6a; Program Design item 2: "`TerminalRestoreRuntime` builds the
/// plan from the pane and configuration it already reads, and passes it to
/// the builder"). Pure and actor-independent — unlike `TerminalRestoreRuntime`
/// (`@MainActor`), this has no MainActor dependency, so the off-main restore
/// decision (`TerminalRestoreKindResolver`, App) can call it directly.
package enum TerminalColdRestorePlanBuilder {
    package static func applyingResumeEvidence(
        _ evidence: ResumeEvidence, providerIdentifier: String, providerSessionId: String,
        to plan: TerminalColdRestorePlan
    ) -> TerminalColdRestorePlan {
        let invocation: ResumeInvocation?
        let notice: String
        switch evidence {
        case .knownExited:
            invocation = nil
            notice = ""
        case .interruptedCandidate(let candidate):
            invocation = candidate
            notice =
                "Resumed \(candidate.provider.displayName) session \(candidate.sessionId.rawValue.prefix(8)) after restart"
        case .unknown:
            invocation = nil
            let provider = ResumeProvider(providerIdentifier: providerIdentifier)?.displayName ?? providerIdentifier
            notice =
                "Could not determine whether \(provider) session \(providerSessionId.prefix(8)) exited; resume it manually."
        }
        return TerminalColdRestorePlan(
            zmxExecutable: plan.zmxExecutable, zmxDirectory: plan.zmxDirectory, sessionID: plan.sessionID,
            loginShell: plan.loginShell, folderCandidates: plan.folderCandidates,
            notice: .init(linesByCandidateIndex: plan.folderCandidates.map { _ in notice }),
            replayFile: plan.replayFile, resume: invocation, attemptID: plan.attemptID)
    }

    /// Applies when a cold pane never had a current binding to report on and
    /// readiness itself could not be checked in time (SR12 defect fix). With
    /// no binding there is no real provider or session id to name, so unlike
    /// `applyingResumeEvidence` this never invents one: every candidate gets
    /// the same honest, unattributed notice, and resume stays nil because
    /// there is nothing to resume into.
    package static func applyingUncheckedAgentStateNotice(to plan: TerminalColdRestorePlan) -> TerminalColdRestorePlan {
        let notice =
            "Agent state couldn't be checked before restore; if an agent was running here, resume it manually."
        return TerminalColdRestorePlan(
            zmxExecutable: plan.zmxExecutable, zmxDirectory: plan.zmxDirectory, sessionID: plan.sessionID,
            loginShell: plan.loginShell, folderCandidates: plan.folderCandidates,
            notice: .init(linesByCandidateIndex: plan.folderCandidates.map { _ in notice }),
            replayFile: plan.replayFile, resume: nil, attemptID: plan.attemptID)
    }

    /// `zmxExecutablePath`, `zmxDirectoryPath` and `loginShellPath` are the
    /// same values `TerminalRestoreRuntime` already resolves for today's warm
    /// attach — passed in rather than re-resolved, so this stays a pure
    /// function of its arguments.
    package static func buildPlan(
        pane: Pane,
        sessionID: ZmxSessionID,
        zmxExecutablePath: String,
        zmxDirectoryPath: String,
        loginShellPath: String,
        repositoryMainFolder: URL?
    ) -> TerminalColdRestorePlan {
        let savedFolder = pane.metadata.cwd ?? pane.metadata.launchDirectory
        let homeFolder = FileManager.default.homeDirectoryForCurrentUser

        var folderCandidates: [URL] = []
        var noticeLines: [String] = []
        if let savedFolder {
            folderCandidates.append(savedFolder)
            noticeLines.append("Restored after restart")
        }
        if let repositoryMainFolder {
            folderCandidates.append(repositoryMainFolder)
            noticeLines.append(
                "Restored after restart (saved folder missing; using the repository's main folder)"
            )
        }
        folderCandidates.append(homeFolder)
        noticeLines.append(
            folderCandidates.count == 1
                ? "Restored after restart"
                : "Restored after restart (saved and repository folders missing; using the home folder)"
        )

        return TerminalColdRestorePlan(
            zmxExecutable: URL(fileURLWithPath: zmxExecutablePath),
            zmxDirectory: URL(fileURLWithPath: zmxDirectoryPath),
            sessionID: sessionID,
            loginShell: URL(fileURLWithPath: loginShellPath),
            folderCandidates: folderCandidates,
            notice: ColdRestoreNotice(linesByCandidateIndex: noticeLines),
            replayFile: nil,
            resume: nil,
            attemptID: .generate()
        )
    }
}

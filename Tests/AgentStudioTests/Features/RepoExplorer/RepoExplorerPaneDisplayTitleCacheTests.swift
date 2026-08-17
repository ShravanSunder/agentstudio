import Foundation
import Testing

@testable import AgentStudioRepoExplorer

@MainActor
private final class NormalizeCallRecorder {
    private(set) var callCount = 0

    func normalize(liveTitle: String, cwd: URL?, shellExecutablePath: String?) -> String {
        callCount += 1
        return "normalized:\(liveTitle)"
    }
}

@MainActor
@Suite("RepoExplorerPaneDisplayTitleCache")
struct RepoExplorerPaneDisplayTitleCacheTests {
    @Test("F6b: unchanged inputs skip re-derivation and return the memoized value")
    func unchangedInputsSkipRederivation() {
        let recorder = NormalizeCallRecorder()
        let cache = RepoExplorerPaneDisplayTitleCache(normalize: recorder.normalize)
        let paneId = UUID()
        let cwd = URL(filePath: "/tmp/agent-studio")

        let first = cache.resolve(paneId: paneId, liveTitle: "building", cwd: cwd, shellExecutablePath: "/bin/zsh")
        let second = cache.resolve(paneId: paneId, liveTitle: "building", cwd: cwd, shellExecutablePath: "/bin/zsh")

        #expect(first == "normalized:building")
        #expect(second == "normalized:building")
        #expect(recorder.callCount == 1)
    }

    @Test("F6b: a changed input re-derives and updates the memoized value")
    func changedInputRederives() {
        let recorder = NormalizeCallRecorder()
        let cache = RepoExplorerPaneDisplayTitleCache(normalize: recorder.normalize)
        let paneId = UUID()
        let cwd = URL(filePath: "/tmp/agent-studio")

        _ = cache.resolve(paneId: paneId, liveTitle: "building", cwd: cwd, shellExecutablePath: "/bin/zsh")
        let afterTitleChange = cache.resolve(
            paneId: paneId, liveTitle: "tests running", cwd: cwd, shellExecutablePath: "/bin/zsh")

        #expect(afterTitleChange == "normalized:tests running")
        #expect(recorder.callCount == 2)
    }

    @Test("F6b: entries are isolated per pane")
    func entriesAreIsolatedPerPane() {
        let recorder = NormalizeCallRecorder()
        let cache = RepoExplorerPaneDisplayTitleCache(normalize: recorder.normalize)
        let firstPaneId = UUID()
        let secondPaneId = UUID()
        let cwd = URL(filePath: "/tmp/agent-studio")

        let firstPaneTitle = cache.resolve(
            paneId: firstPaneId, liveTitle: "same title", cwd: cwd, shellExecutablePath: "/bin/zsh")
        let secondPaneTitle = cache.resolve(
            paneId: secondPaneId, liveTitle: "same title", cwd: cwd, shellExecutablePath: "/bin/zsh")

        #expect(firstPaneTitle == secondPaneTitle)
        #expect(recorder.callCount == 2)
    }

    @Test("F6b: retainOnly drops entries for panes no longer present")
    func retainOnlyDropsMissingPaneEntries() {
        let recorder = NormalizeCallRecorder()
        let cache = RepoExplorerPaneDisplayTitleCache(normalize: recorder.normalize)
        let retainedPaneId = UUID()
        let closedPaneId = UUID()
        let cwd = URL(filePath: "/tmp/agent-studio")

        _ = cache.resolve(paneId: retainedPaneId, liveTitle: "kept", cwd: cwd, shellExecutablePath: "/bin/zsh")
        _ = cache.resolve(paneId: closedPaneId, liveTitle: "closed", cwd: cwd, shellExecutablePath: "/bin/zsh")
        cache.retainOnly(paneIds: [retainedPaneId])

        let callCountBeforeReResolve = recorder.callCount
        _ = cache.resolve(paneId: retainedPaneId, liveTitle: "kept", cwd: cwd, shellExecutablePath: "/bin/zsh")
        _ = cache.resolve(paneId: closedPaneId, liveTitle: "closed", cwd: cwd, shellExecutablePath: "/bin/zsh")

        // The retained pane's unchanged inputs stay memoized (no new call); the pruned pane's
        // entry is gone, so resolving it again re-derives.
        #expect(recorder.callCount == callCountBeforeReResolve + 1)
    }
}

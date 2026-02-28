import Foundation
import Testing

@testable import AgentStudio

@Suite("PaneRuntime contracts")
struct PaneRuntimeContractsTests {
    @Test("terminal events expose action policy")
    func terminalPolicy() {
        let event = PaneRuntimeEvent.terminal(.bellRang)
        #expect(event.actionPolicy == .critical)
    }

    @Test("runtime command namespace is distinct from workspace PaneAction")
    func commandTypeIsDistinct() {
        let command = RuntimeCommand.activate
        #expect(String(describing: command).contains("activate"))
    }

    @Test("event identifier supports built-in and plugin tags")
    func eventIdentifierExtensibility() {
        #expect(EventIdentifier.commandFinished.rawValue == "commandFinished")
        #expect(EventIdentifier.plugin("logViewer.lineAppended").rawValue == "logViewer.lineAppended")
    }

    @Test("pane metadata remains available after relocation to pane runtime contracts")
    func paneMetadataRelocation() {
        let metadata = PaneMetadata(source: .floating(workingDirectory: nil, title: "X"), title: "X")
        #expect(metadata.title == "X")
        #expect(metadata.paneId.isV7)
        #expect(metadata.contentType == .terminal)
        #expect(metadata.executionBackend == .local)
        #expect(metadata.createdAt.timeIntervalSince1970 > 0)
        #expect(metadata.facets.tags.isEmpty)
    }

    @Test("pane context facets merge source defaults for worktree metadata")
    func paneContextFacetsMergeSourceDefaults() {
        let worktreeId = UUID()
        let repoId = UUID()
        let metadata = PaneMetadata(
            source: .worktree(worktreeId: worktreeId, repoId: repoId),
            facets: PaneContextFacets(tags: ["focus"])
        )
        #expect(metadata.facets.worktreeId == worktreeId)
        #expect(metadata.facets.repoId == repoId)
        #expect(metadata.facets.tags == ["focus"])
    }

    @Test("system source three-tier hierarchy: builtin, service, plugin")
    func systemSourceHierarchy() {
        #expect(
            EventSource.system(.builtin(.filesystemWatcher)).description
                == "system:builtin/filesystemWatcher"
        )
        #expect(
            EventSource.system(.builtin(.securityBackend)).description
                == "system:builtin/securityBackend"
        )
        #expect(
            EventSource.system(.builtin(.coordinator)).description
                == "system:builtin/coordinator"
        )
        #expect(
            EventSource.system(.service(.gitForge(provider: "github"))).description
                == "system:service/gitForge/github"
        )
        #expect(
            EventSource.system(.service(.containerService(provider: "docker"))).description
                == "system:service/containerService/docker"
        )
        #expect(
            EventSource.system(.plugin("mcp-weather")).description
                == "system:plugin/mcp-weather"
        )
    }

    @Test("provider names with special characters produce unambiguous descriptions")
    func systemSourceProviderEscaping() {
        let forgeWithColon = EventSource.system(.service(.gitForge(provider: "my:forge")))
        #expect(forgeWithColon.description == "system:service/gitForge/my:forge")

        let pluginWithSlash = EventSource.system(.plugin("mcp/weather"))
        #expect(pluginWithSlash.description == "system:plugin/mcp/weather")
    }

    @Test("filesystem source identity is system builtin watcher with worktree in facets")
    func filesystemSourceIdentityContract() {
        let worktreeId = UUID()
        let now = ContinuousClock().now
        let envelope = PaneEventEnvelope(
            source: .system(.builtin(.filesystemWatcher)),
            sourceFacets: PaneContextFacets(worktreeId: worktreeId),
            paneKind: nil,
            seq: 1,
            commandId: nil,
            correlationId: nil,
            timestamp: now,
            epoch: 0,
            event: .filesystem(
                .filesChanged(
                    changeset: FileChangeset(
                        worktreeId: worktreeId,
                        rootPath: URL(fileURLWithPath: "/tmp/worktree-\(UUID().uuidString)"),
                        paths: ["README.md"],
                        timestamp: now,
                        batchSeq: 1
                    )
                )
            )
        )

        #expect(envelope.source == .system(.builtin(.filesystemWatcher)))
        #expect(envelope.sourceFacets.worktreeId == worktreeId)
    }
}

import AppKit
import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("Prepared terminal mount admission")
struct PreparedTerminalMountAdmissionPortTests {
    @Test("retry reuses one generation claim and final success settles it")
    func retryReusesOneClaim() async throws {
        // Arrange
        let generation = try makePreparedTerminalTestGeneration()
        let pane = makePreparedTerminalTestPane()
        let descriptor = makePreparedTerminalTestDescriptor(pane: pane)
        let paneID = descriptor.paneID
        let frame = NSRect(x: 10, y: 20, width: 900, height: 600)
        let surfaceID = UUIDv7.generate()
        let registry = ViewRegistry()
        registry.installPreparedContentMountCohort(
            WorkspacePreparedContentMountCohort(
                generation: generation,
                terminalActivationInput: TerminalActivationInput(entries: [descriptor]),
                nonterminalContentMountInput: NonterminalContentMountInput(entries: [])
            )
        )
        let handler = RecordingPreparedTerminalMountHandler(
            results: [
                .failed(
                    failure: .surfaceCreationFailed(code: "transient"),
                    retry: .retry
                ),
                .ready(surfaceID: surfaceID),
            ]
        )
        let port = PreparedTerminalMountAdmissionPort(
            generation: generation,
            initialFramesByPaneID: [paneID: frame],
            viewRegistry: registry,
            mountHandler: handler
        )

        // Act
        let first = await port.activate(
            TerminalActivationAdmission(generation: generation, descriptor: descriptor, attempt: 1)
        )
        let stateAfterFirst = registry.preparedContentMountState(for: paneID, generation: generation)
        let second = await port.activate(
            TerminalActivationAdmission(generation: generation, descriptor: descriptor, attempt: 2)
        )

        // Assert
        #expect(first == .failed(failure: .surfaceCreationFailed(code: "transient"), retry: .retry))
        #expect(stateAfterFirst == .mounting(owner: .terminal))
        #expect(second == .ready(surfaceID: surfaceID))
        #expect(
            registry.preparedContentMountState(for: paneID, generation: generation)
                == .completed(owner: .terminal, disposition: .mounted)
        )
        #expect(handler.admissions.map(\.attempt) == [1, 2])
        #expect(handler.initialFrames == [frame, frame])
    }

    @Test("stale generation is rejected before terminal mount handling")
    func staleGenerationIsRejectedBeforeMountHandling() async throws {
        // Arrange
        let generation = try makePreparedTerminalTestGeneration()
        let staleGeneration = try makePreparedTerminalTestGeneration()
        let pane = makePreparedTerminalTestPane()
        let descriptor = makePreparedTerminalTestDescriptor(pane: pane)
        let registry = ViewRegistry()
        registry.installPreparedContentMountCohort(
            WorkspacePreparedContentMountCohort(
                generation: generation,
                terminalActivationInput: TerminalActivationInput(entries: [descriptor]),
                nonterminalContentMountInput: NonterminalContentMountInput(entries: [])
            )
        )
        let handler = RecordingPreparedTerminalMountHandler(
            results: [.ready(surfaceID: UUIDv7.generate())]
        )
        let port = PreparedTerminalMountAdmissionPort(
            generation: generation,
            initialFramesByPaneID: [descriptor.paneID: NSRect(x: 0, y: 0, width: 800, height: 600)],
            viewRegistry: registry,
            mountHandler: handler
        )

        // Act
        let result = await port.activate(
            TerminalActivationAdmission(generation: staleGeneration, descriptor: descriptor, attempt: 1)
        )

        // Assert
        #expect(
            result
                == .failed(
                    failure: .attachmentRejected(code: "stale_generation"),
                    retry: .doNotRetry
                )
        )
        #expect(handler.admissions.isEmpty)
        #expect(
            registry.preparedContentMountState(for: descriptor.paneID, generation: generation)
                == .pending(owner: .terminal)
        )
    }

    @Test("nonretryable failure settles custody and duplicate admission cannot remount")
    func nonretryableFailureSettlesAndDuplicateCannotRemount() async throws {
        // Arrange
        let generation = try makePreparedTerminalTestGeneration()
        let descriptor = makePreparedTerminalTestDescriptor(pane: makePreparedTerminalTestPane())
        let registry = ViewRegistry()
        registry.installPreparedContentMountCohort(
            WorkspacePreparedContentMountCohort(
                generation: generation,
                terminalActivationInput: TerminalActivationInput(entries: [descriptor]),
                nonterminalContentMountInput: NonterminalContentMountInput(entries: [])
            )
        )
        let failure = TerminalActivationAttemptResult.failed(
            failure: .surfaceCreationFailed(code: "terminal_failure"),
            retry: .doNotRetry
        )
        let handler = RecordingPreparedTerminalMountHandler(results: [failure])
        let port = PreparedTerminalMountAdmissionPort(
            generation: generation,
            initialFramesByPaneID: [descriptor.paneID: NSRect(x: 0, y: 0, width: 800, height: 600)],
            viewRegistry: registry,
            mountHandler: handler
        )

        // Act
        let first = await port.activate(
            TerminalActivationAdmission(generation: generation, descriptor: descriptor, attempt: 1)
        )
        let duplicate = await port.activate(
            TerminalActivationAdmission(generation: generation, descriptor: descriptor, attempt: 1)
        )

        // Assert
        #expect(first == failure)
        #expect(
            registry.preparedContentMountState(for: descriptor.paneID, generation: generation)
                == .completed(owner: .terminal, disposition: .failed)
        )
        #expect(
            duplicate
                == .failed(
                    failure: .attachmentRejected(code: "claim_rejected"),
                    retry: .doNotRetry
                )
        )
        #expect(handler.admissions.count == 1)
    }

    @Test("activation without installed frame snapshot fails and settles custody")
    func activationWithoutInstalledFrameSnapshotFailsAndSettles() async throws {
        // Arrange
        let generation = try makePreparedTerminalTestGeneration()
        let descriptor = makePreparedTerminalTestDescriptor(pane: makePreparedTerminalTestPane())
        let registry = ViewRegistry()
        registry.installPreparedContentMountCohort(
            WorkspacePreparedContentMountCohort(
                generation: generation,
                terminalActivationInput: TerminalActivationInput(entries: [descriptor]),
                nonterminalContentMountInput: NonterminalContentMountInput(entries: [])
            )
        )
        let handler = RecordingPreparedTerminalMountHandler(results: [])
        let port = PreparedTerminalMountAdmissionPort(
            generation: generation,
            viewRegistry: registry,
            mountHandler: handler
        )

        // Act
        let result = await port.activate(
            TerminalActivationAdmission(generation: generation, descriptor: descriptor, attempt: 1)
        )

        // Assert
        #expect(
            result
                == .failed(
                    failure: .surfaceCreationFailed(code: "trusted_initial_frames_not_installed"),
                    retry: .doNotRetry
                )
        )
        #expect(handler.admissions.isEmpty)
        #expect(
            registry.preparedContentMountState(for: descriptor.paneID, generation: generation)
                == .completed(owner: .terminal, disposition: .failed)
        )
    }
}

@MainActor
private final class RecordingPreparedTerminalMountHandler: PreparedTerminalMountHandling {
    private var results: [TerminalActivationAttemptResult]
    private(set) var admissions: [TerminalActivationAdmission] = []
    private(set) var initialFrames: [NSRect?] = []

    init(results: [TerminalActivationAttemptResult]) {
        self.results = results
    }

    func mountPreparedTerminalContent(
        admission: TerminalActivationAdmission,
        initialFrame: NSRect?
    ) -> TerminalActivationAttemptResult {
        admissions.append(admission)
        initialFrames.append(initialFrame)
        return results.removeFirst()
    }
}

@MainActor
private func makePreparedTerminalTestGeneration() throws -> WorkspaceContentMountGeneration {
    WorkspaceContentMountGeneration()
}

private func makePreparedTerminalTestPane() -> Pane {
    Pane(
        id: UUIDv7.generate(),
        content: .terminal(
            TerminalState(
                provider: .zmx,
                lifetime: .persistent,
                zmxSessionID: .generateUUIDv7()
            )
        ),
        metadata: PaneMetadata(
            launchDirectory: URL(filePath: "/tmp/prepared-terminal-admission"),
            title: "Prepared Terminal"
        )
    )
}

private func makePreparedTerminalTestDescriptor(pane: Pane) -> TerminalActivationDescriptor {
    guard case .terminal = pane.content else {
        preconditionFailure("prepared terminal test requires terminal content")
    }
    return TerminalActivationDescriptor(
        pane: pane,
        visibilityPriority: .activeVisible,
        hostPlacement: .tab(tabID: UUIDv7.generate())
    )
}

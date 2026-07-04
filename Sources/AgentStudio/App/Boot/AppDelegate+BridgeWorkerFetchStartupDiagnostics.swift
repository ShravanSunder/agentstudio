import AppKit
import Foundation

@MainActor
extension AppDelegate {
    #if DEBUG
        func runBridgeWorkerFetchSchemeSmokeDiagnostic(
            action: AgentStudioStartupDiagnosticAction
        ) async {
            recordBridgeWorkerFetchSchemeSmokePhase("activation_started", action: action)
            NSApp.activate(ignoringOtherApps: true)
            mainWindowController?.window?.makeKeyAndOrderFront(nil)
            await waitForStartupDiagnosticAppActivation()

            guard let terminalContainerBounds = await startupDiagnosticLaunchRestoreBounds() else {
                recordBridgeWorkerFetchSchemeSmokeUnavailable(
                    action: action,
                    outcome: "skipped",
                    reason: "missing_bounds"
                )
                return
            }

            if !launchRestoreObservationState.didComplete {
                await finishLaunchRestore(
                    using: terminalContainerBounds,
                    source: "bridgeWorkerFetchSchemeSmokePreflight"
                )
            }

            guard let pane = workspaceSurfaceCoordinator.openBridgeReviewObservabilitySmoke() else {
                recordBridgeWorkerFetchSchemeSmokeUnavailable(
                    action: action,
                    outcome: "blocked",
                    reason: "bridge_pane_creation_failed"
                )
                return
            }
            workspaceSurfaceCoordinator.restoreVisiblePaneIfNeeded(pane.id, forceWhenBoundsExist: true)
            await Task.yield()

            guard
                let bridgeView = viewRegistry.view(for: pane.id)?
                    .mountedContent(as: BridgePaneMountView.self)
            else {
                recordBridgeWorkerFetchSchemeSmokeUnavailable(
                    action: action,
                    outcome: "blocked",
                    reason: "bridge_view_missing"
                )
                return
            }

            let commandId = UUIDv7.generate()
            let commandResult = await bridgeView.controller.handleDiffCommand(
                .loadDiff(
                    DiffArtifact(
                        diffId: BridgeObservabilitySmokeReviewSourceProvider.diffId,
                        worktreeId: BridgeObservabilitySmokeReviewSourceProvider.worktreeId,
                        patchData: Data()
                    )
                ),
                commandId: commandId,
                correlationId: nil
            )
            if case .failure = commandResult {
                recordBridgeWorkerFetchSchemeSmokeUnavailable(
                    action: action,
                    outcome: "blocked",
                    reason: "load_diff_failed"
                )
                return
            }

            guard
                let resourceURL = bridgeWorkerFetchSchemeSmokeContentResourceURL(
                    for: bridgeView.controller
                )
            else {
                recordBridgeWorkerFetchSchemeSmokeUnavailable(
                    action: action,
                    outcome: "blocked",
                    reason: "content_resource_missing"
                )
                return
            }

            let proof = await bridgeWorkerFetchSchemeSmokeProof(
                resourceURL: resourceURL,
                controller: bridgeView.controller
            )
            recordBridgeWorkerFetchSchemeSmokeResult(action: action, proof: proof)
        }

        private func bridgeWorkerFetchSchemeSmokeContentResourceURL(
            for controller: BridgePaneController
        ) -> String? {
            guard let package = controller.paneState.diff.packageMetadata else { return nil }
            for itemId in package.orderedItemIds {
                guard let descriptor = package.itemsById[itemId] else { continue }
                if let handle = descriptor.contentRoles.head ?? descriptor.contentRoles.file
                    ?? descriptor.contentRoles.base ?? descriptor.contentRoles.diff
                {
                    return handle.resourceUrl
                }
            }
            return nil
        }

        private func bridgeWorkerFetchSchemeSmokeProof(
            resourceURL: String,
            controller: BridgePaneController
        ) async -> BridgeWorkerFetchSchemeSmokeProof {
            do {
                let script = try Self.bridgeWorkerFetchSchemeSmokeJavaScript(resourceURL: resourceURL)
                guard
                    let result = try await controller.page.callJavaScript(script) as? String,
                    let data = result.data(using: .utf8)
                else {
                    return .unavailable(reason: "missing_js_result")
                }
                return try JSONDecoder().decode(BridgeWorkerFetchSchemeSmokeProof.self, from: data)
            } catch {
                return .unavailable(reason: "javascript_probe_failed")
            }
        }

        private static func bridgeWorkerFetchSchemeSmokeJavaScript(resourceURL: String) throws -> String {
            let encodedResourceData = try JSONEncoder().encode(resourceURL)
            guard let encodedResourceURL = String(bytes: encodedResourceData, encoding: .utf8) else {
                throw BridgeWorkerFetchSchemeSmokeScriptError.invalidResourceEncoding
            }
            return """
                return await (async function() {
                  const resourceUrl = \(encodedResourceURL);
                  const workerSource = `
                    function holdStreamOpen() {
                      return new Promise(function() {});
                    }
                    self.onmessage = async function(event) {
                      const mode = event.data.mode;
                      const resourceUrl = event.data.resourceUrl;
                      try {
                        const response = await fetch(resourceUrl);
                        if (mode === 'stream') {
                          const reader = response.body.getReader();
                          const firstChunk = await reader.read();
                          self.postMessage({
                            mode,
                            succeeded: response.ok,
                            status: response.status,
                            streamFirstChunkByteCount: firstChunk.value ? firstChunk.value.byteLength : 0,
                            streamHeldOpen: !firstChunk.done
                          });
                          await holdStreamOpen();
                          return;
                        }
                        const body = await response.arrayBuffer();
                        self.postMessage({
                          mode,
                          succeeded: response.ok,
                          status: response.status,
                          workerObservedByteCount: body.byteLength,
                          contentUrlScheme: new URL(resourceUrl).protocol.replace(':', ''),
                          contentResourceKind: 'content'
                        });
                      } catch (error) {
                        self.postMessage({
                          mode,
                          succeeded: false,
                          status: 0,
                          workerObservedByteCount: 0,
                          streamFirstChunkByteCount: 0,
                          streamHeldOpen: false,
                          contentUrlScheme: 'agentstudio',
                          contentResourceKind: 'content'
                        });
                      }
                    };
                  `;
                  const workerUrl = URL.createObjectURL(
                    new Blob([workerSource], { type: 'text/javascript' })
                  );
                  function runProbe(mode) {
                    return new Promise(function(resolve) {
                      const worker = new Worker(workerUrl);
                      worker.onmessage = function(event) {
                        worker.terminate();
                        resolve(event.data);
                      };
                      worker.postMessage({ mode, resourceUrl });
                    });
                  }
                  const fetchResult = await runProbe('fetch');
                  const streamResult = await runProbe('stream');
                  URL.revokeObjectURL(workerUrl);
                  return JSON.stringify({
                    markerCount: 1,
                    contentUrlScheme: fetchResult.contentUrlScheme || 'agentstudio',
                    contentResourceKind: fetchResult.contentResourceKind || 'content',
                    fetchSucceeded: fetchResult.succeeded === true,
                    streamSucceeded: streamResult.succeeded === true,
                    workerObservedByteCount: fetchResult.workerObservedByteCount || 0,
                    streamFirstChunkByteCount: streamResult.streamFirstChunkByteCount || 0,
                    streamHeldOpen: streamResult.streamHeldOpen === true
                  });
                })();
                """
        }

        private func recordBridgeWorkerFetchSchemeSmokePhase(
            _ phase: String,
            action: AgentStudioStartupDiagnosticAction
        ) {
            startupTraceRecorder.recordAppStartup(
                "app.startup_diagnostic_action.bridge_worker_fetch.\(phase)",
                phase: "startup_diagnostic_action",
                attributes: startupDiagnosticTraceAttributes(for: action)
            )
        }

        private func recordBridgeWorkerFetchSchemeSmokeUnavailable(
            action: AgentStudioStartupDiagnosticAction,
            outcome: String,
            reason: String
        ) {
            let proof = BridgeWorkerFetchSchemeSmokeProof.unavailable(reason: reason)
            startupTraceRecorder.recordAppStartup(
                "app.startup_diagnostic_action.\(outcome)",
                phase: "startup_diagnostic_action",
                outcome: outcome,
                attributes: startupDiagnosticTraceAttributes(for: action).merging(
                    proof.attributes
                ) { _, newValue in newValue }
            )
        }

        private func recordBridgeWorkerFetchSchemeSmokeResult(
            action: AgentStudioStartupDiagnosticAction,
            proof: BridgeWorkerFetchSchemeSmokeProof
        ) {
            let outcome = proof.succeeded ? "succeeded" : "blocked"
            startupTraceRecorder.recordAppStartup(
                "app.startup_diagnostic_action.command_exercised",
                phase: "startup_diagnostic_action",
                outcome: outcome,
                attributes: startupDiagnosticTraceAttributes(for: action).merging(
                    proof.attributes
                ) { _, newValue in newValue }
            )
            startupTraceRecorder.recordAppStartup(
                proof.succeeded
                    ? "app.startup_diagnostic_action.completed"
                    : "app.startup_diagnostic_action.blocked",
                phase: "startup_diagnostic_action",
                outcome: outcome,
                attributes: startupDiagnosticTraceAttributes(for: action).merging(
                    proof.attributes
                ) { _, newValue in newValue }
            )
        }
    #endif
}

#if DEBUG
    private enum BridgeWorkerFetchSchemeSmokeScriptError: Error {
        case invalidResourceEncoding
    }

    private struct BridgeWorkerFetchSchemeSmokeProof: Decodable {
        let markerCount: Int
        let contentUrlScheme: String
        let contentResourceKind: String
        let fetchSucceeded: Bool
        let streamSucceeded: Bool
        let workerObservedByteCount: Int
        let streamFirstChunkByteCount: Int
        let streamHeldOpen: Bool
        let failureReason: String?

        var succeeded: Bool {
            fetchSucceeded
                && streamSucceeded
                && workerObservedByteCount > 0
                && streamFirstChunkByteCount > 0
                && streamHeldOpen
        }

        var attributes: [String: AgentStudioTraceValue] {
            [
                "agentstudio.startup_diagnostic.bridge.worker_fetch.marker.count": .int(markerCount),
                "agentstudio.startup_diagnostic.bridge.worker_fetch.content_url.scheme": .string(contentUrlScheme),
                "agentstudio.startup_diagnostic.bridge.worker_fetch.content_resource.kind": .string(
                    contentResourceKind),
                "agentstudio.startup_diagnostic.bridge.worker_fetch.fetch.succeeded": .bool(fetchSucceeded),
                "agentstudio.startup_diagnostic.bridge.worker_fetch.stream.succeeded": .bool(streamSucceeded),
                "agentstudio.startup_diagnostic.bridge.worker_fetch.worker_observed_byte.count": .int(
                    workerObservedByteCount),
                "agentstudio.startup_diagnostic.bridge.worker_fetch.stream_first_chunk_byte.count": .int(
                    streamFirstChunkByteCount),
                "agentstudio.startup_diagnostic.bridge.worker_fetch.stream_held_open": .bool(streamHeldOpen),
                "agentstudio.startup_diagnostic.bridge.worker_fetch.failure.reason": .string(failureReason ?? "none"),
                "agentstudio.startup_diagnostic.render_proof.succeeded": .bool(succeeded),
            ]
        }

        static func unavailable(reason: String) -> Self {
            Self(
                markerCount: 1,
                contentUrlScheme: "agentstudio",
                contentResourceKind: "content",
                fetchSucceeded: false,
                streamSucceeded: false,
                workerObservedByteCount: 0,
                streamFirstChunkByteCount: 0,
                streamHeldOpen: false,
                failureReason: reason
            )
        }
    }
#endif

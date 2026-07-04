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
            let encodedWorkerScriptData = try JSONEncoder().encode(bridgeWorkerFetchSchemeSmokeWorkerScriptURL)
            guard let encodedWorkerScriptURL = String(bytes: encodedWorkerScriptData, encoding: .utf8) else {
                throw BridgeWorkerFetchSchemeSmokeScriptError.invalidWorkerScriptEncoding
            }
            return
                bridgeWorkerFetchSchemeSmokeJavaScriptTemplate
                .replacingOccurrences(of: "__RESOURCE_URL__", with: encodedResourceURL)
                .replacingOccurrences(of: "__WORKER_SCRIPT_URL__", with: encodedWorkerScriptURL)
        }

        private static let bridgeWorkerFetchSchemeSmokeJavaScriptTemplate = """
            return await (async function() {
              const resourceUrl = __RESOURCE_URL__;
              const workerScriptUrl = __WORKER_SCRIPT_URL__;
              function failedProbe(mode, reason) {
                return {
                  mode,
                  succeeded: false,
                  status: 0,
                  workerObservedByteCount: 0,
                  streamFirstChunkByteCount: 0,
                  streamHeldOpen: false,
                  contentUrlScheme: 'agentstudio',
                  contentResourceKind: 'content',
                  failureReason: reason
                };
              }
              function normalizedProbe(mode, data) {
                if (!data || typeof data !== 'object') {
                  return failedProbe(mode, 'worker_invalid_response');
                }
                return {
                  mode,
                  succeeded: data.succeeded === true,
                  status: Number.isFinite(data.status) ? data.status : 0,
                  workerObservedByteCount: data.workerObservedByteCount || 0,
                  streamFirstChunkByteCount: data.streamFirstChunkByteCount || 0,
                  streamHeldOpen: data.streamHeldOpen === true,
                  contentUrlScheme: data.contentUrlScheme || 'agentstudio',
                  contentResourceKind: data.contentResourceKind || 'content',
                  failureReason: data.failureReason || 'none'
                };
              }
              function runProbe(mode) {
                return new Promise(function(resolve) {
                  let worker = null;
                  let settled = false;
                  function finish(data) {
                    if (settled) {
                      return;
                    }
                    settled = true;
                    if (worker !== null) {
                      worker.terminate();
                    }
                    resolve(normalizedProbe(mode, data));
                  }
                  try {
                    worker = new Worker(workerScriptUrl, { type: 'module' });
                  } catch (error) {
                    resolve(failedProbe(mode, 'worker_constructor_failed'));
                    return;
                  }
                  worker.onmessage = function(event) {
                    finish(event.data);
                  };
                  worker.onerror = function() {
                    finish(failedProbe(mode, 'worker_error'));
                  };
                  try {
                    worker.postMessage({ mode, resourceUrl });
                  } catch (error) {
                    finish(failedProbe(mode, 'worker_post_failed'));
                  }
                });
              }
              try {
                const fetchResult = await runProbe('fetch');
                const streamResult = await runProbe('stream');
                return JSON.stringify({
                  markerCount: 1,
                  contentUrlScheme: fetchResult.contentUrlScheme || 'agentstudio',
                  contentResourceKind: fetchResult.contentResourceKind || 'content',
                  fetchSucceeded: fetchResult.succeeded === true,
                  streamSucceeded: streamResult.succeeded === true,
                  workerObservedByteCount: fetchResult.workerObservedByteCount || 0,
                  streamFirstChunkByteCount: streamResult.streamFirstChunkByteCount || 0,
                  streamHeldOpen: streamResult.streamHeldOpen === true,
                  failureReason: fetchResult.failureReason !== 'none'
                    ? fetchResult.failureReason
                    : streamResult.failureReason
                });
              } catch (error) {
                return JSON.stringify({
                  markerCount: 1,
                  contentUrlScheme: 'agentstudio',
                  contentResourceKind: 'content',
                  fetchSucceeded: false,
                  streamSucceeded: false,
                  workerObservedByteCount: 0,
                  streamFirstChunkByteCount: 0,
                  streamHeldOpen: false,
                  failureReason: 'page_probe_exception'
                });
              }
            })();
            """

        private static let bridgeWorkerFetchSchemeSmokeWorkerScriptURL =
            "agentstudio://app/assets/bridge-worker-fetch-probe-worker.js"

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
            if proof.succeeded {
                startupTraceRecorder.recordAppStartup(
                    "app.startup_diagnostic_action.command_exercised",
                    phase: "startup_diagnostic_action",
                    outcome: outcome,
                    attributes: startupDiagnosticTraceAttributes(for: action).merging(
                        proof.attributes
                    ) { _, newValue in newValue }
                )
            }
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
        case invalidWorkerScriptEncoding
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

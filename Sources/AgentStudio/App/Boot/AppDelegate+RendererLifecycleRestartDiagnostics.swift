import AgentStudioCore
import AgentStudioInfrastructure
import AppKit
import Foundation

#if DEBUG
    @MainActor
    func scheduleRendererLifecycleDiagnosticTermination(
        _ terminate: @escaping @MainActor () -> Void
    ) {
        RunLoop.main.perform(inModes: [.default]) {
            MainActor.assumeIsolated {
                terminate()
            }
        }
    }

    private struct RendererLifecycleRestartManifest: Codable {
        struct Entry: Codable {
            let paneID: UUID
            let sessionID: String
            let priorSurfaceID: UUID
        }

        let entries: [Entry]
    }

    @MainActor
    extension AppDelegate {
        func completeInitialRendererLifecycleDiagnostic(
            action: AgentStudioStartupDiagnosticAction,
            _ fixture: RendererLifecycleContinuityFixture,
            initialSurfaceIDs: [UUID: UUID],
            initialSessionIDs: [UUID: ZmxSessionID]
        ) async {
            let transitionResult = await exerciseRendererLifecycleTransitions(
                fixture,
                initialSurfaceIDs: initialSurfaceIDs,
                initialSessionIDs: initialSessionIDs
            )
            guard transitionResult.succeeded else {
                recordRendererLifecycleDiagnosticResult(
                    action: action,
                    succeeded: false,
                    reason: transitionResult.reason,
                    paneCount: fixture.paneIDs.count
                )
                return
            }
            guard Set(initialSessionIDs.values).count == fixture.paneIDs.count else {
                recordRendererLifecycleDiagnosticResult(
                    action: action,
                    succeeded: false,
                    reason: "session_identity_not_unique",
                    paneCount: fixture.paneIDs.count
                )
                return
            }
            let finalSurfaceIDs = rendererLifecycleSurfaceIDs(for: fixture.paneIDs)
            let finalSessionIDs = rendererLifecycleSessionIDs(for: fixture.paneIDs)
            guard (await store.flushAsync()).succeeded else {
                recordRendererLifecycleDiagnosticResult(
                    action: action,
                    succeeded: false,
                    reason: "workspace_flush_failed",
                    paneCount: fixture.paneIDs.count
                )
                return
            }
            guard
                writeRendererLifecycleRestartManifest(
                    paneIDs: fixture.paneIDs,
                    surfaceIDs: finalSurfaceIDs,
                    sessionIDs: finalSessionIDs
                )
            else {
                recordRendererLifecycleDiagnosticResult(
                    action: action,
                    succeeded: false,
                    reason: "restart_manifest_failed",
                    paneCount: fixture.paneIDs.count
                )
                return
            }
            recordRendererLifecycleDiagnosticResult(
                action: action, succeeded: true, reason: "none", paneCount: fixture.paneIDs.count)
            scheduleRendererLifecycleDiagnosticTermination {
                NSApp.terminate(nil)
            }
        }

        func runRendererLifecycleRestartDiagnostic(
            action: AgentStudioStartupDiagnosticAction
        ) async {
            guard let manifest = readRendererLifecycleRestartManifest(), manifest.entries.count == 20 else {
                recordRendererLifecycleDiagnosticResult(
                    action: action, succeeded: false, reason: "restart_manifest_missing")
                return
            }
            let paneIDs = manifest.entries.map(\.paneID)
            guard
                await waitForRendererLifecycleCondition(
                    timeout: .seconds(20),
                    {
                        paneIDs.allSatisfy { paneID in
                            self.store.paneAtom.pane(paneID) != nil
                                && self.viewRegistry.terminalView(for: paneID)?.ghosttySurface != nil
                                && self.workspaceSurfaceCoordinator.runtimeForPane(PaneId(existingUUID: paneID))?
                                    .lifecycle == .ready
                        }
                    })
            else {
                recordRendererLifecycleDiagnosticResult(
                    action: action, succeeded: false, reason: "restart_restore_not_ready")
                return
            }

            let restoredSessionIDs = rendererLifecycleSessionIDs(for: paneIDs)
            let restoredSurfaceIDs = rendererLifecycleSurfaceIDs(for: paneIDs)
            let expectedSessionIDs = Dictionary(
                uniqueKeysWithValues: manifest.entries.map { ($0.paneID, $0.sessionID) }
            )
            guard restoredSessionIDs.count == 20, restoredSurfaceIDs.count == 20 else {
                recordRendererLifecycleDiagnosticResult(
                    action: action, succeeded: false, reason: "restart_identity_missing")
                return
            }
            guard Set(restoredSessionIDs.values).count == 20 else {
                recordRendererLifecycleDiagnosticResult(
                    action: action, succeeded: false, reason: "restart_session_identity_not_unique")
                return
            }
            guard restoredSessionIDs.allSatisfy({ expectedSessionIDs[$0.key] == $0.value.rawValue }) else {
                recordRendererLifecycleDiagnosticResult(
                    action: action, succeeded: false, reason: "restart_session_identity_changed")
                return
            }
            guard manifest.entries.allSatisfy({ restoredSurfaceIDs[$0.paneID] != $0.priorSurfaceID }) else {
                recordRendererLifecycleDiagnosticResult(
                    action: action, succeeded: false, reason: "restart_surface_identity_reused")
                return
            }

            let snapshot = performanceTraceRecorder.rendererLifecycleSnapshot()
            guard snapshot.successfulCreatedTotal == 20,
                snapshot.permanentReleaseTotal == 0,
                snapshot.deinitializedFreeTotal == 0,
                snapshot.liveCurrent == 20,
                snapshot.managerOwnedCurrent == 20,
                snapshot.closeUndoCurrent == 0,
                snapshot.orphanCandidateCurrent == 0,
                snapshot.isValid
            else {
                recordRendererLifecycleDiagnosticResult(
                    action: action, succeeded: false, reason: "restart_lifecycle_not_fresh")
                return
            }
            recordRendererLifecycleDiagnosticResult(
                action: action, succeeded: true, reason: "none", paneCount: 20)
            scheduleRendererLifecycleDiagnosticTermination {
                NSApp.terminate(nil)
            }
        }

        func writeRendererLifecycleRestartManifest(
            paneIDs: [UUID],
            surfaceIDs: [UUID: UUID],
            sessionIDs: [UUID: ZmxSessionID]
        ) -> Bool {
            guard let manifestURL = rendererLifecycleRestartManifestURL() else { return false }
            let entries = paneIDs.compactMap { paneID -> RendererLifecycleRestartManifest.Entry? in
                guard let surfaceID = surfaceIDs[paneID], let sessionID = sessionIDs[paneID] else { return nil }
                return .init(
                    paneID: paneID,
                    sessionID: sessionID.rawValue,
                    priorSurfaceID: surfaceID
                )
            }
            guard entries.count == paneIDs.count else { return false }
            do {
                try JSONEncoder().encode(RendererLifecycleRestartManifest(entries: entries)).write(
                    to: manifestURL,
                    options: .atomic
                )
                return true
            } catch {
                return false
            }
        }

        private func readRendererLifecycleRestartManifest() -> RendererLifecycleRestartManifest? {
            guard let manifestURL = rendererLifecycleRestartManifestURL(),
                let data = try? Data(contentsOf: manifestURL)
            else { return nil }
            return try? JSONDecoder().decode(RendererLifecycleRestartManifest.self, from: data)
        }

        private func rendererLifecycleRestartManifestURL() -> URL? {
            Self.validatedRendererLifecycleRestartManifestURL(
                rawPath: ProcessInfo.processInfo.environment[
                    "AGENTSTUDIO_RENDERER_LIFECYCLE_RESTART_MANIFEST"
                ]
            )
        }

        static func validatedRendererLifecycleRestartManifestURL(rawPath: String?) -> URL? {
            guard let rawPath, !rawPath.isEmpty else { return nil }
            let standardizedURL = URL(fileURLWithPath: rawPath).standardizedFileURL
            let canonicalTmpURL =
                if standardizedURL.path.hasPrefix("/tmp/") {
                    URL(fileURLWithPath: "/private\(standardizedURL.path)")
                } else {
                    standardizedURL
                }
            let resolvedURL =
                canonicalTmpURL
                .resolvingSymlinksInPath()
                .standardizedFileURL
            let containmentURL =
                if resolvedURL.path.hasPrefix("/tmp/") {
                    URL(fileURLWithPath: "/private\(resolvedURL.path)")
                } else {
                    resolvedURL
                }
            guard containmentURL.lastPathComponent == "restart-manifest.json" else { return nil }

            let proofRootPath = containmentURL.deletingLastPathComponent().path
            let dedicatedProofRootPrefix = "/private/tmp/agentstudio-renderer-lifecycle."
            guard proofRootPath.hasPrefix(dedicatedProofRootPrefix) else { return nil }
            let proofRootSuffix = proofRootPath.dropFirst(dedicatedProofRootPrefix.count)
            guard !proofRootSuffix.isEmpty, !proofRootSuffix.contains("/") else { return nil }
            return containmentURL
        }
    }
#endif

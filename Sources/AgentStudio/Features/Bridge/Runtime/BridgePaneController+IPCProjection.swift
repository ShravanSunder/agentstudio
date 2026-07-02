import AgentStudioProgrammaticControl
import Foundation

private struct BridgePageRenderSnapshot: Decodable {
    let pageTitle: String?
    let hasAppRoot: Bool
    let hasEmptyShell: Bool
    let hasReviewShell: Bool
    let sidebarPosition: String?
    let hasFileShell: Bool?
    let hasFileTree: Bool?
    let hasFileCodeView: Bool?
    let bridgeProtocol: String?
    let worktreeSourceSpecState: String?
    let worktreeSourceState: String?
    let worktreeOpenFileState: String?
    let worktreeOpenFilePath: String?
    let worktreeRenderedFilePath: String?
    let worktreeSelectedDisplayPath: String?
    let worktreeDescriptorCount: Int?
    let worktreeTotalDescriptorCount: Int?
    let worktreeIntakeFrameCount: Int?
    let worktreeCommandCount: Int?
    let worktreeOpenSourceCommandCount: Int?
    let worktreeCodeTextLength: Int?
    let pageErrorCount: Int
    let pageErrorKinds: [String]
    let pageErrorMessages: [String]
}

private struct BridgePageControlProbeSnapshot: Decodable {
    let sequence: Int
    let method: String
    let status: String
    let itemId: String?
    let path: String?
    let treeSearchText: String
    let gitStatusFilter: String
    let fileClassFilter: String
    let renderMode: BridgePageControlRenderModeSnapshot
    let reason: String?
}

private struct BridgePageControlRenderModeSnapshot: Decodable {
    let kind: String
}

@MainActor
extension BridgePaneController {
    func ipcReviewPackageSnapshot() throws -> IPCBridgeReviewPackageResult {
        let package = paneState.diff.packageMetadata
        let result = IPCBridgeReviewPackageResult(
            paneId: paneId,
            status: paneState.diff.status.rawValue,
            error: paneState.diff.error,
            selectedItemId: selectedReviewItemId,
            packageId: package?.packageId,
            reviewGeneration: package?.reviewGeneration.rawValue,
            revision: package?.revision,
            summary: package.map(ipcPackageSummary)
        )
        try BridgeIPCResponseBudget.validate(result)
        return result
    }

    func refreshReviewForIPC(correlationId: UUID?) async throws -> IPCBridgeReviewRefreshResult {
        guard let worktreeId = runtime.metadata.worktreeId else {
            throw BridgeIPCProjectionError(reason: .packageUnavailable)
        }

        let commandId = UUID()
        let result = await handleDiffCommand(
            .loadDiff(
                DiffArtifact(
                    diffId: UUIDv7.generate(),
                    worktreeId: worktreeId,
                    patchData: Data()
                )
            ),
            commandId: commandId,
            correlationId: correlationId
        )

        switch result {
        case .success, .queued:
            return IPCBridgeReviewRefreshResult(
                paneId: paneId,
                refreshed: paneState.diff.status == .ready,
                status: paneState.diff.status.rawValue,
                packageId: paneState.diff.packageMetadata?.packageId,
                reviewGeneration: paneState.diff.packageMetadata?.reviewGeneration.rawValue,
                correlationId: correlationId
            )
        case .failure:
            throw BridgeIPCProjectionError(reason: .packageUnavailable)
        }
    }

    func renderStateForIPC() async throws -> IPCBridgeRenderStateResult {
        do {
            let result = try await page.callJavaScript(Self.renderStateJavaScript)
            guard let json = result as? String, let data = json.data(using: .utf8) else {
                return makeRenderStateFailureResult(
                    reason: "render_state_result_not_string",
                    detail: String(describing: result)
                )
            }
            let snapshot = try JSONDecoder().decode(BridgePageRenderSnapshot.self, from: data)
            return IPCBridgeRenderStateResult(
                paneId: paneId,
                summary: IPCBridgeRenderSummary(
                    pageTitle: snapshot.pageTitle,
                    hasAppRoot: snapshot.hasAppRoot,
                    hasEmptyShell: snapshot.hasEmptyShell,
                    hasReviewShell: snapshot.hasReviewShell,
                    sidebarPosition: snapshot.sidebarPosition,
                    hasFileShell: snapshot.hasFileShell,
                    hasFileTree: snapshot.hasFileTree,
                    hasFileCodeView: snapshot.hasFileCodeView,
                    bridgeProtocol: snapshot.bridgeProtocol,
                    worktreeSourceSpecState: snapshot.worktreeSourceSpecState,
                    worktreeSourceState: snapshot.worktreeSourceState,
                    worktreeOpenFileState: snapshot.worktreeOpenFileState,
                    worktreeOpenFilePath: snapshot.worktreeOpenFilePath,
                    worktreeRenderedFilePath: snapshot.worktreeRenderedFilePath,
                    worktreeSelectedDisplayPath: snapshot.worktreeSelectedDisplayPath,
                    worktreeDescriptorCount: snapshot.worktreeDescriptorCount,
                    worktreeTotalDescriptorCount: snapshot.worktreeTotalDescriptorCount,
                    worktreeIntakeFrameCount: snapshot.worktreeIntakeFrameCount,
                    worktreeCommandCount: snapshot.worktreeCommandCount,
                    worktreeOpenSourceCommandCount: snapshot.worktreeOpenSourceCommandCount,
                    worktreeCodeTextLength: snapshot.worktreeCodeTextLength
                ),
                diagnostics: IPCBridgeRenderDiagnostics(
                    evaluateSucceeded: true,
                    pageErrorCount: snapshot.pageErrorCount,
                    pageErrorKinds: snapshot.pageErrorKinds,
                    pageErrorMessages: snapshot.pageErrorMessages
                )
            )
        } catch {
            return makeRenderStateFailureResult(reason: "render_state_evaluation_failed", detail: "\(error)")
        }
    }

    func selectReviewItemForIPC(
        itemId: String,
        correlationId: UUID?
    ) async throws -> IPCBridgeReviewSelectFileResult {
        guard let package = paneState.diff.packageMetadata else {
            throw BridgeIPCProjectionError(reason: .packageUnavailable)
        }
        guard package.itemsById[itemId] != nil else {
            throw BridgeIPCProjectionError(reason: .itemNotFound)
        }

        try await dispatchReviewItemSelectionToPage(itemId: itemId)
        selectedReviewItemId = itemId
        return IPCBridgeReviewSelectFileResult(
            paneId: paneId,
            itemId: itemId,
            selected: true,
            correlationId: correlationId
        )
    }

    private func dispatchReviewItemSelectionToPage(itemId: String) async throws {
        let itemIdLiteral = try javaScriptStringLiteral(itemId)
        try await page.callJavaScript(
            """
            window.dispatchEvent(new CustomEvent('__bridge_select_review_item', {
              detail: { itemId: \(itemIdLiteral) }
            }));
            """,
            contentWorld: .page
        )
    }

    func applyPageControlForIPC(
        _ command: IPCBridgePageControlCommand,
        correlationId: UUID?
    ) async throws -> IPCBridgePageControlResult {
        let commandLiteral = try javaScriptLiteral(command)
        let methodLiteral = try javaScriptStringLiteral(command.method)
        let result = try await page.callJavaScript(
            """
            return JSON.stringify((() => {
              window.__bridgeReviewControlProbe = undefined;
              window.dispatchEvent(new CustomEvent('__bridge_review_control', {
                detail: \(commandLiteral)
              }));
              const nextProbe = window.__bridgeReviewControlProbe || null;
              return nextProbe || {
                sequence: -1,
                method: \(methodLiteral),
                status: 'rejected',
                itemId: null,
                path: null,
                treeSearchText: '',
                gitStatusFilter: 'all',
                fileClassFilter: 'all',
                renderMode: { kind: 'codeView' },
                reason: 'missing_control_probe'
              };
            })())
            """,
            contentWorld: .page
        )
        guard let json = result as? String, let data = json.data(using: .utf8) else {
            throw BridgeIPCProjectionError(reason: .validationRejected)
        }
        let snapshot = try JSONDecoder().decode(BridgePageControlProbeSnapshot.self, from: data)
        guard snapshot.method == command.method, snapshot.sequence >= 0 else {
            throw BridgeIPCProjectionError(reason: .validationRejected)
        }
        return IPCBridgePageControlResult(
            paneId: paneId,
            method: snapshot.method,
            status: snapshot.status,
            itemId: snapshot.itemId,
            path: snapshot.path,
            treeSearchText: snapshot.treeSearchText,
            gitStatusFilter: snapshot.gitStatusFilter,
            fileClassFilter: snapshot.fileClassFilter,
            renderMode: snapshot.renderMode.kind,
            reason: snapshot.reason,
            correlationId: correlationId
        )
    }

    func loadContentForIPC(
        contentHandleId: String,
        reviewGeneration: Int
    ) async throws -> IPCBridgeContentGetResult {
        guard
            !resourceLeaseRegistry.isRevokedSynchronously(
                paneId: paneId,
                protocolId: "review",
                resourceKind: "content"
            )
        else {
            throw BridgeIPCProjectionError(reason: .contentUnavailable)
        }
        let handle: BridgeContentHandle
        do {
            handle = try await reviewContentStore.metadata(
                handleId: contentHandleId,
                requestedGeneration: BridgeReviewGeneration(reviewGeneration)
            )
        } catch {
            throw BridgeIPCProjectionError(reason: .contentUnavailable)
        }
        guard
            !resourceLeaseRegistry.isRevokedSynchronously(
                paneId: paneId,
                protocolId: "review",
                resourceKind: "content"
            )
        else {
            throw BridgeIPCProjectionError(reason: .contentUnavailable)
        }

        let ipcResult = IPCBridgeContentGetResult(
            paneId: paneId,
            handle: ipcContentHandle(handle),
            mimeType: handle.mimeType
        )
        try BridgeIPCResponseBudget.validate(ipcResult)
        return ipcResult
    }

    func flushTelemetryForIPC() async throws -> IPCBridgeTelemetryFlushResult {
        try await telemetryRecorder?.drain()
        return IPCBridgeTelemetryFlushResult(paneId: paneId, flushed: telemetryRecorder != nil)
    }

    func telemetrySnapshotForIPC() -> IPCBridgeTelemetrySnapshotResult {
        let recorder = telemetryRecorder as? BridgePerformanceTraceRecorder
        return IPCBridgeTelemetrySnapshotResult(
            paneId: paneId,
            recorderAttached: telemetryRecorder != nil,
            traceExportEnabled: recorder?.isEnabled ?? false,
            status: paneState.diff.status.rawValue,
            packageId: paneState.diff.packageMetadata?.packageId,
            reviewGeneration: paneState.diff.packageMetadata?.reviewGeneration.rawValue,
            selectedItemId: selectedReviewItemId
        )
    }

    private nonisolated static var renderStateJavaScript: String {
        """
        return JSON.stringify((() => {
          const errorProbe = Array.isArray(window.__bridgeErrorProbe)
            ? window.__bridgeErrorProbe
            : [];
          const clip = (value, limit) => String(value ?? '').slice(0, limit);
          const reviewShell = document.querySelector('[data-testid="review-viewer-shell"]');
          const fileShell = document.querySelector('[data-testid="bridge-file-viewer-shell"]');
          const fileTree = document.querySelector('[data-testid="bridge-file-viewer-pierre-file-tree"]');
          const fileCodeCanvas = document.querySelector('[data-testid="bridge-file-viewer-code-canvas"]');
          const fileCodeView = document.querySelector('[data-testid="bridge-file-viewer-code-view"]');
          const filterCountText =
            document.querySelector('[data-testid="worktree-file-filter-count"]')?.textContent || '0/0';
          const worktreeDescriptorCount = Number(filterCountText.split('/')[0] || '0');
          const worktreeTotalDescriptorCount = Number(filterCountText.split('/')[1] || '0');
          const intakeProbe = Array.isArray(window.__bridgeIntakeProbe)
            ? window.__bridgeIntakeProbe
            : [];
          const commandProbe = Array.isArray(window.__bridgeCommandProbe)
            ? window.__bridgeCommandProbe
            : [];
          const rawWorktreeSourceSpec =
            document.documentElement.getAttribute('data-bridge-worktree-file-source-spec');
          let worktreeSourceSpecState = 'missing';
          if (rawWorktreeSourceSpec !== null) {
            try {
              const parsedSourceSpec = JSON.parse(rawWorktreeSourceSpec);
              worktreeSourceSpecState =
                parsedSourceSpec &&
                typeof parsedSourceSpec === 'object' &&
                typeof parsedSourceSpec.clientRequestId === 'string' &&
                typeof parsedSourceSpec.repoId === 'string' &&
                typeof parsedSourceSpec.worktreeId === 'string' &&
                typeof parsedSourceSpec.rootPathToken === 'string' &&
                parsedSourceSpec.freshness === 'live'
                  ? 'parseable'
                  : 'invalid_shape';
            } catch {
              worktreeSourceSpecState = 'malformed_json';
            }
          }
          const diffContainers = [...document.querySelectorAll('diffs-container')];
          const codeViewShadowText = diffContainers
            .map((element) => element.shadowRoot?.textContent || '')
            .join(' ');
          const fileCodeText = `${fileCodeCanvas?.textContent || ''} ${codeViewShadowText}`;
          const pageErrorKinds = Array.from(new Set(errorProbe.slice(-8).map((entry) => {
            return clip(entry.kind, 80);
          }).filter((kind) => kind.length > 0)));
          const pageErrorMessages = errorProbe.slice(-4).map((entry) => {
            const kind = clip(entry.kind, 80);
            const message = clip(entry.message, 300);
            const stack = clip(entry.stack, 500);
            return [kind, message, stack].filter((part) => part.length > 0).join(': ');
          }).filter((message) => message.length > 0);
          return {
            pageTitle: document.title || null,
            hasAppRoot: document.querySelector('[data-testid="bridge-app-root"]') !== null,
            hasEmptyShell: document.querySelector('[data-testid="bridge-review-empty-shell"]') !== null,
            hasReviewShell: reviewShell !== null,
            sidebarPosition: reviewShell?.getAttribute('data-sidebar-position') || null,
            hasFileShell: fileShell !== null,
            hasFileTree: fileTree !== null,
            hasFileCodeView: fileCodeView !== null,
            bridgeProtocol: document.documentElement.getAttribute('data-bridge-app-protocol') || null,
            worktreeSourceSpecState,
            worktreeSourceState: fileShell?.getAttribute('data-worktree-source-state') || null,
            worktreeOpenFileState: fileCodeCanvas?.getAttribute('data-worktree-open-file-state') || null,
            worktreeOpenFilePath: fileCodeCanvas?.getAttribute('data-worktree-open-file-path') || null,
            worktreeRenderedFilePath: fileCodeCanvas?.getAttribute('data-worktree-rendered-file-path') || null,
            worktreeSelectedDisplayPath: fileShell?.getAttribute('data-selected-display-path') || null,
            worktreeDescriptorCount,
            worktreeTotalDescriptorCount,
            worktreeIntakeFrameCount: intakeProbe.length,
            worktreeCommandCount: commandProbe.length,
            worktreeOpenSourceCommandCount: commandProbe.filter((entry) => {
              return entry?.method === 'worktreeFileSurface.openSourceStream';
            }).length,
            worktreeCodeTextLength: fileCodeText.length,
            pageErrorCount: errorProbe.length,
            pageErrorKinds,
            pageErrorMessages
          };
        })())
        """
    }

    private func makeRenderStateFailureResult(
        reason: String,
        detail: String
    ) -> IPCBridgeRenderStateResult {
        IPCBridgeRenderStateResult(
            paneId: paneId,
            summary: IPCBridgeRenderSummary(
                pageTitle: page.title,
                hasAppRoot: false,
                hasEmptyShell: false,
                hasReviewShell: false,
                sidebarPosition: nil
            ),
            diagnostics: IPCBridgeRenderDiagnostics(
                evaluateSucceeded: false,
                pageErrorCount: 1,
                pageErrorKinds: [reason],
                pageErrorMessages: [detail]
            )
        )
    }

    private func ipcPackageSummary(_ package: BridgeReviewPackage) -> IPCBridgeReviewPackageSummary {
        IPCBridgeReviewPackageSummary(
            filesChanged: package.summary.filesChanged,
            additions: package.summary.additions,
            deletions: package.summary.deletions,
            visibleFileCount: package.summary.visibleFileCount,
            hiddenFileCount: package.summary.hiddenFileCount
        )
    }

    private func ipcContentHandle(_ handle: BridgeContentHandle) -> IPCBridgeContentHandleSummary {
        IPCBridgeContentHandleSummary(
            identity: IPCBridgeContentHandleIdentity(
                handleId: handle.handleId,
                itemId: handle.itemId,
                role: handle.role.rawValue,
                reviewGeneration: handle.reviewGeneration.rawValue
            ),
            presentation: IPCBridgeContentHandlePresentation(
                resourceUrl: handle.resourceUrl,
                mimeType: handle.mimeType,
                language: handle.language
            ),
            size: IPCBridgeContentHandleSize(
                sizeBytes: handle.sizeBytes,
                isBinary: handle.isBinary
            )
        )
    }

    private nonisolated func javaScriptStringLiteral(_ value: String) throws -> String {
        let data = try JSONEncoder().encode(value)
        guard let literal = String(data: data, encoding: .utf8) else {
            throw BridgeIPCProjectionError(reason: .validationRejected)
        }
        return literal
    }

    private nonisolated func javaScriptLiteral<T: Encodable>(_ value: T) throws -> String {
        let data = try JSONEncoder().encode(value)
        guard let literal = String(data: data, encoding: .utf8) else {
            throw BridgeIPCProjectionError(reason: .validationRejected)
        }
        return literal
    }
}

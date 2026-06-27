import AgentStudioProgrammaticControl
import Foundation

private struct BridgePageRenderSnapshot: Decodable {
    let pageTitle: String?
    let hasAppRoot: Bool
    let hasEmptyShell: Bool
    let hasReviewShell: Bool
    let sidebarPosition: String?
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
        let result = IPCBridgeReviewPackageResult(
            paneId: paneId,
            status: paneState.diff.status.rawValue,
            error: paneState.diff.error,
            selectedItemId: selectedReviewItemId,
            package: paneState.diff.packageMetadata.map(ipcPackage)
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
                    sidebarPosition: snapshot.sidebarPosition
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
        let result: BridgeContentLoadResult
        do {
            result = try await reviewContentStore.load(
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

        guard result.data.count <= AppPolicies.Bridge.ipcMaxResponsePayloadBytes else {
            throw BridgeIPCProjectionError(reason: .payloadTooLarge)
        }

        let text = String(data: result.data, encoding: .utf8)
        let contentBase64 = text == nil ? result.data.base64EncodedString() : nil
        if let contentBase64,
            contentBase64.utf8.count > AppPolicies.Bridge.ipcMaxResponsePayloadBytes
        {
            throw BridgeIPCProjectionError(reason: .payloadTooLarge)
        }

        let ipcResult = IPCBridgeContentGetResult(
            paneId: paneId,
            handle: ipcContentHandle(result.handle),
            mimeType: result.mimeType,
            body: IPCBridgeContentBody(
                byteCount: result.data.count,
                isUtf8: text != nil,
                contentText: text,
                contentBase64: contentBase64
            )
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

    private func ipcPackage(_ package: BridgeReviewPackage) -> IPCBridgeReviewPackage {
        IPCBridgeReviewPackage(
            packageId: package.packageId,
            reviewGeneration: package.reviewGeneration.rawValue,
            revision: package.revision,
            orderedItemIds: package.orderedItemIds,
            summary: IPCBridgeReviewPackageSummary(
                filesChanged: package.summary.filesChanged,
                additions: package.summary.additions,
                deletions: package.summary.deletions,
                visibleFileCount: package.summary.visibleFileCount,
                hiddenFileCount: package.summary.hiddenFileCount
            ),
            items: package.orderedItemIds.compactMap { itemId in
                package.itemsById[itemId].map(ipcReviewItem)
            }
        )
    }

    private func ipcReviewItem(_ item: BridgeReviewItemDescriptor) -> IPCBridgeReviewItem {
        IPCBridgeReviewItem(
            identity: IPCBridgeReviewItemIdentity(
                itemId: item.itemId,
                itemKind: item.itemKind.rawValue
            ),
            paths: IPCBridgeReviewItemPaths(
                basePath: item.basePath,
                headPath: item.headPath,
                language: item.language
            ),
            classification: IPCBridgeReviewItemClassification(
                changeKind: item.changeKind.rawValue,
                fileClass: item.fileClass.rawValue,
                isHiddenByDefault: item.isHiddenByDefault,
                reviewPriority: item.reviewPriority.rawValue
            ),
            stats: IPCBridgeReviewItemStats(additions: item.additions, deletions: item.deletions),
            contentRoles: IPCBridgeContentRoles(
                base: item.contentRoles.base.map(ipcContentHandle),
                head: item.contentRoles.head.map(ipcContentHandle),
                diff: item.contentRoles.diff.map(ipcContentHandle),
                file: item.contentRoles.file.map(ipcContentHandle)
            )
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

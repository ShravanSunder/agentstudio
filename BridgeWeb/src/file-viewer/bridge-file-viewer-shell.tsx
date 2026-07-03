import { RefreshCwIcon } from 'lucide-react';
import type { ReactElement, ReactNode } from 'react';

import { BridgeViewerButton, BridgeViewerIcon } from '../app/bridge-viewer-button.js';
import { BridgeViewerContentHeader } from '../app/bridge-viewer-content-header.js';
import { BridgeViewerResizableRailLayout } from '../app/bridge-viewer-resizable-rail-layout.js';
import type {
	WorktreeFileDescriptor,
	WorktreeFileSurfaceSourceIdentity,
} from '../features/worktree-file/models/worktree-file-protocol-models.js';
import type { BridgeTelemetryRecorder } from '../foundation/telemetry/bridge-telemetry-recorder.js';
import type { BridgeTraceContext } from '../foundation/telemetry/bridge-trace-context.js';
import type { WorktreeFileSurfaceLoadTelemetry } from '../worktree-file-surface/worktree-file-surface-runtime.js';
import { BridgeFileViewerCodePanel } from './bridge-file-viewer-code-panel.js';
import type {
	BridgeFileViewerDescriptorProjection,
	BridgeFileViewerFilterMode,
	BridgeFileViewerSearchMode,
	BridgeFileViewerVisibleFileDemandChange,
} from './bridge-file-viewer-contracts.js';
import {
	bridgeFileViewerHasActiveCommentDraft,
	shouldAutoRefreshStaleOpenFile,
} from './bridge-file-viewer-stale-refresh-policy.js';
import {
	firstSuccessfulDemandLoadResult,
	worktreeFileDemandFailedCountByLane,
	worktreeFileDemandFailedCountByReason,
	type BridgeFileViewerDemandDispatchDebugState,
	type BridgeFileViewerInitialSurfaceLoadState,
	type BridgeFileViewerOpenState,
	type BridgeFileViewerRefreshDebugState,
	type BridgeFileViewerRenderState,
	type BridgeFileViewerRenderedOpenFileContent,
} from './bridge-file-viewer-state.js';
import { BridgeFileViewerTreePanel } from './bridge-file-viewer-tree-panel.js';

interface BridgeFileViewerShellProps {
	readonly canRefreshOpenFile: boolean;
	readonly codeViewWorkerFactory?: () => Worker;
	readonly codeViewWorkerPoolEnabled?: boolean;
	readonly contentHeaderTitle: string;
	readonly descriptorProjection: BridgeFileViewerDescriptorProjection;
	readonly dispatchVisibleFileDemand: (change: BridgeFileViewerVisibleFileDemandChange) => void;
	readonly fileDescriptorByPath: ReadonlyMap<string, WorktreeFileDescriptor>;
	readonly filterMode: BridgeFileViewerFilterMode;
	readonly initialSurfaceLoadState: BridgeFileViewerInitialSurfaceLoadState;
	readonly isActive: boolean;
	readonly lastDemandDispatchDebugState: BridgeFileViewerDemandDispatchDebugState;
	readonly lastOpenLoadTelemetry: WorktreeFileSurfaceLoadTelemetry | null;
	readonly metadataFileTreeRowCount: number;
	readonly onFilterModeChange: (mode: BridgeFileViewerFilterMode) => void;
	readonly onOpenFile: (descriptor: WorktreeFileDescriptor) => Promise<void>;
	readonly onOpenReviewComparison?: (descriptor: WorktreeFileDescriptor) => void;
	readonly onRequestFileDescriptor: Parameters<
		typeof BridgeFileViewerTreePanel
	>[0]['onRequestFileDescriptor'];
	readonly onSearchModeChange: (mode: BridgeFileViewerSearchMode) => void;
	readonly onSearchTextChange: (text: string) => void;
	readonly openFileState: BridgeFileViewerOpenState;
	readonly openFileTotalHeightPixels: number | null;
	readonly refreshDebugState: BridgeFileViewerRefreshDebugState | null;
	readonly refreshOpenFile: (state: BridgeFileViewerOpenState) => Promise<void>;
	readonly renderedOpenFileContent: BridgeFileViewerRenderedOpenFileContent | null;
	readonly renderState: BridgeFileViewerRenderState;
	readonly searchMode: BridgeFileViewerSearchMode;
	readonly searchText: string;
	readonly selectedPath: string | null;
	readonly sourceIdentity: WorktreeFileSurfaceSourceIdentity | null;
	readonly telemetryRecorder: BridgeTelemetryRecorder | undefined;
	readonly telemetryTraceContext: BridgeTraceContext | null;
	readonly totalTreeHeight: {
		readonly heightPixels: number | null;
		readonly source: 'localProjection' | 'providerFacts' | null;
	};
	readonly totalTreeRowCount: number;
	readonly viewerHeaderControls?: ReactNode;
}

export function BridgeFileViewerShell({
	canRefreshOpenFile,
	codeViewWorkerFactory,
	codeViewWorkerPoolEnabled,
	contentHeaderTitle,
	descriptorProjection,
	dispatchVisibleFileDemand,
	fileDescriptorByPath,
	filterMode,
	initialSurfaceLoadState,
	isActive,
	lastDemandDispatchDebugState,
	lastOpenLoadTelemetry,
	metadataFileTreeRowCount,
	onFilterModeChange: setFilterMode,
	onOpenFile: openFile,
	onOpenReviewComparison,
	onRequestFileDescriptor: requestFileDescriptor,
	onSearchModeChange: setSearchMode,
	onSearchTextChange: setSearchText,
	openFileState,
	openFileTotalHeightPixels,
	refreshDebugState,
	refreshOpenFile,
	renderedOpenFileContent,
	renderState,
	searchMode,
	searchText,
	selectedPath,
	telemetryRecorder,
	telemetryTraceContext,
	totalTreeHeight,
	totalTreeRowCount,
	viewerHeaderControls,
}: BridgeFileViewerShellProps): ReactElement {
	const lastDemandDispatchResult =
		lastDemandDispatchDebugState.status === 'settled' ? lastDemandDispatchDebugState.result : null;
	const firstDemandLoadResult =
		lastDemandDispatchResult === null
			? null
			: firstSuccessfulDemandLoadResult(lastDemandDispatchResult);
	const firstDemandLoadTelemetry = firstDemandLoadResult?.loadTelemetry ?? null;

	return (
		<main
			className="flex h-full min-h-0 w-full flex-col overflow-hidden bg-[var(--bridge-app-bg)]"
			data-file-viewer-active={isActive}
			data-file-viewer-owner="BridgeViewerApp.FileViewer"
			data-last-refresh-commit-state={refreshDebugState?.commitState}
			data-last-refresh-current-request-id={refreshDebugState?.currentRequestId}
			data-last-refresh-descriptor-id={refreshDebugState?.descriptorId}
			data-last-refresh-request-id={refreshDebugState?.requestId}
			data-last-refresh-result={refreshDebugState?.result}
			data-last-demand-dispatch-error={
				lastDemandDispatchDebugState.status === 'failed'
					? lastDemandDispatchDebugState.reason
					: undefined
			}
			data-last-demand-dispatch-executor-in-flight-after={
				lastDemandDispatchResult?.executorInFlightCountAfter
			}
			data-last-demand-dispatch-executor-in-flight-bytes-after={
				lastDemandDispatchResult?.executorInFlightBytesAfter
			}
			data-last-demand-dispatch-executor-queued-after={
				lastDemandDispatchResult?.executorQueuedLoadCountAfter
			}
			data-last-demand-dispatch-executor-queued-bytes-after={
				lastDemandDispatchResult?.executorQueuedBytesAfter
			}
			data-last-demand-dispatch-failed-count={lastDemandDispatchResult?.failedCount}
			data-last-demand-dispatch-failed-count-by-lane={
				lastDemandDispatchResult === null
					? undefined
					: JSON.stringify(worktreeFileDemandFailedCountByLane(lastDemandDispatchResult))
			}
			data-last-demand-dispatch-failed-count-by-reason={
				lastDemandDispatchResult === null
					? undefined
					: JSON.stringify(worktreeFileDemandFailedCountByReason(lastDemandDispatchResult))
			}
			data-last-demand-dispatch-first-disposition={firstDemandLoadTelemetry?.disposition}
			data-last-demand-dispatch-first-dedupe-key={firstDemandLoadResult?.dedupeKey}
			data-last-demand-dispatch-first-freshness-key={firstDemandLoadResult?.freshnessKey}
			data-last-demand-dispatch-first-executor-in-flight-ms={
				firstDemandLoadTelemetry?.executorInFlightMilliseconds ?? undefined
			}
			data-last-demand-dispatch-first-executor-pending-wait-ms={
				firstDemandLoadTelemetry?.executorPendingWaitMilliseconds ?? undefined
			}
			data-last-demand-dispatch-first-lane={firstDemandLoadTelemetry?.lane}
			data-last-demand-dispatch-first-scheduler-queue-wait-ms={
				firstDemandLoadTelemetry?.schedulerQueueWaitMilliseconds ?? undefined
			}
			data-last-demand-dispatch-origin={
				lastDemandDispatchDebugState.status === 'settled'
					? lastDemandDispatchDebugState.origin.kind
					: undefined
			}
			data-last-demand-dispatch-expected-visible-file-count={
				lastDemandDispatchDebugState.status === 'settled' &&
				lastDemandDispatchDebugState.origin.kind === 'visibleViewport'
					? lastDemandDispatchDebugState.origin.expectedVisibleFileCount
					: undefined
			}
			data-last-demand-dispatch-open-file-path-before={
				lastDemandDispatchDebugState.status === 'settled' &&
				lastDemandDispatchDebugState.origin.kind === 'recentlyUpdatedFile'
					? (lastDemandDispatchDebugState.origin.openFilePathBefore ?? undefined)
					: undefined
			}
			data-last-demand-dispatch-open-file-path-after={
				lastDemandDispatchDebugState.status === 'settled' &&
				lastDemandDispatchDebugState.origin.kind === 'recentlyUpdatedFile'
					? (lastDemandDispatchDebugState.origin.openFilePathAfter ?? undefined)
					: undefined
			}
			data-last-demand-dispatch-intent-count={lastDemandDispatchResult?.intentCount}
			data-last-demand-dispatch-loaded-count={lastDemandDispatchResult?.loadedCount}
			data-last-demand-dispatch-scheduler-queued-after={
				lastDemandDispatchResult?.schedulerQueuedIntentCountAfter
			}
			data-last-demand-dispatch-scheduler-queued-bytes-after={
				lastDemandDispatchResult?.schedulerQueuedEstimatedBytesAfter
			}
			data-last-demand-dispatch-status={lastDemandDispatchDebugState.status}
			data-last-demand-dispatch-stimulus-count={lastDemandDispatchResult?.stimulusCount}
			data-worktree-initial-surface-error={
				initialSurfaceLoadState.status === 'failed' ? initialSurfaceLoadState.reason : undefined
			}
			data-worktree-initial-surface-state={initialSurfaceLoadState.status}
			data-last-open-load-disposition={lastOpenLoadTelemetry?.disposition}
			data-last-open-load-duration-ms={lastOpenLoadTelemetry?.durationMilliseconds}
			data-last-open-load-estimated-bytes={lastOpenLoadTelemetry?.estimatedBytes ?? undefined}
			data-last-open-load-executor-in-flight-after={
				lastOpenLoadTelemetry?.executorInFlightCountAfter
			}
			data-last-open-load-executor-in-flight-bytes-after={
				lastOpenLoadTelemetry?.executorInFlightBytesAfter
			}
			data-last-open-load-executor-in-flight-bytes-before={
				lastOpenLoadTelemetry?.executorInFlightBytesBefore
			}
			data-last-open-load-executor-in-flight-before={
				lastOpenLoadTelemetry?.executorInFlightCountBefore
			}
			data-last-open-load-executor-in-flight-ms={
				lastOpenLoadTelemetry?.executorInFlightMilliseconds ?? undefined
			}
			data-last-open-load-executor-pending-wait-ms={
				lastOpenLoadTelemetry?.executorPendingWaitMilliseconds ?? undefined
			}
			data-last-open-load-executor-queued-after={
				lastOpenLoadTelemetry?.executorQueuedLoadCountAfter
			}
			data-last-open-load-executor-queued-bytes-after={
				lastOpenLoadTelemetry?.executorQueuedBytesAfter
			}
			data-last-open-load-executor-queued-bytes-before={
				lastOpenLoadTelemetry?.executorQueuedBytesBefore
			}
			data-last-open-load-executor-queued-before={
				lastOpenLoadTelemetry?.executorQueuedLoadCountBefore
			}
			data-last-open-load-lane={lastOpenLoadTelemetry?.lane}
			data-last-open-load-resource-body-registry-commit-ms={
				lastOpenLoadTelemetry?.resourceBodyRegistryCommitMilliseconds ?? undefined
			}
			data-last-open-load-resource-fetch-response-wait-ms={
				lastOpenLoadTelemetry?.resourceFetchResponseWaitMilliseconds ?? undefined
			}
			data-last-open-load-resource-first-chunk-wait-ms={
				lastOpenLoadTelemetry?.resourceFirstChunkWaitMilliseconds ?? undefined
			}
			data-last-open-load-resource-stream-read-ms={
				lastOpenLoadTelemetry?.resourceStreamReadMilliseconds ?? undefined
			}
			data-last-open-load-scheduler-queue-wait-ms={
				lastOpenLoadTelemetry?.schedulerQueueWaitMilliseconds ?? undefined
			}
			data-last-open-load-scheduler-queued-bytes-after={
				lastOpenLoadTelemetry?.schedulerQueuedEstimatedBytesAfter
			}
			data-last-open-load-scheduler-queued-bytes-before={
				lastOpenLoadTelemetry?.schedulerQueuedEstimatedBytesBefore
			}
			data-last-open-load-scheduler-queued-after={
				lastOpenLoadTelemetry?.schedulerQueuedIntentCountAfter
			}
			data-last-open-load-scheduler-queued-before={
				lastOpenLoadTelemetry?.schedulerQueuedIntentCountBefore
			}
			data-worktree-metadata-file-row-count={metadataFileTreeRowCount}
			data-worktree-metadata-tree-row-count={renderState.treeRows.length}
			data-worktree-tree-extent-kind={renderState.treeSizeFacts?.extentKind ?? undefined}
			data-worktree-tree-path-count={renderState.treeSizeFacts?.pathCount ?? undefined}
			data-selected-display-path={selectedPath ?? undefined}
			data-sidebar-position="right"
			data-testid="bridge-file-viewer-shell"
			{...(renderState.sourceIdentity === null
				? {}
				: {
						'data-worktree-source-cursor': renderState.sourceIdentity.sourceCursor,
						'data-worktree-source-id': renderState.sourceIdentity.sourceId,
						'data-worktree-source-state': 'live',
					})}
			{...(renderState.provenance === null
				? {}
				: {
						'data-worktree-base-ref': renderState.provenance.baseRef,
						'data-worktree-root-token': renderState.provenance.worktreeRootToken,
						'data-worktree-scenario': renderState.provenance.scenarioName,
					})}
		>
			<BridgeViewerResizableRailLayout
				autosaveId="bridge-viewer-right-rail"
				isActive={isActive}
				content={
					<section className="grid h-full min-h-0 min-w-0 grid-rows-[auto_minmax(0,1fr)]">
						<BridgeViewerContentHeader
							controls={viewerHeaderControls}
							eyebrow="Files"
							title={contentHeaderTitle}
						/>
						<BridgeFileViewerCodePanel
							openFileState={openFileState}
							renderedFileContent={renderedOpenFileContent}
							staleNotice={
								openFileState.status === 'stale' &&
								!shouldAutoRefreshStaleOpenFile({
									hasActiveCommentDraft: bridgeFileViewerHasActiveCommentDraft,
								}) ? (
									<BridgeFileViewerStaleNotice
										canRefresh={canRefreshOpenFile}
										onRefresh={() => {
											void refreshOpenFile(openFileState);
										}}
									/>
								) : null
							}
							totalHeightPixels={openFileTotalHeightPixels}
							{...(codeViewWorkerFactory === undefined ? {} : { codeViewWorkerFactory })}
							{...(codeViewWorkerPoolEnabled === undefined ? {} : { codeViewWorkerPoolEnabled })}
						/>
					</section>
				}
				contentTestId="bridge-file-viewer-content-panel"
				handleTestId="bridge-file-viewer-rail-resize-handle"
				rail={
					<BridgeFileViewerTreePanel
						descriptorProjection={descriptorProjection}
						fileDescriptorByPath={fileDescriptorByPath}
						filterMode={filterMode}
						onFilterModeChange={setFilterMode}
						onOpenFile={openFile}
						{...(onOpenReviewComparison === undefined ? {} : { onOpenReviewComparison })}
						{...(requestFileDescriptor === undefined
							? {}
							: { onRequestFileDescriptor: requestFileDescriptor })}
						onSearchModeChange={setSearchMode}
						onSearchTextChange={setSearchText}
						onVisibleFileDemandChange={dispatchVisibleFileDemand}
						searchMode={searchMode}
						searchText={searchText}
						selectedPath={selectedPath}
						sourceIdentity={renderState.sourceIdentity}
						{...(telemetryRecorder === undefined ? {} : { telemetryRecorder })}
						telemetryTraceContext={telemetryTraceContext}
						totalTreeRowCount={totalTreeRowCount}
						totalTreeHeightPixels={totalTreeHeight.heightPixels}
						totalTreeHeightSource={totalTreeHeight.source}
					/>
				}
				railTestId="bridge-file-viewer-resizable-rail"
			/>
		</main>
	);
}

function BridgeFileViewerStaleNotice({
	canRefresh,
	onRefresh,
}: {
	readonly canRefresh: boolean;
	readonly onRefresh: () => void;
}): ReactElement {
	return (
		<div
			className="absolute right-3 top-3 z-10 flex items-center gap-2 rounded-md border border-[var(--bridge-border-opaque)] bg-[var(--bridge-menu-bg)] px-3 py-2 text-xs shadow-lg"
			data-testid="worktree-file-content-stale"
		>
			<span>Content changed</span>
			<BridgeViewerButton
				className="border-[var(--bridge-border-opaque)] bg-[var(--bridge-header-control-bg)] px-2"
				data-testid="worktree-file-refresh"
				disabled={!canRefresh}
				onClick={onRefresh}
			>
				<BridgeViewerIcon>
					<RefreshCwIcon aria-hidden="true" className="size-3" />
				</BridgeViewerIcon>
				Refresh
			</BridgeViewerButton>
		</div>
	);
}

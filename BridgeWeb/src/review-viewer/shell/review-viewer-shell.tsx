import type { ReactElement, ReactNode } from 'react';

import { BridgeViewerContentHeader } from '../../app/bridge-viewer-content-header.js';
import { BridgeViewerRailToolbar } from '../../app/bridge-viewer-rail-toolbar.js';
import { BridgeViewerResizableRailLayout } from '../../app/bridge-viewer-resizable-rail-layout.js';
import { BridgeViewerRightRailShell } from '../../app/bridge-viewer-right-rail-shell.js';
import { BridgeViewerSearchControl } from '../../app/bridge-viewer-search-control.js';
import { BridgeViewerSearchField } from '../../app/bridge-viewer-search-field.js';
import { Skeleton } from '../../components/ui/skeleton.js';
import type { BridgeMainCodeViewItem } from '../../core/comm-worker/bridge-main-render-snapshot-store.js';
import type { BridgeWorkerPanelChromePatchPayload } from '../../core/comm-worker/bridge-worker-contracts.js';
import { compileBridgeFileTreeSearchPattern } from '../../core/models/bridge-file-tree-search.js';
import type { ReviewTreeRowMetadata } from '../../features/review/models/review-protocol-models.js';
import {
	type BridgeReviewItemRegistry,
	reviewItemPathLabel,
} from '../../foundation/review-package/bridge-review-item-registry.js';
import type {
	BridgeFileChangeKind,
	BridgeFileClass,
	BridgeReviewPackage,
} from '../../foundation/review-package/bridge-review-package.js';
import type { BridgeTelemetryRecorder } from '../../foundation/telemetry/bridge-telemetry-recorder.js';
import type { BridgeTraceContext } from '../../foundation/telemetry/bridge-trace-context.js';
import {
	BridgeReviewFacetMenu,
	bridgeReviewFileClassIcon,
	type BridgeReviewFacetMenuOption,
} from '../chrome/bridge-review-facet-menu.js';
import { BridgeReviewProjectionMenu } from '../chrome/bridge-review-projection-menu.js';
import type { BridgeCodeViewItemPresentation } from '../code-view/bridge-code-view-materialization.js';
import type { SelectedContentPaintTelemetryStart } from '../code-view/bridge-code-view-panel-types.js';
import {
	BridgeCodeViewPanel,
	type BridgeCodeViewControlHandle,
} from '../code-view/bridge-code-view-panel.js';
import type { BridgeCodeViewRenderFulfillmentCoordinator } from '../code-view/bridge-code-view-render-fulfillment.js';
import type { ReviewContentDemandTelemetry } from '../content/review-content-demand-types.js';
import { BridgeMarkdownPreview } from '../markdown/bridge-markdown-preview.js';
import type {
	BridgeReviewProjectionMode,
	BridgeReviewProjectionResult,
	BridgeReviewSearchMode,
} from '../models/review-projection-models.js';
import { bridgeTreesDisclosurePolicyIdentity } from '../trees/bridge-trees-controller.js';
import { BridgeReviewTreesPanel } from '../trees/bridge-trees-panel.js';
import type { BridgeReviewTreeSelectionRevealRequest } from '../trees/bridge-trees-panel.js';

export interface ReviewViewerShellProps {
	readonly presentationRegistry: BridgeReviewItemRegistry;
	readonly presentationPositionKey: string;
	readonly reviewPackage: BridgeReviewPackage;
	readonly reviewTreeRows?: readonly ReviewTreeRowMetadata[];
	readonly projection: BridgeReviewProjectionResult;
	readonly renderFulfillmentCoordinator: BridgeCodeViewRenderFulfillmentCoordinator;
	readonly selectedItemId: string | null;
	readonly selectedContentLoadingItemId?: string | null;
	readonly selectedContentPaintTelemetryStart?: SelectedContentPaintTelemetryStart | null;
	readonly onSelectItem: (itemId: string) => void;
	readonly onHoveredItemIdChange?: (itemId: string | null) => void;
	readonly panelChromeSlice: BridgeWorkerPanelChromePatchPayload;
	readonly selectedContentText?: string | null;
	readonly selectedCodeViewItem?: BridgeMainCodeViewItem | null;
	readonly selectionCommitDurationMilliseconds?: number | null;
	readonly selectedItemPresentation?: BridgeCodeViewItemPresentation | null;
	readonly selectedContentUnavailablePath?: string | null;
	readonly selectedCanvasLoadingReason?: BridgeReviewCanvasLoadingReason | null;
	readonly lastSelectedDemandTelemetry?: ReviewContentDemandTelemetry | null;
	readonly lastVisibleDemandTelemetry?: ReviewContentDemandTelemetry | null;
	readonly selectedMarkdownPreviewHtml?: string | null;
	readonly selectedMarkdownPreviewSourcePath?: string | null;
	readonly codeViewWorkerPoolEnabled?: boolean;
	readonly codeViewWorkerFactory?: () => Worker;
	readonly projectionMode?: BridgeReviewProjectionMode;
	readonly onProjectionModeChange?: (mode: BridgeReviewProjectionMode) => void;
	readonly treeSearchText?: string;
	readonly treeSelectionRevealRequest?: BridgeReviewTreeSelectionRevealRequest | null;
	readonly treeSearchMode?: BridgeReviewSearchMode;
	readonly treeSearchOpen?: boolean;
	readonly onTreeSearchOpen?: () => void;
	readonly onTreeSearchModeChange?: (mode: BridgeReviewSearchMode) => void;
	readonly onTreeSearchTextChange?: (searchText: string) => void;
	readonly gitStatusFilter?: BridgeFileChangeKind | 'all';
	readonly isActive?: boolean;
	readonly onGitStatusFilterChange?: (status: BridgeFileChangeKind | 'all') => void;
	readonly fileClassFilter?: BridgeFileClass | 'all';
	readonly onFileClassFilterChange?: (fileClass: BridgeFileClass | 'all') => void;
	readonly onCodeViewControlHandleChange?: (handle: BridgeCodeViewControlHandle | null) => void;
	readonly onCodeViewVisibleItemIdsChange?: (itemIds: readonly string[]) => void;
	readonly onTreeVisibleItemIdsChange?: (itemIds: readonly string[]) => void;
	readonly telemetryRecorder?: BridgeTelemetryRecorder;
	readonly telemetryParentTraceContext?: BridgeTraceContext | null;
	readonly visibleCodeViewItems?: readonly BridgeMainCodeViewItem[];
	readonly viewerHeaderControls?: ReactNode;
}

export type BridgeReviewCanvasLoadingReason = 'content' | 'markdownPreview';

const hiddenVisiblePathTextByRegistry = new WeakMap<BridgeReviewItemRegistry, string>();

export function ReviewViewerShell(props: ReviewViewerShellProps): ReactElement {
	const registry = props.presentationRegistry;
	const hiddenVisiblePathText = hiddenVisiblePathTextForRegistry(registry);
	const projectionMode = props.projectionMode ?? { kind: 'normalReview' };
	const gitStatusFilter = props.gitStatusFilter ?? 'all';
	const fileClassFilter = props.fileClassFilter ?? 'all';
	const statusText =
		props.isActive === true && props.panelChromeSlice.isLoading === true
			? (props.panelChromeSlice.message ?? null)
			: null;
	const treeSearchText = props.treeSearchText ?? '';
	const treeSearchMode = props.treeSearchMode ?? { kind: 'text' };
	const treeSearchOpen = props.treeSearchOpen === true || treeSearchText.length > 0;
	const treeSearchCompilation = compileBridgeFileTreeSearchPattern({
		searchMode: treeSearchMode.kind,
		searchText: treeSearchText,
	});
	const treeSearchErrorMessage =
		treeSearchCompilation.searchError === null ? null : 'Invalid regex';
	const projection = props.projection;
	const selectedItem =
		props.selectedItemId === null
			? null
			: (props.reviewPackage.itemsById[props.selectedItemId] ?? null);
	const selectedDisplayPath =
		selectedItem === null
			? null
			: (selectedItem.headPath ?? selectedItem.basePath ?? selectedItem.itemId);
	const contentHeaderTitle = bridgeReviewViewerHeaderTitle({
		reviewPackage: props.reviewPackage,
		selectedDisplayPath,
	});
	const selectedContentState = selectedContentStateForShell({
		selectedCanvasLoadingReason: props.selectedCanvasLoadingReason ?? null,
		selectedCodeViewItem: props.selectedCodeViewItem ?? null,
		selectedContentUnavailablePath: props.selectedContentUnavailablePath ?? null,
		selectedMarkdownPreviewHtml: props.selectedMarkdownPreviewHtml ?? null,
	});
	const canvasBranch = reviewCanvasBranchForShell({
		selectedContentUnavailablePath: props.selectedContentUnavailablePath ?? null,
		selectedMarkdownPreviewHtml: props.selectedMarkdownPreviewHtml ?? null,
		selectedMarkdownPreviewSourcePath: props.selectedMarkdownPreviewSourcePath ?? null,
	});
	const selectedDemandTelemetry = props.lastSelectedDemandTelemetry ?? null;
	const visibleDemandTelemetry = props.lastVisibleDemandTelemetry ?? null;

	return (
		<main
			className="flex h-full min-h-0 w-full flex-col overflow-hidden bg-[var(--bridge-app-bg)] text-[var(--bridge-text-primary)]"
			data-review-selected-demand-admitted-bytes={selectedDemandTelemetry?.admittedBytes}
			data-review-selected-demand-admitted-bytes-by-lane={serializeReviewDemandLaneBytes(
				selectedDemandTelemetry?.admittedBytesByLane,
			)}
			data-review-selected-demand-byte-budget-source={selectedDemandTelemetry?.byteBudgetSource}
			data-review-selected-demand-configured-executor-max-concurrent-loads={
				selectedDemandTelemetry?.configuredExecutorMaxConcurrentLoads
			}
			data-review-selected-demand-configured-executor-max-in-flight-bytes={
				selectedDemandTelemetry?.configuredExecutorMaxInFlightBytes
			}
			data-review-selected-demand-deferred-count={selectedDemandTelemetry?.deferredCount}
			data-review-selected-demand-deferred-estimated-bytes-by-lane={serializeReviewDemandLaneBytes(
				selectedDemandTelemetry?.deferredEstimatedBytesByLane,
			)}
			data-review-selected-demand-dropped-estimated-bytes-by-lane={serializeReviewDemandLaneBytes(
				selectedDemandTelemetry?.droppedEstimatedBytesByLane,
			)}
			data-review-selected-demand-dropped-intent-count={selectedDemandTelemetry?.droppedIntentCount}
			data-review-selected-demand-duration-ms={selectedDemandTelemetry?.durationMilliseconds}
			data-review-selected-demand-executor-in-flight-after-dispatch={
				selectedDemandTelemetry?.executorInFlightCountAfterDispatch
			}
			data-review-selected-demand-executor-in-flight-after={
				selectedDemandTelemetry?.executorInFlightCountAfter
			}
			data-review-selected-demand-executor-in-flight-before={
				selectedDemandTelemetry?.executorInFlightCountBefore
			}
			data-review-selected-demand-executor-queued-load-after={
				selectedDemandTelemetry?.executorQueuedLoadCountAfter
			}
			data-review-selected-demand-failed-count={selectedDemandTelemetry?.failedCount}
			data-review-selected-demand-foreground-intent-count={
				selectedDemandTelemetry?.foregroundIntentCount
			}
			data-review-selected-demand-interest={selectedDemandTelemetry?.interest}
			data-review-selected-demand-item-id={selectedDemandTelemetry?.itemId}
			data-review-selected-demand-package-id={selectedDemandTelemetry?.packageId}
			data-review-selected-demand-package-generation={selectedDemandTelemetry?.reviewGeneration}
			data-review-selected-demand-package-revision={selectedDemandTelemetry?.revision}
			data-review-selected-demand-result-reason={selectedDemandTelemetry?.resultReason}
			data-review-selected-demand-result-status={selectedDemandTelemetry?.resultStatus}
			data-review-selected-demand-load-failure-kind={selectedDemandTelemetry?.resultLoadFailureKind}
			data-review-selected-demand-lane-upgrade-count={selectedDemandTelemetry?.laneUpgradeCount}
			data-review-selected-demand-loaded-count={selectedDemandTelemetry?.loadedCount}
			data-review-selected-demand-max-executor-in-flight={
				selectedDemandTelemetry?.maxExecutorInFlightCount
			}
			data-review-selected-demand-max-executor-queued-load={
				selectedDemandTelemetry?.maxExecutorQueuedLoadCount
			}
			data-review-selected-demand-stale-drop-count={selectedDemandTelemetry?.staleDropCount}
			data-review-selected-demand-visible-intent-count={selectedDemandTelemetry?.visibleIntentCount}
			data-review-visible-demand-admitted-bytes={visibleDemandTelemetry?.admittedBytes}
			data-review-visible-demand-admitted-bytes-by-lane={serializeReviewDemandLaneBytes(
				visibleDemandTelemetry?.admittedBytesByLane,
			)}
			data-review-visible-demand-byte-budget-source={visibleDemandTelemetry?.byteBudgetSource}
			data-review-visible-demand-configured-executor-max-concurrent-loads={
				visibleDemandTelemetry?.configuredExecutorMaxConcurrentLoads
			}
			data-review-visible-demand-configured-executor-max-in-flight-bytes={
				visibleDemandTelemetry?.configuredExecutorMaxInFlightBytes
			}
			data-review-visible-demand-deferred-count={visibleDemandTelemetry?.deferredCount}
			data-review-visible-demand-deferred-estimated-bytes-by-lane={serializeReviewDemandLaneBytes(
				visibleDemandTelemetry?.deferredEstimatedBytesByLane,
			)}
			data-review-visible-demand-dropped-estimated-bytes-by-lane={serializeReviewDemandLaneBytes(
				visibleDemandTelemetry?.droppedEstimatedBytesByLane,
			)}
			data-review-visible-demand-dropped-intent-count={visibleDemandTelemetry?.droppedIntentCount}
			data-review-visible-demand-duration-ms={visibleDemandTelemetry?.durationMilliseconds}
			data-review-visible-demand-executor-in-flight-after-dispatch={
				visibleDemandTelemetry?.executorInFlightCountAfterDispatch
			}
			data-review-visible-demand-executor-in-flight-after={
				visibleDemandTelemetry?.executorInFlightCountAfter
			}
			data-review-visible-demand-executor-in-flight-before={
				visibleDemandTelemetry?.executorInFlightCountBefore
			}
			data-review-visible-demand-executor-queued-load-after={
				visibleDemandTelemetry?.executorQueuedLoadCountAfter
			}
			data-review-visible-demand-failed-count={visibleDemandTelemetry?.failedCount}
			data-review-visible-demand-foreground-intent-count={
				visibleDemandTelemetry?.foregroundIntentCount
			}
			data-review-visible-demand-interest={visibleDemandTelemetry?.interest}
			data-review-visible-demand-item-id={visibleDemandTelemetry?.itemId}
			data-review-visible-demand-package-id={visibleDemandTelemetry?.packageId}
			data-review-visible-demand-package-generation={visibleDemandTelemetry?.reviewGeneration}
			data-review-visible-demand-package-revision={visibleDemandTelemetry?.revision}
			data-review-visible-demand-lane-upgrade-count={visibleDemandTelemetry?.laneUpgradeCount}
			data-review-visible-demand-loaded-count={visibleDemandTelemetry?.loadedCount}
			data-review-visible-demand-max-executor-in-flight={
				visibleDemandTelemetry?.maxExecutorInFlightCount
			}
			data-review-visible-demand-max-executor-queued-load={
				visibleDemandTelemetry?.maxExecutorQueuedLoadCount
			}
			data-review-visible-demand-stale-drop-count={visibleDemandTelemetry?.staleDropCount}
			data-review-visible-demand-visible-intent-count={visibleDemandTelemetry?.visibleIntentCount}
			data-review-selection-commit-duration-ms={
				props.selectionCommitDurationMilliseconds ?? undefined
			}
			data-review-canvas-branch={canvasBranch}
			data-selected-content-state={selectedContentState}
			data-selected-display-path={selectedDisplayPath ?? undefined}
			data-review-metadata-id={props.reviewPackage.packageId}
			data-review-metadata-generation={props.reviewPackage.reviewGeneration}
			data-review-metadata-revision={props.reviewPackage.revision}
			data-review-metadata-item-count={props.reviewPackage.orderedItemIds.length}
			data-review-metadata-tree-row-count={props.reviewTreeRows?.length ?? 0}
			data-review-base-endpoint-id={props.reviewPackage.query.baseEndpointId}
			data-review-base-endpoint-kind={props.reviewPackage.baseEndpoint.kind}
			data-review-base-provider-identity={props.reviewPackage.baseEndpoint.providerIdentity}
			data-review-head-endpoint-id={props.reviewPackage.query.headEndpointId}
			data-review-head-endpoint-kind={props.reviewPackage.headEndpoint.kind}
			data-review-head-provider-identity={props.reviewPackage.headEndpoint.providerIdentity}
			data-projection-id={projection.projectionId}
			data-projection-mode={projectionMode.kind}
			data-sidebar-position="right"
			data-testid="review-viewer-shell"
		>
			<BridgeViewerResizableRailLayout
				autosaveId="bridge-viewer-right-rail"
				// The loaded review shell keeps its resizable frame mounted across activation so the
				// CodeView/markdown canvas and tree are never remounted when Review goes hidden.
				// Rail-frame gating stays on the lightweight fallback shells, not real content.
				isActive={true}
				content={
					<section
						aria-label="Selected content"
						className="grid h-full min-h-0 min-w-0 grid-rows-[auto_minmax(0,1fr)] overflow-hidden overscroll-contain bg-[var(--bridge-canvas-bg)]"
						data-testid="bridge-review-code-scroll"
					>
						<BridgeViewerContentHeader
							controls={props.viewerHeaderControls}
							eyebrow="Review"
							statusText={statusText}
							title={contentHeaderTitle}
						/>
						<section
							aria-label="Code canvas"
							className="relative h-full min-h-0 min-w-0 bg-[var(--bridge-canvas-bg)]"
							data-testid="bridge-review-canvas"
						>
							{props.selectedMarkdownPreviewHtml !== undefined &&
							props.selectedMarkdownPreviewHtml !== null &&
							props.selectedMarkdownPreviewSourcePath !== undefined &&
							props.selectedMarkdownPreviewSourcePath !== null ? (
								<BridgeMarkdownPreview
									html={props.selectedMarkdownPreviewHtml}
									sourcePath={props.selectedMarkdownPreviewSourcePath}
								/>
							) : props.selectedContentUnavailablePath !== undefined &&
							  props.selectedContentUnavailablePath !== null ? (
								<BridgeReviewContentUnavailableState
									sourcePath={props.selectedContentUnavailablePath}
								/>
							) : (
								<BridgeCodeViewPanel
									presentationPositionKey={props.presentationPositionKey}
									projection={projection}
									renderFulfillmentCoordinator={props.renderFulfillmentCoordinator}
									reviewPackage={props.reviewPackage}
									selectedCodeViewItem={props.selectedCodeViewItem ?? null}
									selectedContentLoadingItemId={props.selectedContentLoadingItemId ?? null}
									selectedContentPaintTelemetryStart={
										props.selectedContentPaintTelemetryStart ?? null
									}
									selectedItemId={props.selectedItemId}
									selectedItemPresentation={props.selectedItemPresentation ?? null}
									telemetryParentTraceContext={props.telemetryParentTraceContext ?? null}
									visibleCodeViewItems={props.visibleCodeViewItems ?? []}
									{...(props.onCodeViewVisibleItemIdsChange === undefined
										? {}
										: { onVisibleItemIdsChange: props.onCodeViewVisibleItemIdsChange })}
									{...(props.onCodeViewControlHandleChange === undefined
										? {}
										: {
												onControlHandleChange: props.onCodeViewControlHandleChange,
											})}
									{...(props.codeViewWorkerPoolEnabled === undefined
										? {}
										: { workerPoolEnabled: props.codeViewWorkerPoolEnabled })}
									{...(props.codeViewWorkerFactory === undefined
										? {}
										: { workerFactory: props.codeViewWorkerFactory })}
									{...(props.telemetryRecorder === undefined
										? {}
										: { telemetryRecorder: props.telemetryRecorder })}
								/>
							)}
							{props.selectedCanvasLoadingReason === undefined ||
							props.selectedCanvasLoadingReason === null ||
							props.selectedCanvasLoadingReason === 'content' ? null : (
								<BridgeReviewCanvasLoadingState reason={props.selectedCanvasLoadingReason} />
							)}
						</section>
					</section>
				}
				contentTestId="bridge-review-content-panel"
				handleTestId="bridge-review-rail-resize-handle"
				rail={BridgeViewerRightRailShell({
					body: (
						<nav
							aria-label="Changed files"
							className="h-full min-h-0"
							data-testid="bridge-review-rail-tree-slot"
						>
							<BridgeReviewTreesPanel
								isActive={props.isActive === true}
								key={bridgeTreesDisclosurePolicyIdentity}
								presentationPositionKey={props.presentationPositionKey}
								onSelectItem={props.onSelectItem}
								{...(props.onHoveredItemIdChange === undefined
									? {}
									: { onHoveredItemIdChange: props.onHoveredItemIdChange })}
								{...(props.onTreeVisibleItemIdsChange === undefined
									? {}
									: { onVisibleItemIdsChange: props.onTreeVisibleItemIdsChange })}
								projection={projection}
								reviewPackage={props.reviewPackage}
								reviewTreeRows={props.reviewTreeRows ?? []}
								searchMode={treeSearchMode}
								searchText={treeSearchText}
								selectedItemId={props.selectedItemId}
								selectionRevealRequest={props.treeSelectionRevealRequest ?? null}
								{...(props.telemetryRecorder === undefined
									? {}
									: { telemetryRecorder: props.telemetryRecorder })}
								telemetryTraceContext={props.telemetryParentTraceContext ?? null}
							/>
							{registry.visibleItems.length === 0 ? null : (
								<div aria-hidden="true" hidden>
									{hiddenVisiblePathText}
								</div>
							)}
						</nav>
					),
					bodyClassName: 'min-h-0 flex-1 overflow-hidden overscroll-contain',
					bodyTestId: 'bridge-review-rail-scroll',
					border: 'opaque',
					layout: 'stack',
					testId: 'bridge-review-sidebar',
					toolbarBelow: treeSearchOpen ? (
						<BridgeViewerSearchField
							clearButtonTestId="bridge-review-search-clear"
							errorMessage={treeSearchErrorMessage}
							inputTestId="bridge-review-search-input"
							onChange={(value): void => props.onTreeSearchTextChange?.(value)}
							onClear={(): void => props.onTreeSearchTextChange?.('')}
							onSearchModeChange={(mode): void => props.onTreeSearchModeChange?.(mode)}
							regexToggleTestId="bridge-review-regex-toggle"
							searchMode={treeSearchMode}
							statusTestId="bridge-review-tree-search-status"
							value={treeSearchText}
						/>
					) : null,
					toolbar: BridgeViewerRailToolbar({
						leading: (
							<BridgeReviewProjectionMenu
								projectionMode={projectionMode}
								{...(props.onProjectionModeChange === undefined
									? {}
									: { onProjectionModeChange: props.onProjectionModeChange })}
							/>
						),
						leadingTestId: 'bridge-review-rail-toolbar-leading',
						testId: 'bridge-review-rail-toolbar',
						trailing: [
							<div className="shrink-0" data-testid="bridge-review-facet-menu" key="facet-menu">
								<BridgeReviewFacetMenu
									fileClassFilter={fileClassFilter}
									fileClassOptions={fileClassOptions}
									gitStatusFilter={gitStatusFilter}
									gitStatusOptions={gitStatusOptions}
									onFileClassFilterChange={(value): void => props.onFileClassFilterChange?.(value)}
									onGitStatusFilterChange={(value): void => props.onGitStatusFilterChange?.(value)}
								/>
							</div>,
							<div data-testid="bridge-review-search-control-slot" key="search-control">
								<span className="sr-only">Search files</span>
								<BridgeViewerSearchControl
									isActive={treeSearchOpen}
									onOpenSearch={(): void => props.onTreeSearchOpen?.()}
									searchToggleTestId="bridge-review-search-toggle"
									testId="bridge-review-search-control"
								/>
							</div>,
						],
						trailingTestId: 'bridge-review-rail-toolbar-trailing',
					}),
				})}
				railTestId="bridge-review-resizable-rail"
			/>
		</main>
	);
}

function hiddenVisiblePathTextForRegistry(registry: BridgeReviewItemRegistry): string {
	const cachedText = hiddenVisiblePathTextByRegistry.get(registry);
	if (cachedText !== undefined) {
		return cachedText;
	}
	const text = registry.visibleItems.map((item) => reviewItemPathLabel(item)).join(' ');
	hiddenVisiblePathTextByRegistry.set(registry, text);
	return text;
}

export function BridgeReviewCanvasLoadingState(props: {
	readonly reason: BridgeReviewCanvasLoadingReason;
}): ReactElement {
	return (
		<div
			aria-hidden="true"
			className="pointer-events-none absolute left-8 top-12 z-20 flex w-[min(28rem,calc(100%-4rem))] flex-col gap-2 rounded-md border border-[var(--bridge-border-subtle)] bg-[var(--bridge-surface-bg)]/75 p-3 shadow-[var(--bridge-floating-panel-shadow)] backdrop-blur"
			data-bridge-review-canvas-loading-reason={props.reason}
			data-testid="bridge-review-canvas-loading-state"
		>
			<Skeleton
				className="h-3 w-full bg-[var(--bridge-surface-raised-bg)]"
				data-testid="bridge-review-canvas-loading-line"
			/>
			<Skeleton
				className="h-3 w-11/12 bg-[var(--bridge-surface-raised-bg)]"
				data-testid="bridge-review-canvas-loading-line"
			/>
			<Skeleton
				className="h-3 w-3/4 bg-[var(--bridge-surface-raised-bg)]"
				data-testid="bridge-review-canvas-loading-line"
			/>
		</div>
	);
}

function bridgeReviewViewerHeaderTitle(props: {
	readonly reviewPackage: BridgeReviewPackage;
	readonly selectedDisplayPath: string | null;
}): string {
	const sourceTitle = bridgeReviewComparisonTitle(props.reviewPackage);
	return props.selectedDisplayPath === null
		? sourceTitle
		: `${sourceTitle} / ${props.selectedDisplayPath}`;
}

function bridgeReviewComparisonTitle(reviewPackage: BridgeReviewPackage): string {
	const baseLabel = bridgeReviewEndpointDisplayLabel({
		endpointId: reviewPackage.query.baseEndpointId,
		endpoint: reviewPackage.baseEndpoint,
	});
	const headLabel = bridgeReviewEndpointDisplayLabel({
		endpointId: reviewPackage.query.headEndpointId,
		endpoint: reviewPackage.headEndpoint,
	});
	return `${headLabel} vs ${baseLabel}`;
}

function bridgeReviewEndpointDisplayLabel(props: {
	readonly endpointId: string | null | undefined;
	readonly endpoint: BridgeReviewPackage['baseEndpoint'];
}): string {
	if (props.endpoint.kind === 'workingTree') {
		return 'Current worktree';
	}
	if (
		props.endpointId === 'baseline-local-default' ||
		props.endpointId === 'baseline-origin-default'
	) {
		return 'Default';
	}
	return props.endpoint.label;
}

function BridgeReviewContentUnavailableState(props: { readonly sourcePath: string }): ReactElement {
	return (
		<section
			aria-label="Selected content unavailable"
			className="flex h-full min-h-[260px] items-center justify-center bg-[var(--bridge-canvas-bg)] px-8 text-center"
			data-testid="bridge-review-content-unavailable"
		>
			<div className="max-w-md">
				<p className="text-sm font-medium text-[var(--bridge-text-primary)]">Content unavailable</p>
				<p className="mt-1 truncate text-xs text-[var(--bridge-text-muted)]">{props.sourcePath}</p>
			</div>
		</section>
	);
}

function selectedContentStateForShell(props: {
	readonly selectedCanvasLoadingReason: BridgeReviewCanvasLoadingReason | null;
	readonly selectedCodeViewItem: BridgeMainCodeViewItem | null;
	readonly selectedContentUnavailablePath: string | null;
	readonly selectedMarkdownPreviewHtml: string | null;
}): 'failed' | 'loading' | 'ready' | 'unavailable' {
	if (props.selectedContentUnavailablePath !== null) {
		return 'failed';
	}
	if (props.selectedMarkdownPreviewHtml !== null || props.selectedCodeViewItem !== null) {
		return 'ready';
	}
	if (props.selectedCanvasLoadingReason === 'content') {
		return 'loading';
	}
	return 'unavailable';
}

function reviewCanvasBranchForShell(props: {
	readonly selectedContentUnavailablePath: string | null;
	readonly selectedMarkdownPreviewHtml: string | null;
	readonly selectedMarkdownPreviewSourcePath: string | null;
}): 'code' | 'markdown' | 'unavailable' {
	if (
		props.selectedMarkdownPreviewHtml !== null &&
		props.selectedMarkdownPreviewSourcePath !== null
	) {
		return 'markdown';
	}
	if (props.selectedContentUnavailablePath !== null) {
		return 'unavailable';
	}
	return 'code';
}

const gitStatusOptions: readonly BridgeReviewFacetMenuOption<BridgeFileChangeKind | 'all'>[] = [
	{ value: 'all', label: 'All statuses', description: 'Show every Git change kind', icon: '*' },
	{ value: 'added', label: 'Added', description: 'New files and created paths', icon: 'A' },
	{ value: 'modified', label: 'Modified', description: 'Files changed in place', icon: 'M' },
	{ value: 'renamed', label: 'Renamed', description: 'Moves and path renames', icon: 'R' },
	{ value: 'deleted', label: 'Deleted', description: 'Removed files and paths', icon: 'D' },
	{
		value: 'copied',
		label: 'Copied',
		description: 'Copied paths when Git reports them',
		icon: 'C',
	},
];

const bridgeFileClassOptions: readonly BridgeFileClass[] = [
	'source',
	'test',
	'docs',
	'config',
	'generated',
	'vendor',
	'binary',
	'large',
	'fixture',
	'unknown',
];

const fileClassOptions: readonly BridgeReviewFacetMenuOption<BridgeFileClass | 'all'>[] = [
	{ value: 'all', label: 'All file types', description: 'Show every classified file', icon: '*' },
	...bridgeFileClassOptions.map(
		(fileClass: BridgeFileClass): BridgeReviewFacetMenuOption<BridgeFileClass | 'all'> => ({
			value: fileClass,
			label: sentenceCase(fileClass),
			description: descriptionForFileClass(fileClass),
			icon: bridgeReviewFileClassIcon(fileClass),
		}),
	),
];

function sentenceCase(value: string): string {
	return value.length === 0 ? value : `${value.slice(0, 1).toUpperCase()}${value.slice(1)}`;
}

function serializeReviewDemandLaneBytes(
	value: ReviewContentDemandTelemetry['admittedBytesByLane'] | undefined,
): string | undefined {
	return value === undefined ? undefined : JSON.stringify(value);
}

function descriptionForFileClass(fileClass: BridgeFileClass): string {
	switch (fileClass) {
		case 'source':
			return 'Application and library implementation files';
		case 'test':
			return 'Tests, specs, fixtures, and verification code';
		case 'docs':
			return 'Plans, specs, markdown, and documentation';
		case 'config':
			return 'Build, package, and tool configuration';
		case 'generated':
			return 'Generated files that may be lower review priority';
		case 'vendor':
			return 'Vendored or third-party source trees';
		case 'binary':
			return 'Binary files and non-text assets';
		case 'large':
			return 'Large text files that need careful hydration';
		case 'fixture':
			return 'Fixture data and test inputs';
		case 'unknown':
			return 'Files without a confident class';
	}
	const exhaustiveFileClass: never = fileClass;
	void exhaustiveFileClass;
	return 'Files in this class';
}

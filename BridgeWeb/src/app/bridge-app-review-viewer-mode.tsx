import { useCallback, useEffect, useId, useMemo, useRef, useState, type ReactElement } from 'react';

import type { BridgePaneSurfaceClient } from '../core/comm-worker/bridge-pane-runtime.js';
import type { BridgeActiveViewerSource } from '../core/comm-worker/bridge-product-control-contracts.js';
import type { BridgeProductNavigationCommand } from '../core/comm-worker/bridge-product-session-contracts.js';
import { startBridgeFrameJankProbe } from '../foundation/diagnostics/bridge-frame-jank-probe.js';
import { startBridgeFrameLivenessProbe } from '../foundation/diagnostics/bridge-frame-liveness-probe.js';
import type { BridgeFileChangeKind } from '../foundation/review-package/bridge-review-package.js';
import type { BridgeTelemetryRecorder } from '../foundation/telemetry/bridge-telemetry-recorder.js';
import { recordBridgeFrameJankTelemetrySample } from '../foundation/telemetry/bridge-viewer-telemetry-adapter.js';
import { BridgeReviewProjectionMenu } from '../review-viewer/chrome/bridge-review-projection-menu.js';
import {
	bridgeCodeViewOptions,
	createBridgeReviewViewSettingsDefaults,
	deriveBridgeReviewCodeViewOptions,
} from '../review-viewer/code-view/bridge-code-view-options.js';
import type { BridgeCodeViewControlHandle } from '../review-viewer/code-view/bridge-code-view-panel.js';
import type {
	BridgeReviewProjectionMode,
	BridgeReviewSearchMode,
} from '../review-viewer/models/review-projection-models.js';
import type { BridgeReviewTreeSelectionRevealRequest } from '../review-viewer/trees/bridge-trees-panel.js';
import type { BridgeFileTreeFilterCandidate } from './bridge-app-control.js';
import {
	bridgeAppReviewNavigationSourceForDisplaySlice,
	type BridgeAppNavigationSource,
} from './bridge-app-navigation-admission.js';
import { useBridgeReviewNavigationController } from './bridge-app-review-navigation-controller.js';
import { bridgeReviewPresentationSnapshotForDisplay } from './bridge-app-review-presentation-adapter.js';
import {
	createBridgeReviewWorkerPierreCourier,
	type BridgeReviewRenderSnapshotController,
	useBridgeReviewRenderSnapshotController,
} from './bridge-app-review-render-snapshot-controller.js';
import { useBridgeReviewSelectionController } from './bridge-app-review-selection-controller.js';
import {
	BridgeReviewViewerShellBoundary,
	type BridgeReviewViewerPresentationState,
} from './bridge-app-review-viewer-shell-boundary.js';
import { BridgeReviewComparisonControl } from './bridge-review-comparison-control.js';
import {
	bridgeReviewComparisonPaneIsLoading,
	bridgeReviewComparisonPaneState,
} from './bridge-review-comparison-pane-state.js';
import {
	createBridgeViewerSearchState,
	transitionBridgeViewerSearchState,
	type BridgeViewerSearchAction,
	type BridgeViewerSearchError,
	type BridgeViewerSearchRejectionReason,
} from './bridge-viewer-search-state.js';
import { BridgeViewerViewSettingsMenu } from './bridge-viewer-view-settings-menu.js';
import type { BridgeReviewViewSettings } from './bridge-viewer-view-settings.js';
import { useBridgeReviewControlEventListeners } from './use-bridge-review-control-event-listeners.js';
import { useBridgeViewerToolbarShortcuts } from './use-bridge-viewer-toolbar-shortcuts.js';

export interface BridgeReviewViewerModeProps {
	readonly codeViewWorkerFactory?: () => Worker;
	readonly codeViewWorkerPoolEnabled?: boolean;
	readonly isActive: boolean;
	readonly isNavigationCommandStillEligible: (
		command: Extract<
			BridgeProductNavigationCommand,
			{ readonly commandKind: 'activateTarget'; readonly surface: 'review' }
		>,
	) => boolean;
	readonly navigationCommand?: Extract<
		BridgeProductNavigationCommand,
		{ readonly commandKind: 'activateTarget'; readonly surface: 'review' }
	>;
	readonly onActiveSourceChange: (activeSource: BridgeActiveViewerSource | null) => void;
	readonly onNavigationSourceChange: (
		source: Extract<BridgeAppNavigationSource, { readonly sourceKind: 'review' }> | null,
	) => void;
	readonly reviewClient: BridgePaneSurfaceClient;
	readonly target?: EventTarget;
	readonly telemetryRecorderRef: { readonly current: BridgeTelemetryRecorder };
	readonly viewerContextSwitcher: ReactElement;
}

type BridgeReviewFilterCandidate = Extract<
	BridgeFileTreeFilterCandidate,
	{ readonly surface: 'review' }
>;

const bridgeReviewDefaultViewSettings =
	createBridgeReviewViewSettingsDefaults(bridgeCodeViewOptions);
export function BridgeReviewViewerMode(props: BridgeReviewViewerModeProps): ReactElement {
	const {
		codeViewWorkerFactory,
		codeViewWorkerPoolEnabled,
		isActive,
		isNavigationCommandStillEligible,
		navigationCommand,
		onActiveSourceChange,
		onNavigationSourceChange,
		reviewClient,
		target = document,
		telemetryRecorderRef,
		viewerContextSwitcher,
	} = props;
	const pierreCourier = useMemo(() => createBridgeReviewWorkerPierreCourier(), []);
	const presentationPositionKey = useId();
	const controller = useBridgeReviewRenderSnapshotController({
		pierreCourier,
		reviewClient,
	});
	const catalogSnapshot = controller.catalogSnapshot;
	const comparisonTargetsQueryState = controller.comparisonTargetsQueryState;
	const clearSelectedReviewItemId = controller.clearSelectedReviewItemId;
	const commitSelectedReviewItemId = controller.commitSelectedReviewItemId;
	const displayStore = controller.displayStore;
	const emitHoveredReviewItemIntent = controller.emitHoveredReviewItemIntent;
	const emitSelectedReviewItemIntent = controller.emitSelectedReviewItemIntent;
	const markFileViewed = controller.markFileViewed;
	const panelChromeSlice = controller.panelChromeSlice;
	const reviewSourceSlice = controller.reviewSourceSlice;
	const selectedCodeViewItem = controller.selectedCodeViewItem;
	const selectedContentAvailability = controller.selectedContentAvailability;
	const selectedItemId = controller.selectedItemId;
	const selectedReviewItem = controller.selectedReviewItem;
	const setReviewCodeViewVisibleItemIds = controller.setReviewCodeViewVisibleItemIds;
	const setReviewTreeVisibleItemIds = controller.setReviewTreeVisibleItemIds;
	const updateReviewDisplayProjection = controller.updateReviewDisplayProjection;
	const queryReviewComparisonTargets = controller.queryReviewComparisonTargets;
	const cancelReviewComparisonTargetsQuery = controller.cancelReviewComparisonTargetsQuery;
	const visibleCodeViewItems = controller.visibleCodeViewItems;
	const [treeSearchState, setTreeSearchState] = useState(createBridgeViewerSearchState);
	const [treeSearchRejectionMessage, setTreeSearchRejectionMessage] = useState<string | null>(null);
	const treeSearchStateRef = useRef(treeSearchState);
	treeSearchStateRef.current = treeSearchState;
	const [reviewFilter, setReviewFilter] = useState<BridgeReviewFilterCandidate>({
		categoryFilter: 'all',
		gitStatusFilter: 'all',
		showBinary: false,
		showLarge: false,
		surface: 'review',
	});
	const { categoryFilter, gitStatusFilter, showBinary, showLarge } = reviewFilter;
	const [facetMenuOpen, setFacetMenuOpen] = useState(false);
	const [viewSettings, setViewSettings] = useState<BridgeReviewViewSettings>(
		bridgeReviewDefaultViewSettings,
	);
	const [viewSettingsMenuOpen, setViewSettingsMenuOpen] = useState(false);
	const [projectionMode, setProjectionMode] = useState<BridgeReviewProjectionMode>({
		kind: 'normalReview',
	});
	useEffect((): void => {
		if (!isActive) {
			setFacetMenuOpen(false);
			setViewSettingsMenuOpen(false);
		}
	}, [isActive]);
	const codeViewOptions = useMemo(
		() =>
			deriveBridgeReviewCodeViewOptions({
				compatibilityOptions: bridgeCodeViewOptions,
				viewSettings,
			}),
		[viewSettings],
	);
	const [treeSelectionRevealRequest, setTreeSelectionRevealRequest] =
		useState<BridgeReviewTreeSelectionRevealRequest | null>(null);
	const treeSelectionRevealRevisionRef = useRef(0);
	const codeViewControlHandleRef = useRef<BridgeCodeViewControlHandle | null>(null);
	const controlProbeSequenceRef = useRef(0);
	const isActiveRef = useRef(isActive);
	const wasReviewViewportActiveRef = useRef(isActive);
	isActiveRef.current = isActive;
	useEffect((): void => {
		if (catalogSnapshot.epoch === null) return;
		updateReviewDisplayProjection({ categoryFilter, gitStatusFilter, showBinary, showLarge });
	}, [
		catalogSnapshot.epoch,
		categoryFilter,
		gitStatusFilter,
		showBinary,
		showLarge,
		updateReviewDisplayProjection,
	]);
	useEffect((): (() => void) => startBridgeFrameLivenessProbe(), []);
	useEffect(
		(): (() => void) =>
			startBridgeFrameJankProbe({
				onJankSample: (sample): void => {
					recordBridgeFrameJankTelemetrySample({
						...sample,
						telemetryRecorder: telemetryRecorderRef.current,
						traceContext: null,
						viewer: 'review',
						viewerIsActive: isActiveRef.current,
					});
				},
			}),
		[telemetryRecorderRef],
	);
	useEffect((): void => {
		// The bounded Review display contract intentionally carries no native stream identity.
		// Active-surface mode is still sent through the pane client; do not fabricate a stream id.
		onActiveSourceChange(null);
	}, [onActiveSourceChange]);
	useEffect((): void => {
		onNavigationSourceChange(bridgeAppReviewNavigationSourceForDisplaySlice(reviewSourceSlice));
	}, [onNavigationSourceChange, reviewSourceSlice]);
	useEffect((): void => {
		const wasActive = wasReviewViewportActiveRef.current;
		wasReviewViewportActiveRef.current = isActive;
		if (wasActive && !isActive) {
			emitHoveredReviewItemIntent(null);
			setReviewCodeViewVisibleItemIds([]);
			setReviewTreeVisibleItemIds([]);
		}
	}, [
		emitHoveredReviewItemIntent,
		isActive,
		setReviewCodeViewVisibleItemIds,
		setReviewTreeVisibleItemIds,
	]);
	const publishCodeViewVisibleItemIds = useCallback(
		(itemIds: readonly string[]): void => {
			if (isActive) setReviewCodeViewVisibleItemIds(itemIds);
		},
		[isActive, setReviewCodeViewVisibleItemIds],
	);
	const publishTreeVisibleItemIds = useCallback(
		(itemIds: readonly string[]): void => {
			if (isActive) setReviewTreeVisibleItemIds(itemIds);
		},
		[isActive, setReviewTreeVisibleItemIds],
	);
	const publishHoveredReviewItemId = useCallback(
		(itemId: string | null): void => {
			if (isActive) emitHoveredReviewItemIntent(itemId);
		},
		[emitHoveredReviewItemIntent, isActive],
	);
	const applyTreeSearchActions = useCallback(
		(actions: readonly BridgeViewerSearchAction[]): BridgeViewerSearchRejectionReason | null => {
			let nextState = treeSearchStateRef.current;
			for (const action of actions) {
				const transition = transitionBridgeViewerSearchState(nextState, action);
				if (transition.rejectionReason !== null) {
					setTreeSearchRejectionMessage('Search query is too long');
					return transition.rejectionReason;
				}
				nextState = transition.state;
			}
			setTreeSearchRejectionMessage(null);
			treeSearchStateRef.current = nextState;
			setTreeSearchState(nextState);
			return null;
		},
		[],
	);
	const toggleTreeSearch = useCallback((): void => {
		applyTreeSearchActions([{ type: treeSearchStateRef.current.isOpen ? 'close' : 'open' }]);
	}, [applyTreeSearchActions]);
	const toggleFacetMenu = useCallback(
		(): void => setFacetMenuOpen((isOpen): boolean => !isOpen),
		[],
	);
	useBridgeViewerToolbarShortcuts({
		isActive,
		onToggleFilters: toggleFacetMenu,
		onToggleSearch: toggleTreeSearch,
		target,
	});
	const updateTreeSearchTextFromActiveTree = useCallback(
		(searchText: string): void => {
			if (!isActiveRef.current) {
				return;
			}
			applyTreeSearchActions([{ type: 'change_query', query: searchText }]);
		},
		[applyTreeSearchActions],
	);
	const updateTreeSearchMode = useCallback(
		(mode: BridgeReviewSearchMode): void => {
			applyTreeSearchActions([{ type: 'change_mode', mode: mode.kind }]);
		},
		[applyTreeSearchActions],
	);
	const clearOrCloseTreeSearch = useCallback((): void => {
		applyTreeSearchActions([{ type: 'clear_or_close' }]);
	}, [applyTreeSearchActions]);
	const closeTreeSearch = useCallback((): void => {
		applyTreeSearchActions([{ type: 'close' }]);
	}, [applyTreeSearchActions]);
	const presentationSnapshot = useMemo(
		() =>
			bridgeReviewPresentationSnapshotForDisplay({
				catalogSnapshot,
				displayStore,
				reviewSourceSlice,
			}),
		[catalogSnapshot, displayStore, reviewSourceSlice],
	);
	const comparisonPaneState = bridgeReviewComparisonPaneState({
		comparisonPresentation: panelChromeSlice.reviewComparison,
		displayedReviewPackage: presentationSnapshot?.reviewPackage ?? null,
	});
	const comparisonIsLoading = bridgeReviewComparisonPaneIsLoading(comparisonPaneState);
	const contentHeaderControls = (
		<>
			<BridgeReviewComparisonControl
				comparisonPresentation={panelChromeSlice.reviewComparison}
				displayedReviewPackage={presentationSnapshot?.reviewPackage ?? null}
				disabled={comparisonIsLoading}
				isActive={isActive}
				onApplyTarget={controller.updateReviewComparisonTarget}
				onCancelTargetQuery={cancelReviewComparisonTargetsQuery}
				onQueryTargets={queryReviewComparisonTargets}
				targetQueryState={comparisonTargetsQueryState}
			/>
			<BridgeReviewProjectionMenu
				disabled={comparisonIsLoading}
				onProjectionModeChange={setProjectionMode}
				projectionMode={projectionMode}
			/>
			{isActive ? (
				<BridgeViewerViewSettingsMenu
					defaultSettings={bridgeReviewDefaultViewSettings}
					disabled={comparisonIsLoading}
					onChange={setViewSettings}
					onOpenChange={setViewSettingsMenuOpen}
					open={viewSettingsMenuOpen}
					settings={viewSettings}
					surface="review"
				/>
			) : null}
		</>
	);
	const reviewGeneration = presentationSnapshot?.reviewPackage.reviewGeneration ?? null;
	const reviewPackageId = presentationSnapshot?.reviewPackage.packageId ?? null;
	const orderedItemIds = presentationSnapshot?.reviewPackage.orderedItemIds ?? [];
	const selectionController = useBridgeReviewSelectionController({
		commitLocalSelection: commitSelectedReviewItemId,
		emitSelectIntent: emitSelectedReviewItemIntent,
		hasReviewItem: (itemId): boolean => displayStore.getReviewItemSnapshot(itemId) !== undefined,
		isActive,
		markFileViewed,
		selectedItemId,
		telemetryRecorderRef,
	});
	const selectReviewItem = selectionController.selectReviewItem;
	const clearReviewSelection = useCallback((): void => {
		clearSelectedReviewItemId();
		const treeFallback = document.querySelector('[data-testid="bridge-review-trees-panel"]');
		if (treeFallback instanceof HTMLElement) treeFallback.focus({ preventScroll: true });
	}, [clearSelectedReviewItemId]);
	const selectReviewItemAndRevealTree = useCallback(
		(itemId: string, selectedSource: Parameters<typeof selectReviewItem>[1] = 'user'): boolean => {
			if (!selectReviewItem(itemId, selectedSource)) {
				return false;
			}
			if (reviewGeneration === null || reviewPackageId === null) {
				return true;
			}
			treeSelectionRevealRevisionRef.current += 1;
			setTreeSelectionRevealRequest({
				itemId,
				packageId: reviewPackageId,
				reviewGeneration,
				revision: treeSelectionRevealRevisionRef.current,
			});
			return true;
		},
		[reviewGeneration, reviewPackageId, selectReviewItem],
	);
	const onTargetOutsideAcceptedProjection = useCallback((): void => {}, []);
	useBridgeReviewControlEventListeners({
		codeViewControlHandleRef,
		controlProbeSequenceRef,
		categoryFilter,
		gitStatusFilter,
		isActive,
		onSearchRejected: (): void => setTreeSearchRejectionMessage('Search query is too long'),
		projection: presentationSnapshot?.projection ?? null,
		reviewPackage: presentationSnapshot?.reviewPackage ?? null,
		selectedItemId,
		selectReviewItem: selectReviewItemAndRevealTree,
		applyTreeSearchActions,
		setReviewFilter,
		target,
		treeSearchStateRef,
		treeSearchState,
		showBinary,
		showLarge,
	});
	useBridgeReviewNavigationController({
		catalogRevision: catalogSnapshot.revision,
		clearReviewSelection,
		getReviewItem: displayStore.getReviewItemSnapshot,
		isActive,
		isNavigationCommandStillEligible,
		navigationCommand,
		onTargetOutsideAcceptedProjection,
		orderedItemIds,
		selectedItemId,
		selectInitialReviewItem: selectReviewItem,
		selectReviewItem: selectReviewItemAndRevealTree,
	});
	const presentationState = reviewPresentationState({
		codeViewOptions,
		codeViewWorkerFactory,
		codeViewWorkerPoolEnabled,
		panelChromeSlice,
		comparisonPaneState,
		onRetryComparison: controller.updateReviewComparisonTarget,
		projectionMode,
		codeViewControlHandleRef,
		facetMenuOpen,
		categoryFilter,
		gitStatusFilter,
		showBinary,
		showLarge,
		presentationPositionKey,
		presentationSnapshot,
		renderFulfillmentCoordinator: reviewClient.renderFulfillmentCoordinator,
		reviewSourceSlice,
		selectedCodeViewItem,
		selectedContentAvailability,
		selectedItemId,
		selectedReviewItem,
		selectReviewItem: selectReviewItemAndRevealTree,
		setReviewCodeViewVisibleItemIds: publishCodeViewVisibleItemIds,
		setReviewViewportItemIds: publishTreeVisibleItemIds,
		telemetryRecorder: telemetryRecorderRef.current,
		treeAcceptedSearchMode: { kind: treeSearchState.acceptedCriteria.mode },
		treeAcceptedSearchText: treeSearchState.acceptedCriteria.query,
		treeSearchError: treeSearchState.error,
		treeSearchMode: { kind: treeSearchState.enteredCriteria.mode },
		treeSearchOpen: treeSearchState.isOpen,
		treeSearchText: treeSearchState.enteredCriteria.query,
		treeSearchStatusMessage: treeSearchRejectionMessage,
		treeSelectionRevealRequest,
		visibleCodeViewItems,
		onTreeSearchClear: clearOrCloseTreeSearch,
		onTreeSearchClose: closeTreeSearch,
		onTreeSearchModeChange: updateTreeSearchMode,
		onTreeSearchToggle: toggleTreeSearch,
		onTreeSearchTextChange: updateTreeSearchTextFromActiveTree,
		onFacetMenuOpenChange: setFacetMenuOpen,
		onFilterChange: setReviewFilter,
		onHoveredItemIdChange: publishHoveredReviewItemId,
	});
	return (
		<BridgeReviewViewerShellBoundary
			comparisonPaneState={comparisonPaneState}
			isActive={isActive}
			onRetryComparison={controller.updateReviewComparisonTarget}
			presentationState={presentationState}
			viewerContextSwitcher={viewerContextSwitcher}
			viewerHeaderControls={contentHeaderControls}
		/>
	);
}

function reviewPresentationState(props: {
	readonly comparisonPaneState: ReturnType<typeof bridgeReviewComparisonPaneState>;
	readonly onRetryComparison: BridgeReviewRenderSnapshotController['updateReviewComparisonTarget'];
	readonly codeViewOptions: ReturnType<typeof deriveBridgeReviewCodeViewOptions>;
	readonly codeViewWorkerFactory: (() => Worker) | undefined;
	readonly codeViewWorkerPoolEnabled: boolean | undefined;
	readonly panelChromeSlice: BridgeReviewRenderSnapshotController['panelChromeSlice'];
	readonly projectionMode: BridgeReviewProjectionMode;
	readonly codeViewControlHandleRef: { current: BridgeCodeViewControlHandle | null };
	readonly facetMenuOpen: boolean;
	readonly categoryFilter: BridgeReviewFilterCandidate['categoryFilter'];
	readonly gitStatusFilter: BridgeFileChangeKind | 'all';
	readonly showBinary: boolean;
	readonly showLarge: boolean;
	readonly presentationPositionKey: string;
	readonly presentationSnapshot: ReturnType<typeof bridgeReviewPresentationSnapshotForDisplay>;
	readonly renderFulfillmentCoordinator: BridgePaneSurfaceClient['renderFulfillmentCoordinator'];
	readonly reviewSourceSlice: BridgeReviewRenderSnapshotController['reviewSourceSlice'];
	readonly selectedCodeViewItem: BridgeReviewRenderSnapshotController['selectedCodeViewItem'];
	readonly selectedContentAvailability: BridgeReviewRenderSnapshotController['selectedContentAvailability'];
	readonly selectedItemId: string | null;
	readonly selectedReviewItem: BridgeReviewRenderSnapshotController['selectedReviewItem'];
	readonly selectReviewItem: (itemId: string) => boolean;
	readonly setReviewCodeViewVisibleItemIds: (itemIds: readonly string[]) => void;
	readonly setReviewViewportItemIds: (itemIds: readonly string[]) => void;
	readonly telemetryRecorder: BridgeTelemetryRecorder;
	readonly treeAcceptedSearchMode: BridgeReviewSearchMode;
	readonly treeAcceptedSearchText: string;
	readonly treeSearchError: BridgeViewerSearchError | null;
	readonly treeSearchMode: BridgeReviewSearchMode;
	readonly treeSearchOpen: boolean;
	readonly treeSearchText: string;
	readonly treeSearchStatusMessage: string | null;
	readonly treeSelectionRevealRequest: BridgeReviewTreeSelectionRevealRequest | null;
	readonly visibleCodeViewItems: BridgeReviewRenderSnapshotController['visibleCodeViewItems'];
	readonly onTreeSearchClear: () => void;
	readonly onTreeSearchClose: () => void;
	readonly onTreeSearchModeChange: (mode: BridgeReviewSearchMode) => void;
	readonly onTreeSearchToggle: () => void;
	readonly onTreeSearchTextChange: (searchText: string) => void;
	readonly onFacetMenuOpenChange: (isOpen: boolean) => void;
	readonly onFilterChange: (filter: BridgeReviewFilterCandidate) => void;
	readonly onHoveredItemIdChange: (itemId: string | null) => void;
}): BridgeReviewViewerPresentationState {
	if (props.reviewSourceSlice === null) return { status: 'empty' };
	if (props.reviewSourceSlice.status === 'failed') {
		return { error: 'Review metadata is unavailable', status: 'metadataFailed' };
	}
	if (props.reviewSourceSlice.status === 'loading') return { status: 'metadataLoading' };
	if (props.presentationSnapshot === null) return { status: 'projectionPending' };
	const selectedUnavailablePath = reviewSelectedUnavailablePath(props);
	const selectedContentIsLoading =
		props.selectedItemId !== null &&
		props.selectedCodeViewItem === null &&
		selectedUnavailablePath === null;
	return {
		presentationKey: props.presentationSnapshot.presentationKey,
		shellProps: {
			comparisonPaneState: props.comparisonPaneState,
			codeViewOptions: props.codeViewOptions,
			facetMenuOpen: props.facetMenuOpen,
			categoryFilter: props.categoryFilter,
			gitStatusFilter: props.gitStatusFilter,
			showBinary: props.showBinary,
			showLarge: props.showLarge,
			onCodeViewControlHandleChange: (handle): void => {
				props.codeViewControlHandleRef.current = handle;
			},
			onFilterChange: props.onFilterChange,
			onFacetMenuOpenChange: props.onFacetMenuOpenChange,
			onHoveredItemIdChange: props.onHoveredItemIdChange,
			onRetryComparison: props.onRetryComparison,
			panelChromeSlice: props.panelChromeSlice,
			projectionMode: props.projectionMode,
			presentationPositionKey: props.presentationPositionKey,
			presentationRegistry: props.presentationSnapshot.presentationRegistry,
			renderFulfillmentCoordinator: props.renderFulfillmentCoordinator,
			onCodeViewVisibleItemIdsChange: props.setReviewCodeViewVisibleItemIds,
			onTreeSearchModeChange: props.onTreeSearchModeChange,
			onTreeSearchClear: props.onTreeSearchClear,
			onTreeSearchClose: props.onTreeSearchClose,
			onTreeSearchToggle: props.onTreeSearchToggle,
			onTreeSearchTextChange: props.onTreeSearchTextChange,
			onSelectItem: (itemId): void => {
				props.selectReviewItem(itemId);
			},
			onTreeVisibleItemIdsChange: props.setReviewViewportItemIds,
			projection: props.presentationSnapshot.projection,
			reviewPackage: props.presentationSnapshot.reviewPackage,
			reviewTreeRows: props.presentationSnapshot.reviewTreeRows,
			selectedCanvasLoadingReason: selectedContentIsLoading ? 'content' : null,
			selectedCodeViewItem: props.selectedCodeViewItem,
			selectedContentLoadingItemId: selectedContentIsLoading ? props.selectedItemId : null,
			selectedContentUnavailablePath: selectedUnavailablePath,
			selectedItemId: props.selectedItemId,
			telemetryRecorder: props.telemetryRecorder,
			treeSearchMode: props.treeSearchMode,
			treeSearchOpen: props.treeSearchOpen,
			treeSearchText: props.treeSearchText,
			treeSearchStatusMessage: props.treeSearchStatusMessage,
			treeAcceptedSearchMode: props.treeAcceptedSearchMode,
			treeAcceptedSearchText: props.treeAcceptedSearchText,
			treeSearchError: props.treeSearchError,
			treeSelectionRevealRequest: props.treeSelectionRevealRequest,
			visibleCodeViewItems: props.visibleCodeViewItems,
			...(props.codeViewWorkerFactory === undefined
				? {}
				: { codeViewWorkerFactory: props.codeViewWorkerFactory }),
			...(props.codeViewWorkerPoolEnabled === undefined
				? {}
				: { codeViewWorkerPoolEnabled: props.codeViewWorkerPoolEnabled }),
		},
		status: 'ready',
	};
}

function reviewSelectedUnavailablePath(
	props: Pick<
		Parameters<typeof reviewPresentationState>[0],
		'presentationSnapshot' | 'selectedContentAvailability' | 'selectedItemId' | 'selectedReviewItem'
	>,
): string | null {
	if (
		props.selectedItemId === null ||
		props.presentationSnapshot === null ||
		props.selectedContentAvailability === null ||
		!['failed', 'unavailable'].includes(props.selectedContentAvailability.state)
	) {
		return null;
	}
	return (
		props.selectedReviewItem?.metadata.headPath ??
		props.selectedReviewItem?.metadata.basePath ??
		props.presentationSnapshot.projection.primaryDisplayPathByItemId[props.selectedItemId] ??
		props.selectedItemId
	);
}

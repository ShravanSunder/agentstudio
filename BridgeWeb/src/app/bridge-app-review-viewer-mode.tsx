import { useCallback, useEffect, useId, useMemo, useRef, useState, type ReactElement } from 'react';

import type { BridgePaneSurfaceClient } from '../core/comm-worker/bridge-pane-runtime.js';
import type { BridgeActiveViewerSource } from '../core/comm-worker/bridge-product-control-contracts.js';
import { startBridgeFrameJankProbe } from '../foundation/diagnostics/bridge-frame-jank-probe.js';
import { startBridgeFrameLivenessProbe } from '../foundation/diagnostics/bridge-frame-liveness-probe.js';
import type {
	BridgeFileChangeKind,
	BridgeFileClass,
} from '../foundation/review-package/bridge-review-package.js';
import type { BridgeTelemetryRecorder } from '../foundation/telemetry/bridge-telemetry-recorder.js';
import { recordBridgeFrameJankTelemetrySample } from '../foundation/telemetry/bridge-viewer-telemetry-adapter.js';
import type { BridgeCodeViewControlHandle } from '../review-viewer/code-view/bridge-code-view-panel.js';
import type { BridgeReviewSearchMode } from '../review-viewer/models/review-projection-models.js';
import type { BridgeReviewTreeSelectionRevealRequest } from '../review-viewer/trees/bridge-trees-panel.js';
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
import type { BridgeViewerNavigationCommand } from './bridge-viewer-navigation-models.js';
import { useBridgeReviewControlEventListeners } from './use-bridge-review-control-event-listeners.js';

export interface BridgeReviewViewerModeProps {
	readonly codeViewWorkerFactory?: () => Worker;
	readonly codeViewWorkerPoolEnabled?: boolean;
	readonly isActive: boolean;
	readonly navigationCommand?: BridgeViewerNavigationCommand;
	readonly onActiveSourceChange: (activeSource: BridgeActiveViewerSource | null) => void;
	readonly reviewClient: BridgePaneSurfaceClient;
	readonly target?: EventTarget;
	readonly telemetryRecorderRef: { readonly current: BridgeTelemetryRecorder };
	readonly viewerHeaderControls: ReactElement;
}

export function BridgeReviewViewerMode(props: BridgeReviewViewerModeProps): ReactElement {
	const {
		codeViewWorkerFactory,
		codeViewWorkerPoolEnabled,
		isActive,
		navigationCommand,
		onActiveSourceChange,
		reviewClient,
		target = document,
		telemetryRecorderRef,
		viewerHeaderControls,
	} = props;
	const pierreCourier = useMemo(() => createBridgeReviewWorkerPierreCourier(), []);
	const presentationPositionKey = useId();
	const controller = useBridgeReviewRenderSnapshotController({
		pierreCourier,
		reviewClient,
	});
	const catalogSnapshot = controller.catalogSnapshot;
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
	const visibleCodeViewItems = controller.visibleCodeViewItems;
	const [treeSearchMode, setTreeSearchMode] = useState<BridgeReviewSearchMode>({ kind: 'text' });
	const [treeSearchOpen, setTreeSearchOpen] = useState(false);
	const [treeSearchText, setTreeSearchText] = useState('');
	const [gitStatusFilter, setGitStatusFilter] = useState<BridgeFileChangeKind | 'all'>('all');
	const [fileClassFilter, setFileClassFilter] = useState<BridgeFileClass | 'all'>('all');
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
		updateReviewDisplayProjection({ fileClassFilter, gitStatusFilter });
	}, [catalogSnapshot.epoch, fileClassFilter, gitStatusFilter, updateReviewDisplayProjection]);
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
	const openTreeSearch = useCallback((): void => {
		setTreeSearchOpen(true);
	}, []);
	const updateTreeSearchTextFromActiveTree = useCallback((searchText: string): void => {
		if (!isActiveRef.current) {
			return;
		}
		if (searchText.length === 0) {
			setTreeSearchOpen(false);
		}
		setTreeSearchText(searchText);
	}, []);
	const presentationSnapshot = useMemo(
		() =>
			bridgeReviewPresentationSnapshotForDisplay({
				catalogSnapshot,
				displayStore,
				reviewSourceSlice,
			}),
		[catalogSnapshot, displayStore, reviewSourceSlice],
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
	});
	const selectReviewItem = selectionController.selectReviewItem;
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
		fileClassFilter,
		gitStatusFilter,
		isActive,
		projection: presentationSnapshot?.projection ?? null,
		reviewPackage: presentationSnapshot?.reviewPackage ?? null,
		selectedItemId,
		selectReviewItem: selectReviewItemAndRevealTree,
		setFileClassFilter,
		setGitStatusFilter,
		setTreeSearchMode,
		setTreeSearchOpen,
		setTreeSearchText,
		target,
		treeSearchMode,
		treeSearchText,
	});
	useBridgeReviewNavigationController({
		catalogRevision: catalogSnapshot.revision,
		clearReviewSelection: clearSelectedReviewItemId,
		getReviewItem: displayStore.getReviewItemSnapshot,
		isActive,
		navigationCommand,
		onTargetOutsideAcceptedProjection,
		orderedItemIds,
		selectedItemId,
		selectInitialReviewItem: selectReviewItem,
		selectReviewItem: selectReviewItemAndRevealTree,
	});
	const presentationState = reviewPresentationState({
		codeViewWorkerFactory,
		codeViewWorkerPoolEnabled,
		panelChromeSlice,
		codeViewControlHandleRef,
		fileClassFilter,
		gitStatusFilter,
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
		treeSearchMode,
		treeSearchOpen,
		treeSearchText,
		treeSelectionRevealRequest,
		visibleCodeViewItems,
		onTreeSearchModeChange: setTreeSearchMode,
		onTreeSearchOpen: openTreeSearch,
		onTreeSearchTextChange: updateTreeSearchTextFromActiveTree,
		onFileClassFilterChange: setFileClassFilter,
		onGitStatusFilterChange: setGitStatusFilter,
		onHoveredItemIdChange: publishHoveredReviewItemId,
	});
	return (
		<BridgeReviewViewerShellBoundary
			isActive={isActive}
			presentationState={presentationState}
			viewerHeaderControls={viewerHeaderControls}
		/>
	);
}

function reviewPresentationState(props: {
	readonly codeViewWorkerFactory: (() => Worker) | undefined;
	readonly codeViewWorkerPoolEnabled: boolean | undefined;
	readonly panelChromeSlice: BridgeReviewRenderSnapshotController['panelChromeSlice'];
	readonly codeViewControlHandleRef: { current: BridgeCodeViewControlHandle | null };
	readonly fileClassFilter: BridgeFileClass | 'all';
	readonly gitStatusFilter: BridgeFileChangeKind | 'all';
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
	readonly treeSearchMode: BridgeReviewSearchMode;
	readonly treeSearchOpen: boolean;
	readonly treeSearchText: string;
	readonly treeSelectionRevealRequest: BridgeReviewTreeSelectionRevealRequest | null;
	readonly visibleCodeViewItems: BridgeReviewRenderSnapshotController['visibleCodeViewItems'];
	readonly onTreeSearchModeChange: (mode: BridgeReviewSearchMode) => void;
	readonly onTreeSearchOpen: () => void;
	readonly onTreeSearchTextChange: (searchText: string) => void;
	readonly onFileClassFilterChange: (filter: BridgeFileClass | 'all') => void;
	readonly onGitStatusFilterChange: (filter: BridgeFileChangeKind | 'all') => void;
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
			fileClassFilter: props.fileClassFilter,
			gitStatusFilter: props.gitStatusFilter,
			onCodeViewControlHandleChange: (handle): void => {
				props.codeViewControlHandleRef.current = handle;
			},
			onFileClassFilterChange: props.onFileClassFilterChange,
			onGitStatusFilterChange: props.onGitStatusFilterChange,
			onHoveredItemIdChange: props.onHoveredItemIdChange,
			panelChromeSlice: props.panelChromeSlice,
			presentationPositionKey: props.presentationPositionKey,
			presentationRegistry: props.presentationSnapshot.presentationRegistry,
			renderFulfillmentCoordinator: props.renderFulfillmentCoordinator,
			onCodeViewVisibleItemIdsChange: props.setReviewCodeViewVisibleItemIds,
			onTreeSearchModeChange: props.onTreeSearchModeChange,
			onTreeSearchOpen: props.onTreeSearchOpen,
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

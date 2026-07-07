import type { MutableRefObject, ReactElement } from 'react';
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';

import type { BridgePageHandshakeSession } from '../bridge/bridge-page-handshake.js';
import {
	createBridgeRPCClient,
	type BridgeActiveViewerSource,
} from '../bridge/bridge-rpc-client.js';
import type { ReviewTreeRowMetadata } from '../features/review/models/review-protocol-models.js';
import { startBridgeFrameJankProbe } from '../foundation/diagnostics/bridge-frame-jank-probe.js';
import { startBridgeFrameLivenessProbe } from '../foundation/diagnostics/bridge-frame-liveness-probe.js';
import type { BridgeReviewPackage } from '../foundation/review-package/bridge-review-package.js';
import type { BridgeTelemetryBootstrapConfig } from '../foundation/telemetry/bridge-telemetry-bootstrap-config.js';
import type {
	BridgeTelemetryFlushProps,
	BridgeTelemetryRecorder,
} from '../foundation/telemetry/bridge-telemetry-recorder.js';
import type { BridgeTraceContext } from '../foundation/telemetry/bridge-trace-context.js';
import type { BridgeCodeViewControlHandle } from '../review-viewer/code-view/bridge-code-view-panel.js';
import type { ReviewContentDemandTelemetry } from '../review-viewer/content/review-content-demand-types.js';
import { useBridgeReviewProjectionCoordinator } from '../review-viewer/projections/use-review-projection-coordinator.js';
import {
	selectBridgeReviewPanelChromeSlice,
	useBridgeReviewViewerStoreSelector,
} from '../review-viewer/state/review-viewer-store.js';
import { createBridgeMarkdownRenderWebWorkerClient } from '../review-viewer/workers/markdown/bridge-markdown-render-worker-transport.js';
import type { BridgeReviewProjectionWorkerClient } from '../review-viewer/workers/projection/review-projection-worker-client.js';
import { createBridgeReviewProjectionWebWorkerClient } from '../review-viewer/workers/projection/review-projection-worker-transport.js';
import type { BridgeDiffStatusState } from './bridge-app-review-controller.js';
import { useBridgeReviewDemandTelemetryController } from './bridge-app-review-demand-telemetry-controller.js';
import {
	readBridgeReviewFrameAuthority,
	refreshBridgeReviewFrameAuthority,
	type BridgeReviewFrameAuthority,
} from './bridge-app-review-frame-authority.js';
import { useBridgeReviewIntakeController } from './bridge-app-review-intake-controller.js';
import { useBridgeReviewMarkdownPreviewController } from './bridge-app-review-markdown-preview-controller.js';
import { useBridgeReviewMetadataInterestRuntime } from './bridge-app-review-metadata-interest-runtime.js';
import { useBridgeReviewNavigationController } from './bridge-app-review-navigation-controller.js';
import {
	createBridgeReviewWorkerPierreCourier,
	useBridgeReviewRenderSnapshotController,
} from './bridge-app-review-render-snapshot-controller.js';
import {
	useBridgeResourceDescriptorRegistry,
	useBridgeReviewViewerStore,
} from './bridge-app-review-runtime.js';
import { useBridgeReviewSelectionController } from './bridge-app-review-selection-controller.js';
import {
	makeSelectedContentResourcesKey,
	reviewFileTargetForNavigationCommand,
	selectedCanvasLoadingReasonForCurrentSelection,
	selectedContentUnavailablePathForCurrentSelection,
	selectedItemPresentationForReviewFileTarget,
	type BridgeReviewFileNavigationTarget,
	type SelectedMarkdownPreviewState,
} from './bridge-app-review-selection-state.js';
import { useBridgeReviewRenderTelemetryController } from './bridge-app-review-telemetry-controller.js';
import {
	createChildTraceContext,
	type BridgeReviewPackageTelemetryContext,
} from './bridge-app-review-telemetry.js';
import { BridgeReviewViewerShellBoundary } from './bridge-app-review-viewer-shell-boundary.js';
import type { BridgeAppProps } from './bridge-app.js';
import { useBridgeReviewControlEventListeners } from './use-bridge-review-control-event-listeners.js';

export function BridgeReviewViewerMode(
	props: BridgeAppProps & {
		readonly handshakeSessionRef: MutableRefObject<BridgePageHandshakeSession | null>;
		readonly isActive: boolean;
		readonly onActiveSourceChange: (activeSource: BridgeActiveViewerSource | null) => void;
		readonly registerBridgeReadyCallback: (callback: () => void) => () => void;
		readonly telemetryConfig: BridgeTelemetryBootstrapConfig | null;
		readonly telemetryRecorderRef: MutableRefObject<BridgeTelemetryRecorder>;
		readonly viewerHeaderControls: ReactElement;
	},
): ReactElement {
	const target = props.target ?? document;
	const reviewFrameAuthorityRef = useRef<BridgeReviewFrameAuthority | null>(
		readBridgeReviewFrameAuthority(),
	);
	const getReviewFrameAuthority = useCallback(
		(): BridgeReviewFrameAuthority | null =>
			refreshBridgeReviewFrameAuthority(reviewFrameAuthorityRef),
		[],
	);
	const viewerStore = useBridgeReviewViewerStore();
	const descriptorRegistry = useBridgeResourceDescriptorRegistry();
	const reviewEnvelopeApplyTailRef = useRef<Promise<void>>(Promise.resolve());
	const projection = useBridgeReviewViewerStoreSelector(viewerStore, (state) => state.projection);
	const panelChromeSlice = useBridgeReviewViewerStoreSelector(
		viewerStore,
		selectBridgeReviewPanelChromeSlice,
	);
	const viewerActions = useBridgeReviewViewerStoreSelector(viewerStore, (state) => state.actions);
	const [reviewPackage, setReviewPackage] = useState<BridgeReviewPackage | null>(null);
	const [reviewTreeRows, setReviewTreeRowsState] = useState<readonly ReviewTreeRowMetadata[]>([]);
	const reviewTreeRowsRef = useRef<readonly ReviewTreeRowMetadata[]>(reviewTreeRows);
	reviewTreeRowsRef.current = reviewTreeRows;
	const setReviewTreeRows = useCallback((rows: readonly ReviewTreeRowMetadata[]): void => {
		reviewTreeRowsRef.current = rows;
		setReviewTreeRowsState((): readonly ReviewTreeRowMetadata[] => rows);
	}, []);
	const getReviewTreeRows = useCallback(
		(): readonly ReviewTreeRowMetadata[] => reviewTreeRowsRef.current,
		[],
	);
	const pierreCourier = useMemo(() => createBridgeReviewWorkerPierreCourier(), []);
	const {
		invalidateReviewContent,
		rootSnapshot,
		selectedCodeViewItem,
		selectedContentAvailability,
		selectionSlice,
		selectionSliceRef,
		setReviewViewportItemIds,
		setSelectedReviewItemId,
		synchronizeReviewSource,
		visibleCodeViewItems,
		viewportSliceRef,
	} = useBridgeReviewRenderSnapshotController({
		panelChromeSlice,
		pierreCourier,
		reviewPackage,
		reviewTreeRows,
		telemetryConfig: props.telemetryConfig,
		...(props.reviewWorkerTransportFactory === undefined
			? {}
			: { transportFactory: props.reviewWorkerTransportFactory }),
	});
	const setReviewRenderModeCodeView = useCallback((): void => {
		if (viewerStore.getState().panelChromeSlice.renderMode.kind === 'codeView') {
			return;
		}
		viewerActions.setRenderMode({ kind: 'codeView' });
	}, [viewerActions, viewerStore]);
	const [diffStatus, setDiffStatus] = useState<BridgeDiffStatusState>({
		status: 'idle',
		error: null,
		epoch: 0,
	});
	const [lastVisibleDemandTelemetry, setLastVisibleDemandTelemetry] =
		useState<ReviewContentDemandTelemetry | null>(null);
	const [selectedMarkdownPreviewState, setSelectedMarkdownPreviewState] =
		useState<SelectedMarkdownPreviewState | null>(null);
	const [selectedReviewFileTarget, setSelectedReviewFileTarget] =
		useState<BridgeReviewFileNavigationTarget | null>(null);
	const [bridgeReadyEpoch, setBridgeReadyEpoch] = useState(0);
	const selectedMarkdownPreviewStateRef = useRef<SelectedMarkdownPreviewState | null>(null);
	selectedMarkdownPreviewStateRef.current = selectedMarkdownPreviewState;
	const [isTreeSearchOpen, setIsTreeSearchOpen] = useState(false);
	const telemetryRecorderRef = props.telemetryRecorderRef;
	const bridgeHandshakeSessionRef = props.handshakeSessionRef;
	const onActiveSourceChange = props.onActiveSourceChange;
	const registerBridgeReadyCallback = props.registerBridgeReadyCallback;
	const currentReviewPackageTelemetryContextRef =
		useRef<BridgeReviewPackageTelemetryContext | null>(null);
	const [lastSelectedDemandTelemetry, setLastSelectedDemandTelemetry] =
		useState<ReviewContentDemandTelemetry | null>(null);
	const reviewPackageTelemetryContextRef = useRef<Map<string, BridgeReviewPackageTelemetryContext>>(
		new Map(),
	);
	const reviewReadyStartMillisecondsByPackageKeyRef = useRef<Map<string, number>>(new Map());
	const codeViewControlHandleRef = useRef<BridgeCodeViewControlHandle | null>(null);
	const reviewPackageRef = useRef<BridgeReviewPackage | null>(null);
	reviewPackageRef.current = reviewPackage;
	const projectionRef = useRef(projection);
	projectionRef.current = projection;
	const rootSnapshotRef = useRef(rootSnapshot);
	rootSnapshotRef.current = rootSnapshot;
	const controlProbeSequenceRef = useRef(0);
	useEffect((): (() => void) => startBridgeFrameLivenessProbe(), []);
	useEffect((): (() => void) => startBridgeFrameJankProbe(), []);
	useEffect((): void => {
		const authority = getReviewFrameAuthority();
		if (reviewPackage === null || authority === null) {
			onActiveSourceChange(null);
			return;
		}
		onActiveSourceChange({
			protocol: 'review',
			streamId: authority.streamId,
			generation: reviewPackage.reviewGeneration,
		});
	}, [getReviewFrameAuthority, onActiveSourceChange, reviewPackage]);
	const rpcClient = useMemo(
		() =>
			createBridgeRPCClient({
				target,
				getTraceContext: (): BridgeTraceContext | null =>
					telemetryRecorderRef.current.isEnabled('web')
						? createChildTraceContext(
								currentReviewPackageTelemetryContextRef.current?.traceContext ?? null,
							)
						: null,
				telemetryRecorder: {
					isEnabled: (scope) => telemetryRecorderRef.current.isEnabled(scope),
					record: (sample) => telemetryRecorderRef.current.record(sample),
					measure: (measureProps) => telemetryRecorderRef.current.measure(measureProps),
					flush: (flushProps) => telemetryRecorderRef.current.flush(flushProps),
				},
			}),
		[target, telemetryRecorderRef],
	);
	const projectionWorkerClient = useMemo(
		(): BridgeReviewProjectionWorkerClient | null =>
			props.projectionWorkerClient === undefined
				? createBridgeReviewProjectionWebWorkerClient()
				: props.projectionWorkerClient,
		[props.projectionWorkerClient],
	);
	const defaultMarkdownWorkerClient = useMemo(
		() => createBridgeMarkdownRenderWebWorkerClient(),
		[],
	);
	const markdownWorkerClient =
		props.markdownWorkerClient === undefined
			? defaultMarkdownWorkerClient
			: props.markdownWorkerClient;
	const currentSelectedContentKey =
		reviewPackage === null || rootSnapshot.selectedItemId === null
			? null
			: makeSelectedContentResourcesKey(reviewPackage, rootSnapshot.selectedItemId);
	const initialReviewFileTarget = useMemo(
		() => reviewFileTargetForNavigationCommand(props.navigationCommand),
		[props.navigationCommand],
	);
	const selectedItemPresentation = useMemo(
		() =>
			selectedItemPresentationForReviewFileTarget({
				reviewPackage,
				selectedItemId: rootSnapshot.selectedItemId,
				target: selectedReviewFileTarget ?? initialReviewFileTarget,
			}),
		[initialReviewFileTarget, reviewPackage, rootSnapshot.selectedItemId, selectedReviewFileTarget],
	);
	const demandTelemetryController = useBridgeReviewDemandTelemetryController({
		lastSelectedDemandTelemetry,
		lastVisibleDemandTelemetry,
		reviewPackage,
		setLastSelectedDemandTelemetry,
		setLastVisibleDemandTelemetry,
	});
	const setReviewVisibleItemIds = useCallback(
		(itemIds: readonly string[]): void => {
			setReviewViewportItemIds(itemIds);
		},
		[setReviewViewportItemIds],
	);
	const reviewMetadataInterestRuntime = useBridgeReviewMetadataInterestRuntime({
		authority: getReviewFrameAuthority(),
		bridgeReadyEpoch,
		isActive: props.isActive,
		reviewPackage,
		rpcClient,
		selectedItemId: rootSnapshot.selectedItemId,
		setVisibleContentItemIds: setReviewVisibleItemIds,
	});
	useEffect(
		(): (() => void) =>
			registerBridgeReadyCallback((): void => {
				if (props.isActive) {
					setBridgeReadyEpoch((currentEpoch) => currentEpoch + 1);
				}
			}),
		[props.isActive, registerBridgeReadyCallback],
	);
	const flushTelemetry = useCallback(
		(flushProps: BridgeTelemetryFlushProps = {}): void => {
			telemetryRecorderRef.current.flush(flushProps);
		},
		[telemetryRecorderRef],
	);
	const {
		beginForegroundReviewSelection,
		lastSelectionCommitDurationMilliseconds,
		selectReviewItem,
	} = useBridgeReviewSelectionController({
		currentReviewPackageTelemetryContextRef,
		hasProjection: panelChromeSlice.hasProjection,
		isActive: props.isActive,
		reviewPackage,
		reviewPackageRef,
		selectionSlice,
		selectionSliceRef,
		viewportSliceRef,
		rpcClient,
		setReviewRenderModeCodeView,
		setSelectedReviewFileTarget,
		setSelectedReviewItemId,
		telemetryRecorderRef,
	});
	useBridgeReviewProjectionCoordinator({
		store: viewerStore,
		reviewPackage,
		projectionMode: rootSnapshot.projectionMode,
		facets: rootSnapshot.facets,
		gitStatusFilter: rootSnapshot.gitStatusFilter,
		fileClassFilter: rootSnapshot.fileClassFilter,
		projectionWorkerClient,
		telemetryRecorder: telemetryRecorderRef.current,
		telemetryParentTraceContext:
			currentReviewPackageTelemetryContextRef.current?.traceContext ?? null,
		flushTelemetry,
	});

	useBridgeReviewNavigationController({
		beginForegroundReviewSelection,
		initialReviewFileTarget,
		isActive: props.isActive,
		navigationCommand: props.navigationCommand,
		projection,
		reviewPackage,
		rootSnapshot,
		selectReviewItem,
		setReviewRenderModeCodeView,
		setSelectedReviewItemId,
		setSelectedMarkdownPreviewState,
		viewerActions,
	});

	useBridgeReviewIntakeController({
		target,
		isActive: props.isActive,
		bridgeHandshakeSessionRef,
		getReviewFrameAuthority,
		registerBridgeReadyCallback,
		reviewEnvelopeApplyTailRef,
		beginForegroundReviewSelection,
		setReviewPackage,
		getReviewTreeRows,
		setReviewTreeRows,
		setDiffStatus,
		setSelectedItemId: setSelectedReviewItemId,
		selectionSliceRef,
		reviewPackageRef,
		reviewPackageTelemetryContextRef,
		currentReviewPackageTelemetryContextRef,
		reviewReadyStartMillisecondsByPackageKeyRef,
		descriptorRegistry,
		dispatchReviewInvalidation: invalidateReviewContent,
		synchronizeReviewWorkerSource: synchronizeReviewSource,
		telemetryRecorderRef,
	});
	useBridgeReviewControlEventListeners({
		codeViewControlHandleRef,
		controlProbeSequenceRef,
		isActive: props.isActive,
		markdownWorkerClient,
		projectionRef,
		reviewPackageRef,
		rootSnapshotRef,
		selectedCodeViewItem,
		selectedMarkdownPreviewState,
		selectReviewItem,
		setTreeSearchOpen: setIsTreeSearchOpen,
		target,
		viewerActions,
		viewerStore,
	});

	useBridgeReviewMarkdownPreviewController({
		currentReviewPackageTelemetryContextRef,
		isActive: props.isActive,
		markdownWorkerClient,
		renderModeKind: rootSnapshot.renderMode.kind,
		reviewPackage,
		selectedCodeViewItem,
		selectedItemId: rootSnapshot.selectedItemId,
		selectedMarkdownPreviewStateRef,
		setRenderModeCodeView: setReviewRenderModeCodeView,
		setSelectedMarkdownPreviewState,
		telemetryRecorderRef,
	});

	useBridgeReviewRenderTelemetryController({
		hasProjection: projection !== null,
		isActive: props.isActive,
		reviewPackage,
		reviewPackageTelemetryContextRef,
		reviewReadyStartMillisecondsByPackageKeyRef,
		selectedCodeViewItem,
		telemetryRecorderRef,
	});

	const selectedCanvasLoadingReason = selectedCanvasLoadingReasonForCurrentSelection({
		selectedContentAvailability,
		selectedContentKey: currentSelectedContentKey,
		selectedItemId: rootSnapshot.selectedItemId,
		selectedMarkdownPreviewState,
	});
	const selectedContentLoadingItemId =
		selectedCanvasLoadingReason === 'content' ? rootSnapshot.selectedItemId : null;
	return (
		<BridgeReviewViewerShellBoundary
			codeViewWorkerFactory={props.codeViewWorkerFactory}
			codeViewWorkerPoolEnabled={props.codeViewWorkerPoolEnabled}
			currentSelectedContentKey={currentSelectedContentKey}
			diffStatus={diffStatus}
			isActive={props.isActive}
			lastSelectedDemandTelemetry={
				demandTelemetryController.lastSelectedDemandTelemetryForCurrentPackage
			}
			lastSelectionCommitDurationMilliseconds={lastSelectionCommitDurationMilliseconds}
			lastVisibleDemandTelemetry={
				demandTelemetryController.lastVisibleDemandTelemetryForCurrentPackage
			}
			onCodeViewControlHandleChange={(handle): void => {
				codeViewControlHandleRef.current = handle;
			}}
			onSelectItem={selectReviewItem}
			onTreeSearchOpen={(): void => setIsTreeSearchOpen(true)}
			projection={projection}
			reviewPackage={reviewPackage}
			reviewMetadataInterestRuntime={reviewMetadataInterestRuntime}
			reviewTreeRows={reviewTreeRows}
			rootSnapshot={rootSnapshot}
			selectedCanvasLoadingReason={selectedCanvasLoadingReason}
			selectedCodeViewItem={selectedCodeViewItem}
			selectedContentLoadingItemId={selectedContentLoadingItemId}
			selectedContentUnavailablePath={selectedContentUnavailablePathForCurrentSelection({
				reviewPackage,
				selectedContentAvailability,
				selectedItemId: rootSnapshot.selectedItemId,
			})}
			selectedItemPresentation={selectedItemPresentation}
			selectedMarkdownPreviewState={selectedMarkdownPreviewState}
			telemetryParentTraceContext={
				currentReviewPackageTelemetryContextRef.current?.traceContext ?? null
			}
			telemetryRecorder={telemetryRecorderRef.current}
			treeSearchOpen={isTreeSearchOpen}
			visibleCodeViewItems={visibleCodeViewItems}
			viewerActions={viewerActions}
			viewerHeaderControls={props.viewerHeaderControls}
		/>
	);
}

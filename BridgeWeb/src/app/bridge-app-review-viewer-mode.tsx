import type { MutableRefObject, ReactElement } from 'react';
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { useStore } from 'zustand';

import type { BridgePageHandshakeSession } from '../bridge/bridge-page-handshake.js';
import {
	createBridgeRPCClient,
	type BridgeActiveViewerSource,
} from '../bridge/bridge-rpc-client.js';
import type { BridgeDemandScheduler } from '../core/demand/bridge-demand-scheduler.js';
import type { BridgeDescriptorRef } from '../core/models/bridge-resource-descriptor.js';
import type { ReviewTreeRowMetadata } from '../features/review/models/review-protocol-models.js';
import type { BridgeContentFetch } from '../foundation/content/content-resource-loader.js';
import type { BridgeReviewPackage } from '../foundation/review-package/bridge-review-package.js';
import type {
	BridgeTelemetryFlushProps,
	BridgeTelemetryRecorder,
} from '../foundation/telemetry/bridge-telemetry-recorder.js';
import type { BridgeTraceContext } from '../foundation/telemetry/bridge-trace-context.js';
import type { BridgeCodeViewContentResources } from '../review-viewer/code-view/bridge-code-view-materialization.js';
import type { BridgeCodeViewControlHandle } from '../review-viewer/code-view/bridge-code-view-panel.js';
import type { ReviewContentDemandTelemetry } from '../review-viewer/content/review-content-demand-loader.js';
import { useBridgeReviewProjectionCoordinator } from '../review-viewer/projections/use-review-projection-coordinator.js';
import { selectBridgeReviewViewerRootSnapshot } from '../review-viewer/state/review-viewer-store.js';
import { recordBridgeSelectedContentDroppedTelemetry } from '../review-viewer/telemetry/bridge-review-viewer-telemetry.js';
import { createBridgeMarkdownRenderWebWorkerClient } from '../review-viewer/workers/markdown/bridge-markdown-render-worker-transport.js';
import type { BridgeReviewProjectionWorkerClient } from '../review-viewer/workers/projection/review-projection-worker-client.js';
import { createBridgeReviewProjectionWebWorkerClient } from '../review-viewer/workers/projection/review-projection-worker-transport.js';
import { useBridgeReviewContentIdentityController } from './bridge-app-review-content-identity-controller.js';
import { useBridgeReviewContentPrefetchController } from './bridge-app-review-content-prefetch-controller.js';
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
	createBridgeReviewDemandScheduler,
	useBridgeResourceDescriptorRegistry,
	useBridgeReviewContentRegistry,
	useBridgeReviewResourceExecutor,
	useBridgeReviewViewerStore,
} from './bridge-app-review-runtime.js';
import {
	useBridgeReviewSelectedContentEffect,
	useSelectedReviewContentDemandController,
} from './bridge-app-review-selected-content-controller.js';
import { useBridgeReviewSelectionController } from './bridge-app-review-selection-controller.js';
import {
	makeSelectedContentResourcesKey,
	reviewContentValidityDropReason,
	reviewFileTargetForNavigationCommand,
	scheduleSelectedContentRetry,
	selectedCanvasLoadingReasonForCurrentSelection,
	selectedContentResourcesForCurrentSelection,
	selectedContentUnavailablePathForCurrentSelection,
	selectedItemPresentationForReviewFileTarget,
	shouldRetrySelectedReviewContentAfterDescriptorRegistration,
	type BridgeReviewFileNavigationTarget,
	type SelectedMarkdownPreviewState,
} from './bridge-app-review-selection-state.js';
import { useBridgeReviewRenderTelemetryController } from './bridge-app-review-telemetry-controller.js';
import {
	createChildTraceContext,
	type BridgeReviewPackageTelemetryContext,
} from './bridge-app-review-telemetry.js';
import { BridgeReviewViewerShellBoundary } from './bridge-app-review-viewer-shell-boundary.js';
import { useBridgeReviewVisibleContentController } from './bridge-app-review-visible-content-controller.js';
import type { BridgeAppProps } from './bridge-app.js';
import { useBridgeReviewControlEventListeners } from './use-bridge-review-control-event-listeners.js';

export function BridgeReviewViewerMode(
	props: BridgeAppProps & {
		readonly handshakeSessionRef: MutableRefObject<BridgePageHandshakeSession | null>;
		readonly isActive: boolean;
		readonly onActiveSourceChange: (activeSource: BridgeActiveViewerSource | null) => void;
		readonly registerBridgeReadyCallback: (callback: () => void) => () => void;
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
	const contentRegistry = useBridgeReviewContentRegistry();
	const descriptorRegistry = useBridgeResourceDescriptorRegistry();
	const reviewContentDescriptorRefsByHandleIdRef = useRef<ReadonlyMap<string, BridgeDescriptorRef>>(
		new Map<string, BridgeDescriptorRef>(),
	);
	const invalidatedReviewFreshnessKeysRef = useRef<Set<string>>(new Set<string>());
	const reviewDemandSchedulerRef = useRef<BridgeDemandScheduler | null>(null);
	if (reviewDemandSchedulerRef.current === null) {
		reviewDemandSchedulerRef.current = createBridgeReviewDemandScheduler();
	}
	const reviewDemandScheduler = reviewDemandSchedulerRef.current;
	const reviewEnvelopeApplyTailRef = useRef<Promise<void>>(Promise.resolve());
	const fetchContentRef = useRef<BridgeContentFetch | undefined>(props.fetchContent);
	fetchContentRef.current = props.fetchContent;
	const resourceExecutor = useBridgeReviewResourceExecutor({
		descriptorRegistry,
		descriptorRefsByDescriptorIdRef: reviewContentDescriptorRefsByHandleIdRef,
		fetchContentRef,
		invalidatedFreshnessKeysRef: invalidatedReviewFreshnessKeysRef,
	});
	const projection = useStore(viewerStore, (state) => state.projection);
	const rootSnapshot = useStore(viewerStore, selectBridgeReviewViewerRootSnapshot);
	const viewerActions = useStore(viewerStore, (state) => state.actions);
	const setReviewRenderModeCodeView = useCallback((): void => {
		if (viewerStore.getState().rootSnapshot.renderMode.kind === 'codeView') {
			return;
		}
		viewerActions.setRenderMode({ kind: 'codeView' });
	}, [viewerActions, viewerStore]);
	const [reviewPackage, setReviewPackage] = useState<BridgeReviewPackage | null>(null);
	const [reviewTreeRows, setReviewTreeRows] = useState<readonly ReviewTreeRowMetadata[]>([]);
	const [diffStatus, setDiffStatus] = useState<BridgeDiffStatusState>({
		status: 'idle',
		error: null,
		epoch: 0,
	});
	const [reviewContentInvalidationVersion, setReviewContentInvalidationVersion] = useState(0);
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
	const {
		cancelForegroundSelectionRelease,
		foregroundSelectedContentKey,
		lastSelectedDemandTelemetry,
		lastSelectedDemandTelemetryRef,
		selectedContentAbortControllerRef,
		selectedContentActiveLoadKeyRef,
		selectedContentResourcesState,
		selectedContentResourcesStateRef,
		selectedContentRetryScheduledRef,
		selectedContentRetryVersion,
		setForegroundSelectedContentKey,
		setLastSelectedDemandTelemetry,
		setSelectedContentRetryVersion,
		setSelectedContentResourcesState,
		startSelectedReviewContentDemand,
	} = useSelectedReviewContentDemandController({
		contentRegistry,
		currentReviewPackageTelemetryContextRef,
		reviewContentDescriptorRefsByHandleIdRef,
		resourceExecutor,
		reviewDemandScheduler,
		telemetryRecorderRef,
	});
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
	const [isCodeViewScrollActive, setIsCodeViewScrollActive] = useState(false);
	const controlProbeSequenceRef = useRef(0);
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
	const selectedContentResources = useMemo(
		(): BridgeCodeViewContentResources | null =>
			selectedContentResourcesForCurrentSelection({
				reviewPackage,
				selectedItemId: rootSnapshot.selectedItemId,
				selectedContentResourcesState,
			}),
		[reviewPackage, rootSnapshot.selectedItemId, selectedContentResourcesState],
	);
	const currentSelectedContentKey =
		reviewPackage === null || rootSnapshot.selectedItemId === null
			? null
			: makeSelectedContentResourcesKey(reviewPackage, rootSnapshot.selectedItemId);
	const lastReportedSelectedContentDropContentKeyRef = useRef<string | null>(null);
	useEffect((): void => {
		const dropReason = reviewContentValidityDropReason({
			reviewPackage,
			selectedItemId: rootSnapshot.selectedItemId,
			selectedContentResourcesState,
		});
		if (
			dropReason === 'no_selection' ||
			dropReason === 'valid' ||
			currentSelectedContentKey === null ||
			lastReportedSelectedContentDropContentKeyRef.current === currentSelectedContentKey
		) {
			return;
		}
		lastReportedSelectedContentDropContentKeyRef.current = currentSelectedContentKey;
		recordBridgeSelectedContentDroppedTelemetry({
			telemetryRecorder: telemetryRecorderRef.current,
			traceContext: currentReviewPackageTelemetryContextRef.current?.traceContext ?? null,
			dropReason,
		});
	}, [
		currentReviewPackageTelemetryContextRef,
		currentSelectedContentKey,
		reviewPackage,
		rootSnapshot.selectedItemId,
		selectedContentResourcesState,
		telemetryRecorderRef,
	]);
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
	const visibleContentController = useBridgeReviewVisibleContentController({
		contentRegistry,
		currentReviewPackageTelemetryContextRef,
		currentSelectedContentKey,
		foregroundSelectedContentKey,
		isActive: props.isActive,
		isCodeViewScrollActive,
		resourceExecutor,
		reviewContentDescriptorRefsByHandleIdRef,
		reviewContentInvalidationVersion,
		reviewDemandScheduler,
		reviewPackage,
		selectedContentResourcesState,
		selectedItemId: rootSnapshot.selectedItemId,
		setLastVisibleDemandTelemetry,
		telemetryRecorderRef,
	});
	const visibleOwnedContentItemIds = useMemo(
		(): ReadonlySet<string> => new Set(visibleContentController.visibleItemIds),
		[visibleContentController.visibleItemIds],
	);
	useBridgeReviewContentPrefetchController({
		contentRegistry,
		isActive: props.isActive,
		isCodeViewScrollActive,
		resourceExecutor,
		reviewContentDescriptorRefsByHandleIdRef,
		reviewContentInvalidationVersion,
		reviewDemandScheduler,
		reviewPackage,
		selectedContentLoading: selectedContentResourcesState?.status === 'loading',
		selectedItemId: rootSnapshot.selectedItemId,
		visibleOwnedItemIds: visibleOwnedContentItemIds,
		visibleLoadingItemCount: visibleContentController.visibleLoadingItemCount,
	});
	const reviewMetadataInterestRuntime = useBridgeReviewMetadataInterestRuntime({
		authority: getReviewFrameAuthority(),
		bridgeReadyEpoch,
		isActive: props.isActive,
		reviewPackage,
		rpcClient,
		selectedItemId: rootSnapshot.selectedItemId,
		setVisibleContentItemIds: visibleContentController.setVisibleContentItemIds,
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
	const retrySelectedContentAfterDescriptorRegistration = useCallback(
		(registeredDescriptorRefCount: number): void => {
			if (
				shouldRetrySelectedReviewContentAfterDescriptorRegistration({
					reviewPackage: reviewPackageRef.current,
					selectedItemId: rootSnapshotRef.current.selectedItemId,
					registeredDescriptorRefCount,
					selectedContentResourcesState: selectedContentResourcesStateRef.current,
					lastSelectedDemandTelemetry: lastSelectedDemandTelemetryRef.current,
				})
			) {
				scheduleSelectedContentRetry({
					scheduledRef: selectedContentRetryScheduledRef,
					setSelectedContentRetryVersion,
				});
			}
		},
		[
			lastSelectedDemandTelemetryRef,
			selectedContentResourcesStateRef,
			selectedContentRetryScheduledRef,
			setSelectedContentRetryVersion,
		],
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
		cancelForegroundSelectionRelease,
		currentReviewPackageTelemetryContextRef,
		initialReviewFileTarget,
		isActive: props.isActive,
		projection,
		resourceExecutor,
		reviewContentDescriptorRefsByHandleIdRef,
		reviewDemandScheduler,
		reviewPackage,
		reviewPackageRef,
		rootSnapshot,
		rootSnapshotRef,
		rpcClient,
		selectedContentAbortControllerRef,
		selectedContentActiveLoadKeyRef,
		setForegroundSelectedContentKey,
		setSelectedContentResourcesState,
		setSelectedReviewFileTarget,
		startSelectedReviewContentDemand,
		telemetryRecorderRef,
		viewerActions,
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
		selectedContentAbortControllerRef,
		setSelectedContentResourcesState,
		setSelectedMarkdownPreviewState,
		viewerActions,
	});

	useBridgeReviewContentIdentityController({
		contentRegistry,
		reviewPackage,
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
		setReviewTreeRows,
		setDiffStatus,
		setSelectedItemId: viewerActions.setSelectedItemId,
		viewerStore,
		reviewPackageRef,
		reviewPackageTelemetryContextRef,
		currentReviewPackageTelemetryContextRef,
		reviewReadyStartMillisecondsByPackageKeyRef,
		descriptorRegistry,
		reviewContentDescriptorRefsByHandleIdRef,
		reviewDemandScheduler,
		resourceExecutor,
		contentRegistry,
		invalidatedFreshnessKeysRef: invalidatedReviewFreshnessKeysRef,
		setReviewContentInvalidationVersion,
		retrySelectedContentAfterDescriptorRegistration,
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
		selectedContentResources,
		selectedMarkdownPreviewState,
		selectReviewItem,
		setTreeSearchOpen: setIsTreeSearchOpen,
		target,
		viewerActions,
		viewerStore,
	});

	useBridgeReviewSelectedContentEffect({
		cancelForegroundSelectionRelease,
		currentSelectedContentKey,
		isActive: props.isActive,
		reviewPackageRef,
		rootSnapshotRef,
		selectedContentAbortControllerRef,
		selectedContentActiveLoadKeyRef,
		selectedContentRetryVersion,
		selectedItemPresentation,
		setForegroundSelectedContentKey,
		setLastSelectedDemandTelemetry,
		setSelectedContentResourcesState,
		startSelectedReviewContentDemand,
	});

	useBridgeReviewMarkdownPreviewController({
		currentReviewPackageTelemetryContextRef,
		isActive: props.isActive,
		markdownWorkerClient,
		renderModeKind: rootSnapshot.renderMode.kind,
		reviewPackage,
		selectedContentResources,
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
		selectedContentResourcesState,
		telemetryRecorderRef,
	});

	const selectedCanvasLoadingReason = selectedCanvasLoadingReasonForCurrentSelection({
		selectedContentKey: currentSelectedContentKey,
		selectedContentResourcesState,
		selectedItemId: rootSnapshot.selectedItemId,
		selectedMarkdownPreviewState,
	});
	const selectedContentLoadingItemId =
		selectedCanvasLoadingReason === 'content' ? rootSnapshot.selectedItemId : null;
	const selectedContentDemandStartedAtMilliseconds =
		selectedContentResourcesState?.status === 'ready' &&
		selectedContentResourcesState.itemId === rootSnapshot.selectedItemId &&
		selectedContentResourcesState.contentKey === currentSelectedContentKey
			? (selectedContentResourcesState.demandStartedAtMilliseconds ?? null)
			: null;
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
			onCodeViewScrollActivityChange={setIsCodeViewScrollActive}
			onSelectItem={selectReviewItem}
			onTreeSearchOpen={(): void => setIsTreeSearchOpen(true)}
			projection={projection}
			reviewPackage={reviewPackage}
			reviewMetadataInterestRuntime={reviewMetadataInterestRuntime}
			reviewTreeRows={reviewTreeRows}
			rootSnapshot={rootSnapshot}
			selectedCanvasLoadingReason={selectedCanvasLoadingReason}
			selectedContentDemandStartedAtMilliseconds={selectedContentDemandStartedAtMilliseconds}
			selectedContentLoadingItemId={selectedContentLoadingItemId}
			selectedContentResources={selectedContentResources}
			selectedContentUnavailablePath={selectedContentUnavailablePathForCurrentSelection({
				reviewPackage,
				selectedItemId: rootSnapshot.selectedItemId,
				selectedContentResourcesState,
			})}
			selectedItemPresentation={selectedItemPresentation}
			selectedMarkdownPreviewState={selectedMarkdownPreviewState}
			telemetryParentTraceContext={
				currentReviewPackageTelemetryContextRef.current?.traceContext ?? null
			}
			telemetryRecorder={telemetryRecorderRef.current}
			treeSearchOpen={isTreeSearchOpen}
			viewerActions={viewerActions}
			viewerHeaderControls={props.viewerHeaderControls}
			visibleContentResourcesByItemId={visibleContentController.visibleContentResourcesByItemId}
			visibleLoadingItemCount={visibleContentController.visibleLoadingItemCount}
			visibleLoadingItemIds={visibleContentController.visibleLoadingItemIds}
			visibleReadyItemCount={visibleContentController.visibleReadyItemCount}
		/>
	);
}

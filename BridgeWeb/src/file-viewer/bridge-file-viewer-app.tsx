import { lazy, Suspense, useEffect, useRef, type ReactElement } from 'react';

import type {
	WorktreeFileDescriptor,
	WorktreeFileDescriptorRequest,
} from '../features/worktree-file/models/worktree-file-protocol-models.js';
import type { BridgeFileViewerAppProps } from './bridge-file-viewer-app-props.js';
import { createBridgeFileViewerFrameApplier } from './bridge-file-viewer-frame-applier.js';
import { BridgeFileViewerLazyLoadingFrame } from './bridge-file-viewer-lazy-loading-frame.js';
import {
	bridgeFileViewerCodeViewItemMatchesDescriptor,
	useBridgeFileViewerRenderSnapshotController,
} from './bridge-file-viewer-render-snapshot-controller.js';
import { recordBridgeFileViewerSelectedReadyTelemetry } from './bridge-file-viewer-selected-ready-telemetry.js';
import {
	emptyRenderState,
	findLatestDescriptorForOpenFile,
	type BridgeFileViewerOpenState,
	type BridgeFileViewerPendingRecentlyUpdatedDescriptorDemand,
	type BridgeFileViewerRenderState,
	type WorktreeFileRuntimeFrameApplier,
} from './bridge-file-viewer-state.js';
import { useBridgeFileViewerActiveModeGate } from './use-bridge-file-viewer-active-mode-gate.js';
import { useBridgeFileViewerContentController } from './use-bridge-file-viewer-content-controller.js';
import { useBridgeFileViewerDescriptorRequestController } from './use-bridge-file-viewer-descriptor-request-controller.js';
import { useBridgeFileViewerFrameIntakeController } from './use-bridge-file-viewer-frame-intake-controller.js';
import { useBridgeFileViewerInactiveOpenFileRecovery } from './use-bridge-file-viewer-inactive-open-file-recovery.js';
import { useBridgeFileViewerRecentlyUpdatedDemand } from './use-bridge-file-viewer-recently-updated-demand.js';
import { useBridgeFileViewerSelectionEffects } from './use-bridge-file-viewer-selection-effects.js';
import { useBridgeFileViewerShellModel } from './use-bridge-file-viewer-shell-model.js';
import { useBridgeFileViewerStoreBindings } from './use-bridge-file-viewer-store-bindings.js';
import { useBridgeFileViewerVisibleDemandController } from './use-bridge-file-viewer-visible-demand-controller.js';
export type { BridgeFileViewerRenderState } from './bridge-file-viewer-state.js';
export type { BridgeFileViewerAppProps } from './bridge-file-viewer-app-props.js';
const LazyBridgeFileViewerShell = lazy(async () => {
	const module = await import('./bridge-file-viewer-shell.js');
	return { default: module.BridgeFileViewerShell };
});

export function BridgeFileViewerApp(props: BridgeFileViewerAppProps = {}): ReactElement {
	return <BridgeFileViewerAppImpl {...props} />;
}

export function BridgeFileViewerBrowserTestApp(props: BridgeFileViewerAppProps = {}): ReactElement {
	return <BridgeFileViewerAppImpl {...props} />;
}

function BridgeFileViewerAppImpl(props: BridgeFileViewerAppProps = {}): ReactElement {
	const {
		autoOpenInitialFile = false,
		codeViewWorkerFactory,
		codeViewWorkerPoolEnabled,
		initialFrames,
		isActive = true,
		loadInitialFrames,
		onOpenReviewComparison,
		waitForBridgeReady,
		worktreeFileSurfaceTransport,
	} = props;
	const runtimeRef = useRef<WorktreeFileRuntimeFrameApplier | null>(null);
	const activeVisibleDemandSignatureRef = useRef<string | null>(null);
	const demandDispatchRequestIdRef = useRef(0);
	const recentlyUpdatedDemandRequestIdRef = useRef(0);
	const recentlyUpdatedDemandInFlightRef = useRef(false);
	const recentlyUpdatedLoadedDescriptorIdRef = useRef<string | null>(null);
	const pendingRecentlyUpdatedDescriptorDemandRef =
		useRef<BridgeFileViewerPendingRecentlyUpdatedDescriptorDemand | null>(null);
	const openFileStartedAtRef = useRef<number | null>(null);
	const openFileRequestIdRef = useRef(0);
	const pendingSelectedDescriptorRequestRef = useRef<WorktreeFileDescriptorRequest | null>(null);
	const pendingStaleRefreshDescriptorRequestKeyRef = useRef<string | null>(null);
	const appliedNavigationCommandIdRef = useRef<string | null>(null);
	const renderStateRef = useRef<BridgeFileViewerRenderState>(emptyRenderState);
	const openFileStateRef = useRef<BridgeFileViewerOpenState>({ status: 'idle' });
	const {
		initialSurfaceLoadState,
		lastDemandDispatchDebugState,
		lastOpenLoadTelemetry,
		openFileState,
		refreshDebugState,
		renderState,
		rootSnapshot,
		viewerActions,
	} = useBridgeFileViewerStoreBindings();
	const { filterMode, searchMode, searchText } = rootSnapshot;
	const selectedPath = openFileState.status === 'idle' ? null : openFileState.path;
	openFileStateRef.current = openFileState;
	renderStateRef.current = renderState;
	const telemetryRecorder = props.telemetryRecorder;
	const telemetryTraceContext = props.telemetryTraceContext ?? null;
	if (runtimeRef.current === null) {
		runtimeRef.current = createBridgeFileViewerFrameApplier();
	}

	const recoverOpenFileWorkAfterDeactivation = useBridgeFileViewerInactiveOpenFileRecovery({
		openFileRequestIdRef,
		openFileStateRef,
		setLastOpenLoadTelemetry: viewerActions.setLastOpenLoadTelemetry,
		setOpenFileState: viewerActions.setOpenFileState,
		setRefreshDebugState: viewerActions.setRefreshDebugState,
	});

	const { isActiveRef } = useBridgeFileViewerActiveModeGate({
		activeVisibleDemandSignatureRef,
		appliedNavigationCommandIdRef,
		demandDispatchRequestIdRef,
		isActive,
		onDeactivateOpenFileWork: recoverOpenFileWorkAfterDeactivation,
		openFileRequestIdRef,
		pendingRecentlyUpdatedDescriptorDemandRef,
		pendingSelectedDescriptorRequestRef,
		pendingStaleRefreshDescriptorRequestKeyRef,
		recentlyUpdatedDemandInFlightRef,
		recentlyUpdatedLoadedDescriptorIdRef,
		recentlyUpdatedDemandRequestIdRef,
	});
	const renderSnapshotController = useBridgeFileViewerRenderSnapshotController({
		isActiveRef,
		openFileState,
		renderState,
	});

	const { openFile, refreshOpenFile } = useBridgeFileViewerContentController({
		dispatchSelectedFileViewContentRequest:
			renderSnapshotController.dispatchSelectedFileViewContentRequest,
		isActiveRef,
		openFileStartedAtRef,
		openFileRequestIdRef,
		publishOpenFileLoadingState: renderSnapshotController.publishOpenFileLoadingState,
		publishOpenFileRefreshingState: renderSnapshotController.publishOpenFileRefreshingState,
		renderStateRef,
		setLastOpenLoadTelemetry: viewerActions.setLastOpenLoadTelemetry,
		setOpenFileState: viewerActions.setOpenFileState,
		setRefreshDebugState: viewerActions.setRefreshDebugState,
	});

	useEffect((): void => {
		if (!isActiveRef.current || openFileState.status === 'idle') {
			return;
		}
		const availability = renderSnapshotController.selectedContentAvailability;
		if (availability === null || availability.state === 'loading') {
			return;
		}
		if (availability.state === 'ready') {
			let readyDescriptor = openFileState.descriptor;
			if (openFileState.status === 'stale') {
				const latestDescriptor = findLatestDescriptorForOpenFile({
					descriptor: openFileState.descriptor,
					renderState: renderStateRef.current,
				});
				if (
					latestDescriptor === null ||
					renderSnapshotController.selectedCodeViewItem === null ||
					!bridgeFileViewerCodeViewItemMatchesDescriptor({
						descriptor: latestDescriptor,
						item: renderSnapshotController.selectedCodeViewItem,
					})
				) {
					return;
				}
				readyDescriptor = latestDescriptor;
			} else if (renderSnapshotController.selectedReadyCodeViewItem === null) {
				return;
			}
			if (openFileState.status === 'ready') {
				return;
			}
			viewerActions.setLastOpenLoadTelemetry(null);
			recordBridgeFileViewerSelectedReadyTelemetry({
				descriptor: readyDescriptor,
				nowMilliseconds: performance.now(),
				requestId: openFileRequestIdRef.current,
				startedAtMilliseconds: openFileStartedAtRef.current,
				telemetryRecorder,
				traceContext: telemetryTraceContext,
			});
			openFileStartedAtRef.current = null;
			if (openFileState.status === 'refreshing' || openFileState.status === 'stale') {
				viewerActions.setRefreshDebugState({
					commitState: 'committed',
					currentRequestId: openFileRequestIdRef.current,
					descriptorId: readyDescriptor.contentDescriptor.ref.descriptorId,
					requestId: openFileRequestIdRef.current,
					result: 'ok',
				});
			}
			viewerActions.setOpenFileState({
				status: 'ready',
				path: readyDescriptor.path,
				descriptor: readyDescriptor,
			});
			return;
		}
		const terminalState = bridgeFileViewerOpenStateForWorkerAvailability({
			availabilityState: availability.state,
			openFileState,
		});
		if (terminalState === null) {
			return;
		}
		if (
			openFileState.status === terminalState.status &&
			openFileState.descriptor.contentDescriptor.ref.descriptorId ===
				terminalState.descriptor.contentDescriptor.ref.descriptorId
		) {
			return;
		}
		viewerActions.setLastOpenLoadTelemetry(null);
		renderSnapshotController.publishOpenFileTerminalState({
			descriptor: terminalState.descriptor,
			state: terminalState.status,
		});
		if (openFileState.status === 'refreshing') {
			viewerActions.setRefreshDebugState({
				commitState: 'committed',
				currentRequestId: openFileRequestIdRef.current,
				descriptorId: openFileState.descriptor.contentDescriptor.ref.descriptorId,
				requestId: openFileRequestIdRef.current,
				result: bridgeFileViewerRefreshResultForWorkerAvailability(availability.state),
			});
		}
		viewerActions.setOpenFileState(terminalState);
	}, [
		isActiveRef,
		openFileStartedAtRef,
		openFileRequestIdRef,
		openFileState,
		renderSnapshotController,
		telemetryRecorder,
		telemetryTraceContext,
		viewerActions,
	]);

	const requestFileDescriptorFromHost = worktreeFileSurfaceTransport?.requestFileDescriptor;
	const descriptorRequestController = useBridgeFileViewerDescriptorRequestController({
		isActiveRef,
		openFile,
		pendingSelectedDescriptorRequestRef,
		requestFileDescriptorFromHost,
	});

	const recentlyUpdatedDemandController = useBridgeFileViewerRecentlyUpdatedDemand({
		isActive,
		pendingRecentlyUpdatedDescriptorDemandRef,
		recentlyUpdatedDemandRequestIdRef,
		renderStateRef,
		requestFileDescriptorForDemand: descriptorRequestController.requestFileDescriptorForDemand,
	});

	useBridgeFileViewerFrameIntakeController({
		replayPendingRecentlyUpdatedDemand:
			recentlyUpdatedDemandController.replayPendingDescriptorDemand,
		initialFrames,
		loadInitialFrames,
		loadInitialSurface: worktreeFileSurfaceTransport?.loadInitialSurface,
		openFileRequestIdRef,
		openPendingSelectedDescriptor: descriptorRequestController.openPendingSelectedDescriptor,
		renderStateRef,
		runtimeRef,
		setInitialSurfaceLoadState: viewerActions.setInitialSurfaceLoadState,
		setOpenFileState: viewerActions.setOpenFileState,
		setRenderState: viewerActions.setRenderState,
		subscribeFrames: worktreeFileSurfaceTransport?.subscribeFrames,
		telemetryRecorder,
		telemetryTraceContext,
		waitForBridgeReady,
	});

	useBridgeFileViewerSelectionEffects({
		appliedNavigationCommandIdRef,
		autoOpenInitialFile,
		isActive,
		navigationCommand: props.navigationCommand,
		openFile,
		openFileRequestIdRef,
		openFileState,
		pendingSelectedDescriptorRequestRef,
		pendingStaleRefreshDescriptorRequestKeyRef,
		renderState,
		requestFileDescriptor: descriptorRequestController.requestFileDescriptor,
		requestFileDescriptorForDemand: descriptorRequestController.requestFileDescriptorForDemand,
	});

	const dispatchVisibleFileDemand = useBridgeFileViewerVisibleDemandController({
		dispatchVisibleFileViewViewportFact:
			renderSnapshotController.dispatchVisibleFileViewViewportFact,
		isActive,
		renderStateRef,
	});

	const shellModel = useBridgeFileViewerShellModel({
		filterMode,
		openFileState,
		renderState,
		searchMode,
		searchText,
		selectedPath,
		telemetryRecorder,
		telemetryTraceContext,
	});

	return (
		<Suspense
			fallback={
				<BridgeFileViewerLazyLoadingFrame
					isActive={isActive}
					viewerHeaderControls={props.viewerHeaderControls}
				/>
			}
		>
			<LazyBridgeFileViewerShell
				canRefreshOpenFile={shellModel.canRefreshOpenFile}
				contentHeaderTitle={shellModel.contentHeaderTitle}
				descriptorProjection={shellModel.descriptorProjection}
				dispatchVisibleFileDemand={dispatchVisibleFileDemand}
				fileDescriptorByPath={shellModel.fileDescriptorByPath}
				filterMode={filterMode}
				initialSurfaceLoadState={initialSurfaceLoadState}
				isActive={isActive}
				lastDemandDispatchDebugState={lastDemandDispatchDebugState}
				lastOpenLoadTelemetry={lastOpenLoadTelemetry}
				metadataFileTreeRowCount={shellModel.metadataFileTreeRowCount}
				onFilterModeChange={viewerActions.setFilterMode}
				onOpenFile={openFile}
				onRequestFileDescriptor={descriptorRequestController.requestFileDescriptor}
				onSearchModeChange={viewerActions.setSearchMode}
				onSearchTextChange={viewerActions.setSearchText}
				openFileState={openFileState}
				openFileTotalHeightPixels={shellModel.openFileTotalHeightPixels}
				refreshDebugState={refreshDebugState}
				refreshOpenFile={refreshOpenFile}
				renderState={renderState}
				searchMode={searchMode}
				searchText={searchText}
				selectedCodeViewItem={renderSnapshotController.selectedCodeViewItem}
				selectedPath={selectedPath}
				sourceIdentity={renderState.sourceIdentity}
				telemetryRecorder={telemetryRecorder}
				telemetryTraceContext={telemetryTraceContext}
				totalTreeHeight={shellModel.totalTreeHeight}
				totalTreeRowCount={shellModel.totalTreeRowCount}
				viewerHeaderControls={props.viewerHeaderControls}
				{...(codeViewWorkerFactory === undefined ? {} : { codeViewWorkerFactory })}
				{...(codeViewWorkerPoolEnabled === undefined ? {} : { codeViewWorkerPoolEnabled })}
				{...(onOpenReviewComparison === undefined ? {} : { onOpenReviewComparison })}
			/>
		</Suspense>
	);
}

type BridgeFileViewerTerminalOpenState =
	| {
			readonly descriptor: WorktreeFileDescriptor;
			readonly path: string;
			readonly status: 'failed';
	  }
	| {
			readonly descriptor: WorktreeFileDescriptor;
			readonly path: string;
			readonly status: 'stale';
	  }
	| {
			readonly descriptor: WorktreeFileDescriptor;
			readonly path: string;
			readonly status: 'unavailable';
	  };

function bridgeFileViewerOpenStateForWorkerAvailability(props: {
	readonly availabilityState: 'failed' | 'ready' | 'stale' | 'unavailable';
	readonly openFileState: BridgeFileViewerOpenState;
}): BridgeFileViewerTerminalOpenState | null {
	if (
		props.openFileState.status === 'idle' ||
		props.openFileState.status === 'ready' ||
		props.availabilityState === 'ready'
	) {
		return null;
	}
	if (props.openFileState.status === 'failed' || props.openFileState.status === 'unavailable') {
		return null;
	}
	if (props.availabilityState === 'unavailable') {
		return {
			status: 'unavailable',
			path: props.openFileState.path,
			descriptor: props.openFileState.descriptor,
		};
	}
	if (props.openFileState.status === 'loading' && props.availabilityState === 'failed') {
		return {
			status: 'failed',
			path: props.openFileState.path,
			descriptor: props.openFileState.descriptor,
		};
	}
	return {
		status: 'stale',
		path: props.openFileState.path,
		descriptor: props.openFileState.descriptor,
	};
}

function bridgeFileViewerRefreshResultForWorkerAvailability(
	availabilityState: 'failed' | 'stale' | 'unavailable',
): 'content_unavailable' | 'load_failed' | 'stale_completion' {
	switch (availabilityState) {
		case 'failed':
			return 'load_failed';
		case 'stale':
			return 'stale_completion';
		case 'unavailable':
			return 'content_unavailable';
	}
	return assertNeverBridgeFileViewerRefreshAvailability(availabilityState);
}

function assertNeverBridgeFileViewerRefreshAvailability(availabilityState: never): never {
	throw new Error(`Unhandled File View refresh availability: ${String(availabilityState)}`);
}

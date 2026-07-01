import { lazy, Suspense, useCallback, useRef, type ReactElement } from 'react';

import type {
	WorktreeFileDescriptor,
	WorktreeFileDescriptorRequest,
	WorktreeFileDemandStimulus,
} from '../features/worktree-file/models/worktree-file-protocol-models.js';
import { canFetchWorktreeFileDescriptorContent } from '../features/worktree-file/models/worktree-file-protocol-models.js';
import type { WorktreeFileSurfaceRuntime } from '../worktree-file-surface/worktree-file-surface-runtime.js';
import type { BridgeFileViewerAppProps } from './bridge-file-viewer-app-props.js';
import { BridgeFileViewerLazyLoadingFrame } from './bridge-file-viewer-lazy-loading-frame.js';
import { createBridgeFileViewerRuntime } from './bridge-file-viewer-runtime.js';
import {
	emptyRenderState,
	type BridgeFileViewerDemandDispatchDebugState,
	type BridgeFileViewerOpenState,
	type BridgeFileViewerPendingRecentlyUpdatedDescriptorDemand,
	type BridgeFileViewerRenderState,
} from './bridge-file-viewer-state.js';
import { useBridgeFileViewerActiveModeGate } from './use-bridge-file-viewer-active-mode-gate.js';
import { useBridgeFileViewerBodyState } from './use-bridge-file-viewer-body-state.js';
import { useBridgeFileViewerContentController } from './use-bridge-file-viewer-content-controller.js';
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
	const {
		autoOpenInitialFile = false,
		codeViewWorkerFactory,
		codeViewWorkerPoolEnabled,
		fetchResource,
		initialFrames,
		isActive = true,
		loadInitialFrames,
		loadInitialSurface,
		onOpenReviewComparison,
		subscribeFrames,
		waitForBridgeReady,
	} = props;
	const runtimeRef = useRef<WorktreeFileSurfaceRuntime | null>(null);
	const activeVisibleDemandSignatureRef = useRef<string | null>(null);
	const demandDispatchRequestIdRef = useRef(0);
	const recentlyUpdatedDemandRequestIdRef = useRef(0);
	const recentlyUpdatedDemandInFlightRef = useRef(false);
	const recentlyUpdatedLoadedDescriptorIdRef = useRef<string | null>(null);
	const lastDemandDispatchDebugStateRef = useRef<BridgeFileViewerDemandDispatchDebugState>({
		status: 'idle',
	});
	const lastVisibleDemandSignatureRef = useRef<string | null>(null);
	const pendingRecentlyUpdatedDescriptorDemandRef =
		useRef<BridgeFileViewerPendingRecentlyUpdatedDescriptorDemand | null>(null);
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
	const {
		clearOpenFileBody,
		clearProvisionalOpenFileBody,
		commitOpenFileBody,
		lastGoodOpenFileContent,
		openFileBodyRef,
		openFileBodyState,
		openFileBodyVersion,
		provisionalOpenFileBody,
		provisionalOpenFileBodyRef,
		setProvisionalOpenFileBody,
		setOpenFileBodyState,
	} = useBridgeFileViewerBodyState();
	lastDemandDispatchDebugStateRef.current = lastDemandDispatchDebugState;
	const selectedPath = openFileState.status === 'idle' ? null : openFileState.path;
	openFileStateRef.current = openFileState;
	const telemetryRecorder = props.telemetryRecorder;
	const telemetryTraceContext = props.telemetryTraceContext ?? null;

	if (runtimeRef.current === null) {
		runtimeRef.current = createBridgeFileViewerRuntime({
			fetchResource,
			telemetryRecorder: props.telemetryRecorder,
			telemetryTraceContext: props.telemetryTraceContext,
		});
	}

	const recoverOpenFileWorkAfterDeactivation = useBridgeFileViewerInactiveOpenFileRecovery({
		clearOpenFileBody,
		clearProvisionalOpenFileBody,
		openFileRequestIdRef,
		openFileStateRef,
		setLastOpenLoadTelemetry: viewerActions.setLastOpenLoadTelemetry,
		setOpenFileState: viewerActions.setOpenFileState,
	});

	const { activeModeTokenRef, isActiveRef } = useBridgeFileViewerActiveModeGate({
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

	const { openFile, refreshOpenFile } = useBridgeFileViewerContentController({
		activeModeTokenRef,
		clearOpenFileBody,
		clearProvisionalOpenFileBody,
		commitOpenFileBody,
		isActiveRef,
		openFileBodyRef,
		openFileRequestIdRef,
		provisionalOpenFileBodyRef,
		renderStateRef,
		runtimeRef,
		setLastOpenLoadTelemetry: viewerActions.setLastOpenLoadTelemetry,
		setOpenFileBodyState,
		setOpenFileState: viewerActions.setOpenFileState,
		setProvisionalOpenFileBody,
		setRefreshDebugState: viewerActions.setRefreshDebugState,
		telemetryRecorder,
		telemetryTraceContext,
	});

	const openPendingSelectedDescriptor = useCallback(
		(nextState: BridgeFileViewerRenderState): void => {
			if (!isActiveRef.current) {
				return;
			}
			const pendingRequest = pendingSelectedDescriptorRequestRef.current;
			if (pendingRequest === null) {
				return;
			}
			const descriptor = nextState.descriptors.find(
				(candidate): boolean =>
					candidate.fileId === pendingRequest.fileId &&
					candidate.path === pendingRequest.path &&
					canFetchWorktreeFileDescriptorContent(candidate),
			);
			if (descriptor === undefined) {
				return;
			}
			pendingSelectedDescriptorRequestRef.current = null;
			void openFile(descriptor);
		},
		[isActiveRef, openFile],
	);

	const requestFileDescriptorFromHost = props.requestFileDescriptor;
	const requestFileDescriptor = useCallback(
		(request: WorktreeFileDescriptorRequest): void => {
			if (!isActiveRef.current) {
				return;
			}
			pendingSelectedDescriptorRequestRef.current = request;
			const requestResult = requestFileDescriptorFromHost?.(request);
			if (requestResult === undefined) {
				return;
			}
			void Promise.resolve(requestResult).catch((): void => {
				if (pendingSelectedDescriptorRequestRef.current !== request) {
					return;
				}
				pendingSelectedDescriptorRequestRef.current = null;
			});
		},
		[isActiveRef, requestFileDescriptorFromHost],
	);

	const requestFileDescriptorForDemand = useCallback(
		(request: WorktreeFileDescriptorRequest): void => {
			if (!isActiveRef.current) {
				return;
			}
			const requestResult = requestFileDescriptorFromHost?.(request);
			if (requestResult === undefined) {
				return;
			}
			void Promise.resolve(requestResult).catch((): void => {
				// Demand lanes are advisory warming; failed descriptor requests must not surface
				// as unhandled promise rejections or poison foreground selection state.
			});
		},
		[isActiveRef, requestFileDescriptorFromHost],
	);

	const dispatchRecentlyUpdatedDescriptorDemand = useCallback(
		(demandProps: {
			readonly descriptor: WorktreeFileDescriptor;
			readonly openFilePathBefore: string | null;
			readonly proximity: 'nearby' | 'remote';
			readonly requestId: number;
		}): void => {
			const runtime = runtimeRef.current;
			if (runtime === null) {
				return;
			}
			const stimuli: readonly WorktreeFileDemandStimulus[] = [
				{
					kind: 'recentlyUpdatedFile',
					descriptorRef: demandProps.descriptor.contentDescriptor.ref,
					proximity: demandProps.proximity,
					sourceIdentity: demandProps.descriptor.sourceIdentity.sourceId,
				},
			];
			recentlyUpdatedDemandInFlightRef.current = true;
			recentlyUpdatedLoadedDescriptorIdRef.current =
				demandProps.descriptor.contentDescriptor.ref.descriptorId;
			void runtime
				.dispatchDemandStimuli(stimuli)
				.then((result): void => {
					if (!isActiveRef.current) {
						return;
					}
					if (recentlyUpdatedDemandRequestIdRef.current !== demandProps.requestId) {
						return;
					}
					const openFilePathAfter =
						openFileStateRef.current.status === 'idle' ? null : openFileStateRef.current.path;
					viewerActions.setLastDemandDispatchDebugState({
						origin: {
							descriptorPath: demandProps.descriptor.path,
							kind: 'recentlyUpdatedFile',
							openFilePathAfter,
							openFilePathBefore: demandProps.openFilePathBefore,
						},
						status: 'settled',
						result,
					});
				})
				.catch((error: unknown): void => {
					if (!isActiveRef.current) {
						return;
					}
					if (recentlyUpdatedDemandRequestIdRef.current !== demandProps.requestId) {
						return;
					}
					viewerActions.setLastDemandDispatchDebugState({
						status: 'failed',
						reason: error instanceof Error ? error.message : String(error),
					});
				})
				.finally((): void => {
					if (recentlyUpdatedDemandRequestIdRef.current === demandProps.requestId) {
						recentlyUpdatedDemandInFlightRef.current = false;
					}
				});
		},
		[isActiveRef, viewerActions],
	);

	const dispatchPendingRecentlyUpdatedDescriptorDemand = useCallback(
		(nextState: BridgeFileViewerRenderState): void => {
			if (!isActiveRef.current) {
				return;
			}
			const pendingDemand = pendingRecentlyUpdatedDescriptorDemandRef.current;
			if (pendingDemand === null) {
				return;
			}
			const descriptor = nextState.descriptors.find(
				(candidate): boolean =>
					candidate.fileId === pendingDemand.request.fileId &&
					candidate.path === pendingDemand.request.path &&
					canFetchWorktreeFileDescriptorContent(candidate),
			);
			if (descriptor === undefined) {
				return;
			}
			pendingRecentlyUpdatedDescriptorDemandRef.current = null;
			dispatchRecentlyUpdatedDescriptorDemand({
				descriptor,
				openFilePathBefore: pendingDemand.openFilePathBefore,
				proximity: pendingDemand.proximity,
				requestId: pendingDemand.requestId,
			});
		},
		[dispatchRecentlyUpdatedDescriptorDemand, isActiveRef],
	);

	useBridgeFileViewerFrameIntakeController({
		dispatchPendingRecentlyUpdatedDescriptorDemand,
		initialFrames,
		loadInitialFrames,
		loadInitialSurface,
		openFileBodyRef,
		openFileRequestIdRef,
		openPendingSelectedDescriptor,
		renderStateRef,
		runtimeRef,
		setInitialSurfaceLoadState: viewerActions.setInitialSurfaceLoadState,
		setOpenFileState: viewerActions.setOpenFileState,
		setRenderState: viewerActions.setRenderState,
		subscribeFrames,
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
		requestFileDescriptor,
		requestFileDescriptorForDemand,
	});

	const dispatchVisibleFileDemand = useBridgeFileViewerVisibleDemandController({
		activeVisibleDemandSignatureRef,
		demandDispatchRequestIdRef,
		isActive,
		isActiveRef,
		lastDemandDispatchDebugStateRef,
		lastVisibleDemandSignatureRef,
		recentlyUpdatedDemandInFlightRef,
		recentlyUpdatedDemandRequestIdRef,
		recentlyUpdatedLoadedDescriptorIdRef,
		runtimeRef,
		setLastDemandDispatchDebugState: viewerActions.setLastDemandDispatchDebugState,
		telemetryRecorder,
		telemetryTraceContext,
	});

	useBridgeFileViewerRecentlyUpdatedDemand({
		dispatchRecentlyUpdatedDescriptorDemand,
		isActive,
		openFileStateRef,
		pendingRecentlyUpdatedDescriptorDemandRef,
		recentlyUpdatedDemandRequestIdRef,
		renderStateRef,
		requestFileDescriptorForDemand,
		runtimeRef,
	});

	const shellModel = useBridgeFileViewerShellModel({
		filterMode,
		lastGoodOpenFileContent,
		openFileBodyState,
		openFileBodyVersion,
		openFileState,
		provisionalOpenFileBody,
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
				<BridgeFileViewerLazyLoadingFrame viewerHeaderControls={props.viewerHeaderControls} />
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
				onRequestFileDescriptor={requestFileDescriptor}
				onSearchModeChange={viewerActions.setSearchMode}
				onSearchTextChange={viewerActions.setSearchText}
				openFileState={openFileState}
				openFileTotalHeightPixels={shellModel.openFileTotalHeightPixels}
				refreshDebugState={refreshDebugState}
				refreshOpenFile={refreshOpenFile}
				renderedOpenFileContent={shellModel.renderedOpenFileContent}
				renderState={renderState}
				searchMode={searchMode}
				searchText={searchText}
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

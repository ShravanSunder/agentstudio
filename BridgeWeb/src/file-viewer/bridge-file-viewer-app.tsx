import { lazy, Suspense, useEffect, useRef, type ReactElement } from 'react';

import type { WorktreeFileDescriptorRequest } from '../features/worktree-file/models/worktree-file-protocol-models.js';
import type { WorktreeFileSurfaceRuntime } from '../worktree-file-surface/worktree-file-surface-runtime.js';
import type { BridgeFileViewerAppProps } from './bridge-file-viewer-app-props.js';
import { BridgeFileViewerLazyLoadingFrame } from './bridge-file-viewer-lazy-loading-frame.js';
import { createBridgeFileViewerRuntime } from './bridge-file-viewer-runtime.js';
import {
	bridgeFileViewerHasActiveCommentDraft,
	bridgeFileViewerStaleAutoRefreshCoalesceMilliseconds,
	shouldAutoRefreshStaleOpenFile,
} from './bridge-file-viewer-stale-refresh-policy.js';
import {
	emptyRenderState,
	findLatestDescriptorForOpenFile,
	type BridgeFileViewerDemandDispatchDebugState,
	type BridgeFileViewerOpenState,
	type BridgeFileViewerPendingRecentlyUpdatedDescriptorDemand,
	type BridgeFileViewerRenderState,
} from './bridge-file-viewer-state.js';
import { useBridgeFileViewerActiveModeGate } from './use-bridge-file-viewer-active-mode-gate.js';
import { useBridgeFileViewerBodyState } from './use-bridge-file-viewer-body-state.js';
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

type BridgeFileViewerStaleAutoRefreshGuard = {
	readonly descriptorKey: string;
	readonly state: 'failed' | 'inFlight' | 'scheduled';
} | null;

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
	const staleAutoRefreshGuardRef = useRef<BridgeFileViewerStaleAutoRefreshGuard>(null);
	const staleAutoRefreshTimeoutRef = useRef<ReturnType<typeof setTimeout> | null>(null);
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

	useEffect((): (() => void) => {
		return (): void => {
			if (staleAutoRefreshTimeoutRef.current !== null) {
				clearTimeout(staleAutoRefreshTimeoutRef.current);
				staleAutoRefreshTimeoutRef.current = null;
			}
		};
	}, []);

	useEffect((): void => {
		if (openFileState.status !== 'stale') {
			return;
		}
		if (
			!shouldAutoRefreshStaleOpenFile({
				hasActiveCommentDraft: bridgeFileViewerHasActiveCommentDraft,
			})
		) {
			return;
		}
		const staleRefreshDescriptor =
			findLatestDescriptorForOpenFile({
				descriptor: openFileState.descriptor,
				renderState: renderStateRef.current,
			}) ?? openFileState.descriptor;
		const staleDescriptorKey = `${staleRefreshDescriptor.path}:${staleRefreshDescriptor.contentDescriptor.ref.descriptorId}`;
		if (staleAutoRefreshGuardRef.current?.descriptorKey === staleDescriptorKey) {
			if (staleAutoRefreshGuardRef.current.state !== 'failed') {
				return;
			}
			viewerActions.setRefreshDebugState({
				commitState: 'skipped',
				currentRequestId: openFileRequestIdRef.current,
				descriptorId: staleRefreshDescriptor.contentDescriptor.ref.descriptorId,
				requestId: openFileRequestIdRef.current,
				result: 'duplicate_stale_auto_refresh_failure',
			});
			return;
		}
		staleAutoRefreshGuardRef.current = {
			descriptorKey: staleDescriptorKey,
			state: 'scheduled',
		};
		staleAutoRefreshTimeoutRef.current = setTimeout((): void => {
			void (async (): Promise<void> => {
				staleAutoRefreshTimeoutRef.current = null;
				const currentStateBeforeRefresh = openFileStateRef.current;
				const currentRefreshDescriptor =
					currentStateBeforeRefresh.status === 'stale'
						? (findLatestDescriptorForOpenFile({
								descriptor: currentStateBeforeRefresh.descriptor,
								renderState: renderStateRef.current,
							}) ?? currentStateBeforeRefresh.descriptor)
						: null;
				if (
					currentStateBeforeRefresh.status !== 'stale' ||
					currentRefreshDescriptor === null ||
					`${currentRefreshDescriptor.path}:${currentRefreshDescriptor.contentDescriptor.ref.descriptorId}` !==
						staleDescriptorKey
				) {
					if (staleAutoRefreshGuardRef.current?.descriptorKey === staleDescriptorKey) {
						staleAutoRefreshGuardRef.current = null;
					}
					return;
				}
				staleAutoRefreshGuardRef.current = {
					descriptorKey: staleDescriptorKey,
					state: 'inFlight',
				};
				await refreshOpenFile(openFileState);
				const currentOpenFileState = openFileStateRef.current;
				const currentOpenFileRefreshDescriptor =
					currentOpenFileState.status === 'stale'
						? (findLatestDescriptorForOpenFile({
								descriptor: currentOpenFileState.descriptor,
								renderState: renderStateRef.current,
							}) ?? currentOpenFileState.descriptor)
						: null;
				if (
					currentOpenFileState.status === 'stale' &&
					currentOpenFileRefreshDescriptor !== null &&
					isActiveRef.current
				) {
					const failedRefreshDescriptorKey = `${currentOpenFileRefreshDescriptor.path}:${currentOpenFileRefreshDescriptor.contentDescriptor.ref.descriptorId}`;
					staleAutoRefreshGuardRef.current = {
						descriptorKey: failedRefreshDescriptorKey,
						state: 'failed',
					};
					viewerActions.setRefreshDebugState({
						commitState: 'skipped',
						currentRequestId: openFileRequestIdRef.current,
						descriptorId: currentOpenFileRefreshDescriptor.contentDescriptor.ref.descriptorId,
						requestId: openFileRequestIdRef.current,
						result: 'duplicate_stale_auto_refresh_failure',
					});
					return;
				}
				if (staleAutoRefreshGuardRef.current?.descriptorKey === staleDescriptorKey) {
					staleAutoRefreshGuardRef.current = null;
				}
			})();
		}, bridgeFileViewerStaleAutoRefreshCoalesceMilliseconds);
	}, [
		isActiveRef,
		openFileRequestIdRef,
		openFileState,
		openFileStateRef,
		refreshOpenFile,
		viewerActions,
	]);

	const requestFileDescriptorFromHost = props.requestFileDescriptor;
	const descriptorRequestController = useBridgeFileViewerDescriptorRequestController({
		isActiveRef,
		openFile,
		pendingSelectedDescriptorRequestRef,
		requestFileDescriptorFromHost,
	});

	const recentlyUpdatedDemandController = useBridgeFileViewerRecentlyUpdatedDemand({
		isActive,
		isActiveRef,
		openFileStateRef,
		pendingRecentlyUpdatedDescriptorDemandRef,
		recentlyUpdatedDemandInFlightRef,
		recentlyUpdatedDemandRequestIdRef,
		recentlyUpdatedLoadedDescriptorIdRef,
		renderStateRef,
		requestFileDescriptorForDemand: descriptorRequestController.requestFileDescriptorForDemand,
		runtimeRef,
		setLastDemandDispatchDebugState: viewerActions.setLastDemandDispatchDebugState,
	});

	useBridgeFileViewerFrameIntakeController({
		replayPendingRecentlyUpdatedDemand:
			recentlyUpdatedDemandController.replayPendingDescriptorDemand,
		initialFrames,
		loadInitialFrames,
		loadInitialSurface,
		openFileBodyRef,
		openFileRequestIdRef,
		openPendingSelectedDescriptor: descriptorRequestController.openPendingSelectedDescriptor,
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
		requestFileDescriptor: descriptorRequestController.requestFileDescriptor,
		requestFileDescriptorForDemand: descriptorRequestController.requestFileDescriptorForDemand,
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
				onRequestFileDescriptor={descriptorRequestController.requestFileDescriptor}
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

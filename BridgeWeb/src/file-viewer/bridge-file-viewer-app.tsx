import { lazy, Suspense, useCallback, useEffect, useRef, type ReactElement } from 'react';

import type {
	WorktreeFileDescriptor,
	WorktreeFileDescriptorRequest,
	WorktreeFileDemandStimulus,
	WorktreeFileProtocolFrame,
	WorktreeFileSurfaceSourceIdentity,
} from '../features/worktree-file/models/worktree-file-protocol-models.js';
import { canFetchWorktreeFileDescriptorContent } from '../features/worktree-file/models/worktree-file-protocol-models.js';
import {
	recordBridgeViewerFileOpenReadyTelemetrySample,
	recordBridgeViewerWorktreeFileTreeTelemetrySample,
	recordBridgeWorktreeFileVisibleDemandSettledTelemetrySample,
} from '../foundation/telemetry/bridge-viewer-telemetry-adapter.js';
import type {
	WorktreeFileFrameSubscriptionFactory,
	WorktreeFileSurfaceProvenance,
} from '../worktree-file-surface/worktree-file-app.js';
import type { WorktreeFileSurfaceRuntime } from '../worktree-file-surface/worktree-file-surface-runtime.js';
import type { BridgeFileViewerAppProps } from './bridge-file-viewer-app-props.js';
import { BridgeFileViewerLazyLoadingFrame } from './bridge-file-viewer-lazy-loading-frame.js';
import { createBridgeFileViewerRuntime } from './bridge-file-viewer-runtime.js';
import {
	applyFramesToRuntime,
	emptyRenderState,
	findLatestDescriptorForOpenFile,
	firstSuccessfulDemandLoadResult,
	reconcileOpenFileStateWithFrames,
	visibleFileDemandChangeWithoutDescriptorId,
	visibleFileDemandSignature,
	visibleViewportDemandDispatchSatisfied,
	worktreeTreeWindowRowCount,
	type BridgeFileViewerDemandDispatchDebugState,
	type BridgeFileViewerOpenState,
	type BridgeFileViewerPendingRecentlyUpdatedDescriptorDemand,
	type BridgeFileViewerRenderState,
} from './bridge-file-viewer-state.js';
import { type BridgeFileViewerVisibleFileDemandChange } from './bridge-file-viewer-tree-panel.js';
import { useBridgeFileViewerActiveModeGate } from './use-bridge-file-viewer-active-mode-gate.js';
import { useBridgeFileViewerBodyState } from './use-bridge-file-viewer-body-state.js';
import { useBridgeFileViewerInactiveOpenFileRecovery } from './use-bridge-file-viewer-inactive-open-file-recovery.js';
import { useBridgeFileViewerInitialSurfaceLoader } from './use-bridge-file-viewer-initial-surface-loader.js';
import { useBridgeFileViewerRecentlyUpdatedDemand } from './use-bridge-file-viewer-recently-updated-demand.js';
import { useBridgeFileViewerSelectionEffects } from './use-bridge-file-viewer-selection-effects.js';
import { useBridgeFileViewerShellModel } from './use-bridge-file-viewer-shell-model.js';
import { useBridgeFileViewerStoreBindings } from './use-bridge-file-viewer-store-bindings.js';
export {
	applyFramesToRuntime,
	projectBridgeFileViewerDescriptors,
	pruneEmptyWorktreeFileTreeDirectories,
	visibleFileDemandChangeWithoutDescriptorId,
} from './bridge-file-viewer-state.js';
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
		setOpenFileBodyState,
		setProvisionalOpenFileBody,
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

	const openFile = useCallback(
		async (descriptor: WorktreeFileDescriptor): Promise<void> => {
			if (!isActiveRef.current) {
				return;
			}
			const activeModeToken = activeModeTokenRef.current;
			const openFileStartedAt = performance.now();
			const requestId = openFileRequestIdRef.current + 1;
			openFileRequestIdRef.current = requestId;
			clearOpenFileBody();
			clearProvisionalOpenFileBody();
			viewerActions.setLastOpenLoadTelemetry(null);
			viewerActions.setOpenFileState({ status: 'loading', path: descriptor.path, descriptor });
			const runtime = runtimeRef.current;
			if (runtime === null) {
				if (
					openFileRequestIdRef.current === requestId &&
					isActiveRef.current &&
					activeModeTokenRef.current === activeModeToken
				) {
					viewerActions.setOpenFileState({ status: 'failed', path: descriptor.path, descriptor });
				}
				return;
			}
			const result = await runtime.openFile({
				descriptor,
				onProvisionalTextChunk: (chunk): void => {
					if (
						openFileRequestIdRef.current !== requestId ||
						!isActiveRef.current ||
						activeModeTokenRef.current !== activeModeToken
					) {
						return;
					}
					provisionalOpenFileBodyRef.current = `${provisionalOpenFileBodyRef.current ?? ''}${chunk.text}`;
					setProvisionalOpenFileBody(provisionalOpenFileBodyRef.current);
				},
				openFileSessionId: descriptor.fileId,
			});
			if (
				openFileRequestIdRef.current !== requestId ||
				!isActiveRef.current ||
				activeModeTokenRef.current !== activeModeToken
			) {
				return;
			}
			if (result.ok) {
				const openFileBody = result.content.readText();
				commitOpenFileBody({
					body: openFileBody,
					descriptor,
					path: descriptor.path,
				});
				if (telemetryRecorder !== undefined) {
					recordBridgeViewerFileOpenReadyTelemetrySample({
						disposition: result.loadTelemetry.disposition,
						durationMilliseconds: performance.now() - openFileStartedAt,
						estimatedBytes: result.loadTelemetry.estimatedBytes,
						executorInFlightMilliseconds: result.loadTelemetry.executorInFlightMilliseconds,
						executorPendingWaitMilliseconds: result.loadTelemetry.executorPendingWaitMilliseconds,
						lane: result.loadTelemetry.lane,
						requestId,
						resourceBodyRegistryCommitMilliseconds:
							result.loadTelemetry.resourceBodyRegistryCommitMilliseconds,
						resourceFetchResponseWaitMilliseconds:
							result.loadTelemetry.resourceFetchResponseWaitMilliseconds,
						resourceFirstChunkWaitMilliseconds:
							result.loadTelemetry.resourceFirstChunkWaitMilliseconds,
						resourceStreamReadMilliseconds: result.loadTelemetry.resourceStreamReadMilliseconds,
						result: 'success',
						resultReason: null,
						schedulerQueueWaitMilliseconds: result.loadTelemetry.schedulerQueueWaitMilliseconds,
						sourceGeneration: descriptor.sourceIdentity.subscriptionGeneration,
						telemetryRecorder,
						traceContext: telemetryTraceContext,
					});
				}
				clearProvisionalOpenFileBody();
				viewerActions.setLastOpenLoadTelemetry(result.loadTelemetry);
				viewerActions.setOpenFileState({ status: 'ready', path: descriptor.path, descriptor });
				return;
			}
			clearOpenFileBody();
			clearProvisionalOpenFileBody();
			viewerActions.setLastOpenLoadTelemetry(null);
			if (telemetryRecorder !== undefined) {
				recordBridgeViewerFileOpenReadyTelemetrySample({
					disposition: 'none',
					durationMilliseconds: performance.now() - openFileStartedAt,
					estimatedBytes: descriptor.contentDescriptor.descriptor.content.expectedBytes ?? null,
					executorInFlightMilliseconds: null,
					executorPendingWaitMilliseconds: null,
					lane: 'foreground',
					requestId,
					resourceBodyRegistryCommitMilliseconds: null,
					resourceFetchResponseWaitMilliseconds: null,
					resourceFirstChunkWaitMilliseconds: null,
					resourceStreamReadMilliseconds: null,
					result: 'failed',
					resultReason: result.reason,
					schedulerQueueWaitMilliseconds: null,
					sourceGeneration: descriptor.sourceIdentity.subscriptionGeneration,
					telemetryRecorder,
					traceContext: telemetryTraceContext,
				});
			}
			viewerActions.setOpenFileState({
				status: result.reason === 'content_unavailable' ? 'unavailable' : 'failed',
				path: descriptor.path,
				descriptor,
			});
		},
		[
			clearOpenFileBody,
			clearProvisionalOpenFileBody,
			commitOpenFileBody,
			activeModeTokenRef,
			isActiveRef,
			provisionalOpenFileBodyRef,
			setProvisionalOpenFileBody,
			telemetryRecorder,
			telemetryTraceContext,
			viewerActions,
		],
	);

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

	const applyIncomingFrames = useCallback(
		(
			frames: readonly WorktreeFileProtocolFrame[],
			surface?: {
				readonly provenance: WorktreeFileSurfaceProvenance | null;
				readonly sourceIdentity: WorktreeFileSurfaceSourceIdentity | null;
			},
		): BridgeFileViewerRenderState => {
			const applyStartedAt = performance.now();
			const nextState = applyFramesToRuntime({
				currentRenderState: renderStateRef.current,
				frames,
				provenance: surface?.provenance ?? null,
				runtime: runtimeRef.current,
				sourceIdentity: surface?.sourceIdentity ?? null,
			});
			if (props.telemetryRecorder !== undefined) {
				recordBridgeViewerWorktreeFileTreeTelemetrySample({
					descriptorCount: nextState.descriptors.length,
					durationMilliseconds: performance.now() - applyStartedAt,
					frameCount: frames.length,
					phase: 'worktree_file_frame_apply',
					result: 'success',
					telemetryRecorder: props.telemetryRecorder,
					traceContext: props.telemetryTraceContext ?? null,
					treeRowCount: nextState.treeRows.length,
					treeWindowRowCount: worktreeTreeWindowRowCount(frames),
				});
			}
			renderStateRef.current = nextState;
			viewerActions.setRenderState(nextState);
			viewerActions.setOpenFileState((currentOpenFileState) =>
				reconcileOpenFileStateWithFrames({
					currentOpenFileState,
					frames,
					openFileBodyRef,
					openFileRequestIdRef,
				}),
			);
			dispatchPendingRecentlyUpdatedDescriptorDemand(nextState);
			openPendingSelectedDescriptor(nextState);
			return nextState;
		},
		[
			dispatchPendingRecentlyUpdatedDescriptorDemand,
			openPendingSelectedDescriptor,
			openFileBodyRef,
			props.telemetryRecorder,
			props.telemetryTraceContext,
			viewerActions,
		],
	);
	useBridgeFileViewerInitialSurfaceLoader({
		applyIncomingFrames,
		setInitialSurfaceLoadState: viewerActions.setInitialSurfaceLoadState,
		...(initialFrames === undefined ? {} : { initialFrames }),
		...(loadInitialFrames === undefined ? {} : { loadInitialFrames }),
		...(loadInitialSurface === undefined ? {} : { loadInitialSurface }),
		...(waitForBridgeReady === undefined ? {} : { waitForBridgeReady }),
	});

	useEffect((): ReturnType<WorktreeFileFrameSubscriptionFactory> | undefined => {
		if (subscribeFrames === undefined) {
			return undefined;
		}
		return subscribeFrames((frames) => {
			applyIncomingFrames(frames);
		});
	}, [applyIncomingFrames, subscribeFrames]);

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

	const refreshOpenFile = useCallback(
		async (state: BridgeFileViewerOpenState): Promise<void> => {
			if (!isActiveRef.current) {
				return;
			}
			if (state.status !== 'stale') {
				viewerActions.setRefreshDebugState({
					commitState: 'skipped',
					currentRequestId: openFileRequestIdRef.current,
					descriptorId: 'none',
					requestId: openFileRequestIdRef.current,
					result: 'non_stale_state',
				});
				return;
			}
			const activeModeToken = activeModeTokenRef.current;
			const requestId = openFileRequestIdRef.current + 1;
			openFileRequestIdRef.current = requestId;
			clearProvisionalOpenFileBody();
			viewerActions.setLastOpenLoadTelemetry(null);
			const runtime = runtimeRef.current;
			if (runtime === null) {
				if (
					openFileRequestIdRef.current === requestId &&
					isActiveRef.current &&
					activeModeTokenRef.current === activeModeToken
				) {
					viewerActions.setOpenFileState({
						status: 'failed',
						path: state.path,
						descriptor: state.descriptor,
					});
				}
				return;
			}
			const refreshDescriptor =
				findLatestDescriptorForOpenFile({
					descriptor: state.descriptor,
					renderState: renderStateRef.current,
				}) ?? state.descriptor;
			viewerActions.setOpenFileState({
				status: 'refreshing',
				path: refreshDescriptor.path,
				descriptor: refreshDescriptor,
			});
			viewerActions.setRefreshDebugState({
				commitState: 'started',
				currentRequestId: openFileRequestIdRef.current,
				descriptorId: refreshDescriptor.contentDescriptor.ref.descriptorId,
				requestId,
				result: 'started',
			});
			const result = await runtime.refreshOpenFile({
				onProvisionalTextChunk: (chunk): void => {
					if (
						openFileRequestIdRef.current !== requestId ||
						!isActiveRef.current ||
						activeModeTokenRef.current !== activeModeToken
					) {
						return;
					}
					provisionalOpenFileBodyRef.current = `${provisionalOpenFileBodyRef.current ?? ''}${chunk.text}`;
					setProvisionalOpenFileBody(provisionalOpenFileBodyRef.current);
				},
				openFileSessionId: state.descriptor.fileId,
			});
			if (
				openFileRequestIdRef.current !== requestId ||
				!isActiveRef.current ||
				activeModeTokenRef.current !== activeModeToken
			) {
				viewerActions.setRefreshDebugState({
					commitState: 'ignored',
					currentRequestId: openFileRequestIdRef.current,
					descriptorId: refreshDescriptor.contentDescriptor.ref.descriptorId,
					requestId,
					result: result.ok ? 'ok' : result.reason,
				});
				return;
			}
			viewerActions.setRefreshDebugState({
				commitState: 'committed',
				currentRequestId: openFileRequestIdRef.current,
				descriptorId: refreshDescriptor.contentDescriptor.ref.descriptorId,
				requestId,
				result: result.ok ? 'ok' : result.reason,
			});
			if (result.ok) {
				const openFileBody = result.content.readText();
				commitOpenFileBody({
					body: openFileBody,
					descriptor: refreshDescriptor,
					path: refreshDescriptor.path,
				});
				clearProvisionalOpenFileBody();
				viewerActions.setLastOpenLoadTelemetry(result.loadTelemetry);
				const refreshedDescriptor =
					findLatestDescriptorForOpenFile({
						descriptor: state.descriptor,
						renderState: renderStateRef.current,
					}) ?? state.descriptor;
				viewerActions.setOpenFileState({
					status: 'ready',
					path: refreshedDescriptor.path,
					descriptor: refreshedDescriptor,
				});
				return;
			}
			openFileBodyRef.current =
				result.reason === 'content_unavailable' ? null : openFileBodyRef.current;
			setOpenFileBodyState(
				result.reason === 'content_unavailable' ? null : openFileBodyRef.current,
			);
			clearProvisionalOpenFileBody();
			viewerActions.setLastOpenLoadTelemetry(null);
			viewerActions.setOpenFileState({
				status: result.reason === 'content_unavailable' ? 'unavailable' : 'stale',
				path: refreshDescriptor.path,
				descriptor: refreshDescriptor,
			});
		},
		[
			activeModeTokenRef,
			clearProvisionalOpenFileBody,
			commitOpenFileBody,
			isActiveRef,
			openFileBodyRef,
			provisionalOpenFileBodyRef,
			setOpenFileBodyState,
			setProvisionalOpenFileBody,
			viewerActions,
		],
	);

	const dispatchVisibleFileDemand = useCallback(
		(change: BridgeFileViewerVisibleFileDemandChange): void => {
			if (!isActive) {
				return;
			}
			let visibleDemandChange = change;
			const recentlyUpdatedLoadedDescriptorId = recentlyUpdatedLoadedDescriptorIdRef.current;
			if (recentlyUpdatedLoadedDescriptorId !== null) {
				recentlyUpdatedLoadedDescriptorIdRef.current = null;
				const filteredVisibleDemandChange = visibleFileDemandChangeWithoutDescriptorId(
					change,
					recentlyUpdatedLoadedDescriptorId,
				);
				if (filteredVisibleDemandChange === null) {
					return;
				}
				visibleDemandChange = filteredVisibleDemandChange;
			}
			const runtime = runtimeRef.current;
			if (runtime === null || visibleDemandChange.descriptorRefs.length === 0) {
				return;
			}
			if (recentlyUpdatedDemandInFlightRef.current) {
				return;
			}
			const visibleDemandSignature = visibleFileDemandSignature(visibleDemandChange);
			if (activeVisibleDemandSignatureRef.current === visibleDemandSignature) {
				return;
			}
			if (
				lastVisibleDemandSignatureRef.current === visibleDemandSignature &&
				visibleViewportDemandDispatchSatisfied(lastDemandDispatchDebugStateRef.current)
			) {
				return;
			}
			activeVisibleDemandSignatureRef.current = visibleDemandSignature;
			const requestId = demandDispatchRequestIdRef.current + 1;
			demandDispatchRequestIdRef.current = requestId;
			const visibleDemandStartedAt = performance.now();
			const recentlyUpdatedDemandRequestIdAtStart = recentlyUpdatedDemandRequestIdRef.current;
			const stimuli: readonly WorktreeFileDemandStimulus[] = [
				{
					kind: 'treeViewportChanged',
					descriptorRefs: [...visibleDemandChange.descriptorRefs],
				},
			];
			void runtime
				.dispatchDemandStimuli(stimuli)
				.then((result): void => {
					if (!isActiveRef.current) {
						if (activeVisibleDemandSignatureRef.current === visibleDemandSignature) {
							activeVisibleDemandSignatureRef.current = null;
						}
						return;
					}
					if (recentlyUpdatedDemandRequestIdRef.current !== recentlyUpdatedDemandRequestIdAtStart) {
						if (activeVisibleDemandSignatureRef.current === visibleDemandSignature) {
							activeVisibleDemandSignatureRef.current = null;
						}
						return;
					}
					const nextDebugState: BridgeFileViewerDemandDispatchDebugState = {
						origin: {
							expectedVisibleFileCount: visibleDemandChange.visibleFileCount,
							kind: 'visibleViewport',
						},
						status: 'settled',
						result,
					};
					if (activeVisibleDemandSignatureRef.current === visibleDemandSignature) {
						activeVisibleDemandSignatureRef.current = null;
					}
					if (demandDispatchRequestIdRef.current !== requestId) {
						return;
					}
					if (visibleViewportDemandDispatchSatisfied(nextDebugState)) {
						lastVisibleDemandSignatureRef.current = visibleDemandSignature;
					}
					if (telemetryRecorder !== undefined) {
						const firstLoadTelemetry =
							firstSuccessfulDemandLoadResult(result)?.loadTelemetry ?? null;
						recordBridgeWorktreeFileVisibleDemandSettledTelemetrySample({
							durationMilliseconds: performance.now() - visibleDemandStartedAt,
							enqueueAcceptedCount: result.enqueueAcceptedCount,
							enqueueRejectedCount: result.enqueueRejectedCount,
							executorInFlightMilliseconds:
								firstLoadTelemetry?.executorInFlightMilliseconds ?? null,
							executorPendingWaitMilliseconds:
								firstLoadTelemetry?.executorPendingWaitMilliseconds ?? null,
							failedCount: result.failedCount,
							firstChunkWaitMilliseconds:
								firstLoadTelemetry?.resourceFirstChunkWaitMilliseconds ?? null,
							intentCount: result.intentCount,
							lane: firstLoadTelemetry?.lane ?? null,
							loadedCount: result.loadedCount,
							requestId,
							responseWaitMilliseconds:
								firstLoadTelemetry?.resourceFetchResponseWaitMilliseconds ?? null,
							result: result.failedCount === 0 ? 'success' : 'failed',
							resultReason: result.failedCount === 0 ? null : 'load_failed',
							schedulerQueueWaitMilliseconds:
								firstLoadTelemetry?.schedulerQueueWaitMilliseconds ?? null,
							streamReadMilliseconds: firstLoadTelemetry?.resourceStreamReadMilliseconds ?? null,
							telemetryRecorder,
							traceContext: telemetryTraceContext,
							visibleItemCount: change.visibleFileCount,
						});
					}
					viewerActions.setLastDemandDispatchDebugState(nextDebugState);
				})
				.catch((error: unknown): void => {
					if (!isActiveRef.current) {
						if (activeVisibleDemandSignatureRef.current === visibleDemandSignature) {
							activeVisibleDemandSignatureRef.current = null;
						}
						return;
					}
					if (recentlyUpdatedDemandRequestIdRef.current !== recentlyUpdatedDemandRequestIdAtStart) {
						if (activeVisibleDemandSignatureRef.current === visibleDemandSignature) {
							activeVisibleDemandSignatureRef.current = null;
						}
						return;
					}
					if (activeVisibleDemandSignatureRef.current === visibleDemandSignature) {
						activeVisibleDemandSignatureRef.current = null;
					}
					if (demandDispatchRequestIdRef.current !== requestId) {
						return;
					}
					if (telemetryRecorder !== undefined) {
						recordBridgeWorktreeFileVisibleDemandSettledTelemetrySample({
							durationMilliseconds: performance.now() - visibleDemandStartedAt,
							enqueueAcceptedCount: 0,
							enqueueRejectedCount: 0,
							executorInFlightMilliseconds: null,
							executorPendingWaitMilliseconds: null,
							failedCount: change.visibleFileCount,
							firstChunkWaitMilliseconds: null,
							intentCount: change.visibleFileCount,
							lane: 'visible',
							loadedCount: 0,
							requestId,
							responseWaitMilliseconds: null,
							result: 'failed',
							resultReason: 'load_failed',
							schedulerQueueWaitMilliseconds: null,
							streamReadMilliseconds: null,
							telemetryRecorder,
							traceContext: telemetryTraceContext,
							visibleItemCount: change.visibleFileCount,
						});
					}
					viewerActions.setLastDemandDispatchDebugState({
						status: 'failed',
						reason: error instanceof Error ? error.message : String(error),
					});
				});
		},
		[isActive, isActiveRef, telemetryRecorder, telemetryTraceContext, viewerActions],
	);

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

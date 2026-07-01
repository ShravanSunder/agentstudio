import { useCallback, type MutableRefObject } from 'react';

import type { WorktreeFileDemandStimulus } from '../features/worktree-file/models/worktree-file-protocol-models.js';
import type { BridgeTelemetryRecorder } from '../foundation/telemetry/bridge-telemetry-recorder.js';
import type { BridgeTraceContext } from '../foundation/telemetry/bridge-trace-context.js';
import { recordBridgeWorktreeFileVisibleDemandSettledTelemetrySample } from '../foundation/telemetry/bridge-viewer-telemetry-adapter.js';
import type { WorktreeFileSurfaceRuntime } from '../worktree-file-surface/worktree-file-surface-runtime.js';
import type { BridgeFileViewerVisibleFileDemandChange } from './bridge-file-viewer-contracts.js';
import {
	firstSuccessfulDemandLoadResult,
	visibleFileDemandChangeWithoutDescriptorId,
	visibleFileDemandSignature,
	visibleViewportDemandDispatchSatisfied,
	type BridgeFileViewerDemandDispatchDebugState,
} from './bridge-file-viewer-state.js';

interface UseBridgeFileViewerVisibleDemandControllerProps {
	readonly activeVisibleDemandSignatureRef: MutableRefObject<string | null>;
	readonly demandDispatchRequestIdRef: MutableRefObject<number>;
	readonly isActive: boolean;
	readonly isActiveRef: MutableRefObject<boolean>;
	readonly lastDemandDispatchDebugStateRef: MutableRefObject<BridgeFileViewerDemandDispatchDebugState>;
	readonly lastVisibleDemandSignatureRef: MutableRefObject<string | null>;
	readonly recentlyUpdatedDemandInFlightRef: MutableRefObject<boolean>;
	readonly recentlyUpdatedDemandRequestIdRef: MutableRefObject<number>;
	readonly recentlyUpdatedLoadedDescriptorIdRef: MutableRefObject<string | null>;
	readonly runtimeRef: MutableRefObject<WorktreeFileSurfaceRuntime | null>;
	readonly setLastDemandDispatchDebugState: (
		lastDemandDispatchDebugState: BridgeFileViewerDemandDispatchDebugState,
	) => void;
	readonly telemetryRecorder: BridgeTelemetryRecorder | undefined;
	readonly telemetryTraceContext: BridgeTraceContext | null;
}

export function useBridgeFileViewerVisibleDemandController(
	props: UseBridgeFileViewerVisibleDemandControllerProps,
): (change: BridgeFileViewerVisibleFileDemandChange) => void {
	const {
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
		setLastDemandDispatchDebugState,
		telemetryRecorder,
		telemetryTraceContext,
	} = props;

	return useCallback(
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
					setLastDemandDispatchDebugState(nextDebugState);
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
					setLastDemandDispatchDebugState({
						status: 'failed',
						reason: error instanceof Error ? error.message : String(error),
					});
				});
		},
		[
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
			setLastDemandDispatchDebugState,
			telemetryRecorder,
			telemetryTraceContext,
		],
	);
}

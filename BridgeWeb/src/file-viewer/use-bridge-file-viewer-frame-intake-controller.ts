import { useCallback, useEffect, type MutableRefObject } from 'react';

import type {
	WorktreeFileProtocolFrame,
	WorktreeFileSurfaceSourceIdentity,
} from '../features/worktree-file/models/worktree-file-protocol-models.js';
import type { BridgeTelemetryRecorder } from '../foundation/telemetry/bridge-telemetry-recorder.js';
import type { BridgeTraceContext } from '../foundation/telemetry/bridge-trace-context.js';
import { recordBridgeViewerWorktreeFileTreeTelemetrySample } from '../foundation/telemetry/bridge-viewer-telemetry-adapter.js';
import type {
	WorktreeFileFrameSubscriptionFactory,
	WorktreeFileInitialSurface,
	WorktreeFileSurfaceProvenance,
} from '../worktree-file-surface/worktree-file-app.js';
import type { WorktreeFileSurfaceRuntime } from '../worktree-file-surface/worktree-file-surface-runtime.js';
import {
	applyFramesToRuntime,
	reconcileOpenFileStateWithFrames,
	worktreeTreeWindowRowCount,
	type BridgeFileViewerInitialSurfaceLoadState,
	type BridgeFileViewerOpenState,
	type BridgeFileViewerRenderState,
} from './bridge-file-viewer-state.js';
import { useBridgeFileViewerInitialSurfaceLoader } from './use-bridge-file-viewer-initial-surface-loader.js';

interface UseBridgeFileViewerFrameIntakeControllerProps {
	readonly replayPendingRecentlyUpdatedDemand: (nextState: BridgeFileViewerRenderState) => void;
	readonly initialFrames: readonly WorktreeFileProtocolFrame[] | undefined;
	readonly loadInitialFrames: (() => Promise<readonly WorktreeFileProtocolFrame[]>) | undefined;
	readonly loadInitialSurface: (() => Promise<WorktreeFileInitialSurface>) | undefined;
	readonly openFileBodyRef: MutableRefObject<string | null>;
	readonly openFileRequestIdRef: MutableRefObject<number>;
	readonly openPendingSelectedDescriptor: (nextState: BridgeFileViewerRenderState) => void;
	readonly renderStateRef: MutableRefObject<BridgeFileViewerRenderState>;
	readonly runtimeRef: MutableRefObject<WorktreeFileSurfaceRuntime | null>;
	readonly setInitialSurfaceLoadState: (state: BridgeFileViewerInitialSurfaceLoadState) => void;
	readonly setOpenFileState: (
		openFileState:
			| BridgeFileViewerOpenState
			| ((currentOpenFileState: BridgeFileViewerOpenState) => BridgeFileViewerOpenState),
	) => void;
	readonly setRenderState: (renderState: BridgeFileViewerRenderState) => void;
	readonly subscribeFrames: WorktreeFileFrameSubscriptionFactory | undefined;
	readonly telemetryRecorder: BridgeTelemetryRecorder | undefined;
	readonly telemetryTraceContext: BridgeTraceContext | null;
	readonly waitForBridgeReady: ((callback: () => void) => () => void) | undefined;
}

export function useBridgeFileViewerFrameIntakeController(
	props: UseBridgeFileViewerFrameIntakeControllerProps,
): void {
	const {
		initialFrames,
		loadInitialFrames,
		loadInitialSurface,
		openFileBodyRef,
		openFileRequestIdRef,
		openPendingSelectedDescriptor,
		renderStateRef,
		replayPendingRecentlyUpdatedDemand,
		runtimeRef,
		setInitialSurfaceLoadState,
		setOpenFileState,
		setRenderState,
		subscribeFrames,
		telemetryRecorder,
		telemetryTraceContext,
		waitForBridgeReady,
	} = props;
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
			if (telemetryRecorder !== undefined) {
				recordBridgeViewerWorktreeFileTreeTelemetrySample({
					descriptorCount: nextState.descriptors.length,
					durationMilliseconds: performance.now() - applyStartedAt,
					frameCount: frames.length,
					phase: 'worktree_file_frame_apply',
					result: 'success',
					telemetryRecorder,
					traceContext: telemetryTraceContext,
					treeRowCount: nextState.treeRows.length,
					treeWindowRowCount: worktreeTreeWindowRowCount(frames),
				});
			}
			renderStateRef.current = nextState;
			setRenderState(nextState);
			setOpenFileState((currentOpenFileState) =>
				reconcileOpenFileStateWithFrames({
					currentOpenFileState,
					frames,
					openFileBodyRef,
					openFileRequestIdRef,
				}),
			);
			replayPendingRecentlyUpdatedDemand(nextState);
			openPendingSelectedDescriptor(nextState);
			return nextState;
		},
		[
			openFileBodyRef,
			openFileRequestIdRef,
			openPendingSelectedDescriptor,
			renderStateRef,
			replayPendingRecentlyUpdatedDemand,
			runtimeRef,
			setOpenFileState,
			setRenderState,
			telemetryRecorder,
			telemetryTraceContext,
		],
	);

	useBridgeFileViewerInitialSurfaceLoader({
		applyIncomingFrames,
		setInitialSurfaceLoadState,
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
}

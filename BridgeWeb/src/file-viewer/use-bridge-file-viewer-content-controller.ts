import { useCallback, type MutableRefObject } from 'react';

import type { WorktreeFileDescriptor } from '../features/worktree-file/models/worktree-file-protocol-models.js';
import type { BridgeTelemetryRecorder } from '../foundation/telemetry/bridge-telemetry-recorder.js';
import type { BridgeTraceContext } from '../foundation/telemetry/bridge-trace-context.js';
import { recordBridgeViewerFileOpenReadyTelemetrySample } from '../foundation/telemetry/bridge-viewer-telemetry-adapter.js';
import type {
	WorktreeFileSurfaceLoadResult,
	WorktreeFileSurfaceLoadTelemetry,
	WorktreeFileSurfaceRuntime,
} from '../worktree-file-surface/worktree-file-surface-runtime.js';
import type { BridgeFileViewerRenderSnapshotController } from './bridge-file-viewer-render-snapshot-controller.js';
import {
	findLatestDescriptorForOpenFile,
	type BridgeFileViewerOpenState,
	type BridgeFileViewerRefreshDebugState,
	type BridgeFileViewerRenderState,
	type CommitOpenFileBodyProps,
} from './bridge-file-viewer-state.js';

interface UseBridgeFileViewerContentControllerProps {
	readonly activeModeTokenRef: MutableRefObject<number>;
	readonly clearOpenFileBody: () => void;
	readonly clearProvisionalOpenFileBody: () => void;
	readonly commitOpenFileBody: (commit: CommitOpenFileBodyProps) => void;
	readonly isActiveRef: MutableRefObject<boolean>;
	readonly openFileRequestIdRef: MutableRefObject<number>;
	readonly provisionalOpenFileBodyRef: MutableRefObject<string | null>;
	readonly renderStateRef: MutableRefObject<BridgeFileViewerRenderState>;
	readonly publishOpenFileContent: BridgeFileViewerRenderSnapshotController['publishOpenFileContent'];
	readonly publishOpenFileLoadingState: BridgeFileViewerRenderSnapshotController['publishOpenFileLoadingState'];
	readonly publishOpenFileRefreshingState: BridgeFileViewerRenderSnapshotController['publishOpenFileRefreshingState'];
	readonly publishOpenFileTerminalState: BridgeFileViewerRenderSnapshotController['publishOpenFileTerminalState'];
	readonly runtimeRef: MutableRefObject<WorktreeFileSurfaceRuntime | null>;
	readonly setLastOpenLoadTelemetry: (
		lastOpenLoadTelemetry: WorktreeFileSurfaceLoadTelemetry | null,
	) => void;
	readonly setOpenFileState: (openFileState: BridgeFileViewerOpenState) => void;
	readonly setRefreshDebugState: (
		refreshDebugState: BridgeFileViewerRefreshDebugState | null,
	) => void;
	readonly telemetryRecorder: BridgeTelemetryRecorder | undefined;
	readonly telemetryTraceContext: BridgeTraceContext | null;
}

export interface BridgeFileViewerContentController {
	readonly openFile: (descriptor: WorktreeFileDescriptor) => Promise<void>;
	readonly refreshOpenFile: (
		state: BridgeFileViewerOpenState,
		options?: BridgeFileViewerRefreshOpenFileOptions,
	) => Promise<void>;
}

export interface BridgeFileViewerRefreshOpenFileFailureProps {
	readonly descriptor: WorktreeFileDescriptor;
	readonly requestId: number;
	readonly result: Extract<WorktreeFileSurfaceLoadResult, { readonly ok: false }>;
}

export interface BridgeFileViewerRefreshOpenFileOptions {
	readonly onRefreshFailure?: (props: BridgeFileViewerRefreshOpenFileFailureProps) => void;
}

export function useBridgeFileViewerContentController(
	props: UseBridgeFileViewerContentControllerProps,
): BridgeFileViewerContentController {
	const {
		activeModeTokenRef,
		clearOpenFileBody,
		clearProvisionalOpenFileBody,
		commitOpenFileBody,
		isActiveRef,
		openFileRequestIdRef,
		provisionalOpenFileBodyRef,
		publishOpenFileContent,
		publishOpenFileLoadingState,
		publishOpenFileRefreshingState,
		publishOpenFileTerminalState,
		renderStateRef,
		runtimeRef,
		setLastOpenLoadTelemetry,
		setOpenFileState,
		setRefreshDebugState,
		telemetryRecorder,
		telemetryTraceContext,
	} = props;

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
			setLastOpenLoadTelemetry(null);
			publishOpenFileLoadingState(descriptor);
			setOpenFileState({ status: 'loading', path: descriptor.path, descriptor });
			const runtime = runtimeRef.current;
			if (runtime === null) {
				if (
					openFileRequestIdRef.current === requestId &&
					isActiveRef.current &&
					activeModeTokenRef.current === activeModeToken
				) {
					publishOpenFileTerminalState({
						descriptor,
						state: 'failed',
					});
					setOpenFileState({ status: 'failed', path: descriptor.path, descriptor });
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
					publishOpenFileContent({
						body: provisionalOpenFileBodyRef.current,
						bodyVersion: requestId * 2,
						descriptor,
						path: descriptor.path,
						state: 'loading',
					});
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
				publishOpenFileContent({
					body: openFileBody,
					bodyVersion: requestId * 2 + 1,
					descriptor,
					path: descriptor.path,
					state: 'ready',
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
						demandQueueWaitMilliseconds: result.loadTelemetry.demandQueueWaitMilliseconds,
						sourceGeneration: descriptor.sourceIdentity.subscriptionGeneration,
						telemetryRecorder,
						traceContext: telemetryTraceContext,
					});
				}
				clearProvisionalOpenFileBody();
				setLastOpenLoadTelemetry(result.loadTelemetry);
				setOpenFileState({ status: 'ready', path: descriptor.path, descriptor });
				return;
			}
			clearOpenFileBody();
			clearProvisionalOpenFileBody();
			setLastOpenLoadTelemetry(null);
			publishOpenFileTerminalState({
				descriptor,
				state: result.reason === 'content_unavailable' ? 'unavailable' : 'failed',
			});
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
					demandQueueWaitMilliseconds: null,
					sourceGeneration: descriptor.sourceIdentity.subscriptionGeneration,
					telemetryRecorder,
					traceContext: telemetryTraceContext,
				});
			}
			setOpenFileState({
				status: result.reason === 'content_unavailable' ? 'unavailable' : 'failed',
				path: descriptor.path,
				descriptor,
			});
		},
		[
			activeModeTokenRef,
			clearOpenFileBody,
			clearProvisionalOpenFileBody,
			commitOpenFileBody,
			isActiveRef,
			openFileRequestIdRef,
			publishOpenFileContent,
			publishOpenFileLoadingState,
			publishOpenFileTerminalState,
			provisionalOpenFileBodyRef,
			runtimeRef,
			setLastOpenLoadTelemetry,
			setOpenFileState,
			telemetryRecorder,
			telemetryTraceContext,
		],
	);

	const refreshOpenFile = useCallback(
		async (
			state: BridgeFileViewerOpenState,
			options: BridgeFileViewerRefreshOpenFileOptions = {},
		): Promise<void> => {
			if (!isActiveRef.current) {
				return;
			}
			if (state.status !== 'stale') {
				setRefreshDebugState({
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
			setLastOpenLoadTelemetry(null);
			const runtime = runtimeRef.current;
			if (runtime === null) {
				if (
					openFileRequestIdRef.current === requestId &&
					isActiveRef.current &&
					activeModeTokenRef.current === activeModeToken
				) {
					publishOpenFileTerminalState({
						descriptor: state.descriptor,
						state: 'failed',
					});
					setOpenFileState({
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
			if (refreshDescriptor.fileId !== state.descriptor.fileId) {
				await openFile(refreshDescriptor);
				return;
			}
			setOpenFileState({
				status: 'refreshing',
				path: refreshDescriptor.path,
				descriptor: refreshDescriptor,
			});
			publishOpenFileRefreshingState(refreshDescriptor);
			setRefreshDebugState({
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
					publishOpenFileContent({
						body: provisionalOpenFileBodyRef.current,
						bodyVersion: requestId * 2,
						descriptor: refreshDescriptor,
						path: refreshDescriptor.path,
						state: 'refreshing',
					});
				},
				openFileSessionId: refreshDescriptor.fileId,
			});
			if (
				openFileRequestIdRef.current !== requestId ||
				!isActiveRef.current ||
				activeModeTokenRef.current !== activeModeToken
			) {
				setRefreshDebugState({
					commitState: 'ignored',
					currentRequestId: openFileRequestIdRef.current,
					descriptorId: refreshDescriptor.contentDescriptor.ref.descriptorId,
					requestId,
					result: result.ok ? 'ok' : result.reason,
				});
				return;
			}
			setRefreshDebugState({
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
				publishOpenFileContent({
					body: openFileBody,
					bodyVersion: requestId * 2 + 1,
					descriptor: refreshDescriptor,
					path: refreshDescriptor.path,
					state: 'ready',
				});
				clearProvisionalOpenFileBody();
				setLastOpenLoadTelemetry(result.loadTelemetry);
				const refreshedDescriptor =
					findLatestDescriptorForOpenFile({
						descriptor: state.descriptor,
						renderState: renderStateRef.current,
					}) ?? state.descriptor;
				setOpenFileState({
					status: 'ready',
					path: refreshedDescriptor.path,
					descriptor: refreshedDescriptor,
				});
				return;
			}
			if (result.reason === 'content_unavailable') {
				clearOpenFileBody();
			}
			clearProvisionalOpenFileBody();
			setLastOpenLoadTelemetry(null);
			publishOpenFileTerminalState({
				descriptor: refreshDescriptor,
				state: result.reason === 'content_unavailable' ? 'unavailable' : 'stale',
			});
			setOpenFileState({
				status: result.reason === 'content_unavailable' ? 'unavailable' : 'stale',
				path: refreshDescriptor.path,
				descriptor: refreshDescriptor,
			});
			options.onRefreshFailure?.({
				descriptor: refreshDescriptor,
				requestId,
				result,
			});
		},
		[
			activeModeTokenRef,
			clearOpenFileBody,
			clearProvisionalOpenFileBody,
			commitOpenFileBody,
			isActiveRef,
			openFileRequestIdRef,
			publishOpenFileContent,
			publishOpenFileRefreshingState,
			publishOpenFileTerminalState,
			provisionalOpenFileBodyRef,
			renderStateRef,
			runtimeRef,
			setLastOpenLoadTelemetry,
			setOpenFileState,
			setRefreshDebugState,
			openFile,
		],
	);

	return { openFile, refreshOpenFile };
}

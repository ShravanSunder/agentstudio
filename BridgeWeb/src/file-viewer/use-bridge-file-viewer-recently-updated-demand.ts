import { useCallback, useEffect, type MutableRefObject } from 'react';

import type {
	WorktreeFileDescriptor,
	WorktreeFileDescriptorRequest,
	WorktreeFileDemandStimulus,
} from '../features/worktree-file/models/worktree-file-protocol-models.js';
import { canFetchWorktreeFileDescriptorContent } from '../features/worktree-file/models/worktree-file-protocol-models.js';
import type { WorktreeFileSurfaceRuntime } from '../worktree-file-surface/worktree-file-surface-runtime.js';
import {
	bridgeFileViewerRecentlyUpdatedEventDetailSchema,
	bridgeFileViewerRecentlyUpdatedEventName,
	type BridgeFileViewerDemandDispatchDebugState,
	type BridgeFileViewerOpenState,
	type BridgeFileViewerPendingRecentlyUpdatedDescriptorDemand,
	type BridgeFileViewerRenderState,
} from './bridge-file-viewer-state.js';

interface UseBridgeFileViewerRecentlyUpdatedDemandProps {
	readonly isActive: boolean;
	readonly isActiveRef: MutableRefObject<boolean>;
	readonly openFileStateRef: MutableRefObject<BridgeFileViewerOpenState>;
	readonly pendingRecentlyUpdatedDescriptorDemandRef: MutableRefObject<BridgeFileViewerPendingRecentlyUpdatedDescriptorDemand | null>;
	readonly recentlyUpdatedDemandInFlightRef: MutableRefObject<boolean>;
	readonly recentlyUpdatedLoadedDescriptorIdRef: MutableRefObject<string | null>;
	readonly recentlyUpdatedDemandRequestIdRef: MutableRefObject<number>;
	readonly renderStateRef: MutableRefObject<BridgeFileViewerRenderState>;
	readonly requestFileDescriptorForDemand: (request: WorktreeFileDescriptorRequest) => void;
	readonly runtimeRef: MutableRefObject<WorktreeFileSurfaceRuntime | null>;
	readonly setLastDemandDispatchDebugState: (
		state: BridgeFileViewerDemandDispatchDebugState,
	) => void;
}

interface BridgeFileViewerRecentlyUpdatedDemandController {
	readonly replayPendingDescriptorDemand: (nextState: BridgeFileViewerRenderState) => void;
}

export function useBridgeFileViewerRecentlyUpdatedDemand(
	props: UseBridgeFileViewerRecentlyUpdatedDemandProps,
): BridgeFileViewerRecentlyUpdatedDemandController {
	const {
		isActive,
		isActiveRef,
		openFileStateRef,
		pendingRecentlyUpdatedDescriptorDemandRef,
		recentlyUpdatedDemandInFlightRef,
		recentlyUpdatedLoadedDescriptorIdRef,
		recentlyUpdatedDemandRequestIdRef,
		renderStateRef,
		requestFileDescriptorForDemand,
		runtimeRef,
		setLastDemandDispatchDebugState,
	} = props;
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
					setLastDemandDispatchDebugState({
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
					setLastDemandDispatchDebugState({
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
		[
			isActiveRef,
			openFileStateRef,
			recentlyUpdatedDemandInFlightRef,
			recentlyUpdatedDemandRequestIdRef,
			recentlyUpdatedLoadedDescriptorIdRef,
			runtimeRef,
			setLastDemandDispatchDebugState,
		],
	);
	const replayPendingDescriptorDemand = useCallback(
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
		[
			dispatchRecentlyUpdatedDescriptorDemand,
			isActiveRef,
			pendingRecentlyUpdatedDescriptorDemandRef,
		],
	);
	const dispatchRecentlyUpdatedFileDemand = useCallback(
		(event: Event): void => {
			if (!isActive) {
				return;
			}
			if (!(event instanceof CustomEvent)) {
				return;
			}
			const parsedDetail = bridgeFileViewerRecentlyUpdatedEventDetailSchema.safeParse(event.detail);
			if (!parsedDetail.success) {
				return;
			}
			const runtime = runtimeRef.current;
			const currentRenderState = renderStateRef.current;
			if (runtime === null || currentRenderState.sourceIdentity === null) {
				return;
			}
			if (currentRenderState.sourceIdentity.sourceId !== parsedDetail.data.sourceIdentity) {
				return;
			}
			const descriptor = currentRenderState.descriptors.find(
				(candidateDescriptor): boolean => candidateDescriptor.path === parsedDetail.data.path,
			);
			const openFilePathBefore =
				openFileStateRef.current.status === 'idle' ? null : openFileStateRef.current.path;
			const requestId = recentlyUpdatedDemandRequestIdRef.current + 1;
			recentlyUpdatedDemandRequestIdRef.current = requestId;
			if (descriptor !== undefined && canFetchWorktreeFileDescriptorContent(descriptor)) {
				dispatchRecentlyUpdatedDescriptorDemand({
					descriptor,
					openFilePathBefore,
					proximity: parsedDetail.data.proximity,
					requestId,
				});
				return;
			}
			const treeRow = currentRenderState.treeRows.find(
				(candidateTreeRow): boolean => candidateTreeRow.path === parsedDetail.data.path,
			);
			if (treeRow === undefined || treeRow.fileId === undefined) {
				return;
			}
			const descriptorRequest: WorktreeFileDescriptorRequest = {
				fileId: treeRow.fileId,
				lane: parsedDetail.data.proximity === 'nearby' ? 'nearby' : 'speculative',
				path: treeRow.path,
				rowId: treeRow.rowId,
				sourceIdentity: currentRenderState.sourceIdentity,
			};
			pendingRecentlyUpdatedDescriptorDemandRef.current = {
				openFilePathBefore,
				proximity: parsedDetail.data.proximity,
				request: descriptorRequest,
				requestId,
			};
			requestFileDescriptorForDemand(descriptorRequest);
		},
		[
			dispatchRecentlyUpdatedDescriptorDemand,
			isActive,
			openFileStateRef,
			pendingRecentlyUpdatedDescriptorDemandRef,
			recentlyUpdatedDemandRequestIdRef,
			renderStateRef,
			requestFileDescriptorForDemand,
			runtimeRef,
		],
	);

	useEffect((): (() => void) => {
		if (!isActive) {
			return (): void => {};
		}
		window.addEventListener(
			bridgeFileViewerRecentlyUpdatedEventName,
			dispatchRecentlyUpdatedFileDemand,
		);
		return (): void => {
			window.removeEventListener(
				bridgeFileViewerRecentlyUpdatedEventName,
				dispatchRecentlyUpdatedFileDemand,
			);
		};
	}, [dispatchRecentlyUpdatedFileDemand, isActive]);

	return { replayPendingDescriptorDemand };
}

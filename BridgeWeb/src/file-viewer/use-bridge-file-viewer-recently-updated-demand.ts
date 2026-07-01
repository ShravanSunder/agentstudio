import { useCallback, useEffect, type MutableRefObject } from 'react';

import type {
	WorktreeFileDescriptor,
	WorktreeFileDescriptorRequest,
} from '../features/worktree-file/models/worktree-file-protocol-models.js';
import { canFetchWorktreeFileDescriptorContent } from '../features/worktree-file/models/worktree-file-protocol-models.js';
import type { WorktreeFileSurfaceRuntime } from '../worktree-file-surface/worktree-file-surface-runtime.js';
import {
	bridgeFileViewerRecentlyUpdatedEventDetailSchema,
	bridgeFileViewerRecentlyUpdatedEventName,
	type BridgeFileViewerOpenState,
	type BridgeFileViewerPendingRecentlyUpdatedDescriptorDemand,
	type BridgeFileViewerRenderState,
} from './bridge-file-viewer-state.js';

interface UseBridgeFileViewerRecentlyUpdatedDemandProps {
	readonly dispatchRecentlyUpdatedDescriptorDemand: (demandProps: {
		readonly descriptor: WorktreeFileDescriptor;
		readonly openFilePathBefore: string | null;
		readonly proximity: 'nearby' | 'remote';
		readonly requestId: number;
	}) => void;
	readonly isActive: boolean;
	readonly openFileStateRef: MutableRefObject<BridgeFileViewerOpenState>;
	readonly pendingRecentlyUpdatedDescriptorDemandRef: MutableRefObject<BridgeFileViewerPendingRecentlyUpdatedDescriptorDemand | null>;
	readonly recentlyUpdatedDemandRequestIdRef: MutableRefObject<number>;
	readonly renderStateRef: MutableRefObject<BridgeFileViewerRenderState>;
	readonly requestFileDescriptorForDemand: (request: WorktreeFileDescriptorRequest) => void;
	readonly runtimeRef: MutableRefObject<WorktreeFileSurfaceRuntime | null>;
}

export function useBridgeFileViewerRecentlyUpdatedDemand(
	props: UseBridgeFileViewerRecentlyUpdatedDemandProps,
): void {
	const {
		dispatchRecentlyUpdatedDescriptorDemand,
		isActive,
		openFileStateRef,
		pendingRecentlyUpdatedDescriptorDemandRef,
		recentlyUpdatedDemandRequestIdRef,
		renderStateRef,
		requestFileDescriptorForDemand,
		runtimeRef,
	} = props;
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
}

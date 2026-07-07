import { useCallback, useEffect, type MutableRefObject } from 'react';

import type { WorktreeFileDescriptorRequest } from '../features/worktree-file/models/worktree-file-protocol-models.js';
import { canFetchWorktreeFileDescriptorContent } from '../features/worktree-file/models/worktree-file-protocol-models.js';
import {
	bridgeFileViewerRecentlyUpdatedEventDetailSchema,
	bridgeFileViewerRecentlyUpdatedEventName,
	type BridgeFileViewerPendingRecentlyUpdatedDescriptorDemand,
	type BridgeFileViewerRenderState,
} from './bridge-file-viewer-state.js';

interface UseBridgeFileViewerRecentlyUpdatedDemandProps {
	readonly isActive: boolean;
	readonly pendingRecentlyUpdatedDescriptorDemandRef: MutableRefObject<BridgeFileViewerPendingRecentlyUpdatedDescriptorDemand | null>;
	readonly recentlyUpdatedDemandRequestIdRef: MutableRefObject<number>;
	readonly renderStateRef: MutableRefObject<BridgeFileViewerRenderState>;
	readonly requestFileDescriptorForDemand: (request: WorktreeFileDescriptorRequest) => void;
}

interface BridgeFileViewerRecentlyUpdatedDemandController {
	readonly replayPendingDescriptorDemand: (nextState: BridgeFileViewerRenderState) => void;
}

export function useBridgeFileViewerRecentlyUpdatedDemand(
	props: UseBridgeFileViewerRecentlyUpdatedDemandProps,
): BridgeFileViewerRecentlyUpdatedDemandController {
	const {
		isActive,
		pendingRecentlyUpdatedDescriptorDemandRef,
		recentlyUpdatedDemandRequestIdRef,
		renderStateRef,
		requestFileDescriptorForDemand,
	} = props;
	const replayPendingDescriptorDemand = useCallback(
		(nextState: BridgeFileViewerRenderState): void => {
			if (!isActive) {
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
		},
		[isActive, pendingRecentlyUpdatedDescriptorDemandRef],
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
			const currentRenderState = renderStateRef.current;
			if (currentRenderState.sourceIdentity === null) {
				return;
			}
			if (currentRenderState.sourceIdentity.sourceId !== parsedDetail.data.sourceIdentity) {
				return;
			}
			const descriptor = currentRenderState.descriptors.find(
				(candidateDescriptor): boolean => candidateDescriptor.path === parsedDetail.data.path,
			);
			if (descriptor !== undefined && canFetchWorktreeFileDescriptorContent(descriptor)) {
				return;
			}
			const treeRow = currentRenderState.treeRows.find(
				(candidateTreeRow): boolean => candidateTreeRow.path === parsedDetail.data.path,
			);
			if (treeRow === undefined || treeRow.fileId === undefined) {
				return;
			}
			const requestId = recentlyUpdatedDemandRequestIdRef.current + 1;
			recentlyUpdatedDemandRequestIdRef.current = requestId;
			const descriptorRequest: WorktreeFileDescriptorRequest = {
				fileId: treeRow.fileId,
				lane: parsedDetail.data.proximity === 'nearby' ? 'nearby' : 'speculative',
				path: treeRow.path,
				rowId: treeRow.rowId,
				sourceIdentity: currentRenderState.sourceIdentity,
			};
			pendingRecentlyUpdatedDescriptorDemandRef.current = {
				openFilePathBefore: null,
				proximity: parsedDetail.data.proximity,
				request: descriptorRequest,
				requestId,
			};
			requestFileDescriptorForDemand(descriptorRequest);
		},
		[
			isActive,
			pendingRecentlyUpdatedDescriptorDemandRef,
			recentlyUpdatedDemandRequestIdRef,
			renderStateRef,
			requestFileDescriptorForDemand,
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

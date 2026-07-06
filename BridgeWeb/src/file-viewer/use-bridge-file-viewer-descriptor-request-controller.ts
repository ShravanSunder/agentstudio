import { useCallback, type MutableRefObject } from 'react';

import type {
	WorktreeFileDescriptor,
	WorktreeFileDescriptorRequest,
} from '../features/worktree-file/models/worktree-file-protocol-models.js';
import { canFetchWorktreeFileDescriptorContent } from '../features/worktree-file/models/worktree-file-protocol-models.js';
import type { BridgeFileViewerRenderState } from './bridge-file-viewer-state.js';
import type { BridgeFileViewerWorktreeFileSurfaceTransport } from './bridge-file-viewer-worktree-file-surface-transport.js';

interface UseBridgeFileViewerDescriptorRequestControllerProps {
	readonly isActiveRef: MutableRefObject<boolean>;
	readonly openFile: (descriptor: WorktreeFileDescriptor) => void | Promise<void>;
	readonly pendingSelectedDescriptorRequestRef: MutableRefObject<WorktreeFileDescriptorRequest | null>;
	readonly requestFileDescriptorFromHost: BridgeFileViewerWorktreeFileSurfaceTransport['requestFileDescriptor'];
}

interface BridgeFileViewerDescriptorRequestController {
	readonly openPendingSelectedDescriptor: (nextState: BridgeFileViewerRenderState) => void;
	readonly requestFileDescriptor: (request: WorktreeFileDescriptorRequest) => void;
	readonly requestFileDescriptorForDemand: (request: WorktreeFileDescriptorRequest) => void;
}

export function useBridgeFileViewerDescriptorRequestController(
	props: UseBridgeFileViewerDescriptorRequestControllerProps,
): BridgeFileViewerDescriptorRequestController {
	const {
		isActiveRef,
		openFile,
		pendingSelectedDescriptorRequestRef,
		requestFileDescriptorFromHost,
	} = props;
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
		[isActiveRef, openFile, pendingSelectedDescriptorRequestRef],
	);

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
		[isActiveRef, pendingSelectedDescriptorRequestRef, requestFileDescriptorFromHost],
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

	return {
		openPendingSelectedDescriptor,
		requestFileDescriptor,
		requestFileDescriptorForDemand,
	};
}

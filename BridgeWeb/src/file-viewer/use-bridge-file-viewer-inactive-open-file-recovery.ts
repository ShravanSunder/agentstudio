import { useCallback, type MutableRefObject } from 'react';

import type { WorktreeFileSurfaceLoadTelemetry } from '../worktree-file-surface/worktree-file-surface-runtime.js';
import type {
	BridgeFileViewerOpenState,
	BridgeFileViewerRefreshDebugState,
} from './bridge-file-viewer-state.js';

interface UseBridgeFileViewerInactiveOpenFileRecoveryProps {
	readonly openFileRequestIdRef: MutableRefObject<number>;
	readonly openFileStateRef: MutableRefObject<BridgeFileViewerOpenState>;
	readonly setLastOpenLoadTelemetry: (telemetry: WorktreeFileSurfaceLoadTelemetry | null) => void;
	readonly setOpenFileState: (state: BridgeFileViewerOpenState) => void;
	readonly setRefreshDebugState: (state: BridgeFileViewerRefreshDebugState) => void;
}

export function useBridgeFileViewerInactiveOpenFileRecovery(
	props: UseBridgeFileViewerInactiveOpenFileRecoveryProps,
): () => void {
	const {
		openFileRequestIdRef,
		openFileStateRef,
		setLastOpenLoadTelemetry,
		setOpenFileState,
		setRefreshDebugState,
	} = props;
	return useCallback((): void => {
		const currentOpenFileState = openFileStateRef.current;
		if (currentOpenFileState.status === 'loading') {
			openFileRequestIdRef.current = 0;
			setLastOpenLoadTelemetry(null);
			setOpenFileState({ status: 'idle' });
			return;
		}
		if (currentOpenFileState.status === 'refreshing') {
			setLastOpenLoadTelemetry(null);
			setRefreshDebugState({
				commitState: 'ignored',
				currentRequestId: openFileRequestIdRef.current,
				descriptorId: currentOpenFileState.descriptor.contentDescriptor.ref.descriptorId,
				requestId: openFileRequestIdRef.current,
				result: 'stale_completion',
			});
			setOpenFileState({
				status: 'stale',
				path: currentOpenFileState.path,
				descriptor: currentOpenFileState.descriptor,
			});
		}
	}, [
		openFileRequestIdRef,
		openFileStateRef,
		setLastOpenLoadTelemetry,
		setOpenFileState,
		setRefreshDebugState,
	]);
}

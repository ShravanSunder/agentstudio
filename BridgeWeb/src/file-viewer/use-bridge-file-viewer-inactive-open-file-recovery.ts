import { useCallback, type MutableRefObject } from 'react';

import type { WorktreeFileSurfaceLoadTelemetry } from '../worktree-file-surface/worktree-file-surface-runtime.js';
import type { BridgeFileViewerOpenState } from './bridge-file-viewer-state.js';

interface UseBridgeFileViewerInactiveOpenFileRecoveryProps {
	readonly clearOpenFileBody: () => void;
	readonly clearProvisionalOpenFileBody: () => void;
	readonly openFileRequestIdRef: MutableRefObject<number>;
	readonly openFileStateRef: MutableRefObject<BridgeFileViewerOpenState>;
	readonly setLastOpenLoadTelemetry: (telemetry: WorktreeFileSurfaceLoadTelemetry | null) => void;
	readonly setOpenFileState: (state: BridgeFileViewerOpenState) => void;
}

export function useBridgeFileViewerInactiveOpenFileRecovery(
	props: UseBridgeFileViewerInactiveOpenFileRecoveryProps,
): () => void {
	const {
		clearOpenFileBody,
		clearProvisionalOpenFileBody,
		openFileRequestIdRef,
		openFileStateRef,
		setLastOpenLoadTelemetry,
		setOpenFileState,
	} = props;
	return useCallback((): void => {
		const currentOpenFileState = openFileStateRef.current;
		if (currentOpenFileState.status === 'loading') {
			clearOpenFileBody();
			clearProvisionalOpenFileBody();
			openFileRequestIdRef.current = 0;
			setLastOpenLoadTelemetry(null);
			setOpenFileState({ status: 'idle' });
			return;
		}
		if (currentOpenFileState.status === 'refreshing') {
			clearProvisionalOpenFileBody();
			setLastOpenLoadTelemetry(null);
			setOpenFileState({
				status: 'stale',
				path: currentOpenFileState.path,
				descriptor: currentOpenFileState.descriptor,
			});
		}
	}, [
		clearOpenFileBody,
		clearProvisionalOpenFileBody,
		openFileRequestIdRef,
		openFileStateRef,
		setLastOpenLoadTelemetry,
		setOpenFileState,
	]);
}

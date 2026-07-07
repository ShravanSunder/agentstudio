import { useCallback, type MutableRefObject } from 'react';

import type { WorktreeFileDescriptor } from '../features/worktree-file/models/worktree-file-protocol-models.js';
import type { BridgeFileViewerRenderSnapshotController } from './bridge-file-viewer-render-snapshot-controller.js';
import {
	findLatestDescriptorForOpenFile,
	type BridgeFileViewerOpenState,
	type BridgeFileViewerRefreshDebugState,
	type BridgeFileViewerRenderState,
} from './bridge-file-viewer-state.js';

interface UseBridgeFileViewerContentControllerProps {
	readonly dispatchSelectedFileViewContentRequest: BridgeFileViewerRenderSnapshotController['dispatchSelectedFileViewContentRequest'];
	readonly isActiveRef: MutableRefObject<boolean>;
	readonly openFileStartedAtRef: MutableRefObject<number | null>;
	readonly openFileRequestIdRef: MutableRefObject<number>;
	readonly renderStateRef: MutableRefObject<BridgeFileViewerRenderState>;
	readonly publishOpenFileLoadingState: BridgeFileViewerRenderSnapshotController['publishOpenFileLoadingState'];
	readonly publishOpenFileRefreshingState: BridgeFileViewerRenderSnapshotController['publishOpenFileRefreshingState'];
	readonly setLastOpenLoadTelemetry: (lastOpenLoadTelemetry: null) => void;
	readonly setOpenFileState: (openFileState: BridgeFileViewerOpenState) => void;
	readonly setRefreshDebugState: (
		refreshDebugState: BridgeFileViewerRefreshDebugState | null,
	) => void;
}

export interface BridgeFileViewerContentController {
	readonly openFile: (descriptor: WorktreeFileDescriptor) => Promise<void>;
	readonly refreshOpenFile: (state: BridgeFileViewerOpenState) => Promise<void>;
}

export function useBridgeFileViewerContentController(
	props: UseBridgeFileViewerContentControllerProps,
): BridgeFileViewerContentController {
	const {
		dispatchSelectedFileViewContentRequest,
		isActiveRef,
		openFileStartedAtRef,
		openFileRequestIdRef,
		publishOpenFileLoadingState,
		publishOpenFileRefreshingState,
		renderStateRef,
		setLastOpenLoadTelemetry,
		setOpenFileState,
		setRefreshDebugState,
	} = props;

	const openFile = useCallback(
		async (descriptor: WorktreeFileDescriptor): Promise<void> => {
			if (!isActiveRef.current) {
				return;
			}
			const requestId = openFileRequestIdRef.current + 1;
			openFileRequestIdRef.current = requestId;
			openFileStartedAtRef.current = performance.now();
			setLastOpenLoadTelemetry(null);
			publishOpenFileLoadingState(descriptor);
			setOpenFileState({ status: 'loading', path: descriptor.path, descriptor });
			dispatchSelectedFileViewContentRequest({
				descriptor,
				renderState: renderStateRef.current,
				selectedSource: 'user',
			});
		},
		[
			dispatchSelectedFileViewContentRequest,
			isActiveRef,
			openFileStartedAtRef,
			openFileRequestIdRef,
			publishOpenFileLoadingState,
			renderStateRef,
			setLastOpenLoadTelemetry,
			setOpenFileState,
		],
	);

	const refreshOpenFile = useCallback(
		async (state: BridgeFileViewerOpenState): Promise<void> => {
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
			const requestId = openFileRequestIdRef.current + 1;
			openFileRequestIdRef.current = requestId;
			openFileStartedAtRef.current = performance.now();
			setLastOpenLoadTelemetry(null);
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
			dispatchSelectedFileViewContentRequest({
				descriptor: refreshDescriptor,
				renderState: renderStateRef.current,
				selectedSource: 'programmatic',
			});
		},
		[
			dispatchSelectedFileViewContentRequest,
			isActiveRef,
			openFileStartedAtRef,
			openFileRequestIdRef,
			publishOpenFileRefreshingState,
			renderStateRef,
			setLastOpenLoadTelemetry,
			setOpenFileState,
			setRefreshDebugState,
			openFile,
		],
	);

	return { openFile, refreshOpenFile };
}

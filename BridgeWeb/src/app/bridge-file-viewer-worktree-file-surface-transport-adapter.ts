import type { WorktreeFileDescriptorRequest } from '../features/worktree-file/models/worktree-file-protocol-models.js';
import type { BridgeFileViewerWorktreeFileSurfaceTransport } from '../file-viewer/bridge-file-viewer-worktree-file-surface-transport.js';
import type {
	WorktreeFileFrameSubscriber,
	WorktreeFileFrameSubscriptionDispose,
	WorktreeFileInitialSurface,
} from '../worktree-file-surface/worktree-file-app.js';

interface BridgeFileViewerWorktreeFileSurfaceTransportBackend {
	readonly loadWorktreeFileSurface: () => Promise<WorktreeFileInitialSurface>;
	readonly registerWorktreeFileStreamResetRequiredCallback?: (callback: () => void) => () => void;
	readonly requestWorktreeFileDescriptor: (request: WorktreeFileDescriptorRequest) => Promise<void>;
	readonly subscribeWorktreeFileFrames: (
		subscriber: WorktreeFileFrameSubscriber,
	) => WorktreeFileFrameSubscriptionDispose;
}

export function createBridgeFileViewerWorktreeFileSurfaceTransport(
	backend: BridgeFileViewerWorktreeFileSurfaceTransportBackend,
): BridgeFileViewerWorktreeFileSurfaceTransport {
	return {
		loadInitialSurface: backend.loadWorktreeFileSurface,
		...(backend.registerWorktreeFileStreamResetRequiredCallback === undefined
			? {}
			: {
					registerSurfaceStreamResetRequiredCallback:
						backend.registerWorktreeFileStreamResetRequiredCallback,
				}),
		requestFileDescriptor: backend.requestWorktreeFileDescriptor,
		subscribeFrames: backend.subscribeWorktreeFileFrames,
	};
}

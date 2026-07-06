import type { WorktreeFileDescriptorRequest } from '../features/worktree-file/models/worktree-file-protocol-models.js';
import type { BridgeFileViewerWorktreeFileSurfaceTransport } from '../file-viewer/bridge-file-viewer-worktree-file-surface-transport.js';
import type {
	WorktreeFileFrameSubscriber,
	WorktreeFileFrameSubscriptionDispose,
	WorktreeFileInitialSurface,
} from '../worktree-file-surface/worktree-file-app.js';
import type {
	WorktreeFileSurfaceRuntimeFetchedResource,
	WorktreeFileSurfaceRuntimeFetchResourceProps,
} from '../worktree-file-surface/worktree-file-surface-runtime.js';

interface BridgeFileViewerWorktreeFileSurfaceTransportBackend {
	readonly fetchWorktreeFileResource: (
		props: WorktreeFileSurfaceRuntimeFetchResourceProps,
	) => Promise<WorktreeFileSurfaceRuntimeFetchedResource>;
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
		fetchResource: backend.fetchWorktreeFileResource,
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

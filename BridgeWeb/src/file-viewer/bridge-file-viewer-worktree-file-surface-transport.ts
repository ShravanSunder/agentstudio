import type { WorktreeFileDescriptorRequest } from '../features/worktree-file/models/worktree-file-protocol-models.js';
import type {
	WorktreeFileFrameSubscriptionFactory,
	WorktreeFileInitialSurface,
} from '../worktree-file-surface/worktree-file-app.js';
import type {
	WorktreeFileSurfaceRuntimeFetchedResource,
	WorktreeFileSurfaceRuntimeFetchResourceProps,
} from '../worktree-file-surface/worktree-file-surface-runtime.js';

export interface BridgeFileViewerWorktreeFileSurfaceTransport {
	readonly fetchResource?: (
		props: WorktreeFileSurfaceRuntimeFetchResourceProps,
	) => Promise<WorktreeFileSurfaceRuntimeFetchedResource>;
	readonly loadInitialSurface?: () => Promise<WorktreeFileInitialSurface>;
	readonly registerSurfaceStreamResetRequiredCallback?: (callback: () => void) => () => void;
	readonly requestFileDescriptor?: (request: WorktreeFileDescriptorRequest) => Promise<void> | void;
	readonly subscribeFrames?: WorktreeFileFrameSubscriptionFactory;
}

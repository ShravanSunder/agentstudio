import type { ReactNode } from 'react';

import type { BridgeViewerNavigationCommand } from '../app/bridge-viewer-navigation-models.js';
import type {
	WorktreeFileDescriptor,
	WorktreeFileDescriptorRequest,
	WorktreeFileProtocolFrame,
} from '../features/worktree-file/models/worktree-file-protocol-models.js';
import type { BridgeTelemetryRecorder } from '../foundation/telemetry/bridge-telemetry-recorder.js';
import type { BridgeTraceContext } from '../foundation/telemetry/bridge-trace-context.js';
import type {
	WorktreeFileFrameSubscriptionFactory,
	WorktreeFileInitialSurface,
} from '../worktree-file-surface/worktree-file-app.js';
import type {
	WorktreeFileSurfaceRuntimeFetchedResource,
	WorktreeFileSurfaceRuntimeFetchResourceProps,
} from './bridge-file-viewer-runtime.js';

export interface BridgeFileViewerAppProps {
	readonly autoOpenInitialFile?: boolean;
	readonly codeViewWorkerFactory?: () => Worker;
	readonly codeViewWorkerPoolEnabled?: boolean;
	readonly fetchResource?: (
		props: WorktreeFileSurfaceRuntimeFetchResourceProps,
	) => Promise<WorktreeFileSurfaceRuntimeFetchedResource>;
	readonly initialFrames?: readonly WorktreeFileProtocolFrame[];
	readonly isActive?: boolean;
	readonly loadInitialFrames?: () => Promise<readonly WorktreeFileProtocolFrame[]>;
	readonly loadInitialSurface?: () => Promise<WorktreeFileInitialSurface>;
	readonly navigationCommand?: BridgeViewerNavigationCommand;
	readonly onOpenReviewComparison?: (descriptor: WorktreeFileDescriptor) => void;
	readonly requestFileDescriptor?: (request: WorktreeFileDescriptorRequest) => Promise<void> | void;
	readonly subscribeFrames?: WorktreeFileFrameSubscriptionFactory;
	readonly telemetryRecorder?: BridgeTelemetryRecorder | undefined;
	readonly telemetryTraceContext?: BridgeTraceContext | null | undefined;
	readonly viewerHeaderControls?: ReactNode;
	readonly waitForBridgeReady?: (callback: () => void) => () => void;
}

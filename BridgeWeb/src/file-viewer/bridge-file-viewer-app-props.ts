import type { ReactNode } from 'react';

import type { BridgeViewerNavigationCommand } from '../app/bridge-viewer-navigation-models.js';
import type {
	WorktreeFileDescriptor,
	WorktreeFileProtocolFrame,
} from '../features/worktree-file/models/worktree-file-protocol-models.js';
import type { BridgeTelemetryRecorder } from '../foundation/telemetry/bridge-telemetry-recorder.js';
import type { BridgeTraceContext } from '../foundation/telemetry/bridge-trace-context.js';
import type { BridgeFileViewerWorktreeFileSurfaceTransport } from './bridge-file-viewer-worktree-file-surface-transport.js';

export interface BridgeFileViewerAppProps {
	readonly autoOpenInitialFile?: boolean;
	readonly codeViewWorkerFactory?: () => Worker;
	readonly codeViewWorkerPoolEnabled?: boolean;
	readonly initialFrames?: readonly WorktreeFileProtocolFrame[];
	readonly isActive?: boolean;
	readonly loadInitialFrames?: () => Promise<readonly WorktreeFileProtocolFrame[]>;
	readonly navigationCommand?: BridgeViewerNavigationCommand;
	readonly onOpenReviewComparison?: (descriptor: WorktreeFileDescriptor) => void;
	readonly telemetryRecorder?: BridgeTelemetryRecorder | undefined;
	readonly telemetryTraceContext?: BridgeTraceContext | null | undefined;
	readonly viewerHeaderControls?: ReactNode;
	readonly waitForBridgeReady?: (callback: () => void) => () => void;
	readonly worktreeFileSurfaceTransport?: BridgeFileViewerWorktreeFileSurfaceTransport;
}

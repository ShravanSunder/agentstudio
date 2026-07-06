import { recordBridgeViewerWorktreeFileContentFetchTelemetrySample } from '../foundation/telemetry/bridge-viewer-telemetry-adapter.js';
import {
	createWorktreeFileSurfaceRuntime,
	type WorktreeFileSurfaceRuntime,
	type WorktreeFileSurfaceRuntimeFetchResourceProps,
	type WorktreeFileSurfaceRuntimeFetchedResource,
} from '../worktree-file-surface/worktree-file-surface-runtime.js';
import type { BridgeFileViewerAppProps } from './bridge-file-viewer-app.js';
import { defaultFetchWorktreeFileResource, defaultPaneId } from './bridge-file-viewer-state.js';
import type { BridgeFileViewerWorktreeFileSurfaceTransport } from './bridge-file-viewer-worktree-file-surface-transport.js';

export function createBridgeFileViewerRuntime(props: {
	readonly telemetryRecorder: BridgeFileViewerAppProps['telemetryRecorder'];
	readonly telemetryTraceContext: BridgeFileViewerAppProps['telemetryTraceContext'];
	readonly worktreeFileResourceFetcher: BridgeFileViewerWorktreeFileSurfaceTransport['fetchResource'];
}): WorktreeFileSurfaceRuntime {
	const telemetryRecorder = props.telemetryRecorder;
	return createWorktreeFileSurfaceRuntime({
		paneId: defaultPaneId,
		fetchResource: props.worktreeFileResourceFetcher ?? defaultFetchWorktreeFileResource,
		resourceLoadProbe:
			telemetryRecorder === undefined
				? undefined
				: {
						isEnabled: (): boolean => telemetryRecorder.isEnabled('web'),
						now: (): number => performance.now(),
						record: (sample): void => {
							recordBridgeViewerWorktreeFileContentFetchTelemetrySample({
								...sample,
								telemetryRecorder,
								traceContext: props.telemetryTraceContext ?? null,
							});
						},
					},
	});
}

export type {
	WorktreeFileSurfaceRuntimeFetchResourceProps,
	WorktreeFileSurfaceRuntimeFetchedResource,
};

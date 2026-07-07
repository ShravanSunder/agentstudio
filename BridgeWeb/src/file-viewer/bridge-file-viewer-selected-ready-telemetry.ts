import type { WorktreeFileDescriptor } from '../features/worktree-file/models/worktree-file-protocol-models.js';
import type { BridgeTelemetryRecorder } from '../foundation/telemetry/bridge-telemetry-recorder.js';
import type { BridgeTraceContext } from '../foundation/telemetry/bridge-trace-context.js';
import { recordBridgeViewerFileOpenReadyTelemetrySample } from '../foundation/telemetry/bridge-viewer-telemetry-adapter.js';

export function recordBridgeFileViewerSelectedReadyTelemetry(props: {
	readonly descriptor: WorktreeFileDescriptor;
	readonly nowMilliseconds: number;
	readonly requestId: number;
	readonly startedAtMilliseconds: number | null;
	readonly telemetryRecorder: BridgeTelemetryRecorder | undefined;
	readonly traceContext: BridgeTraceContext | null;
}): void {
	if (props.telemetryRecorder === undefined || props.startedAtMilliseconds === null) {
		return;
	}
	recordBridgeViewerFileOpenReadyTelemetrySample({
		disposition: 'worker-selected',
		durationMilliseconds: props.nowMilliseconds - props.startedAtMilliseconds,
		estimatedBytes: props.descriptor.sizeBytes,
		executorInFlightMilliseconds: null,
		executorPendingWaitMilliseconds: null,
		lane: 'foreground',
		requestId: props.requestId,
		resourceBodyRegistryCommitMilliseconds: null,
		resourceFetchResponseWaitMilliseconds: null,
		resourceFirstChunkWaitMilliseconds: null,
		resourceStreamReadMilliseconds: null,
		result: 'success',
		resultReason: null,
		demandQueueWaitMilliseconds: null,
		sourceGeneration: props.descriptor.sourceIdentity.subscriptionGeneration,
		telemetryRecorder: props.telemetryRecorder,
		traceContext: props.traceContext,
	});
}

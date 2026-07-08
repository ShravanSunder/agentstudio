import { createBridgeTelemetryEventSink } from '../bridge/bridge-telemetry-event-sink.js';
import type { BridgeIntakeReceiveDropReason } from '../core/intake/bridge-intake-receiver.js';
import {
	decodeBridgeTelemetryBootstrapConfig,
	type BridgeTelemetryBootstrapConfig,
} from '../foundation/telemetry/bridge-telemetry-bootstrap-config.js';
import type { BridgeTelemetryRecorder } from '../foundation/telemetry/bridge-telemetry-recorder.js';
import type { BridgeTelemetrySink } from '../foundation/telemetry/bridge-telemetry-sink.js';

export function recordNativeWorktreeFileIntakeRejectTelemetry(props: {
	readonly frameGeneration: number;
	readonly reason: BridgeIntakeReceiveDropReason;
	readonly receiverGeneration: number;
	readonly reopenSignaled: boolean;
	readonly streamIdMatches: boolean;
	readonly telemetryRecorder: BridgeTelemetryRecorder;
}): void {
	if (!props.telemetryRecorder.isEnabled('web')) {
		return;
	}
	props.telemetryRecorder.record({
		scope: 'web',
		name: 'performance.bridge.web.worktree_file_intake_reject',
		durationMilliseconds: null,
		traceContext: null,
		stringAttributes: {
			'agentstudio.bridge.phase': 'intake',
			'agentstudio.bridge.plane': 'control',
			'agentstudio.bridge.priority': 'hot',
			'agentstudio.bridge.result': 'dropped',
			'agentstudio.bridge.result_reason': props.reason,
			'agentstudio.bridge.slice': 'connection_health',
			'agentstudio.bridge.transport': 'intake',
		},
		numericAttributes: {
			'agentstudio.bridge.intake.generation': props.frameGeneration,
			'agentstudio.bridge.worktree_file.receiver.generation': props.receiverGeneration,
		},
		booleanAttributes: {
			'agentstudio.bridge.reopen_signaled': props.reopenSignaled,
			'agentstudio.bridge.stream_id_matches': props.streamIdMatches,
		},
	});
	props.telemetryRecorder.flush();
}

export function extractNativeWorktreeFileTelemetryConfig(
	event: Event,
): BridgeTelemetryBootstrapConfig | null {
	const detail = 'detail' in event ? event.detail : null;
	if (typeof detail !== 'object' || detail === null || !('telemetryConfig' in detail)) {
		return null;
	}
	return decodeBridgeTelemetryBootstrapConfig(detail.telemetryConfig);
}

export function createNativeWorktreeFileTelemetrySink(props: {
	readonly endpointUrl: BridgeTelemetryBootstrapConfig['endpointUrl'];
	readonly fetch?: (input: RequestInfo | URL, init?: RequestInit) => boolean | Promise<Response>;
}): BridgeTelemetrySink {
	return createBridgeTelemetryEventSink(
		props.fetch === undefined
			? { endpointUrl: props.endpointUrl }
			: { endpointUrl: props.endpointUrl, fetch: props.fetch },
	);
}

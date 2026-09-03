import type { BridgeTelemetrySample } from '../../foundation/telemetry/bridge-telemetry-event.js';

export type BridgeOperationLifecyclePhase =
	| 'worker_application_started'
	| 'worker_application_terminal'
	| 'panel_chrome_publish_started'
	| 'panel_chrome_publish_terminal'
	| 'file_content_operation_started'
	| 'file_content_operation_terminal'
	| 'file_descriptor_wait_started'
	| 'file_descriptor_wait_terminal'
	| 'content_operation_started'
	| 'content_operation_terminal'
	| 'main_thread_install_started'
	| 'main_thread_install_terminal'
	| 'render_operation_started'
	| 'render_operation_terminal'
	| 'paint_fulfillment_started'
	| 'paint_fulfillment_terminal';

export interface BridgeOperationLifecycleTelemetryRecorder {
	readonly record: (sample: BridgeTelemetrySample) => void;
}

export function recordBridgeOperationLifecycleTelemetry(props: {
	readonly operationCorrelationId: string;
	readonly phase: BridgeOperationLifecyclePhase;
	readonly recorder?: BridgeOperationLifecycleTelemetryRecorder | undefined;
	readonly result: 'cancelled' | 'failure' | 'stale' | 'started' | 'success';
	readonly stageAttempt: number;
	readonly viewer: 'file' | 'review';
}): void {
	props.recorder?.record({
		booleanAttributes: {},
		durationMilliseconds: null,
		name: 'performance.bridge.web.operation_lifecycle',
		numericAttributes: { 'agentstudio.bridge.stage.attempt': props.stageAttempt },
		scope: 'web',
		stringAttributes: {
			'agentstudio.bridge.operation.id': props.operationCorrelationId,
			'agentstudio.bridge.phase': props.phase,
			'agentstudio.bridge.plane': 'data',
			'agentstudio.bridge.priority': 'hot',
			'agentstudio.bridge.protocol': props.viewer === 'file' ? 'worktree-file' : 'review',
			'agentstudio.bridge.result': props.result,
			'agentstudio.bridge.slice': 'content_fetch',
			'agentstudio.bridge.transport': 'worker',
			'agentstudio.bridge.viewer': props.viewer,
		},
		traceContext: null,
	});
}

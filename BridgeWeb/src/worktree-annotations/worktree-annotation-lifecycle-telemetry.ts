import type { BridgeTelemetrySample } from '../foundation/telemetry/bridge-telemetry-event.js';

export type WorktreeAnnotationLifecyclePhase =
	| 'annotation_invalidation_received'
	| 'annotation_paint_started'
	| 'annotation_paint_terminal'
	| 'content_transfer_started'
	| 'content_transfer_terminal'
	| 'descriptor_claim_started'
	| 'descriptor_claim_terminal'
	| 'main_thread_install_started'
	| 'main_thread_install_terminal'
	| 'metadata_delivery_started'
	| 'metadata_delivery_terminal'
	| 'native_annotation_work_started'
	| 'native_annotation_work_terminal'
	| 'projection_store_started'
	| 'projection_convergence_started'
	| 'projection_convergence_terminal'
	| 'projection_query_started'
	| 'projection_query_terminal'
	| 'projection_store_terminal'
	| 'projection_validation_started'
	| 'projection_validation_terminal'
	| 'worker_application_started'
	| 'worker_application_terminal';

export interface WorktreeAnnotationLifecycleTelemetryRecorder {
	readonly record: (sample: BridgeTelemetrySample) => void;
}

export function recordWorktreeAnnotationLifecycleTelemetry(props: {
	readonly operationCorrelationId: string;
	readonly phase: WorktreeAnnotationLifecyclePhase;
	readonly recorder?: WorktreeAnnotationLifecycleTelemetryRecorder | undefined;
	readonly result: 'cancelled' | 'failure' | 'stale' | 'started' | 'success' | 'unavailable';
	readonly sourceGeneration?: number | undefined;
	readonly stageAttempt?: number | undefined;
	readonly transport: 'local' | 'worker';
	readonly viewer: 'file' | 'review';
}): void {
	props.recorder?.record({
		scope: 'web',
		name: 'performance.bridge.web.annotation_lifecycle',
		durationMilliseconds: null,
		traceContext: null,
		stringAttributes: {
			'agentstudio.bridge.operation.id': props.operationCorrelationId,
			'agentstudio.bridge.phase': props.phase,
			'agentstudio.bridge.plane': 'data',
			'agentstudio.bridge.priority': 'hot',
			'agentstudio.bridge.result': props.result,
			'agentstudio.bridge.slice': 'review_projection',
			'agentstudio.bridge.transport': props.transport,
			'agentstudio.bridge.viewer': props.viewer,
		},
		numericAttributes: {
			'agentstudio.bridge.stage.attempt': props.stageAttempt ?? 0,
			...(props.sourceGeneration === undefined
				? {}
				: { 'agentstudio.bridge.source.generation': props.sourceGeneration }),
		},
		booleanAttributes: {},
	});
}

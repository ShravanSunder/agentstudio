import type { BridgeTelemetrySample } from '../foundation/telemetry/bridge-telemetry-event.js';

export type WorktreeAnnotationLifecyclePhase =
	| 'annotation_catalog_main_begin'
	| 'annotation_catalog_main_commit'
	| 'annotation_catalog_main_window'
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

type WorktreeAnnotationCatalogStagingTelemetry =
	| {
			readonly catalogRevision: number;
			readonly encodedUnitByteCount: number;
			readonly entryCount: number;
			readonly kind: 'begin';
			readonly presentationRevisionAfter: number;
			readonly presentationRevisionBefore: number;
	  }
	| {
			readonly catalogRevision: number;
			readonly encodedUnitByteCount: number;
			readonly entryCount: number;
			readonly kind: 'commit';
			readonly presentationRevisionAfter: number;
			readonly presentationRevisionBefore: number;
			readonly windowCount: number;
	  }
	| {
			readonly catalogRevision: number;
			readonly encodedUnitByteCount: number;
			readonly entryCount: number;
			readonly kind: 'window';
			readonly presentationRevisionAfter: number;
			readonly presentationRevisionBefore: number;
			readonly windowOrdinal: number;
	  };

export interface WorktreeAnnotationLifecycleTelemetryRecorder {
	readonly record: (sample: BridgeTelemetrySample) => void;
}

export function recordWorktreeAnnotationLifecycleTelemetry(props: {
	readonly catalogStaging?: WorktreeAnnotationCatalogStagingTelemetry | undefined;
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
			...(props.transport === 'local' && props.phase.startsWith('annotation_catalog_main_')
				? { 'agentstudio.bridge.source.monotonic_ms': performance.now() }
				: {}),
			...(props.sourceGeneration === undefined
				? {}
				: { 'agentstudio.bridge.source.generation': props.sourceGeneration }),
			...catalogStagingNumericAttributes(props.catalogStaging),
		},
		booleanAttributes: {},
	});
}

function catalogStagingNumericAttributes(
	measurement: WorktreeAnnotationCatalogStagingTelemetry | undefined,
): Readonly<Record<string, number>> {
	if (measurement === undefined) return {};
	const commonAttributes = {
		'agentstudio.bridge.annotation.catalog.entry.count': measurement.entryCount,
		'agentstudio.bridge.annotation.catalog.revision': measurement.catalogRevision,
		'agentstudio.bridge.annotation.catalog.unit.byte_count': measurement.encodedUnitByteCount,
		'agentstudio.bridge.presentation.revision.after': measurement.presentationRevisionAfter,
		'agentstudio.bridge.presentation.revision.before': measurement.presentationRevisionBefore,
	};
	switch (measurement.kind) {
		case 'begin':
			return commonAttributes;
		case 'commit':
			return {
				...commonAttributes,
				'agentstudio.bridge.annotation.catalog.window.count': measurement.windowCount,
			};
		case 'window':
			return {
				...commonAttributes,
				'agentstudio.bridge.annotation.catalog.window.ordinal': measurement.windowOrdinal,
			};
	}
	return assertNeverCatalogStagingTelemetry(measurement);
}

function assertNeverCatalogStagingTelemetry(_value: never): never {
	throw new Error('Unhandled annotation catalog staging telemetry kind.');
}

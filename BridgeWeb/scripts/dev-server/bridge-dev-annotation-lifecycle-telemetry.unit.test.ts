import { describe, expect, test } from 'vitest';

import type { BridgeTelemetrySample } from '../../src/foundation/telemetry/bridge-telemetry-event.js';
import { bridgeDevTelemetryObservationIsSafe } from './bridge-dev-telemetry-otlp.js';

describe('Bridge dev annotation lifecycle telemetry', () => {
	test('admits scrubbed correlation and rejects raw identifiers', () => {
		expect(
			bridgeDevTelemetryObservationIsSafe({
				scenario: 'lifecycle-proof',
				samples: [annotationLifecycleSample('a'.repeat(64))],
			}),
		).toBe(true);
		expect(
			bridgeDevTelemetryObservationIsSafe({
				scenario: 'lifecycle-proof',
				samples: [annotationLifecycleSample('raw-operation-uuid')],
			}),
		).toBe(false);
	});

	test('admits aggregate catalog staging measurements without private identity', () => {
		const sample = annotationCatalogLifecycleSample();

		expect(
			bridgeDevTelemetryObservationIsSafe({
				scenario: 'catalog-staging-proof',
				samples: [sample],
			}),
		).toBe(true);
		expect(
			bridgeDevTelemetryObservationIsSafe({
				scenario: 'catalog-staging-proof',
				samples: [
					{
						...sample,
						stringAttributes: {
							...sample.stringAttributes,
							'agentstudio.bridge.annotation.catalog.session_id':
								'00000000-0000-7000-8000-000000000001',
						},
					},
				],
			}),
		).toBe(false);
	});
});

function annotationLifecycleSample(operationCorrelationId: string): BridgeTelemetrySample {
	return {
		scope: 'web',
		name: 'performance.bridge.web.annotation_lifecycle',
		durationMilliseconds: null,
		traceContext: null,
		stringAttributes: {
			'agentstudio.bridge.operation.id': operationCorrelationId,
			'agentstudio.bridge.phase': 'main_thread_install_terminal',
			'agentstudio.bridge.plane': 'data',
			'agentstudio.bridge.priority': 'hot',
			'agentstudio.bridge.result': 'success',
			'agentstudio.bridge.slice': 'review_projection',
			'agentstudio.bridge.transport': 'local',
			'agentstudio.bridge.viewer': 'review',
		},
		numericAttributes: {
			'agentstudio.bridge.source.generation': 7,
			'agentstudio.bridge.stage.attempt': 0,
		},
		booleanAttributes: {},
	};
}

function annotationCatalogLifecycleSample(): BridgeTelemetrySample {
	return {
		scope: 'web',
		name: 'performance.bridge.web.annotation_lifecycle',
		durationMilliseconds: null,
		traceContext: null,
		stringAttributes: {
			'agentstudio.bridge.operation.id': 'a'.repeat(64),
			'agentstudio.bridge.phase': 'annotation_catalog_main_commit',
			'agentstudio.bridge.plane': 'data',
			'agentstudio.bridge.priority': 'hot',
			'agentstudio.bridge.result': 'success',
			'agentstudio.bridge.slice': 'review_projection',
			'agentstudio.bridge.transport': 'local',
			'agentstudio.bridge.viewer': 'review',
		},
		numericAttributes: {
			'agentstudio.bridge.annotation.catalog.entry.count': 2_001,
			'agentstudio.bridge.annotation.catalog.revision': 9,
			'agentstudio.bridge.annotation.catalog.unit.byte_count': 131_000,
			'agentstudio.bridge.annotation.catalog.window.count': 3,
			'agentstudio.bridge.presentation.revision.after': 8,
			'agentstudio.bridge.presentation.revision.before': 7,
			'agentstudio.bridge.source.monotonic_ms': 12_345.5,
			'agentstudio.bridge.stage.attempt': 0,
		},
		booleanAttributes: {},
	};
}

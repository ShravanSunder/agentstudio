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

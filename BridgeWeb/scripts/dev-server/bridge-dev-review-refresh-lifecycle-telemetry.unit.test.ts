import { describe, expect, test } from 'vitest';

import type { BridgeTelemetrySample } from '../../src/foundation/telemetry/bridge-telemetry-event.js';
import { bridgeDevTelemetryObservationIsSafe } from './bridge-dev-telemetry-otlp.js';

describe('Bridge dev Review refresh lifecycle telemetry', () => {
	test('admits controlled lifecycle aggregates and rejects raw paths', () => {
		const sample = reviewRefreshLifecycleSample();
		expect(
			bridgeDevTelemetryObservationIsSafe({
				scenario: 'review-refresh-proof',
				samples: [sample],
			}),
		).toBe(true);
		expect(
			bridgeDevTelemetryObservationIsSafe({
				scenario: 'review-refresh-proof',
				samples: [
					{
						...sample,
						stringAttributes: {
							...sample.stringAttributes,
							'agentstudio.bridge.result_reason': '/Users/private/review.ts',
						},
					},
				],
			}),
		).toBe(false);
	});
});

function reviewRefreshLifecycleSample(): BridgeTelemetrySample {
	return {
		booleanAttributes: {},
		durationMilliseconds: null,
		name: 'performance.bridge.web.review_refresh_lifecycle',
		numericAttributes: {
			'agentstudio.bridge.review.generation': 7,
			'agentstudio.bridge.review.refresh.affected_stable_file.count': 3,
		},
		scope: 'web',
		stringAttributes: {
			'agentstudio.bridge.phase': 'review_refresh_install_terminal',
			'agentstudio.bridge.plane': 'control',
			'agentstudio.bridge.priority': 'hot',
			'agentstudio.bridge.result': 'success',
			'agentstudio.bridge.result_reason': 'none',
			'agentstudio.bridge.review.refresh.install_trigger': 'apply_now',
			'agentstudio.bridge.review.refresh.presentation_class': 'promoted',
			'agentstudio.bridge.review.refresh.promotion_reason': 'files',
			'agentstudio.bridge.slice': 'review_metadata',
			'agentstudio.bridge.transport': 'worker',
		},
		traceContext: null,
	};
}

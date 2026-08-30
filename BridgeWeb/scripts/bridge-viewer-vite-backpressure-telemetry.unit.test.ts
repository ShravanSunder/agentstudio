import { describe, expect, test } from 'vitest';

import { backpressureTelemetryObservation } from '../tests/e2e/bridge-viewer-vite-backpressure-telemetry.ts';

interface TelemetrySampleProps {
	readonly name: string;
	readonly numericAttributes?: Readonly<Record<string, number>>;
	readonly stringAttributes?: Readonly<Record<string, string>>;
}

describe('Vite backpressure telemetry settlement', () => {
	test('does not classify viewer-less worker replacement snapshots as Review failures', () => {
		const observation = backpressureTelemetryObservation({
			expectedReceiptProducedCount: null,
			status: settledReviewStatus([
				workerReplacementSample(),
				workerReplacementSample(),
				workerReplacementSample(),
			]),
			viewer: 'review',
		});

		expect(observation?.currentCount).toBe(0);
		expect(observation?.failureCount).toBe(0);
	});

	test('keeps Review unsettled while its latest publication count is nonzero', () => {
		const observation = backpressureTelemetryObservation({
			expectedReceiptProducedCount: null,
			status: settledReviewStatus([], 3),
			viewer: 'review',
		});

		expect(observation).toBeNull();
	});
});

function settledReviewStatus(
	additionalSamples: readonly Readonly<Record<string, unknown>>[],
	currentPublicationCount = 0,
): Readonly<Record<string, unknown>> {
	return {
		recentSamples: [
			telemetrySample({
				name: 'performance.bridge.web.render_disposition_admission',
				numericAttributes: {
					'agentstudio.bridge.render_disposition.pending_count': 0,
					'agentstudio.bridge.render_disposition.produced_count': 1,
					'agentstudio.bridge.render_disposition.retained_count': 0,
				},
				stringAttributes: { 'agentstudio.bridge.viewer': 'review' },
			}),
			telemetrySample({
				name: 'performance.bridge.worker.render_publication_outstanding',
				numericAttributes: {
					'agentstudio.bridge.render_publication.current_count': currentPublicationCount,
					'agentstudio.bridge.render_publication.high_water_mark': 1,
				},
				stringAttributes: { 'agentstudio.bridge.viewer': 'review' },
			}),
			...additionalSamples,
		],
	};
}

function workerReplacementSample(): Readonly<Record<string, unknown>> {
	return telemetrySample({
		name: 'performance.bridge.web.comm_worker_session',
		stringAttributes: {
			'agentstudio.bridge.worker.session_state': 'replacement_requested',
		},
	});
}

function telemetrySample(props: TelemetrySampleProps): Readonly<Record<string, unknown>> {
	return {
		name: props.name,
		numericAttributes: props.numericAttributes ?? {},
		stringAttributes: props.stringAttributes ?? {},
	};
}

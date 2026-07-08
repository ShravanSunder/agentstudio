import { describe, expect, test } from 'vitest';

import { makeBridgeReviewPackage } from '../foundation/review-package/bridge-review-package-test-support.js';
import type { BridgeTelemetrySample } from '../foundation/telemetry/bridge-telemetry-event.js';
import type {
	BridgeTelemetryFlushProps,
	BridgeTelemetryRecorder,
} from '../foundation/telemetry/bridge-telemetry-recorder.js';
import {
	makeTelemetryPackageKey,
	recordIntakeApplyTelemetryForSlice,
	recordPushDropTelemetry,
	recordReviewIntakeFrameTelemetry,
	recordReviewStartupTelemetry,
} from './bridge-app-review-telemetry.js';

describe('bridge app review telemetry', () => {
	test('package telemetry keys include revision to reject stale paint tokens', () => {
		const reviewPackage = makeBridgeReviewPackage();

		expect(makeTelemetryPackageKey(reviewPackage)).not.toBe(
			makeTelemetryPackageKey({
				...reviewPackage,
				revision: reviewPackage.revision + 1,
			}),
		);
	});

	test('uses idle flushes for review startup hot-path samples', () => {
		const samples: BridgeTelemetrySample[] = [];
		const flushes: BridgeTelemetryFlushProps[] = [];
		const telemetryRecorder = makeCapturingTelemetryRecorder(samples, flushes);

		recordReviewStartupTelemetry({
			telemetryRecorder,
			phase: 'selection_commit',
			slice: 'review_projection',
			transport: 'worker',
			traceContext: null,
			durationMilliseconds: 12,
			result: 'success',
		});

		expect(samples.map((sample): string => sample.name)).toEqual([
			'performance.bridge.web.selection_commit',
		]);
		expect(flushes).toEqual([{}]);
	});

	test('uses idle flushes for review intake apply and intake frame hot-path samples', () => {
		const samples: BridgeTelemetrySample[] = [];
		const flushes: BridgeTelemetryFlushProps[] = [];
		const telemetryRecorder = makeCapturingTelemetryRecorder(samples, flushes);

		recordIntakeApplyTelemetryForSlice({
			telemetryRecorder,
			slice: 'review_metadata',
			traceContext: null,
			transport: 'intake',
		});
		recordReviewIntakeFrameTelemetry({
			telemetryRecorder,
			frameKind: 'review.metadataSnapshot',
			generation: 1,
			sequence: 1,
			result: 'success',
			resultReason: 'none',
		});

		expect(samples.map((sample): string => sample.name)).toEqual([
			'performance.bridge.web.intake_apply',
			'performance.bridge.web.intake_frame',
		]);
		expect(flushes).toEqual([{}, {}]);
	});

	test('aggregates duplicate stale push drops into one browser telemetry sample', async () => {
		const samples: BridgeTelemetrySample[] = [];
		const flushes: BridgeTelemetryFlushProps[] = [];
		const telemetryRecorder = makeCapturingTelemetryRecorder(samples, flushes);

		recordPushDropTelemetry(telemetryRecorder, 'stale_push');
		recordPushDropTelemetry(telemetryRecorder, 'stale_push');

		expect(samples).toEqual([]);
		expect(flushes).toEqual([]);

		await Promise.resolve();

		expect(samples).toHaveLength(1);
		expect(samples[0]).toMatchObject({
			name: 'performance.bridge.web.telemetry_drop',
			stringAttributes: {
				'agentstudio.bridge.telemetry.drop_reason': 'stale_push',
			},
			numericAttributes: {
				'agentstudio.bridge.telemetry.dropped_count': 2,
			},
		});
		expect(flushes).toEqual([{}]);
	});

	test('flushes pending stale push aggregate before recording another drop reason', async () => {
		const samples: BridgeTelemetrySample[] = [];
		const flushes: BridgeTelemetryFlushProps[] = [];
		const telemetryRecorder = makeCapturingTelemetryRecorder(samples, flushes);

		recordPushDropTelemetry(telemetryRecorder, 'stale_push');
		recordPushDropTelemetry(telemetryRecorder, 'push_decode_failed');

		expect(
			samples.map(
				(sample): string =>
					sample.stringAttributes['agentstudio.bridge.telemetry.drop_reason'] ?? 'missing',
			),
		).toEqual(['stale_push', 'push_decode_failed']);
		expect(
			samples.map(
				(sample): number =>
					sample.numericAttributes['agentstudio.bridge.telemetry.dropped_count'] ?? -1,
			),
		).toEqual([1, 1]);
		expect(flushes).toEqual([{}, {}]);
	});
});

function makeCapturingTelemetryRecorder(
	samples: BridgeTelemetrySample[],
	flushes: BridgeTelemetryFlushProps[],
): BridgeTelemetryRecorder {
	return {
		isEnabled: (): boolean => true,
		record: (sample): void => {
			samples.push(sample);
		},
		measure: (props) => props.operation(),
		flush: (props = {}): boolean => {
			flushes.push(props);
			return true;
		},
	};
}

import { afterEach, describe, expect, test, vi } from 'vitest';

import type {
	BridgeTelemetryBatch,
	BridgeTelemetrySample,
} from '../../foundation/telemetry/bridge-telemetry-event.js';
import { createBridgeCommWorkerTelemetryClient } from './bridge-comm-worker-telemetry.js';

describe('Bridge comm worker telemetry', () => {
	afterEach(() => {
		vi.restoreAllMocks();
		vi.unstubAllGlobals();
		vi.useRealTimers();
	});

	test('batches telemetry through worker buffer and dedicated scheme post', () => {
		const batches: BridgeTelemetryBatch[] = [];
		const idleCallbacks: Array<() => void> = [];
		const client = createBridgeCommWorkerTelemetryClient({
			config: {
				enabledScopes: new Set(['web']),
				endpointUrl: 'agentstudio://telemetry/batch',
				maxEncodedBatchBytes: 16_384,
				maxSamplesPerBatch: 4,
				minimumFlushIntervalMilliseconds: 250,
				scenario: 'bridge-runtime',
			},
			scheduleIdleFlush: (callback): void => {
				idleCallbacks.push(callback);
			},
			sink: {
				flush: (batch): boolean => {
					batches.push(batch);
					return true;
				},
			},
		});

		client.record(makeSample('performance.bridge.web.first_render'));

		expect(batches).toEqual([]);
		expect(idleCallbacks).toHaveLength(1);
		idleCallbacks[0]?.();
		expect(batches).toEqual([
			{
				schemaVersion: 1,
				scenario: 'bridge-runtime',
				sequence: 1,
				samples: [makeSample('performance.bridge.web.first_render')],
			},
		]);
		expect(client.flush()).toBe(true);
		expect(client.transport.endpointUrl).toBe('agentstudio://telemetry/batch');
	});

	test('falls back to a timer when idle callbacks are unavailable', () => {
		vi.useFakeTimers();
		vi.stubGlobal('requestIdleCallback', undefined);
		const batches: BridgeTelemetryBatch[] = [];
		const client = createBridgeCommWorkerTelemetryClient({
			config: {
				enabledScopes: new Set(['web']),
				endpointUrl: 'agentstudio://telemetry/batch',
				maxEncodedBatchBytes: 16_384,
				maxSamplesPerBatch: 4,
				minimumFlushIntervalMilliseconds: 250,
				scenario: 'bridge-runtime',
			},
			sink: {
				flush: (batch): boolean => {
					batches.push(batch);
					return true;
				},
			},
		});

		client.record(makeSample('performance.bridge.web.review_ready'));

		expect(batches).toEqual([]);
		vi.runOnlyPendingTimers();
		expect(batches.map((batch) => batch.samples.map((sample) => sample.name))).toEqual([
			['performance.bridge.web.review_ready'],
		]);
	});
});

function makeSample(name: string): BridgeTelemetrySample {
	return {
		scope: 'web',
		name,
		durationMilliseconds: 1,
		traceContext: null,
		stringAttributes: {
			'agentstudio.bridge.phase': 'render',
			'agentstudio.bridge.plane': 'data',
			'agentstudio.bridge.priority': 'hot',
			'agentstudio.bridge.slice': 'review_metadata',
			'agentstudio.bridge.transport': 'scheme',
		},
		numericAttributes: {},
		booleanAttributes: {},
	};
}

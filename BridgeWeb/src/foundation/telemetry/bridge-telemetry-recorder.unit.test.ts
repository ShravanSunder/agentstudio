import { describe, expect, test } from 'vitest';

import type { BridgeTelemetryBatch } from './bridge-telemetry-event.js';
import { createBridgeTelemetryRecorder } from './bridge-telemetry-recorder.js';

describe('bridge telemetry recorder', () => {
	test('records enabled scopes and flushes batches through the sink', () => {
		const batches: BridgeTelemetryBatch[] = [];
		let now = 10;
		const recorder = createBridgeTelemetryRecorder(
			{
				enabledScopes: new Set(['web']),
				maxSamplesPerBatch: 4,
				maxEncodedBatchBytes: 16_384,
				minimumFlushIntervalMilliseconds: 250,
				rpcMethodName: 'system.bridgeTelemetry',
				scenario: 'bridge-runtime',
			},
			{
				flush: (batch: BridgeTelemetryBatch): boolean => {
					batches.push(batch);
					return true;
				},
			},
			(): number => {
				now += 5;
				return now;
			},
		);

		const result = recorder.measure({
			scope: 'web',
			name: 'performance.bridge.web.first_render',
			traceContext: null,
			stringAttributes: { 'agentstudio.bridge.phase': 'render' },
			operation: (): string => 'ok',
		});
		recorder.record({
			scope: 'webkit',
			name: 'performance.bridge.webkit.rpc_dispatch',
			durationMilliseconds: 1,
			traceContext: null,
			stringAttributes: {},
			numericAttributes: {},
			booleanAttributes: {},
		});

		expect(result).toBe('ok');
		expect(recorder.flush()).toBe(true);
		expect(batches).toHaveLength(1);
		expect(batches[0]?.samples.map((sample) => sample.name)).toEqual([
			'performance.bridge.web.first_render',
		]);
	});

	test('emits drop summaries when the buffer saturates', () => {
		const batches: BridgeTelemetryBatch[] = [];
		const recorder = createBridgeTelemetryRecorder(
			{
				enabledScopes: new Set(['web']),
				maxSamplesPerBatch: 1,
				maxEncodedBatchBytes: 16_384,
				minimumFlushIntervalMilliseconds: 250,
				rpcMethodName: 'system.bridgeTelemetry',
				scenario: 'bridge-runtime',
			},
			{
				flush: (batch: BridgeTelemetryBatch): boolean => {
					batches.push(batch);
					return true;
				},
			},
		);

		recorder.record(makeSample('performance.bridge.web.first_render'));
		recorder.record(makeSample('performance.bridge.web.rpc_send'));
		recorder.flush();

		expect(batches[0]?.samples.map((sample) => sample.name)).toEqual([
			'performance.bridge.web.first_render',
			'performance.bridge.web.telemetry_drop',
		]);
		expect(batches[0]?.samples[1]?.stringAttributes).toMatchObject({
			'agentstudio.bridge.phase': 'dropped',
			'agentstudio.bridge.plane': 'observability',
			'agentstudio.bridge.priority': 'best_effort',
			'agentstudio.bridge.slice': 'telemetry_drop',
			'agentstudio.bridge.telemetry.drop_reason': 'queue_saturated',
			'agentstudio.bridge.transport': 'rpc',
		});
	});

	test('throttles burst flushes unless a boundary forces delivery', () => {
		const batches: BridgeTelemetryBatch[] = [];
		let now = 1_000;
		const recorder = createBridgeTelemetryRecorder(
			{
				enabledScopes: new Set(['web']),
				maxSamplesPerBatch: 4,
				maxEncodedBatchBytes: 16_384,
				minimumFlushIntervalMilliseconds: 250,
				rpcMethodName: 'system.bridgeTelemetry',
				scenario: 'bridge-runtime',
			},
			{
				flush: (batch: BridgeTelemetryBatch): boolean => {
					batches.push(batch);
					return true;
				},
			},
			(): number => now,
		);

		recorder.record(makeSample('performance.bridge.web.push_apply'));
		expect(recorder.flush()).toBe(true);
		recorder.record(makeSample('performance.bridge.web.push_apply'));
		now += 100;
		expect(recorder.flush()).toBe(true);
		expect(batches).toHaveLength(1);

		expect(recorder.flush({ force: true })).toBe(true);

		expect(batches.map((batch) => batch.samples.map((sample) => sample.name))).toEqual([
			['performance.bridge.web.push_apply'],
			['performance.bridge.web.push_apply'],
		]);
	});

	test('keeps drained samples retryable when the sink rejects a flush', () => {
		const batches: BridgeTelemetryBatch[] = [];
		let shouldAcceptFlush = false;
		const recorder = createBridgeTelemetryRecorder(
			{
				enabledScopes: new Set(['web']),
				maxSamplesPerBatch: 4,
				maxEncodedBatchBytes: 16_384,
				minimumFlushIntervalMilliseconds: 250,
				rpcMethodName: 'system.bridgeTelemetry',
				scenario: 'bridge-runtime',
			},
			{
				flush: (batch: BridgeTelemetryBatch): boolean => {
					if (!shouldAcceptFlush) {
						shouldAcceptFlush = true;
						return false;
					}
					batches.push(batch);
					return true;
				},
			},
		);

		recorder.record(makeSample('performance.bridge.web.rpc_send'));

		expect(recorder.flush({ force: true })).toBe(false);
		expect(recorder.flush({ force: true })).toBe(true);
		expect(batches.map((batch) => batch.samples.map((sample) => sample.name))).toEqual([
			['performance.bridge.web.rpc_send'],
		]);
	});

	test('retries failed non-forced flushes without throttle delay', () => {
		const batches: BridgeTelemetryBatch[] = [];
		let shouldAcceptFlush = false;
		const recorder = createBridgeTelemetryRecorder(
			{
				enabledScopes: new Set(['web']),
				maxSamplesPerBatch: 4,
				maxEncodedBatchBytes: 16_384,
				minimumFlushIntervalMilliseconds: 250,
				rpcMethodName: 'system.bridgeTelemetry',
				scenario: 'bridge-runtime',
			},
			{
				flush: (batch: BridgeTelemetryBatch): boolean => {
					if (!shouldAcceptFlush) {
						shouldAcceptFlush = true;
						return false;
					}
					batches.push(batch);
					return true;
				},
			},
			(): number => 1_000,
		);

		recorder.record(makeSample('performance.bridge.web.first_render'));

		expect(recorder.flush()).toBe(false);
		expect(recorder.flush()).toBe(true);
		expect(batches.map((batch) => batch.samples.map((sample) => sample.name))).toEqual([
			['performance.bridge.web.first_render'],
		]);
	});
});

function makeSample(name: string): {
	readonly scope: 'web';
	readonly name: string;
	readonly durationMilliseconds: number;
	readonly traceContext: null;
	readonly stringAttributes: Readonly<Record<string, string>>;
	readonly numericAttributes: Readonly<Record<string, number>>;
	readonly booleanAttributes: Readonly<Record<string, boolean>>;
} {
	return {
		scope: 'web' as const,
		name,
		durationMilliseconds: 1,
		traceContext: null,
		stringAttributes: {},
		numericAttributes: {},
		booleanAttributes: {},
	};
}

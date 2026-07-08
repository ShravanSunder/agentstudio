import { describe, expect, test } from 'vitest';

import type { BridgeTelemetryBatch } from './bridge-telemetry-event.js';
import {
	createBridgeTelemetryRecorder,
	createBridgeTelemetryRecorderFromClient,
	type BridgeTelemetryRecorderClient,
} from './bridge-telemetry-recorder.js';

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
				endpointUrl: 'agentstudio://telemetry/batch',
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
		expect(batches[0]?.sequence).toBe(1);
	});

	test('emits drop summaries when the buffer saturates', () => {
		const batches: BridgeTelemetryBatch[] = [];
		const recorder = createBridgeTelemetryRecorder(
			{
				enabledScopes: new Set(['web']),
				maxSamplesPerBatch: 1,
				maxEncodedBatchBytes: 16_384,
				minimumFlushIntervalMilliseconds: 250,
				endpointUrl: 'agentstudio://telemetry/batch',
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
			'agentstudio.bridge.telemetry.event_name': 'performance.bridge.web.rpc_send',
			'agentstudio.bridge.telemetry.lane': 'unknown',
			'agentstudio.bridge.telemetry.result': 'unknown',
			'agentstudio.bridge.transport': 'scheme',
		});
	});

	test('emits required-class shed counters when required samples are dropped', () => {
		const batches: BridgeTelemetryBatch[] = [];
		const recorder = createBridgeTelemetryRecorder(
			{
				enabledScopes: new Set(['web']),
				maxSamplesPerBatch: 1,
				maxEncodedBatchBytes: 16_384,
				minimumFlushIntervalMilliseconds: 250,
				endpointUrl: 'agentstudio://telemetry/batch',
				scenario: 'bridge-runtime',
			},
			{
				flush: (batch: BridgeTelemetryBatch): boolean => {
					batches.push(batch);
					return true;
				},
			},
		);

		recorder.record(makeSample('performance.bridge.web.rpc_send', 'warm'));
		recorder.record(makeSample('performance.bridge.web.selection_commit', 'warm'));
		recorder.flush();

		expect(
			batches[0]?.samples.map((sample) => ({
				name: sample.name,
				reason: sample.stringAttributes['agentstudio.bridge.telemetry.drop_reason'],
				droppedCount: sample.numericAttributes['agentstudio.bridge.telemetry.dropped_count'],
			})),
		).toEqual([
			{
				name: 'performance.bridge.web.rpc_send',
				reason: undefined,
				droppedCount: undefined,
			},
			{
				name: 'performance.bridge.web.telemetry_drop',
				reason: 'queue_saturated',
				droppedCount: 1,
			},
			{
				name: 'performance.bridge.web.telemetry_drop',
				reason: 'required_event_shed',
				droppedCount: 1,
			},
		]);
	});

	test('schedules non-forced flushing through idle time', () => {
		const batches: BridgeTelemetryBatch[] = [];
		const idleCallbacks: Array<() => void> = [];
		const recorder = createBridgeTelemetryRecorder(
			{
				enabledScopes: new Set(['web']),
				maxSamplesPerBatch: 4,
				maxEncodedBatchBytes: 16_384,
				minimumFlushIntervalMilliseconds: 250,
				endpointUrl: 'agentstudio://telemetry/batch',
				scenario: 'bridge-runtime',
			},
			{
				flush: (batch: BridgeTelemetryBatch): boolean => {
					batches.push(batch);
					return true;
				},
			},
			(): number => 1_000,
			(callback): void => {
				idleCallbacks.push(callback);
			},
		);

		recorder.record(makeSample('performance.bridge.web.first_render'));

		expect(batches).toEqual([]);
		expect(idleCallbacks).toHaveLength(1);
		idleCallbacks[0]?.();
		expect(batches.map((batch) => batch.samples.map((sample) => sample.name))).toEqual([
			['performance.bridge.web.first_render'],
		]);
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
				endpointUrl: 'agentstudio://telemetry/batch',
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
				endpointUrl: 'agentstudio://telemetry/batch',
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
		expect(batches[0]?.sequence).toBe(1);
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
				endpointUrl: 'agentstudio://telemetry/batch',
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
		expect(batches[0]?.sequence).toBe(1);
		expect(batches.map((batch) => batch.samples.map((sample) => sample.name))).toEqual([
			['performance.bridge.web.first_render'],
		]);
	});

	test('main recorder hands samples to worker telemetry client without owning flush order', () => {
		const samples: string[] = [];
		let flushCount = 0;
		const client: BridgeTelemetryRecorderClient = {
			record: (sample): void => {
				samples.push(sample.name);
			},
			flush: (): boolean => {
				flushCount += 1;
				return true;
			},
		};
		let now = 10;
		const recorder = createBridgeTelemetryRecorderFromClient(
			{
				enabledScopes: new Set(['web']),
				endpointUrl: 'agentstudio://telemetry/batch',
				maxSamplesPerBatch: 4,
				maxEncodedBatchBytes: 16_384,
				minimumFlushIntervalMilliseconds: 250,
				scenario: 'bridge-runtime',
			},
			client,
			(): number => {
				now += 5;
				return now;
			},
		);

		recorder.record(makeSample('performance.bridge.web.first_render'));
		recorder.measure({
			scope: 'web',
			name: 'performance.bridge.web.selection_commit',
			traceContext: null,
			stringAttributes: { 'agentstudio.bridge.phase': 'selection' },
			operation: (): string => 'ok',
		});

		expect(samples).toEqual([
			'performance.bridge.web.first_render',
			'performance.bridge.web.selection_commit',
		]);
		expect(recorder.flush({ force: true })).toBe(true);
		expect(flushCount).toBe(1);
	});
});

function makeSample(
	name: string,
	priority = 'unknown',
): {
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
		stringAttributes: { 'agentstudio.bridge.priority': priority },
		numericAttributes: {},
		booleanAttributes: {},
	};
}

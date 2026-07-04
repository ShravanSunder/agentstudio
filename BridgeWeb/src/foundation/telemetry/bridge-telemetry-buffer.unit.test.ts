import { describe, expect, test } from 'vitest';

import { createBridgeTelemetryBuffer } from './bridge-telemetry-buffer.js';
import type { BridgeTelemetrySample } from './bridge-telemetry-event.js';

describe('bridge telemetry buffer', () => {
	test('bounds samples and reports dropped count on drain', () => {
		const buffer = createBridgeTelemetryBuffer(1);
		const sample = makeSample('performance.bridge.web.first_render');

		buffer.add(sample);
		buffer.add(makeSample('performance.bridge.web.rpc_send'));
		const snapshot = buffer.drain();
		const secondSnapshot = buffer.drain();

		expect(snapshot.samples).toEqual([sample]);
		expect(snapshot.droppedCount).toBe(1);
		expect(secondSnapshot.samples).toEqual([]);
		expect(secondSnapshot.droppedCount).toBe(0);
	});

	test('drops oldest optional samples by encoded byte cap and emits aggregate counters', () => {
		const buffer = createBridgeTelemetryBuffer({
			maxSamplesPerBatch: 16,
			maxEncodedBatchBytes: 540,
		});
		const optionalFirstRender = makeSample('performance.bridge.web.first_render', {
			'agentstudio.bridge.phase': 'render',
			'agentstudio.bridge.plane': 'data',
			'agentstudio.bridge.priority': 'best_effort',
			'agentstudio.bridge.result': 'success',
			'agentstudio.bridge.slice': 'review_metadata',
			'agentstudio.bridge.telemetry.event_class': 'optional',
			'agentstudio.bridge.transport': 'intake',
		});
		const requiredRPCSend = makeSample('performance.bridge.web.rpc_send', {
			'agentstudio.bridge.phase': 'send',
			'agentstudio.bridge.plane': 'control',
			'agentstudio.bridge.priority': 'warm',
			'agentstudio.bridge.result': 'success',
			'agentstudio.bridge.rpc.method_class': 'review',
			'agentstudio.bridge.slice': 'review_rpc',
			'agentstudio.bridge.telemetry.event_class': 'required',
			'agentstudio.bridge.transport': 'rpc',
		});

		buffer.add(optionalFirstRender);
		buffer.add(
			makeSample('performance.bridge.web.first_render', optionalFirstRender.stringAttributes),
		);
		buffer.add(requiredRPCSend);
		const snapshot = buffer.drain();

		expect(snapshot.samples).toEqual([requiredRPCSend]);
		const telemetrySnapshot = snapshot as typeof snapshot & {
			readonly dropCounters: readonly unknown[];
			readonly shedRequiredEventCount: number;
		};
		expect(telemetrySnapshot.dropCounters).toEqual([
			{
				count: 2,
				eventName: 'performance.bridge.web.first_render',
				lane: 'best_effort',
				result: 'success',
				reason: 'encoded_byte_cap',
			},
		]);
		expect(telemetrySnapshot.shedRequiredEventCount).toBe(0);
	});
});

function makeSample(
	name: string,
	stringAttributes: Readonly<Record<string, string>> = {},
): BridgeTelemetrySample {
	return {
		scope: 'web',
		name,
		durationMilliseconds: 1,
		traceContext: null,
		stringAttributes,
		numericAttributes: {},
		booleanAttributes: {},
	};
}

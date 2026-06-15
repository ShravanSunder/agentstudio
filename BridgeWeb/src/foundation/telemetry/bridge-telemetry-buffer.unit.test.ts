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
});

function makeSample(name: string): BridgeTelemetrySample {
	return {
		scope: 'web',
		name,
		durationMilliseconds: 1,
		traceContext: null,
		stringAttributes: {},
		numericAttributes: {},
		booleanAttributes: {},
	};
}

import { describe, expect, test, vi } from 'vitest';

import type { BridgeTelemetryBootstrapConfig } from './bridge-telemetry-bootstrap-config.js';
import type { BridgeTelemetrySample } from './bridge-telemetry-event.js';
import {
	createBridgeTelemetryRecorder,
	createBridgeTelemetryRecorderFromClient,
} from './bridge-telemetry-recorder.js';

describe('Bridge telemetry recorder producer adapter', () => {
	test('is inert and allocation-free when telemetry is disabled', () => {
		const operation = vi.fn(() => 7);
		const recorder = createBridgeTelemetryRecorder(null);

		expect(recorder.isEnabled('web')).toBe(false);
		recorder.record(makeSample('web'));
		expect(
			recorder.measure({
				scope: 'web',
				name: 'performance.bridge.web.measure',
				traceContext: null,
				stringAttributes: {},
				operation,
			}),
		).toBe(7);
		expect(operation).toHaveBeenCalledOnce();
		expect(recorder.flush()).toBe(true);
	});

	test('forwards enabled samples directly without buffering or encoding', () => {
		const samples: BridgeTelemetrySample[] = [];
		const flush = vi.fn(() => true);
		const recorder = createBridgeTelemetryRecorderFromClient(
			makeConfig(),
			{ record: (sample): void => void samples.push(sample), flush },
			(): number => 10,
		);

		recorder.record(makeSample('web'));
		recorder.record(makeSample('swift'));

		expect(samples.map((sample) => sample.scope)).toEqual(['web']);
		expect(recorder.flush()).toBe(true);
		expect(flush).toHaveBeenCalledOnce();
	});

	test('measures enabled work and posts one compact source sample immediately', () => {
		const samples: BridgeTelemetrySample[] = [];
		const clockValues = [10, 16];
		const recorder = createBridgeTelemetryRecorderFromClient(
			makeConfig(),
			{ record: (sample): void => void samples.push(sample), flush: (): boolean => true },
			(): number => clockValues.shift() ?? 16,
		);

		const result = recorder.measure({
			scope: 'web',
			name: 'performance.bridge.web.measure',
			traceContext: null,
			stringAttributes: { 'agentstudio.bridge.priority': 'hot' },
			operation: (): string => 'result',
		});

		expect(result).toBe('result');
		expect(samples).toEqual([
			expect.objectContaining({
				name: 'performance.bridge.web.measure',
				durationMilliseconds: 6,
			}),
		]);
	});
});

function makeConfig(): BridgeTelemetryBootstrapConfig {
	return {
		enabledScopes: new Set(['web'] as const),
		scenario: 'bridge-runtime',
	};
}

function makeSample(scope: 'swift' | 'web'): BridgeTelemetrySample {
	return {
		scope,
		name: 'performance.bridge.web.sample',
		durationMilliseconds: 1,
		traceContext: null,
		stringAttributes: { 'agentstudio.bridge.priority': 'hot' },
		numericAttributes: {},
		booleanAttributes: {},
	};
}

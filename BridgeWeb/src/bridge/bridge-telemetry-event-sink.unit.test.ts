import { describe, expect, test, vi } from 'vitest';

import { createBridgeTelemetryEventSink } from './bridge-telemetry-event-sink.js';

describe('bridge telemetry event sink', () => {
	test('posts telemetry batches to the dedicated scheme endpoint', () => {
		const sendCommand = vi.fn();
		const postedBodies: string[] = [];
		const sink = createBridgeTelemetryEventSink({
			endpointUrl: 'agentstudio://telemetry/batch',
			fetch: (input: RequestInfo | URL, init?: RequestInit): boolean => {
				expect(input).toBe('agentstudio://telemetry/batch');
				expect(init?.method).toBe('POST');
				expect(init?.headers).toEqual({ 'Content-Type': 'application/json' });
				const body = init?.body;
				expect(typeof body).toBe('string');
				if (typeof body !== 'string') {
					throw new Error('Expected telemetry POST body to be a string');
				}
				postedBodies.push(body);
				return true;
			},
		});

		const didFlush = sink.flush({
			schemaVersion: 1,
			scenario: 'bridge-runtime',
			streamId: 'page',
			sequence: 1,
			samples: [],
		});

		expect(didFlush).toBe(true);
		expect(sendCommand).not.toHaveBeenCalled();
		expect(postedBodies.map((body) => JSON.parse(body) as unknown)).toEqual([
			{
				schemaVersion: 1,
				scenario: 'bridge-runtime',
				streamId: 'page',
				sequence: 1,
				samples: [],
			},
		]);
	});
});

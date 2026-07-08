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

	test('serializes telemetry posts so native receives each stream in batch order', async () => {
		const firstPost = deferredResponse();
		const fetchTelemetry = vi
			.fn<NonNullable<Parameters<typeof createBridgeTelemetryEventSink>[0]['fetch']>>()
			.mockReturnValueOnce(firstPost.promise)
			.mockResolvedValueOnce(new Response('', { status: 200 }));
		const sink = createBridgeTelemetryEventSink({
			endpointUrl: 'agentstudio://telemetry/batch',
			fetch: fetchTelemetry,
		});

		expect(
			sink.flush({
				schemaVersion: 1,
				scenario: 'bridge-runtime',
				streamId: 'page',
				sequence: 1,
				samples: [],
			}),
		).toBe(true);
		expect(
			sink.flush({
				schemaVersion: 1,
				scenario: 'bridge-runtime',
				streamId: 'page',
				sequence: 2,
				samples: [],
			}),
		).toBe(true);

		await Promise.resolve();

		expect(fetchTelemetry).toHaveBeenCalledTimes(1);

		firstPost.resolve(new Response('', { status: 200 }));
		await Promise.resolve();
		await Promise.resolve();

		expect(fetchTelemetry).toHaveBeenCalledTimes(2);
		const postedBodies = fetchTelemetry.mock.calls.map((call) =>
			JSON.parse(telemetryPostBodyString(call[1])),
		);
		expect(postedBodies.map((body) => body.sequence)).toEqual([1, 2]);
	});
});

function telemetryPostBodyString(init: RequestInit | undefined): string {
	const body = init?.body;
	expect(typeof body).toBe('string');
	if (typeof body !== 'string') {
		throw new Error('Expected telemetry POST body to be a string');
	}
	return body;
}

function deferredResponse(): {
	readonly promise: Promise<Response>;
	readonly resolve: (response: Response) => void;
} {
	let resolveDeferred: ((response: Response) => void) | null = null;
	const promise = new Promise<Response>((resolve) => {
		resolveDeferred = resolve;
	});
	return {
		promise,
		resolve: (response): void => {
			resolveDeferred?.(response);
		},
	};
}

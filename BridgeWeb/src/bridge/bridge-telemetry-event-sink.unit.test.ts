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

	test('continues queued telemetry posts after the active post rejects', async () => {
		const firstPost = deferredResponse();
		const fetchTelemetry = vi
			.fn<NonNullable<Parameters<typeof createBridgeTelemetryEventSink>[0]['fetch']>>()
			.mockReturnValueOnce(firstPost.promise)
			.mockResolvedValueOnce(new Response('', { status: 200 }));
		const sink = createBridgeTelemetryEventSink({
			endpointUrl: 'agentstudio://telemetry/batch',
			fetch: fetchTelemetry,
		});

		expect(sink.flush(makeTelemetryBatch(1))).toBe(true);
		expect(sink.flush(makeTelemetryBatch(2))).toBe(true);

		firstPost.reject(new Error('network failed'));
		await Promise.resolve();
		await Promise.resolve();

		expect(fetchTelemetry).toHaveBeenCalledTimes(2);
		expect(postedTelemetrySequences(fetchTelemetry)).toEqual([1, 2]);
	});

	test('retains a queued telemetry body when starting the queued post throws', async () => {
		const firstPost = deferredResponse();
		let shouldThrowForQueuedStart = true;
		const fetchTelemetry = vi.fn<
			NonNullable<Parameters<typeof createBridgeTelemetryEventSink>[0]['fetch']>
		>((_input: RequestInfo | URL, _init?: RequestInit): Promise<Response> | boolean => {
			if (fetchTelemetry.mock.calls.length === 1) {
				return firstPost.promise;
			}
			if (shouldThrowForQueuedStart) {
				shouldThrowForQueuedStart = false;
				throw new Error('queued post failed to start');
			}
			return true;
		});
		const sink = createBridgeTelemetryEventSink({
			endpointUrl: 'agentstudio://telemetry/batch',
			fetch: fetchTelemetry,
		});

		expect(sink.flush(makeTelemetryBatch(1))).toBe(true);
		expect(sink.flush(makeTelemetryBatch(2))).toBe(true);

		firstPost.resolve(new Response('', { status: 200 }));
		await Promise.resolve();
		await Promise.resolve();

		expect(fetchTelemetry).toHaveBeenCalledTimes(2);
		expect(postedTelemetrySequences(fetchTelemetry)).toEqual([1, 2]);

		expect(sink.flush(makeTelemetryBatch(3))).toBe(true);
		await Promise.resolve();
		await Promise.resolve();

		expect(fetchTelemetry).toHaveBeenCalledTimes(4);
		expect(postedTelemetrySequences(fetchTelemetry)).toEqual([1, 2, 2, 3]);
	});

	test('returns false when the immediate telemetry post fails to start', () => {
		let shouldThrow = true;
		const fetchTelemetry = vi.fn<
			NonNullable<Parameters<typeof createBridgeTelemetryEventSink>[0]['fetch']>
		>(() => {
			if (shouldThrow) {
				shouldThrow = false;
				throw new Error('post failed to start');
			}
			return true;
		});
		const sink = createBridgeTelemetryEventSink({
			endpointUrl: 'agentstudio://telemetry/batch',
			fetch: fetchTelemetry,
		});

		expect(sink.flush(makeTelemetryBatch(1))).toBe(false);
		expect(sink.flush(makeTelemetryBatch(1))).toBe(true);

		expect(fetchTelemetry).toHaveBeenCalledTimes(2);
		expect(postedTelemetrySequences(fetchTelemetry)).toEqual([1, 1]);
	});
});

function makeTelemetryBatch(
	sequence: number,
): Parameters<ReturnType<typeof createBridgeTelemetryEventSink>['flush']>[0] {
	return {
		schemaVersion: 1,
		scenario: 'bridge-runtime',
		streamId: 'page',
		sequence,
		samples: [],
	};
}

function postedTelemetrySequences(
	fetchTelemetry: ReturnType<
		typeof vi.fn<NonNullable<Parameters<typeof createBridgeTelemetryEventSink>[0]['fetch']>>
	>,
): number[] {
	return fetchTelemetry.mock.calls.map((call) => telemetryPostSequence(call[1]));
}

function telemetryPostSequence(init: RequestInit | undefined): number {
	const parsedBody: unknown = JSON.parse(telemetryPostBodyString(init));
	if (
		typeof parsedBody !== 'object' ||
		parsedBody === null ||
		!('sequence' in parsedBody) ||
		typeof parsedBody.sequence !== 'number'
	) {
		throw new Error('Expected telemetry POST body to include a numeric sequence');
	}
	return parsedBody.sequence;
}

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
	readonly reject: (error: Error) => void;
	readonly resolve: (response: Response) => void;
} {
	let rejectDeferred: ((error: Error) => void) | null = null;
	let resolveDeferred: ((response: Response) => void) | null = null;
	const promise = new Promise<Response>((resolve, reject) => {
		rejectDeferred = reject;
		resolveDeferred = resolve;
	});
	return {
		promise,
		reject: (error): void => {
			rejectDeferred?.(error);
		},
		resolve: (response): void => {
			resolveDeferred?.(response);
		},
	};
}

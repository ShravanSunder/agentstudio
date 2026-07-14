import { describe, expect, it } from 'vitest';

import type { BridgeTelemetryWorkerBatchRequest } from './bridge-telemetry-worker-contracts.js';
import { createBridgeTelemetryWorkerFetchTransport } from './bridge-telemetry-worker-transport.js';
import { BridgeTelemetryWorkerTransportError } from './bridge-telemetry-worker-transport.js';

describe('telemetry worker fetch transport', () => {
	it('owns the telemetry route, capability header, and encoded bytes', async () => {
		const requests: Array<{ input: RequestInfo | URL; init?: RequestInit }> = [];
		const fetchTelemetry: typeof fetch = async (input, init) => {
			requests.push({ input, ...(init === undefined ? {} : { init }) });
			return Response.json({
				type: 'accepted',
				telemetrySessionId: 'telemetry-session-entry',
				batchSequence: 1,
				nextExpectedBatchSequence: 2,
				acceptedSampleCount: 0,
				acceptedLossCount: 0,
			});
		};
		const transport = createBridgeTelemetryWorkerFetchTransport({
			endpointUrl: 'agentstudio://telemetry/batch',
			fetch: fetchTelemetry,
		});
		const request: BridgeTelemetryWorkerBatchRequest = {
			type: 'telemetry.batch',
			schemaVersion: 2,
			telemetrySessionId: 'telemetry-session-entry',
			batchSequence: 1,
			samples: [],
			lossSummaries: [],
		};
		const body = new TextEncoder().encode(JSON.stringify(request));

		await transport.postBatch(request, body, 'telemetry-capability-0123456789abcd');

		expect(requests).toHaveLength(1);
		expect(requests[0]?.input).toBe('agentstudio://telemetry/batch');
		expect(requests[0]?.init).toMatchObject({
			method: 'POST',
			headers: {
				'X-AgentStudio-Bridge-Telemetry-Capability': 'telemetry-capability-0123456789abcd',
			},
		});
		const postedBody = requests[0]?.init?.body;
		expect(postedBody).toBeInstanceOf(ArrayBuffer);
		if (!(postedBody instanceof ArrayBuffer)) return;
		expect([...new Uint8Array(postedBody)]).toEqual([...body]);
	});

	it('preserves accepted_with_loss native admission accounting', async () => {
		const transport = createBridgeTelemetryWorkerFetchTransport({
			endpointUrl: 'agentstudio://telemetry/batch',
			fetch: async (): Promise<Response> =>
				Response.json({
					type: 'accepted_with_loss',
					telemetrySessionId: 'telemetry-session-entry',
					batchSequence: 1,
					nextExpectedBatchSequence: 2,
					acceptedSampleCount: 2,
					acceptedLossCount: 3,
					nativeRequiredLossCount: 1,
					nativeOptionalLossCount: 2,
				}),
		});
		const request: BridgeTelemetryWorkerBatchRequest = {
			type: 'telemetry.batch',
			schemaVersion: 2,
			telemetrySessionId: 'telemetry-session-entry',
			batchSequence: 1,
			samples: [],
			lossSummaries: [],
		};

		await expect(
			transport.postBatch(
				request,
				new TextEncoder().encode(JSON.stringify(request)),
				'telemetry-capability-0123456789abcd',
			),
		).resolves.toEqual({
			type: 'accepted_with_loss',
			telemetrySessionId: 'telemetry-session-entry',
			batchSequence: 1,
			nextExpectedBatchSequence: 2,
			acceptedSampleCount: 2,
			acceptedLossCount: 3,
			nativeRequiredLossCount: 1,
			nativeOptionalLossCount: 2,
		});
	});

	it('classifies a fetch rejection before native response', async () => {
		const transport = createBridgeTelemetryWorkerFetchTransport({
			endpointUrl: 'agentstudio://telemetry/batch',
			fetch: async (): Promise<Response> => {
				throw new TypeError('Load failed');
			},
		});

		await expect(
			transport.postBatch(
				makeBatchRequest(),
				new Uint8Array([1]),
				'telemetry-capability-0123456789abcd',
			),
		).rejects.toEqual(
			new BridgeTelemetryWorkerTransportError({ stage: 'fetch', httpStatus: null }),
		);
	});

	it('classifies an HTTP rejection before attempting an empty response body', async () => {
		const transport = createBridgeTelemetryWorkerFetchTransport({
			endpointUrl: 'agentstudio://telemetry/batch',
			fetch: async (): Promise<Response> => new Response(null, { status: 403 }),
		});

		await expect(
			transport.postBatch(
				makeBatchRequest(),
				new Uint8Array([1]),
				'telemetry-capability-0123456789abcd',
			),
		).rejects.toEqual(
			new BridgeTelemetryWorkerTransportError({ stage: 'http_status', httpStatus: 403 }),
		);
	});

	it('separates unreadable response bodies from invalid typed responses', async () => {
		const unreadable = createBridgeTelemetryWorkerFetchTransport({
			endpointUrl: 'agentstudio://telemetry/batch',
			fetch: async (): Promise<Response> => new Response('not-json'),
		});
		const invalid = createBridgeTelemetryWorkerFetchTransport({
			endpointUrl: 'agentstudio://telemetry/batch',
			fetch: async (): Promise<Response> => Response.json({ type: 'unexpected' }),
		});

		await expect(
			unreadable.postBatch(
				makeBatchRequest(),
				new Uint8Array([1]),
				'telemetry-capability-0123456789abcd',
			),
		).rejects.toEqual(
			new BridgeTelemetryWorkerTransportError({ stage: 'response_body', httpStatus: 200 }),
		);
		await expect(
			invalid.postBatch(
				makeBatchRequest(),
				new Uint8Array([1]),
				'telemetry-capability-0123456789abcd',
			),
		).rejects.toEqual(
			new BridgeTelemetryWorkerTransportError({ stage: 'response_schema', httpStatus: 200 }),
		);
	});
});

function makeBatchRequest(): BridgeTelemetryWorkerBatchRequest {
	return {
		type: 'telemetry.batch',
		schemaVersion: 2,
		telemetrySessionId: 'telemetry-session-entry',
		batchSequence: 1,
		samples: [],
		lossSummaries: [],
	};
}

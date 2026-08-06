import { afterEach, describe, expect, test, vi } from 'vitest';

import { executeAgentStudioBridgeProductRequest } from './bridge-product-agent-studio-request-executor.js';
import { executeHttpBridgeProductRequest } from './bridge-product-http-request-executor.js';
import type {
	BridgeProductRequestExecutor,
	BridgeProductRequestRoute,
} from './bridge-product-request-executor.js';

const routeCases = [
	['command', 'agentstudio://rpc/command', '/__bridge-product/command'],
	['stream', 'agentstudio://rpc/stream', '/__bridge-product/stream'],
	['content', 'agentstudio://rpc/content', '/__bridge-product/content'],
] as const satisfies readonly [BridgeProductRequestRoute, string, string][];

afterEach((): void => {
	vi.unstubAllGlobals();
});

describe.each([
	['Agent Studio', executeAgentStudioBridgeProductRequest, 1],
	['HTTP', executeHttpBridgeProductRequest, 2],
] as const)('%s Bridge product request executor', (_name, executeRequest, endpointIndex) => {
	test.each(routeCases)(
		'maps %s and forwards the exact RequestInit through one fetch',
		async (route, agentStudioEndpoint, httpEndpoint) => {
			const response = new Response('unchanged');
			const fetchSpy = vi.fn<typeof fetch>().mockResolvedValue(response);
			vi.stubGlobal('fetch', fetchSpy);
			const abortController = new AbortController();
			const requestInit: RequestInit = {
				body: Uint8Array.from([1, 2, 3]),
				credentials: 'include',
				headers: new Headers({ Authorization: 'Bearer opaque-capability' }),
				method: 'POST',
				signal: abortController.signal,
			};

			const returnedResponse = await executeRequest(route, requestInit);

			expect(returnedResponse).toBe(response);
			expect(fetchSpy).toHaveBeenCalledTimes(1);
			expect(fetchSpy).toHaveBeenCalledWith(
				[agentStudioEndpoint, httpEndpoint][endpointIndex - 1],
				requestInit,
			);
			expect(fetchSpy.mock.calls[0]?.[1]?.signal).toBe(abortController.signal);
		},
	);

	test('returns the original fetch rejection without retrying', async () => {
		const requestFailure = new Error('opaque request failure');
		const fetchSpy = vi.fn<typeof fetch>().mockRejectedValue(requestFailure);
		vi.stubGlobal('fetch', fetchSpy);
		const requestInit: RequestInit = { method: 'POST' };

		const rejection = executeRequest('command', requestInit);

		await expect(rejection).rejects.toBe(requestFailure);
		expect(fetchSpy).toHaveBeenCalledTimes(1);
	});

	test('rejects an invalid runtime route before fetch', async () => {
		const fetchSpy = vi.fn<typeof fetch>();
		vi.stubGlobal('fetch', fetchSpy);

		expect(() =>
			executeRequest('invalid-route' as BridgeProductRequestRoute, { method: 'POST' }),
		).toThrow('Unsupported Bridge product request route.');
		expect(fetchSpy).not.toHaveBeenCalled();
	});
});

function assertExecutorContract(_executor: BridgeProductRequestExecutor): void {}

assertExecutorContract(executeAgentStudioBridgeProductRequest);
assertExecutorContract(executeHttpBridgeProductRequest);

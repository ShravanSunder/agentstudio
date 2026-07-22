import pierrePortableWorkerSource from '@pierre/diffs/worker/worker-portable.js?raw';

import {
	createBridgePierreBlobWorkerFactory,
	type BridgePierreBlobWorkerFactory,
} from './bridge-pierre-worker-pool.js';

export function createBridgePierrePortableBlobWorkerFactory(): BridgePierreBlobWorkerFactory {
	return createBridgePierreBlobWorkerFactory({
		workerSource: pierrePortableWorkerSource,
	});
}

export function installPierrePackagedWorkerFetchMock(): () => void {
	const originalFetch = window.fetch.bind(window);
	window.fetch = async (input: RequestInfo | URL, init?: RequestInit): Promise<Response> => {
		const url = resourceUrlFromFetchInput(input);
		if (url === 'agentstudio://app/workers/pierre-diffs-worker-portable.js') {
			return new Response(pierrePortableWorkerSource, {
				headers: { 'content-type': 'application/javascript' },
			});
		}
		return await originalFetch(input, init);
	};
	return (): void => {
		window.fetch = originalFetch;
	};
}

function resourceUrlFromFetchInput(input: RequestInfo | URL): string {
	if (typeof input === 'string') {
		return input;
	}
	if (input instanceof URL) {
		return input.href;
	}
	return input.url;
}

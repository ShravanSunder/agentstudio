import {
	runProductStreamWebKitFeasibilityProbe,
	type BridgeProductStreamWebKitFeasibilityRequest,
} from './bridge-product-stream-webkit-feasibility-probe.js';

// oxlint-disable unicorn/require-post-message-target-origin -- Worker postMessage has no targetOrigin.

type BridgeWorkerFetchProbeMode = 'fetch' | 'stream';

interface BridgeWorkerContentFetchProbeRequest {
	readonly mode: BridgeWorkerFetchProbeMode;
	readonly resourceUrl: string;
}

type BridgeWorkerFetchProbeRequest =
	| BridgeWorkerContentFetchProbeRequest
	| BridgeProductStreamWebKitFeasibilityRequest;

interface BridgeWorkerFetchProbeResponse {
	readonly mode: BridgeWorkerFetchProbeMode;
	readonly succeeded: boolean;
	readonly status: number;
	readonly workerObservedByteCount: number;
	readonly streamFirstChunkByteCount: number;
	readonly streamHeldOpen: boolean;
	readonly contentUrlScheme: string;
	readonly contentResourceKind: 'content';
	readonly failureReason: string;
}

function holdStreamOpen(): Promise<never> {
	return new Promise<never>(() => {});
}

function failedResponse(
	request: BridgeWorkerContentFetchProbeRequest,
	failureReason: string,
): BridgeWorkerFetchProbeResponse {
	return {
		mode: request.mode,
		succeeded: false,
		status: 0,
		workerObservedByteCount: 0,
		streamFirstChunkByteCount: 0,
		streamHeldOpen: false,
		contentUrlScheme: 'agentstudio',
		contentResourceKind: 'content',
		failureReason,
	};
}

function contentUrlScheme(resourceUrl: string): string {
	try {
		return new URL(resourceUrl).protocol.replace(':', '');
	} catch {
		return 'agentstudio';
	}
}

self.addEventListener('message', (event: MessageEvent<BridgeWorkerFetchProbeRequest>): void => {
	if (event.data.mode === 'product-stream-s2a') {
		void runProductStreamWebKitFeasibilityProbe(event.data);
		return;
	}
	void runProbe(event.data);
});

async function runProbe(request: BridgeWorkerContentFetchProbeRequest): Promise<void> {
	try {
		const response = await fetch(request.resourceUrl);
		if (request.mode === 'stream') {
			if (response.body === null) {
				self.postMessage(failedResponse(request, 'stream_body_missing'));
				return;
			}
			const reader = response.body.getReader();
			const firstChunk = await reader.read();
			self.postMessage({
				mode: request.mode,
				succeeded: response.ok,
				status: response.status,
				workerObservedByteCount: 0,
				streamFirstChunkByteCount: firstChunk.value?.byteLength ?? 0,
				streamHeldOpen: !firstChunk.done,
				contentUrlScheme: contentUrlScheme(request.resourceUrl),
				contentResourceKind: 'content',
				failureReason: 'none',
			} satisfies BridgeWorkerFetchProbeResponse);
			await holdStreamOpen();
			return;
		}

		const body = await response.arrayBuffer();
		self.postMessage({
			mode: request.mode,
			succeeded: response.ok,
			status: response.status,
			workerObservedByteCount: body.byteLength,
			streamFirstChunkByteCount: 0,
			streamHeldOpen: false,
			contentUrlScheme: contentUrlScheme(request.resourceUrl),
			contentResourceKind: 'content',
			failureReason: 'none',
		} satisfies BridgeWorkerFetchProbeResponse);
	} catch {
		self.postMessage(failedResponse(request, 'worker_fetch_failed'));
	}
}

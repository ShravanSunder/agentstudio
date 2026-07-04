type BridgeWorkerFetchProbeMode = 'fetch' | 'stream';

interface BridgeWorkerFetchProbeRequest {
	readonly mode: BridgeWorkerFetchProbeMode;
	readonly resourceUrl: string;
}

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
	request: BridgeWorkerFetchProbeRequest,
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
	void runProbe(event.data);
});

async function runProbe(request: BridgeWorkerFetchProbeRequest): Promise<void> {
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

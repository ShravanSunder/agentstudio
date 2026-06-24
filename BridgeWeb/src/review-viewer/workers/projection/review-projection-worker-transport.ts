// oxlint-disable unicorn/require-post-message-target-origin -- Worker postMessage does not accept a targetOrigin argument.
import {
	createBridgeReviewProjectionWorkerClient,
	type BridgeReviewProjectionWorkerClient,
	type BridgeReviewProjectionWorkerTransport,
} from './review-projection-worker-client.js';
import {
	bridgeReviewProjectionWorkerResponseSchema,
	type BridgeReviewProjectionWorkerRequest,
	type BridgeReviewProjectionWorkerResponse,
} from './review-projection-worker-rpc.js';

export interface CreateBridgeReviewProjectionWebWorkerClientProps {
	readonly createRequestId?: () => string;
	readonly workerFactory?: () => Worker | Promise<Worker>;
	readonly workerScriptUrl?: string;
	readonly createObjectURL?: (blob: Blob) => string;
	readonly revokeObjectURL?: (url: string) => void;
}

interface PendingWorkerRequest {
	readonly resolve: (response: BridgeReviewProjectionWorkerResponse) => void;
	readonly reject: (error: Error) => void;
}

export const bridgeReviewProjectionDefaultWorkerScriptUrl =
	'agentstudio://app/assets/review-projection-worker.js';

export function createBridgeReviewProjectionWebWorkerClient(
	props: CreateBridgeReviewProjectionWebWorkerClientProps = {},
): BridgeReviewProjectionWorkerClient | null {
	if (typeof Worker === 'undefined') {
		return null;
	}

	const transport = createBridgeReviewProjectionWebWorkerTransport({
		workerFactory:
			props.workerFactory ??
			createDefaultBridgeReviewProjectionWorkerFactory({
				workerScriptUrl: props.workerScriptUrl ?? bridgeReviewProjectionDefaultWorkerScriptUrl,
				...(props.createObjectURL === undefined ? {} : { createObjectURL: props.createObjectURL }),
				...(props.revokeObjectURL === undefined ? {} : { revokeObjectURL: props.revokeObjectURL }),
			}),
	});
	return createBridgeReviewProjectionWorkerClient({
		transport,
		...(props.createRequestId === undefined ? {} : { createRequestId: props.createRequestId }),
	});
}

export function createBridgeReviewProjectionModuleWorkerFactory(): () => Worker {
	return (): Worker =>
		new Worker(new URL('./review-projection-worker-entry.ts', import.meta.url), {
			type: 'module',
		});
}

function createBridgeReviewProjectionWebWorkerTransport(props: {
	readonly workerFactory: () => Worker | Promise<Worker>;
}): BridgeReviewProjectionWorkerTransport {
	const pendingByRequestId = new Map<string, PendingWorkerRequest>();
	let worker: Worker | null = null;
	let workerPromise: Promise<Worker> | null = null;

	const getWorker = async (): Promise<Worker> => {
		if (worker !== null) {
			return worker;
		}
		if (workerPromise !== null) {
			return await workerPromise;
		}

		workerPromise = Promise.resolve(props.workerFactory()).then((nextWorker: Worker): Worker => {
			nextWorker.addEventListener('message', (event: MessageEvent<unknown>): void => {
				const parsed = bridgeReviewProjectionWorkerResponseSchema.safeParse(event.data);
				if (!parsed.success) {
					rejectPendingRequests(
						pendingByRequestId,
						new Error('Projection worker sent invalid response'),
					);
					nextWorker.terminate();
					worker = null;
					workerPromise = null;
					return;
				}
				const pending = pendingByRequestId.get(parsed.data.requestId);
				if (pending === undefined) {
					return;
				}
				pendingByRequestId.delete(parsed.data.requestId);
				pending.resolve(parsed.data);
			});
			nextWorker.addEventListener('error', (event: ErrorEvent): void => {
				const errorMessage =
					typeof event.message === 'string' && event.message.length > 0
						? event.message
						: 'Projection worker failed';
				rejectPendingRequests(pendingByRequestId, new Error(errorMessage));
				worker = null;
				workerPromise = null;
			});
			worker = nextWorker;
			return nextWorker;
		});
		return await workerPromise;
	};

	return {
		abort: (abortKey: string): void => {
			if (worker === null) {
				return;
			}
			worker.postMessage({
				schemaVersion: 1,
				method: 'reviewProjection.abort',
				abortKey,
			});
		},
		send: (request: BridgeReviewProjectionWorkerRequest): Promise<unknown> =>
			new Promise<BridgeReviewProjectionWorkerResponse>((resolve, reject): void => {
				pendingByRequestId.set(request.requestId, { resolve, reject });
				void getWorker()
					.then((activeWorker: Worker): void => {
						try {
							activeWorker.postMessage(request);
						} catch (error: unknown) {
							pendingByRequestId.delete(request.requestId);
							reject(error instanceof Error ? error : new Error('Projection worker post failed'));
						}
					})
					.catch((error: unknown): void => {
						pendingByRequestId.delete(request.requestId);
						reject(
							error instanceof Error ? error : new Error('Projection worker construction failed'),
						);
					});
			}),
	};
}

interface CreateDefaultBridgeReviewProjectionWorkerFactoryProps {
	readonly workerScriptUrl: string;
	readonly createObjectURL?: (blob: Blob) => string;
	readonly revokeObjectURL?: (url: string) => void;
}

function createDefaultBridgeReviewProjectionWorkerFactory(
	props: CreateDefaultBridgeReviewProjectionWorkerFactoryProps,
): () => Promise<Worker> {
	const createObjectURL = props.createObjectURL ?? URL.createObjectURL.bind(URL);
	const revokeObjectURL = props.revokeObjectURL ?? URL.revokeObjectURL.bind(URL);
	let workerScriptBlobUrl: string | null = null;

	return async (): Promise<Worker> => {
		if (workerScriptBlobUrl === null) {
			const response = await fetch(props.workerScriptUrl);
			if (!response.ok) {
				throw new Error(`Failed to load projection worker: ${response.status}`);
			}
			const workerSource = await response.text();
			const workerScriptBlob = new Blob([workerSource], { type: 'application/javascript' });
			workerScriptBlobUrl = createObjectURL(workerScriptBlob);
		}
		const worker = new Worker(workerScriptBlobUrl, { type: 'module' });
		worker.addEventListener(
			'error',
			(): void => {
				if (workerScriptBlobUrl !== null) {
					revokeObjectURL(workerScriptBlobUrl);
					workerScriptBlobUrl = null;
				}
			},
			{ once: true },
		);
		return worker;
	};
}

function rejectPendingRequests(
	pendingByRequestId: Map<string, PendingWorkerRequest>,
	error: Error,
): void {
	for (const pending of pendingByRequestId.values()) {
		pending.reject(error);
	}
	pendingByRequestId.clear();
}

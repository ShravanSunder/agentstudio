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
	readonly workerFactory?: () => Worker;
}

interface PendingWorkerRequest {
	readonly resolve: (response: BridgeReviewProjectionWorkerResponse) => void;
	readonly reject: (error: Error) => void;
}

const defaultProjectionWorkerUrl = new URL('./review-projection-worker.js', import.meta.url);

export function createBridgeReviewProjectionWebWorkerClient(
	props: CreateBridgeReviewProjectionWebWorkerClientProps = {},
): BridgeReviewProjectionWorkerClient | null {
	if (typeof Worker === 'undefined') {
		return null;
	}

	const transport = createBridgeReviewProjectionWebWorkerTransport({
		workerFactory: props.workerFactory ?? defaultWorkerFactory,
	});
	return createBridgeReviewProjectionWorkerClient({
		transport,
		...(props.createRequestId === undefined ? {} : { createRequestId: props.createRequestId }),
	});
}

function createBridgeReviewProjectionWebWorkerTransport(props: {
	readonly workerFactory: () => Worker;
}): BridgeReviewProjectionWorkerTransport {
	const pendingByRequestId = new Map<string, PendingWorkerRequest>();
	let worker: Worker | null = null;

	const getWorker = (): Worker => {
		if (worker !== null) {
			return worker;
		}

		const nextWorker = props.workerFactory();
		nextWorker.addEventListener('message', (event: MessageEvent<unknown>): void => {
			const parsed = bridgeReviewProjectionWorkerResponseSchema.safeParse(event.data);
			if (!parsed.success) {
				rejectPendingRequests(
					pendingByRequestId,
					new Error('Projection worker sent invalid response'),
				);
				nextWorker.terminate();
				worker = null;
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
		});
		worker = nextWorker;
		return nextWorker;
	};

	return {
		abort: (abortKey: string): void => {
			getWorker().postMessage({
				schemaVersion: 1,
				method: 'reviewProjection.abort',
				abortKey,
			});
		},
		send: (request: BridgeReviewProjectionWorkerRequest): Promise<unknown> =>
			new Promise<BridgeReviewProjectionWorkerResponse>((resolve, reject): void => {
				pendingByRequestId.set(request.requestId, { resolve, reject });
				try {
					getWorker().postMessage(request);
				} catch (error: unknown) {
					pendingByRequestId.delete(request.requestId);
					reject(error instanceof Error ? error : new Error('Projection worker post failed'));
				}
			}),
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

function defaultWorkerFactory(): Worker {
	return new Worker(defaultProjectionWorkerUrl, { type: 'module' });
}

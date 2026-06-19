// oxlint-disable unicorn/require-post-message-target-origin -- Worker postMessage does not accept a targetOrigin argument.
import {
	createBridgeMarkdownRenderWorkerClient,
	type BridgeMarkdownRenderWorkerClient,
	type BridgeMarkdownRenderWorkerTransport,
} from './bridge-markdown-render-worker-client.js';
import {
	bridgeMarkdownRenderWorkerResponseSchema,
	type BridgeMarkdownRenderWorkerRequest,
	type BridgeMarkdownRenderWorkerResponse,
	type BridgeMarkdownRenderWorkerAbortRequest,
} from './bridge-markdown-render-worker-rpc.js';

export interface CreateBridgeMarkdownRenderWebWorkerClientProps {
	readonly createRequestId?: () => string;
	readonly workerFactory?: () => Worker | Promise<Worker>;
	readonly workerScriptUrl?: string;
	readonly createObjectURL?: (blob: Blob) => string;
	readonly revokeObjectURL?: (url: string) => void;
}

interface PendingWorkerRequest {
	readonly resolve: (response: BridgeMarkdownRenderWorkerResponse) => void;
	readonly reject: (error: Error) => void;
}

export const bridgeMarkdownDefaultWorkerScriptUrl =
	'agentstudio://app/assets/bridge-markdown-render-worker.js';

export function createBridgeMarkdownRenderWebWorkerClient(
	props: CreateBridgeMarkdownRenderWebWorkerClientProps = {},
): BridgeMarkdownRenderWorkerClient | null {
	if (typeof Worker === 'undefined') {
		return null;
	}

	const transport = createBridgeMarkdownRenderWebWorkerTransport({
		workerFactory:
			props.workerFactory ??
			createDefaultBridgeMarkdownWorkerFactory({
				workerScriptUrl: props.workerScriptUrl ?? bridgeMarkdownDefaultWorkerScriptUrl,
				...(props.createObjectURL === undefined ? {} : { createObjectURL: props.createObjectURL }),
				...(props.revokeObjectURL === undefined ? {} : { revokeObjectURL: props.revokeObjectURL }),
			}),
	});
	return createBridgeMarkdownRenderWorkerClient({
		transport,
		...(props.createRequestId === undefined ? {} : { createRequestId: props.createRequestId }),
	});
}

export function createBridgeMarkdownRenderModuleWorkerFactory(): () => Worker {
	return (): Worker =>
		new Worker(new URL('./bridge-markdown-render-worker-entry.ts', import.meta.url), {
			type: 'module',
		});
}

function createBridgeMarkdownRenderWebWorkerTransport(props: {
	readonly workerFactory: () => Worker | Promise<Worker>;
}): BridgeMarkdownRenderWorkerTransport {
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
				const parsed = bridgeMarkdownRenderWorkerResponseSchema.safeParse(event.data);
				if (!parsed.success) {
					rejectPendingRequests(
						pendingByRequestId,
						new Error('Markdown render worker sent invalid response'),
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
						: 'Markdown render worker failed';
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
		abort: (abortRequest: BridgeMarkdownRenderWorkerAbortRequest): void => {
			if (worker !== null) {
				try {
					worker.postMessage(abortRequest);
				} catch (error: unknown) {
					rejectPendingRequests(
						pendingByRequestId,
						error instanceof Error ? error : new Error('Markdown render worker abort post failed'),
					);
					worker.terminate();
					worker = null;
					workerPromise = null;
					return;
				}
			}
			const pending = pendingByRequestId.get(abortRequest.requestId);
			if (pending !== undefined) {
				pendingByRequestId.delete(abortRequest.requestId);
				pending.reject(new Error('Markdown render request aborted'));
			}
		},
		send: (request: BridgeMarkdownRenderWorkerRequest): Promise<unknown> =>
			new Promise<BridgeMarkdownRenderWorkerResponse>((resolve, reject): void => {
				pendingByRequestId.set(request.requestId, { resolve, reject });
				void getWorker()
					.then((activeWorker: Worker): void => {
						try {
							activeWorker.postMessage(request);
						} catch (error: unknown) {
							pendingByRequestId.delete(request.requestId);
							reject(
								error instanceof Error ? error : new Error('Markdown render worker post failed'),
							);
						}
					})
					.catch((error: unknown): void => {
						pendingByRequestId.delete(request.requestId);
						reject(
							error instanceof Error
								? error
								: new Error('Markdown render worker construction failed'),
						);
					});
			}),
	};
}

interface CreateDefaultBridgeMarkdownWorkerFactoryProps {
	readonly workerScriptUrl: string;
	readonly createObjectURL?: (blob: Blob) => string;
	readonly revokeObjectURL?: (url: string) => void;
}

function createDefaultBridgeMarkdownWorkerFactory(
	props: CreateDefaultBridgeMarkdownWorkerFactoryProps,
): () => Promise<Worker> {
	const createObjectURL = props.createObjectURL ?? URL.createObjectURL.bind(URL);
	const revokeObjectURL = props.revokeObjectURL ?? URL.revokeObjectURL.bind(URL);
	let workerScriptBlobUrl: string | null = null;

	return async (): Promise<Worker> => {
		if (workerScriptBlobUrl === null) {
			const response = await fetch(props.workerScriptUrl);
			if (!response.ok) {
				throw new Error(`Failed to load markdown worker: ${response.status}`);
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

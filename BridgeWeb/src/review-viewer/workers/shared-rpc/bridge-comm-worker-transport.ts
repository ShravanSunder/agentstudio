import { readBridgeCommWorkerAbsoluteNowMilliseconds } from '../../../core/comm-worker/bridge-comm-worker-telemetry.js';
// oxlint-disable unicorn/require-post-message-target-origin -- Worker postMessage does not accept a targetOrigin argument.
import type {
	BridgeCommWorkerBootstrapRequest,
	BridgeWorkerMainToServerMessage,
	BridgeWorkerServerToMainMessage,
} from '../../../core/comm-worker/bridge-worker-contracts.js';
import {
	BRIDGE_WORKER_WIRE_VERSION,
	bridgeWorkerMainToServerMessageSchema,
	bridgeWorkerServerToMainMessageSchema,
} from '../../../core/comm-worker/bridge-worker-contracts.js';

export interface BridgeReviewCommWorkerTransportDispatcher {
	readonly dispatch: (message: BridgeWorkerMainToServerMessage) => void;
	readonly dispose: () => void;
}

export interface CreateBridgeReviewCommWorkerTransportDispatcherProps {
	readonly bootstrapRequest: BridgeCommWorkerBootstrapRequest;
	readonly createObjectURL?: (blob: Blob) => string;
	readonly now?: () => number;
	readonly publishWorkerMessages: (messages: readonly BridgeWorkerServerToMainMessage[]) => void;
	readonly revokeObjectURL?: (url: string) => void;
	readonly workerFactory?: () => Promise<Worker> | Worker;
	readonly workerScriptUrl?: string;
}

export const bridgeReviewCommWorkerDefaultScriptUrl =
	'agentstudio://app/assets/bridge-comm-worker.js';

export function createBridgeReviewCommWorkerTransportDispatcher(
	props: CreateBridgeReviewCommWorkerTransportDispatcherProps,
): BridgeReviewCommWorkerTransportDispatcher {
	const workerFactory =
		props.workerFactory ??
		createDefaultBridgeReviewCommWorkerFactory({
			workerScriptUrl: props.workerScriptUrl ?? bridgeReviewCommWorkerDefaultScriptUrl,
			...(props.createObjectURL === undefined ? {} : { createObjectURL: props.createObjectURL }),
			...(props.revokeObjectURL === undefined ? {} : { revokeObjectURL: props.revokeObjectURL }),
		});
	const now = props.now ?? readBridgeCommWorkerTransportNowMilliseconds;
	const queuedCommands: BridgeWorkerMainToServerMessage[] = [];
	const inFlightMarkFileViewedRequestIds = new Set<string>();
	let worker: Worker | null = null;
	let workerPromise: Promise<Worker> | null = null;
	let isBootstrapReady = false;
	let isDisposed = false;

	const resetWorkerBootstrapState = (activeWorker: Worker | null): void => {
		queuedCommands.splice(0, queuedCommands.length);
		inFlightMarkFileViewedRequestIds.clear();
		isBootstrapReady = false;
		if (activeWorker !== null) {
			activeWorker.terminate();
		} else if (worker !== null) {
			worker.terminate();
		}
		worker = null;
		workerPromise = null;
	};
	const publishBootstrapFailure = (message: string): void => {
		if (isDisposed) {
			return;
		}
		props.publishWorkerMessages([
			{
				wireVersion: BRIDGE_WORKER_WIRE_VERSION,
				direction: 'serverWorkerToMain',
				kind: 'health',
				requestId: props.bootstrapRequest.requestId,
				status: 'degraded',
				message,
				transferDescriptors: [],
			},
		]);
	};
	const publishQueuedMarkFileViewedFailures = (): void => {
		if (isDisposed) {
			return;
		}
		publishMarkFileViewedFailuresForRequestIds({
			publishWorkerMessages: props.publishWorkerMessages,
			requestIds: queuedCommands
				.filter((queuedCommand): boolean => queuedCommand.command === 'markFileViewed')
				.map((queuedCommand): string => queuedCommand.requestId),
		});
	};
	const publishInFlightMarkFileViewedFailures = (): void => {
		if (isDisposed) {
			return;
		}
		publishMarkFileViewedFailuresForRequestIds({
			publishWorkerMessages: props.publishWorkerMessages,
			requestIds: inFlightMarkFileViewedRequestIds,
		});
	};
	const failBootstrap = (activeWorker: Worker | null, message: string): void => {
		publishBootstrapFailure(message);
		publishQueuedMarkFileViewedFailures();
		publishInFlightMarkFileViewedFailures();
		resetWorkerBootstrapState(activeWorker);
	};
	const postWorkerCommand = (
		activeWorker: Worker,
		message: BridgeWorkerMainToServerMessage,
	): void => {
		if (message.command === 'markFileViewed') {
			inFlightMarkFileViewedRequestIds.add(message.requestId);
		}
		activeWorker.postMessage(
			stampBridgeWorkerDispatchTimestamp({
				message,
				now,
			}),
		);
	};
	const getWorker = async (): Promise<Worker> => {
		if (worker !== null) {
			return worker;
		}
		if (workerPromise !== null) {
			return await workerPromise;
		}

		workerPromise = Promise.resolve(workerFactory())
			.then((nextWorker: Worker): Worker => {
				if (isDisposed) {
					nextWorker.terminate();
					return nextWorker;
				}
				nextWorker.addEventListener('message', (event: MessageEvent<unknown>): void => {
					const parsed = bridgeWorkerServerToMainMessageSchema.safeParse(event.data);
					if (!parsed.success) {
						failBootstrap(
							nextWorker,
							'Bridge comm worker transport received invalid worker message.',
						);
						return;
					}
					if (parsed.data.kind === 'health' && parsed.data.requestId !== undefined) {
						inFlightMarkFileViewedRequestIds.delete(parsed.data.requestId);
					}
					props.publishWorkerMessages([parsed.data]);
					if (
						parsed.data.kind === 'health' &&
						parsed.data.requestId === props.bootstrapRequest.requestId
					) {
						if (parsed.data.status === 'ready') {
							isBootstrapReady = true;
							flushQueuedCommands({
								postWorkerCommand,
								queuedCommands,
								worker: nextWorker,
							});
							return;
						}
						resetWorkerBootstrapState(nextWorker);
					}
				});
				nextWorker.addEventListener('error', (): void => {
					failBootstrap(nextWorker, 'Bridge comm worker transport failed during bootstrap.');
				});
				worker = nextWorker;
				try {
					nextWorker.postMessage(props.bootstrapRequest);
				} catch {
					failBootstrap(nextWorker, 'Bridge comm worker transport failed during bootstrap.');
					throw new Error('Bridge comm worker transport failed during bootstrap.');
				}
				return nextWorker;
			})
			.catch((error: unknown): never => {
				if (workerPromise !== null) {
					failBootstrap(null, 'Bridge comm worker transport failed during bootstrap.');
				}
				throw error;
			});
		return await workerPromise;
	};

	return {
		dispatch: (message: BridgeWorkerMainToServerMessage): void => {
			if (isDisposed) {
				return;
			}
			if (!isBootstrapReady) {
				queuedCommands.push(message);
				void getWorker().catch((): void => {});
				return;
			}
			void getWorker()
				.then((activeWorker: Worker): void => {
					if (!isDisposed) {
						try {
							postWorkerCommand(activeWorker, message);
						} catch {
							failBootstrap(activeWorker, 'Bridge comm worker transport failed during bootstrap.');
						}
					}
				})
				.catch((): void => {});
		},
		dispose: (): void => {
			isDisposed = true;
			queuedCommands.splice(0, queuedCommands.length);
			if (worker !== null) {
				worker.terminate();
				worker = null;
			}
			void workerPromise?.then((activeWorker: Worker): void => {
				activeWorker.terminate();
			});
			workerPromise = null;
		},
	};
}

interface CreateDefaultBridgeReviewCommWorkerFactoryProps {
	readonly createObjectURL?: (blob: Blob) => string;
	readonly revokeObjectURL?: (url: string) => void;
	readonly workerScriptUrl: string;
}

function createDefaultBridgeReviewCommWorkerFactory(
	props: CreateDefaultBridgeReviewCommWorkerFactoryProps,
): () => Promise<Worker> {
	const createObjectURL = props.createObjectURL ?? URL.createObjectURL.bind(URL);
	const revokeObjectURL = props.revokeObjectURL ?? URL.revokeObjectURL.bind(URL);
	let workerScriptBlobUrl: string | null = null;

	return async (): Promise<Worker> => {
		if (workerScriptBlobUrl === null) {
			const response = await fetch(props.workerScriptUrl);
			if (!response.ok) {
				throw new Error(`Failed to load bridge comm worker: ${response.status}`);
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

function flushQueuedCommands(props: {
	readonly postWorkerCommand: (worker: Worker, message: BridgeWorkerMainToServerMessage) => void;
	readonly queuedCommands: BridgeWorkerMainToServerMessage[];
	readonly worker: Worker;
}): void {
	for (const queuedCommand of props.queuedCommands.splice(0, props.queuedCommands.length)) {
		props.postWorkerCommand(props.worker, queuedCommand);
	}
}

function publishMarkFileViewedFailuresForRequestIds(props: {
	readonly publishWorkerMessages: (messages: readonly BridgeWorkerServerToMainMessage[]) => void;
	readonly requestIds: Iterable<string>;
}): void {
	const markFileViewedFailures: BridgeWorkerServerToMainMessage[] = Array.from(
		new Set(props.requestIds),
		(requestId): BridgeWorkerServerToMainMessage => ({
			wireVersion: BRIDGE_WORKER_WIRE_VERSION,
			direction: 'serverWorkerToMain',
			kind: 'health',
			requestId,
			status: 'degraded',
			message: 'Bridge comm worker transport failed before review.markFileViewed delivery.',
			transferDescriptors: [],
		}),
	);
	if (markFileViewedFailures.length > 0) {
		props.publishWorkerMessages(markFileViewedFailures);
	}
}

function stampBridgeWorkerDispatchTimestamp(props: {
	readonly message: BridgeWorkerMainToServerMessage;
	readonly now: () => number;
}): BridgeWorkerMainToServerMessage {
	return bridgeWorkerMainToServerMessageSchema.parse({
		...props.message,
		issuedAtMilliseconds: props.now(),
	});
}

function readBridgeCommWorkerTransportNowMilliseconds(): number {
	return readBridgeCommWorkerAbsoluteNowMilliseconds();
}

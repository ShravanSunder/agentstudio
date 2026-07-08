import { readBridgeCommWorkerAbsoluteNowMilliseconds } from '../../../core/comm-worker/bridge-comm-worker-telemetry.js';
// oxlint-disable unicorn/require-post-message-target-origin -- Worker postMessage does not accept a targetOrigin argument.
import type {
	BridgeCommWorkerBootstrapRequest,
	BridgeWorkerHealthEvent,
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
	const inFlightAwaitedOrdinaryRpcFailuresByRequestId = new Map<
		string,
		AwaitedOrdinaryRpcFailure
	>();
	let worker: Worker | null = null;
	let workerPromise: Promise<Worker> | null = null;
	let isBootstrapReady = false;
	let isDisposed = false;

	const resetWorkerBootstrapState = (activeWorker: Worker | null): void => {
		queuedCommands.splice(0, queuedCommands.length);
		inFlightAwaitedOrdinaryRpcFailuresByRequestId.clear();
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
	const publishQueuedAwaitedOrdinaryRpcFailures = (): void => {
		if (isDisposed) {
			return;
		}
		publishAwaitedOrdinaryRpcFailures({
			failures: queuedCommands.flatMap((queuedCommand): readonly AwaitedOrdinaryRpcFailure[] => {
				const message = awaitedOrdinaryRpcFailureMessageForCommand(queuedCommand);
				if (message === null) {
					return [];
				}
				return [{ requestId: queuedCommand.requestId, message }];
			}),
			publishWorkerMessages: props.publishWorkerMessages,
		});
	};
	const publishInFlightAwaitedOrdinaryRpcFailures = (): void => {
		if (isDisposed) {
			return;
		}
		publishAwaitedOrdinaryRpcFailures({
			failures: Array.from(inFlightAwaitedOrdinaryRpcFailuresByRequestId.values()),
			publishWorkerMessages: props.publishWorkerMessages,
		});
	};
	const publishDefiniteAwaitedOrdinaryRpcFailure = (
		message: BridgeWorkerMainToServerMessage,
	): void => {
		if (isDisposed) {
			return;
		}
		const failureMessage = awaitedOrdinaryRpcFailureMessageForCommand(message);
		if (failureMessage === null) {
			return;
		}
		publishAwaitedOrdinaryRpcFailures({
			failures: [{ requestId: message.requestId, message: failureMessage }],
			publishWorkerMessages: props.publishWorkerMessages,
		});
	};
	const failBootstrap = (activeWorker: Worker | null, message: string): void => {
		publishBootstrapFailure(message);
		publishQueuedAwaitedOrdinaryRpcFailures();
		publishInFlightAwaitedOrdinaryRpcFailures();
		resetWorkerBootstrapState(activeWorker);
	};
	const postWorkerCommand = (
		activeWorker: Worker,
		message: BridgeWorkerMainToServerMessage,
	): void => {
		activeWorker.postMessage(
			stampBridgeWorkerDispatchTimestamp({
				message,
				now,
			}),
		);
		const failure = inFlightAwaitedOrdinaryRpcFailureForCommand(message);
		if (failure !== null) {
			inFlightAwaitedOrdinaryRpcFailuresByRequestId.set(message.requestId, failure);
		}
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
						inFlightAwaitedOrdinaryRpcFailuresByRequestId.delete(parsed.data.requestId);
					}
					props.publishWorkerMessages([parsed.data]);
					if (
						parsed.data.kind === 'health' &&
						parsed.data.requestId === props.bootstrapRequest.requestId
					) {
						if (parsed.data.status === 'ready') {
							isBootstrapReady = true;
							flushQueuedCommands({
								onPostFailure: (queuedCommand): void => {
									failBootstrap(
										nextWorker,
										'Bridge comm worker transport failed during bootstrap.',
									);
									publishDefiniteAwaitedOrdinaryRpcFailure(queuedCommand);
								},
								postWorkerCommand,
								queuedCommands,
								worker: nextWorker,
							});
							return;
						}
						publishQueuedAwaitedOrdinaryRpcFailures();
						publishInFlightAwaitedOrdinaryRpcFailures();
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
							publishDefiniteAwaitedOrdinaryRpcFailure(message);
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
	readonly onPostFailure: (message: BridgeWorkerMainToServerMessage) => void;
	readonly postWorkerCommand: (worker: Worker, message: BridgeWorkerMainToServerMessage) => void;
	readonly queuedCommands: BridgeWorkerMainToServerMessage[];
	readonly worker: Worker;
}): void {
	while (props.queuedCommands.length > 0) {
		const queuedCommand = props.queuedCommands.shift();
		if (queuedCommand === undefined) {
			return;
		}
		try {
			props.postWorkerCommand(props.worker, queuedCommand);
		} catch {
			props.onPostFailure(queuedCommand);
			return;
		}
	}
}

interface AwaitedOrdinaryRpcFailure {
	readonly deliveryStatus?: BridgeWorkerHealthEvent['deliveryStatus'];
	readonly message: string;
	readonly requestId: string;
}

function publishAwaitedOrdinaryRpcFailures(props: {
	readonly failures: readonly AwaitedOrdinaryRpcFailure[];
	readonly publishWorkerMessages: (messages: readonly BridgeWorkerServerToMainMessage[]) => void;
}): void {
	const uniqueFailuresByRequestId = new Map<string, AwaitedOrdinaryRpcFailure>();
	for (const failure of props.failures) {
		uniqueFailuresByRequestId.set(failure.requestId, failure);
	}
	const failures: BridgeWorkerServerToMainMessage[] = Array.from(
		uniqueFailuresByRequestId.values(),
		(failure): BridgeWorkerServerToMainMessage => ({
			wireVersion: BRIDGE_WORKER_WIRE_VERSION,
			direction: 'serverWorkerToMain',
			kind: 'health',
			requestId: failure.requestId,
			status: 'degraded',
			message: failure.message,
			...(failure.deliveryStatus === undefined ? {} : { deliveryStatus: failure.deliveryStatus }),
			transferDescriptors: [],
		}),
	);
	if (failures.length > 0) {
		props.publishWorkerMessages(failures);
	}
}

function inFlightAwaitedOrdinaryRpcFailureForCommand(
	message: BridgeWorkerMainToServerMessage,
): AwaitedOrdinaryRpcFailure | null {
	if (message.command === 'activeViewerModeUpdate') {
		return {
			requestId: message.requestId,
			message:
				'Bridge comm worker transport lost confirmation after bridge.activeViewerMode.update dispatch.',
			deliveryStatus: 'unknownAfterDispatch',
		};
	}
	const failureMessage = awaitedOrdinaryRpcFailureMessageForCommand(message);
	return failureMessage === null ? null : { requestId: message.requestId, message: failureMessage };
}

function awaitedOrdinaryRpcFailureMessageForCommand(
	message: BridgeWorkerMainToServerMessage,
): string | null {
	switch (message.command) {
		case 'markFileViewed':
			return 'Bridge comm worker transport failed before review.markFileViewed delivery.';
		case 'metadataInterestUpdate':
			return 'Bridge comm worker transport failed before bridge.metadata_interest.update delivery.';
		case 'reviewIntakeReady':
			return 'Bridge comm worker transport failed before bridge.intakeReady delivery.';
		case 'worktreeFileIntakeReady':
			return 'Bridge comm worker transport failed before bridge.intakeReady delivery.';
		case 'activeViewerModeUpdate':
			return 'Bridge comm worker transport failed before bridge.activeViewerMode.update delivery.';
		case 'fileViewSourceUpdate':
		case 'hover':
		case 'mode':
		case 'reviewInvalidate':
		case 'reviewSourceUpdate':
		case 'select':
		case 'viewport':
			return null;
		default:
			return assertNeverBridgeWorkerTransportCommand(message);
	}
}

function assertNeverBridgeWorkerTransportCommand(_message: never): never {
	throw new Error('Unhandled bridge worker transport command.');
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

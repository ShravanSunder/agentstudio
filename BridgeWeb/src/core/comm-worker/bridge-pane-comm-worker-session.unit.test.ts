// oxlint-disable unicorn/require-post-message-target-origin -- MessagePort postMessage does not accept a target origin.
import { describe, expect, test, vi } from 'vitest';

import { bridgeWorkerPierreRenderPolicy } from '../demand/bridge-content-demand-policy.js';
import { encodeBridgeWorkerSelectCommand } from './bridge-comm-worker-protocol.js';
import {
	BridgePaneCommWorkerSession,
	disposeBridgePaneCommWorkerSession,
	getBridgePaneCommWorkerSession,
	installBridgePaneCommWorkerSessionForHost,
	type BridgePaneCommWorkerNativeBootstrap,
} from './bridge-pane-comm-worker-session.js';
import {
	BRIDGE_PRODUCT_CAPABILITY_BYTE_LENGTH,
	BRIDGE_PRODUCT_MAXIMUM_CONTENT_BYTES,
	BRIDGE_PRODUCT_MAXIMUM_METADATA_FRAME_BYTES,
	BRIDGE_PRODUCT_MAXIMUM_QUEUED_STREAM_BYTES,
	BRIDGE_PRODUCT_MAXIMUM_QUEUED_STREAM_FRAMES,
	BRIDGE_PRODUCT_MAXIMUM_REQUEST_BODY_BYTES,
	BRIDGE_PRODUCT_TERMINAL_FRAME_RESERVE,
	BRIDGE_PRODUCT_WIRE_VERSION,
} from './bridge-product-contract-primitives.js';
import { bridgePaneCommWorkerInstallSchema } from './bridge-product-session-contracts.js';
import {
	bridgeWorkerMainToServerMessageSchema,
	bridgeWorkerServerToMainMessageSchema,
	type BridgeCommWorkerBootstrapRequest,
	type BridgeWorkerServerToMainMessage,
} from './bridge-worker-contracts.js';

interface RecordedGlobalWorkerPost {
	readonly message: unknown;
	readonly transferredCapability: boolean;
	readonly transferredPort: boolean;
	readonly transferListLength: number;
}

describe('Bridge pane comm worker session', () => {
	test('accepts exactly one host-owned shared session', () => {
		const session = new BridgePaneCommWorkerSession({
			workerFactory: (): Worker => new RecordingPaneCommWorker(),
		});

		try {
			installBridgePaneCommWorkerSessionForHost(session);

			expect(getBridgePaneCommWorkerSession()).toBe(session);
			expect(() =>
				installBridgePaneCommWorkerSessionForHost(
					new BridgePaneCommWorkerSession({
						workerFactory: (): Worker => new RecordingPaneCommWorker(),
					}),
				),
			).toThrow('Bridge pane comm worker session host was already installed.');
		} finally {
			disposeBridgePaneCommWorkerSession();
		}
	});

	test('owns one transferred worker across two clients and terminates it only with the session', async () => {
		const worker = new RecordingPaneCommWorker();
		const workerFactory = vi.fn((): Worker => worker);
		let nowMilliseconds = 100;
		const session = new BridgePaneCommWorkerSession({
			now: (): number => nowMilliseconds++,
			workerFactory,
		});
		const firstClient = new RecordingPaneCommWorkerClient();
		const secondClient = new RecordingPaneCommWorkerClient();
		const runtimeBootstrap = makeRuntimeBootstrapRequest('pane-runtime-bootstrap-1');
		const firstDispatcher = session.createDispatcher({
			bootstrapRequest: runtimeBootstrap,
			publishWorkerMessages: firstClient.publish,
		});
		const secondDispatcher = session.createDispatcher({
			bootstrapRequest: makeRuntimeBootstrapRequest('pane-runtime-bootstrap-2'),
			publishWorkerMessages: secondClient.publish,
		});
		const nativeBootstrap = makeNativeBootstrap();
		let workerPortRecorder: MessagePortRecorder | null = null;

		try {
			session.installNativeBootstrap(nativeBootstrap);
			firstDispatcher.dispatch(makeSelectCommand('first-client-command', 1, 'item-1', 'review'));
			secondDispatcher.dispatch(makeSelectCommand('second-client-command', 2, 'item-2', 'review'));
			await flushMicrotasks();

			expect(workerFactory).toHaveBeenCalledOnce();
			expect(worker.globalPosts).toHaveLength(1);
			const globalPost = expectRecordedGlobalPost(worker.globalPosts[0]);
			expect(globalPost.transferListLength).toBe(2);
			expect(globalPost.transferredCapability).toBe(true);
			expect(globalPost.transferredPort).toBe(true);
			expect(nativeBootstrap.productCapability.byteLength).toBe(0);
			const install = bridgePaneCommWorkerInstallSchema.parse(globalPost.message);
			expect(install.bootstrap).toEqual(nativeBootstrap.bootstrap);
			expect(install.productCapability.byteLength).toBe(BRIDGE_PRODUCT_CAPABILITY_BYTE_LENGTH);

			workerPortRecorder = new MessagePortRecorder(install.productPort);
			const bootstrapMessages = await workerPortRecorder.waitForCount(1);
			expect(bootstrapMessages).toEqual([
				{
					...runtimeBootstrap,
					runtime: {
						...runtimeBootstrap.runtime,
						surfacePolicies: {
							fileView: {
								bridgeDemandRank: { lane: 'selected', priority: 0 },
								budget: bridgeWorkerPierreRenderPolicy.fileViewSelectedRenderBudget,
							},
							review: {
								bridgeDemandRank: { lane: 'selected', priority: 0 },
								budget: bridgeWorkerPierreRenderPolicy.reviewInteractiveRenderBudget,
							},
						},
					},
				},
			]);
			expect(worker.globalPosts).toHaveLength(1);

			const firstClientReady = firstClient.waitForCount(1);
			const secondClientReady = secondClient.waitForCount(1);
			install.productPort.postMessage(makeReadyHealth(runtimeBootstrap.requestId));
			await Promise.all([firstClientReady, secondClientReady]);
			const workerPortMessages = await workerPortRecorder.waitForCount(3);
			const ordinaryCommands = workerPortMessages
				.slice(1)
				.map((message) => bridgeWorkerMainToServerMessageSchema.parse(message));
			expect(ordinaryCommands).toEqual([
				expect.objectContaining({
					requestId: 'first-client-command',
					issuedAtMilliseconds: 100,
				}),
				expect.objectContaining({
					requestId: 'second-client-command',
					issuedAtMilliseconds: 101,
				}),
			]);
			expect(worker.globalPosts).toHaveLength(1);

			firstClient.clear();
			secondClient.clear();
			const firstClientReplies = firstClient.waitForCount(2);
			const secondClientReplies = secondClient.waitForCount(2);
			const firstReply = makeReadyHealth('first-client-command');
			const secondReply = makeReadyHealth('second-client-command');
			install.productPort.postMessage(firstReply);
			install.productPort.postMessage(secondReply);
			expect(await firstClientReplies).toEqual([firstReply, secondReply]);
			expect(await secondClientReplies).toEqual([firstReply, secondReply]);

			firstClient.clear();
			secondClient.clear();
			firstDispatcher.dispose();
			expect(worker.terminateCount).toBe(0);
			firstDispatcher.dispatch(makeSelectCommand('disposed-client-command', 3, 'item-3', 'review'));
			secondDispatcher.dispatch(
				makeSelectCommand('remaining-client-command', 4, 'item-4', 'review'),
			);
			const postDisposeMessages = await workerPortRecorder.waitForCount(4);
			expect(
				postDisposeMessages
					.slice(3)
					.map((message) => bridgeWorkerMainToServerMessageSchema.parse(message).requestId),
			).toEqual(['remaining-client-command']);

			const remainingClientReply = makeReadyHealth('remaining-client-command');
			const remainingClientReplies = secondClient.waitForCount(1);
			install.productPort.postMessage(remainingClientReply);
			expect(await remainingClientReplies).toEqual([remainingClientReply]);
			expect(firstClient.messages).toEqual([]);

			session.dispose();
			await flushMicrotasks();
			expect(worker.terminateCount).toBe(1);
		} finally {
			workerPortRecorder?.close();
			firstDispatcher.dispose();
			secondDispatcher.dispose();
			session.dispose();
		}
	});

	test('forwards strict File display patches through the authoritative server parser', async () => {
		const worker = new RecordingPaneCommWorker();
		const session = new BridgePaneCommWorkerSession({ workerFactory: (): Worker => worker });
		const client = new RecordingPaneCommWorkerClient();
		const runtimeBootstrap = makeRuntimeBootstrapRequest('file-display-bootstrap');
		const dispatcher = session.createDispatcher({
			bootstrapRequest: runtimeBootstrap,
			publishWorkerMessages: client.publish,
		});

		try {
			session.installNativeBootstrap(makeNativeBootstrap());
			await flushMicrotasks();
			const install = bridgePaneCommWorkerInstallSchema.parse(worker.globalPosts[0]?.message);
			const recorder = new MessagePortRecorder(install.productPort);
			await recorder.waitForCount(1);
			install.productPort.postMessage(makeReadyHealth(runtimeBootstrap.requestId));
			await client.waitForCount(1);
			client.clear();

			const fileDisplayEvent = bridgeWorkerServerToMainMessageSchema.parse({
				wireVersion: 1,
				direction: 'serverWorkerToMain',
				transferDescriptors: [],
				kind: 'fileDisplayPatch',
				surface: 'fileView',
				epoch: 4,
				sequence: 9,
				projectionRevision: 3,
				patches: [
					{
						slice: 'fileStatus',
						operation: 'upsert',
						payload: { state: 'stale' },
					},
				],
			});
			install.productPort.postMessage(fileDisplayEvent);

			expect(await client.waitForCount(1)).toEqual([fileDisplayEvent]);
			recorder.close();
		} finally {
			dispatcher.dispose();
			session.dispose();
		}
	});

	test.each(['error', 'messageerror'] as const)(
		'restarts after %s only when native installs fresh authority',
		async (failureEventName) => {
			const workers = [new RecordingPaneCommWorker(), new RecordingPaneCommWorker()];
			const workerFactory = vi.fn((): Worker => {
				const worker = workers[workerFactory.mock.calls.length - 1];
				if (worker === undefined) {
					throw new Error('unexpected worker factory call');
				}
				return worker;
			});
			const restartReasons: string[] = [];
			const session = new BridgePaneCommWorkerSession({
				requestNativeBootstrap: (reason): void => {
					restartReasons.push(reason);
				},
				workerFactory,
			});
			const client = new RecordingPaneCommWorkerClient();
			const runtimeBootstrap = makeRuntimeBootstrapRequest('restart-runtime-bootstrap');
			const dispatcher = session.createDispatcher({
				bootstrapRequest: runtimeBootstrap,
				publishWorkerMessages: client.publish,
			});
			const firstBootstrap = makeNativeBootstrap('worker-instance-1');
			session.installNativeBootstrap(firstBootstrap);
			await flushMicrotasks();
			const firstInstall = bridgePaneCommWorkerInstallSchema.parse(
				workers[0]?.globalPosts[0]?.message,
			);
			const firstPortRecorder = new MessagePortRecorder(firstInstall.productPort);
			await firstPortRecorder.waitForCount(1);
			firstInstall.productPort.postMessage(makeReadyHealth(runtimeBootstrap.requestId));
			await client.waitForCount(1);
			client.clear();

			workers[0]?.dispatchEvent(new Event(failureEventName));
			dispatcher.dispatch(makeSelectCommand('queued-during-restart', 1, 'item-1', 'review'));
			const secondBootstrap = makeNativeBootstrap('worker-instance-2');
			session.installNativeBootstrap(secondBootstrap);
			await flushMicrotasks();

			expect(restartReasons).toEqual(['workerReplacement']);
			expect(workers[0]?.terminateCount).toBe(1);
			expect(workers[1]?.globalPosts).toHaveLength(1);
			expect(secondBootstrap.productCapability.byteLength).toBe(0);
			const secondInstall = bridgePaneCommWorkerInstallSchema.parse(
				workers[1]?.globalPosts[0]?.message,
			);
			const secondPortRecorder = new MessagePortRecorder(secondInstall.productPort);
			const secondMessagesBeforeReady = await secondPortRecorder.waitForCount(1);
			expect(secondMessagesBeforeReady).toEqual([
				expect.objectContaining({
					requestId: runtimeBootstrap.requestId,
					runtime: expect.objectContaining({
						surfacePolicies: expectPaneSurfacePolicies(),
					}),
				}),
			]);
			secondInstall.productPort.postMessage(makeReadyHealth(runtimeBootstrap.requestId));
			const secondMessages = await secondPortRecorder.waitForCount(2);
			expect(bridgeWorkerMainToServerMessageSchema.parse(secondMessages[1]).requestId).toBe(
				'queued-during-restart',
			);

			firstInstall.productPort.postMessage(makeReadyHealth('late-old-worker'));
			await flushMicrotasks();
			expect(client.messages).not.toContainEqual(
				expect.objectContaining({ requestId: 'late-old-worker' }),
			);

			firstPortRecorder.close();
			secondPortRecorder.close();
			dispatcher.dispose();
			session.dispose();
		},
	);

	test('requests one replacement when worker bootstrap readiness times out', async () => {
		vi.useFakeTimers();
		const worker = new RecordingPaneCommWorker();
		const restartReasons: string[] = [];
		const session = new BridgePaneCommWorkerSession({
			bootstrapTimeoutMilliseconds: 25,
			requestNativeBootstrap: (reason): void => {
				restartReasons.push(reason);
			},
			workerFactory: (): Worker => worker,
		});
		const dispatcher = session.createDispatcher({
			bootstrapRequest: makeRuntimeBootstrapRequest('timed-bootstrap'),
			publishWorkerMessages: (): void => {},
		});

		try {
			session.installNativeBootstrap(makeNativeBootstrap());
			await flushMicrotasks();
			vi.advanceTimersByTime(25);

			expect(worker.terminateCount).toBe(1);
			expect(restartReasons).toEqual(['workerReplacement']);
		} finally {
			dispatcher.dispose();
			session.dispose();
			vi.useRealTimers();
		}
	});

	test('requests fresh authority and preserves queued commands when worker creation fails', async () => {
		const replacementWorker = new RecordingPaneCommWorker();
		const workerFactory = vi
			.fn<() => Promise<Worker> | Worker>()
			.mockRejectedValueOnce(new Error('worker creation failed'))
			.mockReturnValueOnce(replacementWorker);
		const restartReasons: string[] = [];
		const replacementRequest = createDeferredVoid();
		const session = new BridgePaneCommWorkerSession({
			requestNativeBootstrap: (reason): void => {
				restartReasons.push(reason);
				replacementRequest.resolve();
			},
			workerFactory,
		});
		const runtimeBootstrap = makeRuntimeBootstrapRequest('factory-rejection-bootstrap');
		const dispatcher = session.createDispatcher({
			bootstrapRequest: runtimeBootstrap,
			publishWorkerMessages: (): void => {},
		});

		try {
			session.installNativeBootstrap(makeNativeBootstrap('failed-worker-instance'));
			dispatcher.dispatch(
				makeSelectCommand('queued-after-factory-rejection', 1, 'item-1', 'review'),
			);
			await replacementRequest.promise;

			expect(workerFactory).toHaveBeenCalledOnce();
			expect(restartReasons).toEqual(['workerReplacement']);

			const replacementBootstrap = makeNativeBootstrap('replacement-worker-instance');
			session.installNativeBootstrap(replacementBootstrap);
			await flushMicrotasks();
			const replacementInstall = bridgePaneCommWorkerInstallSchema.parse(
				replacementWorker.globalPosts[0]?.message,
			);
			const replacementPortRecorder = new MessagePortRecorder(replacementInstall.productPort);
			const replacementMessagesBeforeReady = await replacementPortRecorder.waitForCount(1);
			expect(replacementMessagesBeforeReady).toEqual([
				expect.objectContaining({
					requestId: runtimeBootstrap.requestId,
					runtime: expect.objectContaining({
						surfacePolicies: expectPaneSurfacePolicies(),
					}),
				}),
			]);

			replacementInstall.productPort.postMessage(makeReadyHealth(runtimeBootstrap.requestId));
			const replacementMessages = await replacementPortRecorder.waitForCount(2);
			expect(bridgeWorkerMainToServerMessageSchema.parse(replacementMessages[1]).requestId).toBe(
				'queued-after-factory-rejection',
			);
			replacementPortRecorder.close();
		} finally {
			dispatcher.dispose();
			session.dispose();
		}
	});
});

class RecordingPaneCommWorker extends EventTarget implements Worker {
	onmessage: ((this: Worker, event: MessageEvent) => void) | null = null;
	onmessageerror: ((this: Worker, event: MessageEvent) => void) | null = null;
	onerror: ((this: AbstractWorker, event: ErrorEvent) => void) | null = null;
	readonly globalPosts: RecordedGlobalWorkerPost[] = [];
	terminateCount = 0;

	override addEventListener<KEventName extends keyof WorkerEventMap>(
		type: KEventName,
		listener: (this: Worker, event: WorkerEventMap[KEventName]) => void,
		options?: boolean | AddEventListenerOptions,
	): void;
	override addEventListener(
		type: string,
		listener: EventListenerOrEventListenerObject | null,
		options?: boolean | AddEventListenerOptions,
	): void;
	override addEventListener(
		type: string,
		listener: EventListenerOrEventListenerObject | null,
		options?: boolean | AddEventListenerOptions,
	): void {
		super.addEventListener(type, listener, options);
	}

	override removeEventListener<KEventName extends keyof WorkerEventMap>(
		type: KEventName,
		listener: (this: Worker, event: WorkerEventMap[KEventName]) => void,
		options?: boolean | EventListenerOptions,
	): void;
	override removeEventListener(
		type: string,
		listener: EventListenerOrEventListenerObject | null,
		options?: boolean | EventListenerOptions,
	): void;
	override removeEventListener(
		type: string,
		listener: EventListenerOrEventListenerObject | null,
		options?: boolean | EventListenerOptions,
	): void {
		super.removeEventListener(type, listener, options);
	}

	postMessage(message: unknown, transferList: Transferable[]): void;
	postMessage(message: unknown, options?: StructuredSerializeOptions): void;
	postMessage(
		message: unknown,
		transferListOrOptions: Transferable[] | StructuredSerializeOptions = [],
	): void {
		const transferList = Array.isArray(transferListOrOptions)
			? transferListOrOptions
			: (transferListOrOptions.transfer ?? []);
		const parsedInstall = bridgePaneCommWorkerInstallSchema.safeParse(message);
		const transferredCapability =
			parsedInstall.success && transferList.includes(parsedInstall.data.productCapability);
		const transferredPort =
			parsedInstall.success && transferList.includes(parsedInstall.data.productPort);
		const clonedMessage = structuredClone(message, { transfer: transferList });
		this.globalPosts.push({
			message: clonedMessage,
			transferredCapability,
			transferredPort,
			transferListLength: transferList.length,
		});
	}

	terminate(): void {
		this.terminateCount += 1;
	}
}

class MessagePortRecorder {
	readonly #messages: unknown[] = [];
	readonly #port: MessagePort;
	readonly #waiters: Array<{
		readonly count: number;
		readonly resolve: (messages: readonly unknown[]) => void;
	}> = [];

	constructor(port: MessagePort) {
		this.#port = port;
		port.addEventListener('message', (event: MessageEvent<unknown>): void => {
			this.#messages.push(event.data);
			this.#resolveWaiters();
		});
		port.start();
	}

	waitForCount(count: number): Promise<readonly unknown[]> {
		if (this.#messages.length >= count) {
			return Promise.resolve([...this.#messages]);
		}
		return new Promise((resolve) => {
			this.#waiters.push({ count, resolve });
		});
	}

	close(): void {
		this.#port.close();
	}

	#resolveWaiters(): void {
		for (let index = this.#waiters.length - 1; index >= 0; index -= 1) {
			const waiter = this.#waiters[index];
			if (waiter !== undefined && this.#messages.length >= waiter.count) {
				this.#waiters.splice(index, 1);
				waiter.resolve([...this.#messages]);
			}
		}
	}
}

class RecordingPaneCommWorkerClient {
	readonly messages: BridgeWorkerServerToMainMessage[] = [];
	readonly #waiters: Array<{
		readonly count: number;
		readonly resolve: (messages: readonly BridgeWorkerServerToMainMessage[]) => void;
	}> = [];

	readonly publish = (messages: readonly BridgeWorkerServerToMainMessage[]): void => {
		this.messages.push(...messages);
		this.#resolveWaiters();
	};

	waitForCount(count: number): Promise<readonly BridgeWorkerServerToMainMessage[]> {
		if (this.messages.length >= count) {
			return Promise.resolve([...this.messages]);
		}
		return new Promise((resolve) => {
			this.#waiters.push({ count, resolve });
		});
	}

	clear(): void {
		this.messages.splice(0, this.messages.length);
	}

	#resolveWaiters(): void {
		for (let index = this.#waiters.length - 1; index >= 0; index -= 1) {
			const waiter = this.#waiters[index];
			if (waiter !== undefined && this.messages.length >= waiter.count) {
				this.#waiters.splice(index, 1);
				waiter.resolve([...this.messages]);
			}
		}
	}
}

function makeNativeBootstrap(
	workerInstanceId = 'worker-instance-1',
): BridgePaneCommWorkerNativeBootstrap {
	return {
		bootstrap: {
			kind: 'productSession.bootstrap',
			paneSessionId: 'pane-session-1',
			policy: {
				maximumContentBytes: BRIDGE_PRODUCT_MAXIMUM_CONTENT_BYTES,
				maximumRequestBodyBytes: BRIDGE_PRODUCT_MAXIMUM_REQUEST_BODY_BYTES,
				maximumMetadataFrameBytes: BRIDGE_PRODUCT_MAXIMUM_METADATA_FRAME_BYTES,
				maximumQueuedStreamBytes: BRIDGE_PRODUCT_MAXIMUM_QUEUED_STREAM_BYTES,
				maximumQueuedStreamFrames: BRIDGE_PRODUCT_MAXIMUM_QUEUED_STREAM_FRAMES,
				terminalFrameReserve: BRIDGE_PRODUCT_TERMINAL_FRAME_RESERVE,
			},
			wireVersion: BRIDGE_PRODUCT_WIRE_VERSION,
			workerInstanceId,
		},
		productCapability: new ArrayBuffer(BRIDGE_PRODUCT_CAPABILITY_BYTE_LENGTH),
	};
}

function makeRuntimeBootstrapRequest(requestId: string): BridgeCommWorkerBootstrapRequest {
	return {
		schemaVersion: 1,
		method: 'bridgeCommWorker.bootstrap',
		requestId,
		runtime: {
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			budget: {
				className: 'interactive',
				maxBytes: 512 * 1024,
				maxWindowLines: 400,
			},
		},
	};
}

function expectPaneSurfacePolicies(): ReturnType<typeof expect.objectContaining> {
	return expect.objectContaining({
		fileView: {
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			budget: bridgeWorkerPierreRenderPolicy.fileViewSelectedRenderBudget,
		},
		review: {
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			budget: bridgeWorkerPierreRenderPolicy.reviewInteractiveRenderBudget,
		},
	});
}

function makeSelectCommand(
	requestId: string,
	epoch: number,
	selectedItemId: string,
	surface: 'fileView' | 'review',
): ReturnType<typeof encodeBridgeWorkerSelectCommand> {
	return encodeBridgeWorkerSelectCommand({
		requestId,
		epoch,
		surface,
		selectedItemId,
		selectedSource: 'user',
	});
}

function makeReadyHealth(requestId: string): BridgeWorkerServerToMainMessage {
	return bridgeWorkerServerToMainMessageSchema.parse({
		wireVersion: 1,
		direction: 'serverWorkerToMain',
		kind: 'health',
		requestId,
		status: 'ready',
		transferDescriptors: [],
	});
}

function expectRecordedGlobalPost(
	post: RecordedGlobalWorkerPost | undefined,
): RecordedGlobalWorkerPost {
	if (post === undefined) {
		throw new Error('Expected one global typed install post.');
	}
	return post;
}

async function flushMicrotasks(): Promise<void> {
	await Promise.resolve();
	await Promise.resolve();
	await Promise.resolve();
}

function createDeferredVoid(): { readonly promise: Promise<void>; readonly resolve: () => void } {
	let resolvePromise: (() => void) | null = null;
	const promise = new Promise<void>((resolve): void => {
		resolvePromise = resolve;
	});
	return {
		promise,
		resolve: (): void => {
			if (resolvePromise === null) {
				throw new Error('Deferred promise resolver was not initialized.');
			}
			resolvePromise();
		},
	};
}

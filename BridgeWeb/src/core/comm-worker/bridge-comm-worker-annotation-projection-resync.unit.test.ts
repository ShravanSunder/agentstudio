import { describe, expect, test } from 'vitest';

import {
	createWorktreeAnnotationSurfaceClient,
	type WorktreeAnnotationSurfaceClient,
} from '../../worktree-annotations/worktree-annotation-surface-client.js';
import { registerBridgeCommWorkerRuntimePortProtocol } from './bridge-comm-worker-runtime-protocol.js';
import {
	createRecordingBridgeCommWorkerPort,
	flushBridgeWorkerRuntimeContinuations,
} from './bridge-comm-worker-runtime-protocol.test-support.js';
import { createBridgeMainRenderFulfillmentCoordinator } from './bridge-main-render-fulfillment-coordinator.js';
import { createBridgeMainRenderSnapshotStore } from './bridge-main-render-snapshot-store.js';
import type { BridgePaneSurfaceClient } from './bridge-pane-runtime.js';
import {
	BridgeProductBoundedAsyncQueue,
	createBridgeProductDeferred,
} from './bridge-product-async-queue.js';
import type { BridgeProductSubscriptionEvent } from './bridge-product-subscription-contracts.js';
import type { BridgeProductSubscription } from './bridge-product-transport-contract.js';
import type { BridgeProductTransportSession } from './bridge-product-transport.js';
import type {
	BridgeWorkerMainToServerMessage,
	BridgeWorkerServerToMainMessage,
} from './bridge-worker-contracts.js';
import { createBridgeWorkerRpcClient } from './bridge-worker-rpc-client.js';
import { createBridgeWorkerRpcLifecycleStore } from './bridge-worker-rpc-lifecycle-store.js';

describe('annotation projection resync runtime', () => {
	test('publishes ready only after the replacement first-state barrier', async () => {
		const fixture = createRuntimeResyncFixture();
		fixture.dispatchResync('file-old', 'resync-ready');
		await flushBridgeWorkerRuntimeContinuations();
		expect(fixture.requestMessages('resync-ready')).toEqual([]);

		fixture.fileReplacement.queue.push(projectionState(2, 1));
		await flushBridgeWorkerRuntimeContinuations();
		expect(fixture.requestMessages('resync-ready')).toEqual([
			expect.objectContaining({
				event: expect.objectContaining({ payload: expect.objectContaining({ revision: 2 }) }),
				kind: 'annotationProjection',
				subscriptionId: 'file-new',
			}),
			expect.objectContaining({ kind: 'health', status: 'ready' }),
		]);
	});

	test('times out before a late cancellation can subscribe or publish twice', async () => {
		const cancel = createBridgeProductDeferred<void>();
		const fixture = createRuntimeResyncFixture({ fileCancel: () => cancel.promise });
		fixture.dispatchResync('file-old', 'resync-timeout');
		fixture.fireDeadline();
		await flushBridgeWorkerRuntimeContinuations();
		expect(fixture.requestMessages('resync-timeout')).toEqual([
			expect.objectContaining({ kind: 'health', status: 'degraded' }),
		]);

		cancel.resolve();
		await flushBridgeWorkerRuntimeContinuations();
		expect(fixture.fileReplacement.wasRequested()).toBe(false);
		expect(fixture.requestMessages('resync-timeout')).toHaveLength(1);
	});

	test('degrades cancellation rejection and a non-state provisional replay exactly once', async () => {
		const rejected = createRuntimeResyncFixture({
			fileCancel: (): Promise<void> => Promise.reject(new Error('cancel rejected')),
		});
		rejected.dispatchResync('file-old', 'resync-rejected');
		await flushBridgeWorkerRuntimeContinuations();
		expect(rejected.requestMessages('resync-rejected')).toEqual([
			expect.objectContaining({ kind: 'health', status: 'degraded' }),
		]);

		const preState = createRuntimeResyncFixture();
		preState.dispatchResync('file-old', 'resync-pre-state');
		await flushBridgeWorkerRuntimeContinuations();
		preState.fileReplacement.queue.push(messageBatch(2));
		await flushBridgeWorkerRuntimeContinuations();
		expect(preState.requestMessages('resync-pre-state')).toEqual([
			expect.objectContaining({ kind: 'health', status: 'degraded' }),
		]);
		expect(preState.fileReplacement.cancelCount()).toBe(1);
	});

	test('rejects stale and same-surface concurrent RPCs without extra cancellation', async () => {
		const cancel = createBridgeProductDeferred<void>();
		const fixture = createRuntimeResyncFixture({ fileCancel: () => cancel.promise });
		fixture.dispatchResync('wrong-id', 'resync-stale');
		fixture.dispatchResync('file-old', 'resync-active');
		fixture.dispatchResync('file-old', 'resync-concurrent');
		await flushBridgeWorkerRuntimeContinuations();
		expect(fixture.requestMessages('resync-stale')).toEqual([
			expect.objectContaining({ kind: 'health', status: 'degraded' }),
		]);
		expect(fixture.requestMessages('resync-concurrent')).toEqual([
			expect.objectContaining({ kind: 'health', status: 'degraded' }),
		]);
		expect(fixture.fileOld.cancelCount()).toBe(1);
	});

	test('keeps the last complete main snapshot unavailable until the replay completes', async () => {
		const fixture = createRuntimeResyncFixture({ connectMainSurface: true });
		const client = requireAnnotationClient(fixture.annotationClient);
		fixture.fileOld.queue.push(projectionState(1, 1));
		fixture.fileOld.queue.push(messageBatch(1));
		await flushBridgeWorkerRuntimeContinuations();
		expect(client.getSnapshot()).toMatchObject({
			revision: 1,
			transportStatus: { kind: 'available' },
		});

		fixture.fileOld.queue.push(projectionState(2, 1));
		fixture.fileOld.queue.push(messageBatch(2, { messageThreadId: 'wrong-thread' }));
		fixture.fileOld.queue.push(projectionState(2, 0));
		await flushBridgeWorkerRuntimeContinuations();
		expect(client.getSnapshot()).toMatchObject({
			recoveryStatus: 'available',
			revision: 1,
			transportStatus: { kind: 'unavailable', recovery: 'requested' },
		});
		expect(fixture.resyncCommandCount()).toBe(1);

		fixture.fileReplacement.queue.push(projectionState(2, 1));
		await flushBridgeWorkerRuntimeContinuations();
		expect(client.getSnapshot()).toMatchObject({
			revision: 1,
			transportStatus: { kind: 'unavailable', recovery: 'awaitingReplay' },
		});

		fixture.fileReplacement.queue.push(messageBatch(2));
		await flushBridgeWorkerRuntimeContinuations();
		expect(client.getSnapshot()).toMatchObject({
			revision: 2,
			transportStatus: { kind: 'available' },
		});
		expect(fixture.resyncCommandCount()).toBe(1);
		expect(fixture.productCallCount).toBe(0);
	});

	test('allows zero-thread completion before ready without regressing on late ready', async () => {
		const fixture = createRuntimeResyncFixture({ connectMainSurface: true });
		const client = requireAnnotationClient(fixture.annotationClient);
		fixture.fileOld.queue.push(projectionState(1, 1));
		fixture.fileOld.queue.push(messageBatch(1, { messageThreadId: 'wrong-thread' }));
		await flushBridgeWorkerRuntimeContinuations();

		fixture.fileReplacement.queue.push(projectionState(1, 0));
		await flushBridgeWorkerRuntimeContinuations();
		expect(client.getSnapshot()).toMatchObject({
			revision: 1,
			transportStatus: { kind: 'available' },
		});
		await flushBridgeWorkerRuntimeContinuations();
		expect(client.getSnapshot().transportStatus).toEqual({ kind: 'available' });
	});
});

interface RuntimeResyncFixture {
	readonly annotationClient: WorktreeAnnotationSurfaceClient | null;
	readonly dispatchResync: (subscriptionId: string, requestId: string) => void;
	readonly fileOld: TestAnnotationSubscription<'file.annotations'>;
	readonly fileReplacement: TestAnnotationSubscription<'file.annotations'>;
	readonly fireDeadline: () => void;
	readonly productCallCount: number;
	readonly requestMessages: (requestId: string) => BridgeWorkerServerToMainMessage[];
	readonly resyncCommandCount: () => number;
}

function createRuntimeResyncFixture(
	options: {
		readonly connectMainSurface?: boolean;
		readonly fileCancel?: () => Promise<void>;
	} = {},
): RuntimeResyncFixture {
	const fileOld = annotationSubscription('file.annotations', 'file-old', options.fileCancel);
	const fileReplacement = annotationSubscription('file.annotations', 'file-new');
	const reviewOld = annotationSubscription('review.annotations', 'review-old');
	const subscriptions = {
		'file.annotations': [fileOld, fileReplacement],
		'review.annotations': [reviewOld],
	};
	let productCallCount = 0;
	const productTransport = {
		bumpWorkerDerivationEpoch: (): number => 0,
		call: (async (method: string): Promise<unknown> => {
			if (method === 'file.source.current') {
				return { reason: 'resync-test-no-file-source', status: 'unavailable' };
			}
			productCallCount += 1;
			throw new Error('Projection resync must not call a native product method.');
		}) as BridgeProductTransportSession['call'],
		openContent: (): never => {
			throw new Error('Projection resync must not open product content.');
		},
		subscribe: ((subscriptionKind: keyof typeof subscriptions): unknown => {
			const subscription = subscriptions[subscriptionKind].shift();
			if (subscription === undefined) throw new Error(`No ${subscriptionKind} subscription.`);
			return subscription;
		}) as BridgeProductTransportSession['subscribe'],
		workerDerivationEpoch: (): number => 0,
	} satisfies BridgeProductTransportSession;
	let receiveMainMessage = (_message: BridgeWorkerServerToMainMessage): void => {};
	const { dispatch, postedMessages } = createRecordingBridgeCommWorkerPort({
		beforePostMessage: (message): void => receiveMainMessage(message),
	});
	let sentResyncCommandCount = 0;
	const dispatchWorkerMessage = (message: Parameters<typeof dispatch.message>[0]): void => {
		if (
			typeof message === 'object' &&
			message !== null &&
			'command' in message &&
			message.command === 'annotationProjectionResync'
		) {
			sentResyncCommandCount += 1;
		}
		dispatch.message(message);
	};
	let deadline: (() => void) | null = null;
	registerBridgeCommWorkerRuntimePortProtocol(dispatch.port, {
		bridgeDemandRank: { lane: 'selected', priority: 0 },
		budget: { className: 'interactive', maxBytes: 512 * 1024, maxWindowLines: 50 },
		productTransport,
		productControlTimeoutMilliseconds: 50,
		scheduleAnnotationProjectionResyncDeadline: (_delay, fire): (() => void) => {
			deadline = fire;
			return (): void => {
				deadline = null;
			};
		},
	});

	let annotationClient: WorktreeAnnotationSurfaceClient | null = null;
	let dispatchResync = (subscriptionId: string, requestId: string): void => {
		dispatchWorkerMessage(resyncCommand(subscriptionId, requestId));
	};
	const resyncCommandCount = (): number => sentResyncCommandCount;
	if (options.connectMainSurface === true) {
		const lifecycleStore = createBridgeWorkerRpcLifecycleStore();
		const rpcClient = createBridgeWorkerRpcClient({
			dispatch: dispatchWorkerMessage,
			lifecycleStore,
			requestIdFactory: (() => {
				let nextRequest = 0;
				return (): string => {
					nextRequest += 1;
					return `main-request-${nextRequest}`;
				};
			})(),
			surface: 'fileView',
		});
		receiveMainMessage = (message): void => {
			void rpcClient.receive(message);
		};
		const surfaceClient = bridgePaneSurfaceClient(rpcClient);
		annotationClient = createWorktreeAnnotationSurfaceClient(surfaceClient);
		dispatchResync = (subscriptionId, requestId): void => {
			void subscriptionId;
			void requestId;
			throw new Error('Connected main surface owns resync dispatch.');
		};
	}

	return {
		annotationClient,
		dispatchResync,
		fileOld,
		fileReplacement,
		fireDeadline: (): void => {
			if (deadline === null) throw new Error('No annotation resync deadline is scheduled.');
			deadline();
		},
		get productCallCount(): number {
			return productCallCount;
		},
		requestMessages: (requestId): BridgeWorkerServerToMainMessage[] =>
			postedMessages
				.map(({ message }) => message)
				.filter((message) =>
					message.kind === 'health'
						? message.requestId === requestId
						: message.kind === 'annotationProjection',
				),
		resyncCommandCount,
	};
}

function bridgePaneSurfaceClient(
	rpcClient: ReturnType<typeof createBridgeWorkerRpcClient>,
): BridgePaneSurfaceClient {
	return {
		lifecycle: {
			getServerSnapshot: rpcClient.getLifecycleSnapshot,
			getSnapshot: rpcClient.getLifecycleSnapshot,
			subscribe: (): (() => void) => (): void => {},
		},
		renderFulfillmentCoordinator: createBridgeMainRenderFulfillmentCoordinator({
			cancelAnimationFrame: (): void => {},
			nowMilliseconds: (): number => 0,
			requestAnimationFrame: (): number => 1,
			sendDisposition: (): void => {},
		}),
		renderStore: createBridgeMainRenderSnapshotStore(),
		send: rpcClient.send,
		subscribeMessages: rpcClient.subscribe,
		surface: 'fileView',
	};
}

type TestAnnotationSubscription<TKind extends 'file.annotations' | 'review.annotations'> =
	BridgeProductSubscription<TKind> & {
		readonly cancelCount: () => number;
		readonly queue: BridgeProductBoundedAsyncQueue<BridgeProductSubscriptionEvent<TKind>>;
		readonly wasRequested: () => boolean;
	};

function annotationSubscription<TKind extends 'file.annotations' | 'review.annotations'>(
	subscriptionKind: TKind,
	subscriptionId: string,
	cancel: () => Promise<void> = (): Promise<void> => Promise.resolve(),
): TestAnnotationSubscription<TKind> {
	const queue = new BridgeProductBoundedAsyncQueue<BridgeProductSubscriptionEvent<TKind>>(8);
	let cancellationCount = 0;
	let requested = false;
	return {
		cancel: async (): Promise<void> => {
			cancellationCount += 1;
			await cancel();
			queue.close(true);
		},
		cancelCount: (): number => cancellationCount,
		events: {
			[Symbol.asyncIterator](): AsyncIterator<BridgeProductSubscriptionEvent<TKind>> {
				requested = true;
				return queue;
			},
		},
		queue,
		subscriptionId,
		subscriptionKind,
		update: async (): Promise<void> => {},
		wasRequested: (): boolean => requested,
	};
}

function resyncCommand(subscriptionId: string, requestId: string): BridgeWorkerMainToServerMessage {
	return {
		command: 'annotationProjectionResync',
		direction: 'mainToServerWorker',
		epoch: 0,
		failureClass: 'messageIdentityViolation',
		kind: 'command',
		requestId,
		revision: 2,
		subscriptionId,
		surface: 'fileView',
		transferDescriptors: [],
		wireVersion: 1,
	} as const;
}

function projectionState(
	revision: number,
	expectedThreadCount: number,
): Extract<
	BridgeProductSubscriptionEvent<'file.annotations'>,
	{ readonly eventKind: 'projection.state' }
> {
	return {
		eventKind: 'projection.state',
		payload: {
			commandOutcomes: [],
			expectedThreadCount,
			outputHistory: [],
			recoveryStatus: 'available',
			revision,
			sessions: [],
			worktreeId: 'worktree-1',
		},
	};
}

function messageBatch(
	revision: number,
	options: { readonly messageThreadId?: string } = {},
): Extract<
	BridgeProductSubscriptionEvent<'file.annotations'>,
	{ readonly eventKind: 'message.batch' }
> {
	const threadId = '00000000-0000-7000-8000-000000000012';
	return {
		eventKind: 'message.batch',
		payload: {
			context: {
				diffSide: null,
				endLine: 1,
				path: 'Sources/App.swift',
				placement: 'exact',
				resolution: 'open',
				scope: 'located',
				sourceIdentity: 'source-1',
				sourceRole: 'file',
				startLine: 1,
				threadId,
			},
			isLastBatchForThread: true,
			messages: [
				{
					authorKind: 'human',
					createdAt: 1,
					draft: null,
					messageId: '00000000-0000-7000-8000-000000000013',
					messageRevision: 1,
					ordinal: 0,
					savedBody: 'Saved',
					savedRevision: 1,
					sessionId: '00000000-0000-7000-8000-000000000011',
					sessionRevision: 1,
					status: 'editable',
					threadId: options.messageThreadId ?? threadId,
				},
			],
			revision,
		},
	};
}

function requireAnnotationClient(
	client: WorktreeAnnotationSurfaceClient | null,
): WorktreeAnnotationSurfaceClient {
	if (client === null) throw new Error('Expected connected annotation client.');
	return client;
}

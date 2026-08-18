import { describe, expect, test } from 'vitest';

import { runAnnotationProjectionResyncWithDeadline } from './bridge-comm-worker-annotation-projection-resync.js';
import { BridgeCommWorkerAnnotationSubscriptionController } from './bridge-comm-worker-annotation-subscription-controller.js';
import {
	BridgeProductBoundedAsyncQueue,
	createBridgeProductDeferred,
} from './bridge-product-async-queue.js';
import type { BridgeProductSubscriptionEvent } from './bridge-product-subscription-contracts.js';
import type { BridgeProductSubscription } from './bridge-product-transport-contract.js';
import type { BridgeProductTransportSession } from './bridge-product-transport.js';
import type { BridgeWorkerServerToMainMessage } from './bridge-worker-contracts.js';

describe('Bridge comm worker annotation subscription resync', () => {
	test('retires the old slot and promotes a provisional replacement only on its first state', async () => {
		const cancel = createBridgeProductDeferred<void>();
		const oldFile = annotationSubscription('file.annotations', 'file-old', () => cancel.promise);
		const replacementFile = annotationSubscription('file.annotations', 'file-new');
		const review = annotationSubscription('review.annotations', 'review-old');
		const forwarded: Array<{ readonly revision: number; readonly subscriptionId: string }> = [];
		const controller = annotationController({
			fileSubscriptions: [oldFile, replacementFile],
			onEvent: (event, subscriptionId): void => {
				forwarded.push({ revision: event.payload.revision, subscriptionId });
			},
			reviewSubscriptions: [review],
		});
		controller.ensureSubscriptions();

		const task = controller.beginResync({
			requestId: 'resync-1',
			subscriptionId: oldFile.subscriptionId,
			surface: 'file',
		});
		oldFile.queue.push(projectionState(1));
		await flushContinuations();
		expect(forwarded).toEqual([]);

		cancel.resolve();
		await flushContinuations();
		expect(forwarded).toEqual([]);
		replacementFile.queue.push(projectionState(2));
		await expect(task.completion).resolves.toBeUndefined();
		expect(forwarded).toEqual([{ revision: 2, subscriptionId: 'file-new' }]);

		replacementFile.queue.push(messageBatch(2));
		await flushContinuations();
		expect(forwarded).toEqual([
			{ revision: 2, subscriptionId: 'file-new' },
			{ revision: 2, subscriptionId: 'file-new' },
		]);
	});

	test('rejects stale and concurrent requests without a second cancellation', async () => {
		const cancel = createBridgeProductDeferred<void>();
		let cancelCount = 0;
		const oldFile = annotationSubscription('file.annotations', 'file-old', (): Promise<void> => {
			cancelCount += 1;
			return cancel.promise;
		});
		const controller = annotationController({
			fileSubscriptions: [oldFile],
			reviewSubscriptions: [annotationSubscription('review.annotations', 'review-old')],
		});
		controller.ensureSubscriptions();

		await expect(
			controller.beginResync({
				requestId: 'stale',
				subscriptionId: 'wrong-id',
				surface: 'file',
			}).completion,
		).rejects.toThrow('stale');
		await expect(
			controller.beginResync({
				requestId: 'wrong-surface',
				subscriptionId: 'file-old',
				surface: 'review',
			}).completion,
		).rejects.toThrow('stale');
		const active = controller.beginResync({
			requestId: 'active',
			subscriptionId: 'file-old',
			surface: 'file',
		});
		await expect(
			controller.beginResync({
				requestId: 'concurrent',
				subscriptionId: 'file-old',
				surface: 'file',
			}).completion,
		).rejects.toThrow('stale');
		expect(cancelCount).toBe(1);
		active.invalidate('concurrentReplacement');
		await expect(active.completion).rejects.toThrow('concurrentReplacement');
	});

	test('recovers File and Review concurrently without mixing their slots', async () => {
		const fileOld = annotationSubscription('file.annotations', 'file-old');
		const fileNew = annotationSubscription('file.annotations', 'file-new');
		const reviewOld = annotationSubscription('review.annotations', 'review-old');
		const reviewNew = annotationSubscription('review.annotations', 'review-new');
		const forwarded: string[] = [];
		const controller = annotationController({
			fileSubscriptions: [fileOld, fileNew],
			onEvent: (_event, subscriptionId): void => {
				forwarded.push(subscriptionId);
			},
			reviewSubscriptions: [reviewOld, reviewNew],
		});
		controller.ensureSubscriptions();
		const fileTask = controller.beginResync({
			requestId: 'file-resync',
			subscriptionId: 'file-old',
			surface: 'file',
		});
		const reviewTask = controller.beginResync({
			requestId: 'review-resync',
			subscriptionId: 'review-old',
			surface: 'review',
		});
		await flushContinuations();
		fileNew.queue.push(projectionState(2));
		reviewNew.queue.push(projectionState(3));
		await Promise.all([fileTask.completion, reviewTask.completion]);

		expect(forwarded.toSorted()).toEqual(['file-new', 'review-new']);
		expect(fileOld.cancelCount()).toBe(1);
		expect(reviewOld.cancelCount()).toBe(1);
	});

	test('invalidates a timed-out cancellation before late settlement can subscribe', async () => {
		const cancel = createBridgeProductDeferred<void>();
		const oldFile = annotationSubscription('file.annotations', 'file-old', () => cancel.promise);
		const replacementFile = annotationSubscription('file.annotations', 'file-new');
		const controller = annotationController({
			fileSubscriptions: [oldFile, replacementFile],
			reviewSubscriptions: [annotationSubscription('review.annotations', 'review-old')],
		});
		controller.ensureSubscriptions();
		const task = controller.beginResync({
			requestId: 'timeout-request',
			subscriptionId: 'file-old',
			surface: 'file',
		});
		const published: BridgeWorkerServerToMainMessage[] = [];
		let fireDeadline: (() => void) | null = null;
		runAnnotationProjectionResyncWithDeadline({
			publish: (message): void => {
				published.push(message);
			},
			scheduleDeadline: (_delay, deadline): (() => void) => {
				fireDeadline = deadline;
				return (): void => {
					fireDeadline = null;
				};
			},
			task,
			timeoutMilliseconds: 50,
		});
		requireDeadline(fireDeadline)();
		await expect(task.completion).rejects.toThrow('timeout');
		expect(published).toEqual([
			expect.objectContaining({ requestId: 'timeout-request', status: 'degraded' }),
		]);

		cancel.resolve();
		await flushContinuations();
		expect(replacementFile.wasRequested()).toBe(false);
		expect(published).toHaveLength(1);
	});

	test('fences a replaced runtime controller before late cancellation can install', async () => {
		const cancel = createBridgeProductDeferred<void>();
		let currentController = true;
		const oldFile = annotationSubscription('file.annotations', 'file-old', () => cancel.promise);
		const replacementFile = annotationSubscription('file.annotations', 'file-new');
		const controller = annotationController({
			fileSubscriptions: [oldFile, replacementFile],
			isCurrentController: (): boolean => currentController,
			reviewSubscriptions: [annotationSubscription('review.annotations', 'review-old')],
		});
		controller.ensureSubscriptions();
		const task = controller.beginResync({
			requestId: 'controller-replaced',
			subscriptionId: 'file-old',
			surface: 'file',
		});
		currentController = false;
		cancel.resolve();
		await expect(task.completion).rejects.toThrow('concurrentReplacement');
		expect(replacementFile.wasRequested()).toBe(false);
	});

	test('rejects cancellation failure and every pre-state provisional failure without an active slot', async () => {
		for (const firstReplay of ['batch', 'end', 'error'] as const) {
			const oldFile = annotationSubscription('file.annotations', `file-old-${firstReplay}`);
			const replacement = annotationSubscription('file.annotations', `file-new-${firstReplay}`);
			const controller = annotationController({
				fileSubscriptions: [oldFile, replacement],
				reviewSubscriptions: [
					annotationSubscription('review.annotations', `review-${firstReplay}`),
				],
			});
			controller.ensureSubscriptions();
			const task = controller.beginResync({
				requestId: `pre-state-${firstReplay}`,
				subscriptionId: oldFile.subscriptionId,
				surface: 'file',
			});
			await flushContinuations();
			if (firstReplay === 'batch') replacement.queue.push(messageBatch(1));
			else if (firstReplay === 'end') replacement.queue.close(true);
			else replacement.queue.fail(new Error('stream failed'), true);
			await expect(task.completion).rejects.toThrow();
			expect(replacement.cancelCount()).toBe(1);
			expect((): void => replacement.queue.push(projectionState(2))).toThrow('post-terminal');
			await expect(
				controller.beginResync({
					requestId: `no-active-${firstReplay}`,
					subscriptionId: replacement.subscriptionId,
					surface: 'file',
				}).completion,
			).rejects.toThrow('stale');
		}

		const rejectingOld = annotationSubscription(
			'file.annotations',
			'file-old-reject',
			(): Promise<void> => Promise.reject(new Error('cancel rejected')),
		);
		const controller = annotationController({
			fileSubscriptions: [rejectingOld],
			reviewSubscriptions: [annotationSubscription('review.annotations', 'review-reject')],
		});
		controller.ensureSubscriptions();
		await expect(
			controller.beginResync({
				requestId: 'cancel-reject',
				subscriptionId: rejectingOld.subscriptionId,
				surface: 'file',
			}).completion,
		).rejects.toThrow('commandRejected');

		const subscribeFailureOld = annotationSubscription('file.annotations', 'file-old-subscribe');
		const subscribeFailureController = annotationController({
			fileSubscriptions: [subscribeFailureOld],
			reviewSubscriptions: [annotationSubscription('review.annotations', 'review-subscribe')],
		});
		subscribeFailureController.ensureSubscriptions();
		await expect(
			subscribeFailureController.beginResync({
				requestId: 'subscribe-failure',
				subscriptionId: subscribeFailureOld.subscriptionId,
				surface: 'file',
			}).completion,
		).rejects.toThrow('commandRejected');
	});
});

type TestAnnotationSubscription<TKind extends 'file.annotations' | 'review.annotations'> =
	BridgeProductSubscription<TKind> & {
		readonly queue: BridgeProductBoundedAsyncQueue<BridgeProductSubscriptionEvent<TKind>>;
		readonly cancelCount: () => number;
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

function annotationController(props: {
	readonly fileSubscriptions: TestAnnotationSubscription<'file.annotations'>[];
	readonly isCurrentController?: () => boolean;
	readonly onEvent?: (
		event: BridgeProductSubscriptionEvent<'file.annotations' | 'review.annotations'>,
		subscriptionId: string,
	) => void;
	readonly reviewSubscriptions: TestAnnotationSubscription<'review.annotations'>[];
}): BridgeCommWorkerAnnotationSubscriptionController {
	const productTransport = {
		bumpWorkerDerivationEpoch: (): number => 0,
		call: async (): Promise<never> => {
			throw new Error('Annotation resync must not call native product methods.');
		},
		openContent: (): never => {
			throw new Error('Annotation resync must not open product content.');
		},
		subscribe: ((subscriptionKind: string): unknown => {
			const subscriptions =
				subscriptionKind === 'file.annotations'
					? props.fileSubscriptions
					: props.reviewSubscriptions;
			const subscription = subscriptions.shift();
			if (subscription === undefined) {
				throw new Error(`Unexpected annotation subscribe ${subscriptionKind}.`);
			}
			return subscription;
		}) as BridgeProductTransportSession['subscribe'],
		workerDerivationEpoch: (): number => 0,
	} satisfies BridgeProductTransportSession;
	return new BridgeCommWorkerAnnotationSubscriptionController({
		isCurrentController: props.isCurrentController ?? ((): boolean => true),
		onEvent: (event, subscriptionId): void => props.onEvent?.(event, subscriptionId),
		productTransport,
	});
}

function projectionState(
	revision: number,
): Extract<
	BridgeProductSubscriptionEvent<'file.annotations'>,
	{ readonly eventKind: 'projection.state' }
> {
	return {
		eventKind: 'projection.state',
		payload: {
			commandOutcomes: [],
			expectedThreadCount: 0,
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
): Extract<
	BridgeProductSubscriptionEvent<'file.annotations'>,
	{ readonly eventKind: 'message.batch' }
> {
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
				threadId: '00000000-0000-7000-8000-000000000012',
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
					threadId: '00000000-0000-7000-8000-000000000012',
				},
			],
			revision,
		},
	};
}

async function flushContinuations(): Promise<void> {
	await Promise.resolve();
	await Promise.resolve();
	await Promise.resolve();
}

function requireDeadline(deadline: (() => void) | null): () => void {
	if (deadline === null) throw new Error('Expected resync deadline.');
	return deadline;
}

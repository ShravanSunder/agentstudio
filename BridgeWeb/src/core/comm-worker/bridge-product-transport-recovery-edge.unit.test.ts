import { afterEach, describe, expect, test, vi } from 'vitest';

import { createBridgeProductDeferred } from './bridge-product-async-queue.js';
import {
	bridgeProductFileMetadataApplicationProtocol,
	bridgeProductReviewMetadataApplicationProtocol,
} from './bridge-product-metadata-application-registry.js';
import {
	bridgeProductMetadataFrameSchema,
	type BridgeProductMetadataStreamRequest,
} from './bridge-product-session-contracts.js';
import {
	createTransportHarness,
	disposeTransportHarnesses,
	emptyInterestHash,
	fileSourceAcceptedData,
	fileSourceConfiguration,
	metadataAccepted,
	interestBarrier,
	subscriptionAccepted,
	subscriptionCancelled,
	waitForCondition,
} from './test-fixtures/bridge-product-transport-metadata.test-support.js';
import {
	establishFileSubscription,
	observeSettlement,
	resyncResponse,
	retainedResponse,
} from './test-fixtures/bridge-product-transport-recovery.test-support.js';

afterEach(async () => {
	try {
		await disposeTransportHarnesses();
	} finally {
		vi.unstubAllGlobals();
		vi.useRealTimers();
	}
});

describe('Bridge product transport recovery edges', () => {
	test('does not invent a received cursor when the first stream fails before acceptance', async () => {
		// Arrange
		const harness = createTransportHarness();
		const subscription = harness.transport.subscribe(
			bridgeProductReviewMetadataApplicationProtocol,
			{
				interests: [],
			},
		);
		const terminal = subscription.events[Symbol.asyncIterator]().next();
		observeSettlement(terminal, (): void => {});
		await harness.server.waitForMetadataStream();

		// Act: no complete metadata frame has ever been delivered.
		harness.server.failMetadataReader(new Error('initial stream acceptance unavailable'));
		await expect(terminal).rejects.toThrow(/initial stream acceptance unavailable/iu);
		await new Promise<void>((resolve): void => {
			setImmediate(resolve);
		});

		// Assert: fail explicitly instead of claiming unobserved sequence zero.
		expect(
			harness.server.controlRequests.filter((request) => request.kind === 'workerSession.resync'),
		).toHaveLength(0);
		expect(harness.server.metadataFetchCount).toBe(1);
	});

	test('discards an interrupted frame prefix and reconciles from the last complete frame', async () => {
		// Arrange
		const harness = createTransportHarness();
		const first = await establishFileSubscription(harness);
		harness.server.resyncHandler = (request): Response =>
			resyncResponse(
				request,
				[
					{
						disposition: 'reopenRequired',
						reason: 'snapshot_required',
						requiredWorkerDerivationEpoch: 0,
						subscriptionId: first.subscription.subscriptionId,
						subscriptionKind: 'file.metadata',
					},
				],
				3,
			);
		const terminal = first.events.next();
		observeSettlement(terminal, (): void => {});

		// Act: native queued frame 3, but only half its length prefix arrives.
		harness.server.emitMetadataPrefix(
			fileSourceAcceptedData({
				epoch: 0,
				interestHash: emptyInterestHash('file.metadata'),
				request: harness.server.requiredMetadataRequest(),
				streamSequence: 3,
				subscriptionId: first.subscription.subscriptionId,
				subscriptionSequence: 2,
			}),
		);
		harness.server.endMetadataStream();

		// Assert: no partial frame is committed, and the old subscription is
		// retired only by the authoritative snapshot-required reconciliation.
		await harness.server.waitForMetadataStream(2);
		expect(
			harness.server.requiredControlRequest('workerSession.resync', 0).lastAcceptedStreamSequence,
		).toBe(2);
		await expect(terminal).rejects.toThrow(/snapshot_required/iu);
		const replacement = harness.server.requiredMetadataRequest(1);
		expect(replacement.resumeFromStreamSequence).toBe(3);
		harness.server.emitMetadata(metadataAccepted(replacement, 4, 'resumed'));
		await harness.server.waitForFrameAcknowledgementCount(4);
	});

	test.each(['network error', 'timeout'] as const)(
		'reconnects after acknowledgement %s using the locally committed frame cursor',
		async (failure): Promise<void> => {
			// Arrange
			const harness = createTransportHarness();
			const first = await establishFileSubscription(harness);
			const heldAcknowledgement = createBridgeProductDeferred<Response>();
			harness.server.nextAcknowledgementHandler = (): Promise<Response> => {
				if (failure === 'network error')
					return Promise.reject(new Error('acknowledgement connection lost'));
				return heldAcknowledgement.promise;
			};
			if (failure === 'timeout') vi.useFakeTimers({ toFake: ['setTimeout', 'clearTimeout'] });

			try {
				// Act: frame 3 commits locally, but its acknowledgement cannot finish.
				harness.server.emitMetadata(
					fileSourceAcceptedData({
						epoch: 0,
						interestHash: emptyInterestHash('file.metadata'),
						request: harness.server.requiredMetadataRequest(),
						streamSequence: 3,
						subscriptionId: first.subscription.subscriptionId,
						subscriptionSequence: 2,
					}),
				);
				await first.events.next();
				await harness.server.waitForFrameAcknowledgementCount(4);
				if (failure === 'timeout') await vi.advanceTimersByTimeAsync(5000);
				await harness.server.waitForMetadataStream(2);

				// Assert: acknowledgement loss does not replay already committed data.
				const resync = harness.server.requiredControlRequest('workerSession.resync', 0);
				expect(resync.lastAcceptedStreamSequence).toBe(3);
				const replacement = harness.server.requiredMetadataRequest(1);
				expect(replacement.resumeFromStreamSequence).toBe(3);
				harness.server.emitMetadata(metadataAccepted(replacement, 4, 'resumed'));
				harness.server.emitMetadata(
					fileSourceAcceptedData({
						epoch: 0,
						interestHash: emptyInterestHash('file.metadata'),
						request: replacement,
						streamSequence: 5,
						subscriptionId: first.subscription.subscriptionId,
						subscriptionSequence: 3,
					}),
				);
				await expect(first.events.next()).resolves.toMatchObject({
					done: false,
					value: { streamSequence: 5, subscriptionId: first.subscription.subscriptionId },
				});
				await waitForCondition(
					() =>
						harness.transport.metadataStreamDiagnostics?.().lastAcknowledgedStreamSequence === 5,
				);
			} finally {
				heldAcknowledgement.resolve(new Response(null, { status: 204 }));
			}
		},
	);

	test('bounds repeated connection openings even when no subscription frame was ever received', async () => {
		// Arrange: native accepted each open but its subscription acceptance was
		// lost. Reconciliation therefore requires a fresh subscription identity.
		const harness = createTransportHarness();
		harness.server.resyncHandler = (request): Response =>
			resyncResponse(
				request,
				request.activeSubscriptions.map((subscription) => ({
					disposition: 'reopenRequired',
					reason: 'snapshot_required',
					requiredWorkerDerivationEpoch: subscription.workerDerivationEpoch,
					subscriptionId: subscription.subscriptionId,
					subscriptionKind: subscription.subscriptionKind,
				})),
				request.lastAcceptedStreamSequence + 1,
			);
		const first = harness.transport.subscribe(bridgeProductReviewMetadataApplicationProtocol, {
			interests: [],
		});
		const firstTerminal = first.events[Symbol.asyncIterator]().next();
		observeSettlement(firstTerminal, (): void => {});
		await harness.server.waitForMetadataStream();
		harness.server.emitMetadata(metadataAccepted(harness.server.requiredMetadataRequest(), 0));
		await harness.server.waitForControlKind('subscription.open');
		harness.server.failMetadataReader(new Error('first subscription acceptance lost'));
		await expect(firstTerminal).rejects.toThrow(/snapshot_required/iu);
		const fresh = harness.transport.subscribe(bridgeProductReviewMetadataApplicationProtocol, {
			interests: [],
		});
		const freshTerminal = fresh.events[Symbol.asyncIterator]().next();
		observeSettlement(freshTerminal, (): void => {});
		await harness.server.waitForMetadataStream(2);
		harness.server.emitMetadata(
			metadataAccepted(harness.server.requiredMetadataRequest(1), 2, 'resumed'),
		);
		await harness.server.waitForControlKind('subscription.open', 2);

		// Act: another EOF with opening acknowledgements only is no useful progress.
		harness.server.endMetadataStream();

		// Assert
		await expect(freshTerminal).rejects.toThrow(/ended unexpectedly/iu);
		expect(
			harness.server.controlRequests.filter((request) => request.kind === 'workerSession.resync'),
		).toHaveLength(1);
		expect(harness.server.metadataFetchCount).toBe(2);
	});

	test('fails closed on a reset response that is not canonical empty authority', async () => {
		const harness = createTransportHarness();
		const first = await establishFileSubscription(harness);
		harness.server.resyncHandler = (request): Response =>
			resyncResponse(request, [
				{
					disposition: 'reset',
					interestRevision: 1,
					interestSha256: 'f'.repeat(64),
					reason: 'interest_mismatch',
					subscriptionId: first.subscription.subscriptionId,
					subscriptionKind: 'file.metadata',
					workerDerivationEpoch: 0,
				},
			]);
		const terminal = first.events.next();
		let terminalSettled = false;
		observeSettlement(terminal, (): void => {
			terminalSettled = true;
		});
		harness.server.failMetadataReader(new Error('reader failed'));
		await waitForCondition(() => terminalSettled);
		await expect(terminal).rejects.toThrow(/canonical|interest/iu);
		expect(harness.server.metadataFetchCount).toBe(1);
		harness.server.shutdown();
	});

	test('rejects a preserved pending update when replacement fails before reset replay attaches', async () => {
		const harness = createTransportHarness();
		const subscription = harness.transport.subscribe(
			bridgeProductReviewMetadataApplicationProtocol,
			{ interests: [] },
		);
		await harness.server.waitForMetadataStream();
		const initial = harness.server.requiredMetadataRequest();
		const emptyHash = emptyInterestHash('review.metadata');
		harness.server.emitMetadata(metadataAccepted(initial, 0));
		harness.server.emitMetadata(
			subscriptionAccepted({
				epoch: 0,
				interestHash: emptyHash,
				kind: 'review.metadata',
				request: initial,
				streamSequence: 1,
				subscriptionId: subscription.subscriptionId,
			}),
		);
		await harness.server.waitForControlKind('subscription.open');
		const update = subscription.update({
			interests: [{ itemIds: ['item-1'], lane: 'foreground' }],
		});
		observeSettlement(update, (): void => {});
		await harness.server.waitForControlKind('subscription.updateBatch');
		harness.server.resyncHandler = (request): Response =>
			resyncResponse(request, [
				{
					disposition: 'reset',
					interestRevision: 1,
					interestSha256: emptyHash,
					reason: 'interest_mismatch',
					subscriptionId: subscription.subscriptionId,
					subscriptionKind: 'review.metadata',
					workerDerivationEpoch: 0,
				},
			]);
		harness.server.failMetadataReader(new Error('lost barrier'));
		await harness.server.waitForMetadataStream(2);
		harness.server.failMetadataReader(new Error('replacement failed before acceptance'));
		let settled = false;
		observeSettlement(update, (): void => {
			settled = true;
		});
		await waitForCondition(() => settled);
		await expect(update).rejects.toThrow(/replacement failed/iu);
		harness.server.shutdown();
	});

	test('keeps a pending update unresolved until reset replay commits', async () => {
		const harness = createTransportHarness();
		const subscription = harness.transport.subscribe(
			bridgeProductReviewMetadataApplicationProtocol,
			{
				interests: [],
			},
		);
		await harness.server.waitForMetadataStream();
		const initial = harness.server.requiredMetadataRequest();
		const emptyHash = emptyInterestHash('review.metadata');
		harness.server.emitMetadata(metadataAccepted(initial, 0));
		harness.server.emitMetadata(
			subscriptionAccepted({
				epoch: 0,
				interestHash: emptyHash,
				kind: 'review.metadata',
				request: initial,
				streamSequence: 1,
				subscriptionId: subscription.subscriptionId,
			}),
		);
		await harness.server.waitForControlKind('subscription.open');
		const update = subscription.update({
			interests: [{ itemIds: ['item-1'], lane: 'foreground' }],
		});
		await harness.server.waitForControlKind('subscription.updateBatch');
		const newerUpdate = subscription.update({
			interests: [{ itemIds: ['item-2'], lane: 'foreground' }],
		});
		const queuedCancel = subscription.cancel();
		const originalUpdate = harness.server.requiredControlRequest('subscription.updateBatch', 0);
		let updateSettled = false;
		observeSettlement(update, (): void => {
			updateSettled = true;
		});
		harness.server.resyncHandler = (request): Response =>
			resyncResponse(request, [
				{
					disposition: 'reset',
					interestRevision: 1,
					interestSha256: emptyHash,
					reason: 'interest_mismatch',
					subscriptionId: subscription.subscriptionId,
					subscriptionKind: 'review.metadata',
					workerDerivationEpoch: 0,
				},
			]);
		harness.server.failMetadataReader(new Error('lost update barrier'));
		await harness.server.waitForMetadataStream(2);
		const replacement = harness.server.requiredMetadataRequest(1);
		expect(updateSettled).toBe(false);
		expect(
			harness.server.controlRequests.filter((request) => request.kind === 'subscription.cancel'),
		).toHaveLength(0);
		harness.server.emitMetadata(metadataAccepted(replacement, 2, 'resumed'));
		await harness.server.waitForControlKind('subscription.updateBatch', 2);
		const replay = harness.server.requiredControlRequest('subscription.updateBatch', 1);
		expect(replay).toMatchObject({
			baseInterestRevision: 1,
			baseInterestSha256: emptyHash,
			subscriptionId: subscription.subscriptionId,
		});
		expect(replay.updateId).not.toBe(originalUpdate.updateId);
		expect(updateSettled).toBe(false);
		harness.server.emitMetadata(interestBarrier(replay, replacement, 3, 1));
		await update;
		expect(updateSettled).toBe(true);
		await harness.server.waitForControlKind('subscription.updateBatch', 3);
		const newerRequest = harness.server.requiredControlRequest('subscription.updateBatch', 2);
		expect(newerRequest).toMatchObject({
			baseInterestRevision: replay.targetInterestRevision,
			delta: {
				add: [{ itemId: 'item-2', lane: 'foreground' }],
				removeItemIds: ['item-1'],
			},
		});
		harness.server.emitMetadata(interestBarrier(newerRequest, replacement, 4, 2));
		await newerUpdate;
		await harness.server.waitForControlKind('subscription.cancel');
		harness.server.emitMetadata(
			subscriptionCancelled({
				epoch: 0,
				interestHash: newerRequest.targetInterestSha256,
				kind: 'review.metadata',
				request: replacement,
				sourceGeneration: 1,
				streamSequence: 5,
				subscriptionId: subscription.subscriptionId,
				subscriptionSequence: 3,
			}),
		);
		await queuedCancel;
		harness.server.shutdown();
	});

	test('claims a half-open control-admitted subscription and waits for replacement before typed recovery', async () => {
		const harness = createTransportHarness();
		const subscription = harness.transport.subscribe(bridgeProductFileMetadataApplicationProtocol, {
			interests: [],
			pathScope: [],
			source: fileSourceConfiguration(),
		});
		const terminal = subscription.events[Symbol.asyncIterator]().next();
		observeSettlement(terminal, (): void => {});
		await harness.server.waitForMetadataStream();
		const initial = harness.server.requiredMetadataRequest();
		harness.server.emitMetadata(metadataAccepted(initial, 0));
		await harness.server.waitForControlKind('subscription.open');
		harness.server.resyncHandler = (request): Response =>
			resyncResponse(request, [
				{
					disposition: 'reopenRequired',
					reason: 'snapshot_required',
					requiredWorkerDerivationEpoch: 0,
					subscriptionId: subscription.subscriptionId,
					subscriptionKind: 'file.metadata',
				},
			]);
		harness.server.failMetadataReader(new Error('lost acceptance'));
		await harness.server.waitForControlKind('workerSession.resync');
		const resync = harness.server.requiredControlRequest('workerSession.resync', 0);
		expect(resync.activeSubscriptions).toHaveLength(1);
		await harness.server.waitForMetadataStream(2);
		await expect(terminal).rejects.toThrow(/snapshot_required/iu);
		const fresh = harness.transport.subscribe(bridgeProductFileMetadataApplicationProtocol, {
			interests: [],
			pathScope: [],
			source: fileSourceConfiguration(),
		});
		expect(fresh.subscriptionId).not.toBe(subscription.subscriptionId);
		await Promise.resolve();
		expect(
			harness.server.controlRequests.filter((request) => request.kind === 'subscription.open'),
		).toHaveLength(1);
		const replacement = harness.server.requiredMetadataRequest(1);
		harness.server.emitMetadata(metadataAccepted(replacement, 1, 'snapshot_required'));
		await harness.server.waitForControlKind('subscription.open', 2);
		harness.server.shutdown();
	});

	test('completes an admitted local cancel on authoritative native_missing without reopening', async () => {
		const harness = createTransportHarness();
		const first = await establishFileSubscription(harness);
		const cancel = first.subscription.cancel();
		await harness.server.waitForControlKind('subscription.cancel');
		harness.server.resyncHandler = (request): Response =>
			resyncResponse(request, [
				{
					disposition: 'reopenRequired',
					reason: 'native_missing',
					requiredWorkerDerivationEpoch: 0,
					subscriptionId: first.subscription.subscriptionId,
					subscriptionKind: 'file.metadata',
				},
			]);
		harness.server.failMetadataReader(new Error('lost cancellation terminal'));
		await harness.server.waitForMetadataStream(2);
		let settled = false;
		observeSettlement(cancel, (): void => {
			settled = true;
		});
		expect(settled).toBe(false);
		const replacement = harness.server.requiredMetadataRequest(1);
		harness.server.emitMetadata(metadataAccepted(replacement, 3, 'resumed'));
		await cancel;
		expect(
			harness.server.controlRequests.filter((request) => request.kind === 'subscription.open'),
		).toHaveLength(1);
		harness.server.shutdown();
	});
	test('holds a fresh subscription behind an in-flight resync and does not open a second stream', async () => {
		const harness = createTransportHarness();
		const heldResponse = createBridgeProductDeferred<Response>();
		harness.server.resyncHandler = (): Promise<Response> => heldResponse.promise;
		const first = await establishFileSubscription(harness);
		harness.server.failMetadataReader(new Error('reader failed'));
		await harness.server.waitForControlKind('workerSession.resync');

		const fresh = harness.transport.subscribe(bridgeProductReviewMetadataApplicationProtocol, {
			interests: [],
		});
		await Promise.resolve();
		expect(harness.server.metadataFetchCount).toBe(1);
		expect(
			harness.server.controlRequests.filter((request) => request.kind === 'subscription.open'),
		).toHaveLength(1);

		const request = harness.server.requiredControlRequest('workerSession.resync', 0);
		heldResponse.resolve(retainedResponse(request));
		await harness.server.waitForMetadataStream(2);
		const replacement = harness.server.requiredMetadataRequest(1);
		harness.server.emitMetadata(metadataAccepted(replacement, 3, 'resumed'));
		await harness.server.waitForControlKind('subscription.open', 2);
		void fresh;
		void first;
		harness.server.shutdown();
	});

	test('settles subscriptions and recovery waiters when resync fails', async () => {
		const harness = createTransportHarness();
		const heldResponse = createBridgeProductDeferred<Response>();
		harness.server.resyncHandler = (): Promise<Response> => heldResponse.promise;
		const first = await establishFileSubscription(harness);
		const terminal = first.events.next();
		observeSettlement(terminal, (): void => {});
		harness.server.failMetadataReader(new Error('reader failed'));
		await harness.server.waitForControlKind('workerSession.resync');
		const fresh = harness.transport.subscribe(bridgeProductReviewMetadataApplicationProtocol, {
			interests: [],
		});
		const freshTerminal = fresh.events[Symbol.asyncIterator]().next();
		let freshSettled = false;
		observeSettlement(freshTerminal, (): void => {
			freshSettled = true;
		});
		// Release failure only after the fresh subscriber has joined recovery.
		heldResponse.reject(new Error('resync transport failed twice'));
		await expect(terminal).rejects.toThrow(/resync transport failed/iu);
		await waitForCondition(() => freshSettled);
		await expect(freshTerminal).rejects.toThrow(/resync transport failed/iu);
		expect(harness.transport.metadataStreamDiagnostics?.().activeSubscriptionCount).toBe(0);
		harness.server.shutdown();
	});

	test.each(['none', 'presentation', 'selection'] as const)(
		'does not replenish recovery from connection replay (%s)',
		async (replayKind): Promise<void> => {
			const harness = createTransportHarness();
			const first = await establishFileSubscription(harness);
			const terminal = first.events.next();
			let terminalSettled = false;
			observeSettlement(terminal, (): void => {
				terminalSettled = true;
			});
			const emitReplay = (
				request: BridgeProductMetadataStreamRequest,
				streamSequence: number,
			): void => {
				const replay =
					replayKind === 'presentation'
						? {
								fileRefreshFailure: null,
								kind: 'pane.presentation',
								nativeActivity: 'foreground',
								operationCorrelationId: null,
								presentationRevision: 1,
								refreshingLanes: [],
								reviewComparison: null,
							}
						: {
								kind: 'pane.surfaceSelectionRequested',
								navigationCommand: {
									bindingRevision: 1,
									commandId: 'retained-navigation',
									commandKind: 'activateContext',
									surface: 'file',
								},
							};
				harness.server.emitMetadata(
					bridgeProductMetadataFrameSchema.parse({
						...replay,
						metadataStreamId: request.metadataStreamId,
						paneSessionId: request.paneSessionId,
						streamSequence,
						wireVersion: request.wireVersion,
						workerInstanceId: request.workerInstanceId,
					}),
				);
			};
			let nextStreamSequence = 3;
			if (replayKind !== 'none') {
				emitReplay(harness.server.requiredMetadataRequest(), nextStreamSequence++);
				await harness.server.waitForFrameAcknowledgementCount(nextStreamSequence);
			}
			harness.server.endMetadataStream();
			await harness.server.waitForMetadataStream(2);
			const replacement = harness.server.requiredMetadataRequest(1);
			harness.server.emitMetadata(metadataAccepted(replacement, nextStreamSequence++, 'resumed'));
			if (replayKind !== 'none') emitReplay(replacement, nextStreamSequence++);
			await harness.server.waitForFrameAcknowledgementCount(nextStreamSequence);
			harness.server.endMetadataStream();

			await waitForCondition(() => terminalSettled || harness.server.metadataFetchCount > 2);
			expect(harness.server.metadataFetchCount).toBe(2);
			await expect(terminal).rejects.toThrow(/ended unexpectedly/iu);
			harness.server.shutdown();
		},
	);

	test('does not resync or reopen after a strict metadata identity failure', async () => {
		const harness = createTransportHarness();
		const subscription = harness.transport.subscribe(
			bridgeProductReviewMetadataApplicationProtocol,
			{ interests: [] },
		);
		const terminal = subscription.events[Symbol.asyncIterator]().next();
		await harness.server.waitForMetadataStream();
		const request = harness.server.requiredMetadataRequest();
		harness.server.emitMetadata(metadataAccepted(request, 0));
		harness.server.emitMetadata(
			bridgeProductMetadataFrameSchema.parse({
				...metadataAccepted(request, 1),
				metadataStreamId: 'wrong-stream',
			}),
		);

		await expect(terminal).rejects.toThrow();
		expect(harness.server.metadataFetchCount).toBe(1);
		expect(
			harness.server.controlRequests.filter(
				(candidate) => candidate.kind === 'workerSession.resync',
			),
		).toHaveLength(0);
		harness.server.shutdown();
	});
});

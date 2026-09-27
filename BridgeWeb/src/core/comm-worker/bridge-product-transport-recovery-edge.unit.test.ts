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
	fileSourceConfiguration,
	metadataAccepted,
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
	test('does not invent a received stream sequence when the first stream fails before acceptance', async () => {
		// Arrange
		const harness = createTransportHarness();
		const subscription = harness.transport.subscribe(
			bridgeProductReviewMetadataApplicationProtocol,
			{},
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

		// Assert: fail explicitly instead of claiming unobserved stream sequence zero.
		expect(
			harness.server.controlRequests.filter((request) => request.kind === 'workerSession.resync'),
		).toHaveLength(0);
		expect(harness.server.metadataFetchCount).toBe(1);
	});

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
		const first = harness.transport.subscribe(bridgeProductReviewMetadataApplicationProtocol, {});
		const firstTerminal = first.events[Symbol.asyncIterator]().next();
		observeSettlement(firstTerminal, (): void => {});
		await harness.server.waitForMetadataStream();
		harness.server.emitMetadata(metadataAccepted(harness.server.requiredMetadataRequest(), 0));
		await harness.server.waitForControlKind('subscription.open');
		harness.server.failMetadataReader(new Error('first subscription acceptance lost'));
		await expect(firstTerminal).rejects.toThrow(/snapshot_required/iu);
		const fresh = harness.transport.subscribe(bridgeProductReviewMetadataApplicationProtocol, {});
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

	test('claims a half-open control-admitted subscription and waits for replacement before typed recovery', async () => {
		const harness = createTransportHarness();
		const subscription = harness.transport.subscribe(bridgeProductFileMetadataApplicationProtocol, {
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

		const fresh = harness.transport.subscribe(bridgeProductReviewMetadataApplicationProtocol, {});
		await Promise.resolve();
		expect(harness.server.metadataFetchCount).toBe(1);
		expect(
			harness.server.controlRequests.filter((request) => request.kind === 'subscription.open'),
		).toHaveLength(1);

		const request = harness.server.requiredControlRequest('workerSession.resync', 0);
		heldResponse.resolve(retainedResponse(request));
		await harness.server.waitForMetadataStream(2);
		const replacement = harness.server.requiredMetadataRequest(1);
		if (replacement.resumeFromStreamSequence === null)
			throw new Error('Expected a resumed metadata stream.');
		harness.server.emitMetadata(
			metadataAccepted(replacement, replacement.resumeFromStreamSequence + 1, 'resumed'),
		);
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
		const fresh = harness.transport.subscribe(bridgeProductReviewMetadataApplicationProtocol, {});
		const freshTerminal = fresh.events[Symbol.asyncIterator]().next();
		let freshSettled = false;
		observeSettlement(freshTerminal, (): void => {
			freshSettled = true;
		});
		// Release failure only after the fresh subscriber has joined recovery.
		heldResponse.reject(new Error('resync transport failed twice'));
		await expect(terminal).rejects.toMatchObject({ name: 'BridgeProductSessionSuspectError' });
		await waitForCondition(() => freshSettled);
		await expect(freshTerminal).rejects.toMatchObject({ name: 'BridgeProductSessionSuspectError' });
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
			let nextStreamSequence = 2;
			if (replayKind !== 'none') {
				emitReplay(harness.server.requiredMetadataRequest(), nextStreamSequence++);
				await waitForCondition(
					() =>
						harness.transport.metadataStreamDiagnostics?.().routedFrameCount === nextStreamSequence,
				);
			}
			harness.server.endMetadataStream();
			await harness.server.waitForMetadataStream(2);
			const replacement = harness.server.requiredMetadataRequest(1);
			harness.server.emitMetadata(metadataAccepted(replacement, nextStreamSequence++, 'resumed'));
			if (replayKind !== 'none') {
				emitReplay(replacement, nextStreamSequence++);
				await waitForCondition(
					() =>
						harness.transport.metadataStreamDiagnostics?.().routedFrameCount === nextStreamSequence,
				);
			}
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
			{},
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

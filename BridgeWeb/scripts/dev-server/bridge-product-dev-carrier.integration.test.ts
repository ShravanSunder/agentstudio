import { createHash } from 'node:crypto';

import { afterEach, describe, expect, test } from 'vitest';

import {
	assertBridgeProductResyncReconciliationMatchesRequest,
	bridgeProductControlRequestSchema,
} from '../../src/core/comm-worker/bridge-product-session-contracts.js';
import type { BridgeProductSubscriptionInterestState } from '../../src/core/comm-worker/bridge-product-subscription-contracts.js';
import { encodeBridgeProductSubscriptionInterestState } from '../../src/core/comm-worker/bridge-product-subscription-interest-state-codec.js';
import {
	LiveProductClient,
	LiveViteProductServer,
	liveViteCarrierTestTimeoutMilliseconds,
} from './bridge-product-dev-carrier-live.test-support.js';

describe('Bridge product real Vite pane carrier recovery', () => {
	let liveServer: LiveViteProductServer | null = null;

	afterEach(async (): Promise<void> => {
		await liveServer?.close();
		liveServer = null;
	});

	test(
		'reconnects, resyncs positionally, reopens, streams File content, and cancels',
		async () => {
			liveServer = await LiveViteProductServer.start();
			const client = await LiveProductClient.connect(liveServer.baseURL);
			const opened = await client.postControl(1, { kind: 'workerSession.open', request: null });
			const source = await client.postControl(2, {
				call: { method: 'file.source.current', request: {} },
				kind: 'product.call',
				workerDerivationEpoch: 0,
			});
			if (
				source.value.kind !== 'call.completed' ||
				source.value.call.method !== 'file.source.current' ||
				source.value.call.result.status !== 'available'
			) {
				throw new Error('Expected an available live File source.');
			}

			const firstStream = await client.openStream('vite-real-stream-1', null);
			const firstAccepted = await firstStream.frames.waitFor(
				(frame) => frame.kind === 'metadataStream.accepted',
			);
			const foregroundPresentation = await firstStream.frames.waitFor(
				(frame) => frame.kind === 'pane.presentation',
			);
			const oldSubscriptionId = 'vite-real-subscription-old';
			const oldSubscription = await client.postControl(3, {
				kind: 'subscription.open',
				subscription: {
					source: source.value.call.result.source,
					subscriptionKind: 'file.metadata',
				},
				subscriptionId: oldSubscriptionId,
				workerDerivationEpoch: 0,
			});
			if (oldSubscription.value.kind !== 'subscription.openAccepted') {
				throw new Error('Expected the old live subscription to open.');
			}
			const finalTreeWindow = await firstStream.frames.waitFor(
				(frame) =>
					frame.kind === 'subscription.data' &&
					frame.subscriptionId === oldSubscriptionId &&
					frame.data.subscriptionKind === 'file.metadata' &&
					frame.data.event.eventKind === 'file.treeWindow' &&
					frame.data.event.finalWindow,
			);
			const committedStreamSequence = finalTreeWindow.streamSequence;
			firstStream.close();
			await liveServer.waitForMetadataStreamClose(0);

			const replacementStream = await client.openStream(
				'vite-real-stream-2',
				committedStreamSequence,
			);
			const replacementAccepted = await replacementStream.frames.waitFor(
				(frame) => frame.kind === 'metadataStream.accepted',
			);
			const replacementForegroundPresentation = await replacementStream.frames.waitFor(
				(frame) => frame.kind === 'pane.presentation',
			);
			const resyncRequest = bridgeProductControlRequestSchema.parse({
				...client.controlIdentity(4),
				activeSubscriptions: [
					{
						interestRevision: 0,
						interestSha256: oldSubscription.value.interestSha256,
						subscriptionId: oldSubscriptionId,
						subscriptionKind: 'file.metadata',
						workerDerivationEpoch: 0,
					},
					{
						interestRevision: 3,
						interestSha256: 'a'.repeat(64),
						subscriptionId: 'vite-real-unclaimed-review-subscription',
						subscriptionKind: 'review.metadata',
						workerDerivationEpoch: 7,
					},
				],
				kind: 'workerSession.resync',
				lastAcceptedRequestSequence: 3,
				lastAcceptedStreamSequence: committedStreamSequence,
			});
			const resync = await client.postParsedControl(resyncRequest);
			assertBridgeProductResyncReconciliationMatchesRequest({
				request: resyncRequest,
				response: resync.value,
			});
			if (resync.value.kind !== 'resync.accepted') throw new Error('Expected resync acceptance.');
			expect(resync.value.reconciliation).toEqual([
				{
					disposition: 'reopenRequired',
					reason: 'snapshot_required',
					requiredWorkerDerivationEpoch: 0,
					subscriptionId: oldSubscriptionId,
					subscriptionKind: 'file.metadata',
				},
				{
					disposition: 'reopenRequired',
					reason: 'snapshot_required',
					requiredWorkerDerivationEpoch: 7,
					subscriptionId: 'vite-real-unclaimed-review-subscription',
					subscriptionKind: 'review.metadata',
				},
			]);

			const freshSubscriptionId = 'vite-real-subscription-fresh';
			const fresh = await client.postControl(5, {
				kind: 'subscription.open',
				subscription: {
					source: source.value.call.result.source,
					subscriptionKind: 'file.metadata',
				},
				subscriptionId: freshSubscriptionId,
				workerDerivationEpoch: 0,
			});
			if (fresh.value.kind !== 'subscription.openAccepted') {
				throw new Error('Expected the fresh live subscription to open.');
			}
			const path = 'README.md';
			const targetInterestState: BridgeProductSubscriptionInterestState = {
				interests: [{ lane: 'foreground', paths: [path] }],
				pathScope: [],
				subscriptionKind: 'file.metadata',
			};
			const targetInterestSha256 = createHash('sha256')
				.update(encodeBridgeProductSubscriptionInterestState(targetInterestState))
				.digest('hex');
			const updated = await client.postControl(6, {
				baseInterestRevision: 0,
				baseInterestSha256: fresh.value.interestSha256,
				batchCount: 1,
				batchIndex: 0,
				delta: {
					add: [{ lane: 'foreground', path }],
					addPathScope: [],
					removePathScope: [],
					removePaths: [],
					subscriptionKind: 'file.metadata',
				},
				kind: 'subscription.updateBatch',
				subscriptionId: freshSubscriptionId,
				subscriptionKind: 'file.metadata',
				targetInterestRevision: 1,
				targetInterestSha256,
				totalDeltaItemCount: 1,
				updateId: 'vite-real-update-1',
				workerDerivationEpoch: 0,
			});
			expect(updated.value.kind).toBe('subscription.updateBatchAccepted');
			const descriptorFrame = await replacementStream.frames.waitFor(
				(frame) =>
					frame.kind === 'subscription.data' &&
					frame.subscriptionId === freshSubscriptionId &&
					frame.data.subscriptionKind === 'file.metadata' &&
					frame.data.event.eventKind === 'file.descriptorReady' &&
					frame.data.event.path === path,
			);
			const descriptorEvent =
				descriptorFrame.kind === 'subscription.data' &&
				descriptorFrame.data.subscriptionKind === 'file.metadata'
					? descriptorFrame.data.event
					: null;
			if (
				descriptorEvent?.eventKind !== 'file.descriptorReady' ||
				descriptorEvent.availability.availabilityKind !== 'available'
			) {
				throw new Error('Expected an available live File descriptor.');
			}
			const content = await client.openContent(descriptorEvent.availability.contentDescriptor);
			const cancelled = await client.postControl(7, {
				kind: 'subscription.cancel',
				subscriptionId: freshSubscriptionId,
				subscriptionKind: 'file.metadata',
				workerDerivationEpoch: 0,
			});
			const cancelledFrame = await replacementStream.frames.waitFor(
				(frame) =>
					frame.kind === 'subscription.cancelled' && frame.subscriptionId === freshSubscriptionId,
			);
			replacementStream.close();
			await liveServer.waitForMetadataStreamClose(1);

			expect(opened).toMatchObject({ status: 200, value: { kind: 'workerSession.accepted' } });
			expect(firstAccepted).toMatchObject({ kind: 'metadataStream.accepted', streamSequence: 0 });
			expect(foregroundPresentation).toMatchObject({
				activityRevision: 1,
				kind: 'pane.presentation',
				nativeActivity: 'foreground',
				refreshingLanes: [],
			});
			expect(replacementAccepted).toMatchObject({
				kind: 'metadataStream.accepted',
				resumeDisposition: 'snapshot_required',
				streamSequence: committedStreamSequence + 1,
			});
			expect(resync.value.metadataStreamSequenceBarrier).toBe(
				replacementForegroundPresentation.streamSequence,
			);
			expect(content).toEqual({
				byteLength: descriptorEvent.availability.contentDescriptor.declaredByteLength,
				contentKind: 'file.content',
				status: 200,
				terminalKind: 'complete',
			});
			expect(cancelled).toMatchObject({
				status: 200,
				value: { kind: 'subscription.cancelAccepted', subscriptionId: freshSubscriptionId },
			});
			expect(cancelledFrame.streamSequence).toBeGreaterThan(replacementAccepted.streamSequence);
		},
		liveViteCarrierTestTimeoutMilliseconds,
	);

	test(
		'multiplexes real Review and File metadata on one acknowledged physical stream',
		async () => {
			liveServer = await LiveViteProductServer.start();
			const client = await LiveProductClient.connect(liveServer.baseURL);
			await client.postControl(1, { kind: 'workerSession.open', request: null });
			const stream = await client.openStream('vite-mixed-stream-1', null);
			await stream.frames.waitFor((frame) => frame.kind === 'metadataStream.accepted');

			const reviewSubscriptionId = 'vite-real-review-subscription';
			const reviewOpened = await client.postControl(2, {
				kind: 'subscription.open',
				subscription: { subscriptionKind: 'review.metadata' },
				subscriptionId: reviewSubscriptionId,
				workerDerivationEpoch: 1,
			});
			const finalReviewWindow = await stream.frames.waitFor(
				(frame) =>
					frame.kind === 'subscription.data' &&
					frame.subscriptionId === reviewSubscriptionId &&
					frame.data.subscriptionKind === 'review.metadata' &&
					(frame.data.event.eventKind === 'review.snapshot' ||
						frame.data.event.eventKind === 'review.window') &&
					frame.data.event.itemWindow.finalWindow,
			);

			const source = await client.postControl(3, {
				call: { method: 'file.source.current', request: {} },
				kind: 'product.call',
				workerDerivationEpoch: 1,
			});
			if (
				source.value.kind !== 'call.completed' ||
				source.value.call.method !== 'file.source.current' ||
				source.value.call.result.status !== 'available'
			) {
				throw new Error('Expected an available mixed-lane File source.');
			}
			const fileSubscriptionId = 'vite-real-file-subscription';
			const fileOpened = await client.postControl(4, {
				kind: 'subscription.open',
				subscription: {
					source: source.value.call.result.source,
					subscriptionKind: 'file.metadata',
				},
				subscriptionId: fileSubscriptionId,
				workerDerivationEpoch: 1,
			});
			const finalFileWindow = await stream.frames.waitFor(
				(frame) =>
					frame.kind === 'subscription.data' &&
					frame.subscriptionId === fileSubscriptionId &&
					frame.data.subscriptionKind === 'file.metadata' &&
					frame.data.event.eventKind === 'file.treeWindow' &&
					frame.data.event.finalWindow,
			);
			const reviewCancelled = await client.postControl(5, {
				kind: 'subscription.cancel',
				subscriptionId: reviewSubscriptionId,
				subscriptionKind: 'review.metadata',
				workerDerivationEpoch: 1,
			});
			const reviewCancelledFrame = await stream.frames.waitFor(
				(frame) =>
					frame.kind === 'subscription.cancelled' && frame.subscriptionId === reviewSubscriptionId,
			);
			stream.close();

			expect(reviewOpened.value).toMatchObject({
				kind: 'subscription.openAccepted',
				subscriptionKind: 'review.metadata',
			});
			expect(fileOpened.value).toMatchObject({
				kind: 'subscription.openAccepted',
				subscriptionKind: 'file.metadata',
			});
			expect(finalFileWindow.streamSequence).toBeGreaterThan(finalReviewWindow.streamSequence);
			expect(reviewCancelled.value.kind).toBe('subscription.cancelAccepted');
			expect(reviewCancelledFrame.streamSequence).toBeGreaterThan(finalFileWindow.streamSequence);
		},
		liveViteCarrierTestTimeoutMilliseconds,
	);
});

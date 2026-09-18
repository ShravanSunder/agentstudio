import { afterEach, describe, expect, test, vi } from 'vitest';

import { bridgeProductFileMetadataApplicationProtocol } from './bridge-product-metadata-application-registry.js';
import {
	createTransportHarness,
	disposeTransportHarnesses,
	emptyInterestHash,
	fileSourceAcceptedData,
	fileSourceConfiguration,
	fileSourceIdentity,
	metadataAccepted,
	subscriptionAccepted,
	subscriptionCancelled,
} from './test-fixtures/bridge-product-transport-metadata.test-support.js';

afterEach(async () => {
	try {
		await disposeTransportHarnesses();
	} finally {
		vi.unstubAllGlobals();
	}
});

describe('Bridge product transport metadata reconnection', () => {
	test.each(['read-error', 'eof'] as const)(
		'retains an accepted File subscription across a physical metadata %s',
		async (failureKind) => {
			const harness = createTransportHarness();
			const subscription = harness.transport.subscribe(
				bridgeProductFileMetadataApplicationProtocol,
				{
					interests: [],
					pathScope: [],
					source: fileSourceConfiguration(),
				},
			);
			const events = subscription.events[Symbol.asyncIterator]();
			const interestHash = emptyInterestHash('file.metadata');

			try {
				await harness.server.waitForMetadataStream();
				const initialStreamRequest = harness.server.requiredMetadataRequest(0);
				harness.server.emitMetadata(metadataAccepted(initialStreamRequest, 0));
				harness.server.emitMetadata(
					subscriptionAccepted({
						epoch: 0,
						interestHash,
						kind: 'file.metadata',
						request: initialStreamRequest,
						streamSequence: 1,
						subscriptionId: subscription.subscriptionId,
					}),
				);
				await harness.server.waitForControlKind('subscription.open');
				harness.server.emitMetadata(
					fileSourceAcceptedData({
						epoch: 0,
						interestHash,
						request: initialStreamRequest,
						streamSequence: 2,
						subscriptionId: subscription.subscriptionId,
					}),
				);

				await expect(events.next()).resolves.toMatchObject({
					done: false,
					value: {
						data: { eventKind: 'file.sourceAccepted', source: fileSourceIdentity(1) },
						streamSequence: 2,
						subscriptionId: subscription.subscriptionId,
						subscriptionSequence: 1,
					},
				});
				await harness.server.waitForFrameAcknowledgementCount(3);

				if (failureKind === 'read-error') {
					harness.server.failMetadataReader(new Error('deliberate physical metadata read failure'));
				} else {
					harness.server.endMetadataStream();
				}

				await harness.server.waitForControlKind('workerSession.resync');
				const resyncRequest = harness.server.requiredControlRequest('workerSession.resync', 0);
				expect(resyncRequest).toMatchObject({
					activeSubscriptions: [
						{
							interestRevision: 0,
							interestSha256: interestHash,
							subscriptionId: subscription.subscriptionId,
							subscriptionKind: 'file.metadata',
							workerDerivationEpoch: 0,
						},
					],
					lastAcceptedRequestSequence: 2,
					lastAcceptedStreamSequence: 2,
				});
				await harness.server.waitForMetadataStream(2);
				const replacementStreamRequest = harness.server.requiredMetadataRequest(1);
				expect(replacementStreamRequest).toMatchObject({
					paneSessionId: initialStreamRequest.paneSessionId,
					resumeFromStreamSequence: 2,
					workerInstanceId: initialStreamRequest.workerInstanceId,
				});
				expect(replacementStreamRequest.metadataStreamId).not.toBe(
					initialStreamRequest.metadataStreamId,
				);
				harness.server.emitMetadata(metadataAccepted(replacementStreamRequest, 3, 'resumed'));
				await harness.server.waitForFrameAcknowledgementCount(4);

				harness.server.emitMetadata(
					fileSourceAcceptedData({
						epoch: 0,
						interestHash,
						request: replacementStreamRequest,
						sourceGeneration: 2,
						streamSequence: 4,
						subscriptionId: subscription.subscriptionId,
						subscriptionSequence: 2,
					}),
				);

				await expect(events.next()).resolves.toMatchObject({
					done: false,
					value: {
						data: { eventKind: 'file.sourceAccepted', source: fileSourceIdentity(2) },
						streamSequence: 4,
						subscriptionId: subscription.subscriptionId,
						subscriptionSequence: 2,
						workerDerivationEpoch: 0,
					},
				});
				await harness.server.waitForFrameAcknowledgementCount(5);
				expect(harness.transport.metadataStreamDiagnostics?.()).toMatchObject({
					activeSubscriptionCount: 1,
					failureStage: null,
					lastAcknowledgedStreamSequence: 4,
					lifecycleState: 'reading',
					streamOpenCount: 2,
				});

				const cancel = subscription.cancel();
				await harness.server.waitForControlKind('subscription.cancel');
				harness.server.emitMetadata(
					subscriptionCancelled({
						epoch: 0,
						interestHash,
						kind: 'file.metadata',
						request: replacementStreamRequest,
						sourceGeneration: 2,
						streamSequence: 5,
						subscriptionId: subscription.subscriptionId,
						subscriptionSequence: 3,
					}),
				);
				await cancel;
				await harness.server.waitForFrameAcknowledgementCount(6);
				expect(await events.next()).toEqual({ done: true, value: undefined });
				expect(harness.transport.metadataStreamDiagnostics?.().activeSubscriptionCount).toBe(0);
			} finally {
				harness.server.shutdown();
			}
		},
	);
});

describe('Bridge product transport fresh metadata stream after poison', () => {
	test('a fresh metadata stream after an exhausted recovery does not need native replay of the old subscription ids', async () => {
		const harness = createTransportHarness();
		const interestHash = emptyInterestHash('file.metadata');
		const poisoned = harness.transport.subscribe(bridgeProductFileMetadataApplicationProtocol, {
			interests: [],
			pathScope: [],
			source: fileSourceConfiguration(),
		});
		const poisonedEvents = poisoned.events[Symbol.asyncIterator]();
		// Keep the poisoned iterator's rejection handled, and use it as the barrier that
		// says the transport has finished forgetting its subscription ids.
		const poisonedSettled = poisonedEvents.next().then(
			() => 'delivered',
			() => 'failed',
		);

		try {
			await harness.server.waitForMetadataStream();
			const firstRequest = harness.server.requiredMetadataRequest(0);
			harness.server.emitMetadata(metadataAccepted(firstRequest, 0));
			harness.server.emitMetadata(
				subscriptionAccepted({
					epoch: 0,
					interestHash,
					kind: 'file.metadata',
					request: firstRequest,
					streamSequence: 1,
					subscriptionId: poisoned.subscriptionId,
				}),
			);
			await harness.server.waitForControlKind('subscription.open');
			await harness.server.waitForFrameAcknowledgementCount(2);

			// Spend the single recovery attempt: kill stream #1, let the resync reopen...
			harness.server.failMetadataReader(new Error('deliberate metadata read failure'));
			await harness.server.waitForControlKind('workerSession.resync');
			await harness.server.waitForMetadataStream(2);
			expect(harness.server.requiredMetadataRequest(1).resumeFromStreamSequence).toBe(1);

			// ...then kill the replacement before it makes progress. Recovery is exhausted,
			// so the transport poisons and holds no subscription ids at all.
			harness.server.failMetadataReader(new Error('deliberate replacement read failure'));
			await expect(poisonedSettled).resolves.toBe('failed');

			// The surface still wants its data, so it subscribes again. That opens a FRESH
			// stream under a NEW id, and native must not replay the id the client forgot.
			const replacement = harness.transport.subscribe(
				bridgeProductFileMetadataApplicationProtocol,
				{ interests: [], pathScope: [], source: fileSourceConfiguration() },
			);
			const replacementEvents = replacement.events[Symbol.asyncIterator]();
			await harness.server.waitForMetadataStream(3);
			const freshRequest = harness.server.requiredMetadataRequest(2);
			expect(freshRequest.resumeFromStreamSequence).toBeNull();
			expect(replacement.subscriptionId).not.toBe(poisoned.subscriptionId);

			harness.server.emitMetadata(metadataAccepted(freshRequest, 0));
			harness.server.emitMetadata(
				subscriptionAccepted({
					epoch: 0,
					interestHash,
					kind: 'file.metadata',
					request: freshRequest,
					streamSequence: 1,
					subscriptionId: replacement.subscriptionId,
				}),
			);
			await harness.server.waitForControlKind('subscription.open', 2);
			harness.server.emitMetadata(
				fileSourceAcceptedData({
					epoch: 0,
					interestHash,
					request: freshRequest,
					streamSequence: 2,
					subscriptionId: replacement.subscriptionId,
				}),
			);

			await expect(replacementEvents.next()).resolves.toMatchObject({
				done: false,
				value: {
					data: { eventKind: 'file.sourceAccepted' },
					streamSequence: 2,
					subscriptionId: replacement.subscriptionId,
				},
			});
			expect(harness.transport.metadataStreamDiagnostics?.()).toMatchObject({
				activeSubscriptionCount: 1,
				failureStage: null,
				lifecycleState: 'reading',
			});
		} finally {
			harness.server.shutdown();
		}
	});

	test('a frame naming a subscription the client no longer holds fails the fresh stream closed', async () => {
		const harness = createTransportHarness();
		const interestHash = emptyInterestHash('file.metadata');
		const subscription = harness.transport.subscribe(
			bridgeProductFileMetadataApplicationProtocol,
			{ interests: [], pathScope: [], source: fileSourceConfiguration() },
		);
		const events = subscription.events[Symbol.asyncIterator]();
		const settled = events.next().then(
			() => 'delivered',
			() => 'failed',
		);

		try {
			await harness.server.waitForMetadataStream();
			const request = harness.server.requiredMetadataRequest(0);
			harness.server.emitMetadata(metadataAccepted(request, 0));
			harness.server.emitMetadata(
				subscriptionAccepted({
					epoch: 0,
					interestHash,
					kind: 'file.metadata',
					request,
					streamSequence: 1,
					subscriptionId: subscription.subscriptionId,
				}),
			);
			await harness.server.waitForControlKind('subscription.open');
			await harness.server.waitForFrameAcknowledgementCount(2);

			// This is what the pre-fix native side did on a fresh stream: announce a
			// subscription under an id from before the client poisoned its session.
			harness.server.emitMetadata(
				subscriptionAccepted({
					epoch: 0,
					interestHash,
					kind: 'file.metadata',
					request,
					streamSequence: 2,
					subscriptionId: 'subscription-the-client-never-opened',
				}),
			);

			// The client fails CLOSED: the whole stream dies, taking the live
			// subscription with it. That is the contract the native fix relies on.
			await expect(settled).resolves.toBe('failed');
			expect(harness.transport.metadataStreamDiagnostics?.()).toMatchObject({
				routeFailureCode: 'unknown_subscription',
				routeFailureSubscriptionId: 'subscription-the-client-never-opened',
			});
		} finally {
			harness.server.shutdown();
		}
	});
});

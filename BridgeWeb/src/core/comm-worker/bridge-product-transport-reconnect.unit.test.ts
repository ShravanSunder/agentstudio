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

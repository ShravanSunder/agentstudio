import { afterEach, describe, expect, test, vi } from 'vitest';

import { BridgeCommWorkerProductController } from './bridge-comm-worker-product-controller.js';
import {
	createTransportHarness,
	disposeTransportHarnesses,
	emptyInterestHash,
	fileSourceAcceptedData,
	fileSourceConfiguration,
	metadataAccepted,
	reviewData,
	subscriptionAccepted,
	subscriptionCancelled,
	waitForCondition,
} from './test-fixtures/bridge-product-transport-metadata.test-support.js';

afterEach(async (): Promise<void> => {
	try {
		await disposeTransportHarnesses();
	} finally {
		vi.unstubAllGlobals();
	}
});

describe('Bridge product source retirement through the real transport', () => {
	test.each(['file', 'review'] as const)(
		'drains queued %s metadata until cancellation instead of poisoning the shared stream',
		async (surface): Promise<void> => {
			// Arrange: the real controller consumes one accepted File subscription.
			const harness = createTransportHarness();
			let publishedEventCount = 0;
			const controller = new BridgeCommWorkerProductController({
				callCurrentFileSource: async () => ({
					source: fileSourceConfiguration(),
					status: 'available',
				}),
				onFileMetadataEvent: (): void => {
					publishedEventCount += 1;
				},
				onReviewMetadataEvent: (): void => {
					publishedEventCount += 1;
				},
				productTransport: harness.transport,
			});
			if (surface === 'file') await controller.ensureFileSource();
			else controller.ensureReviewMetadata();
			await harness.server.waitForMetadataStream();
			const streamRequest = harness.server.requiredMetadataRequest();
			harness.server.emitMetadata(metadataAccepted(streamRequest, 0));
			await harness.server.waitForControlKind('subscription.open');
			const opened = harness.server.requiredControlRequest('subscription.open', 0);
			const subscriptionKind = surface === 'file' ? 'file.metadata' : 'review.metadata';
			const makeDataFrame = surface === 'file' ? fileSourceAcceptedData : reviewData;
			const interestHash = emptyInterestHash(subscriptionKind);
			harness.server.emitMetadata(
				subscriptionAccepted({
					epoch: 1,
					interestHash,
					kind: subscriptionKind,
					request: streamRequest,
					streamSequence: 1,
					subscriptionId: opened.subscriptionId,
				}),
			);
			harness.server.emitMetadata(
				makeDataFrame({
					epoch: 1,
					interestHash,
					request: streamRequest,
					streamSequence: 2,
					subscriptionSequence: 1,
					subscriptionId: opened.subscriptionId,
				}),
			);
			await waitForCondition(() => publishedEventCount === 1);
			await harness.server.waitForFrameAcknowledgementCount(3);

			// Act: source reconciliation retires application authority, while native
			// frames already ordered before the cancellation terminal still drain.
			const reconciliation = controller.reconcileAnnotationProjectionSourceAuthority({
				currentSourceGeneration: 2,
				requestedSourceGeneration: 1,
				surface,
			});
			await harness.server.waitForControlKind('subscription.cancel');
			for (const streamSequence of [3, 4]) {
				harness.server.emitMetadata(
					makeDataFrame({
						epoch: 1,
						interestHash,
						request: streamRequest,
						streamSequence,
						subscriptionId: opened.subscriptionId,
						subscriptionSequence: streamSequence - 1,
					}),
				);
			}
			await waitForCondition(() => {
				const diagnostic = harness.transport.metadataStreamDiagnostics?.();
				return (
					harness.server.metadataFetchCount > 1 ||
					diagnostic?.lifecycleState === 'failed' ||
					diagnostic?.lastAcknowledgedStreamSequence === 4
				);
			});

			// Assert: retired facts are not published, but legal in-flight frames
			// cannot terminate the physical stream shared with other consumers.
			try {
				expect(harness.transport.metadataStreamDiagnostics?.()).toMatchObject({
					failureStage: null,
					lastAcknowledgedStreamSequence: 4,
					lifecycleState: 'reading',
					streamOpenCount: 1,
				});
				expect(publishedEventCount).toBe(1);

				// Only the ordered cancellation terminal releases the old subscription.
				harness.server.emitMetadata(
					subscriptionCancelled({
						epoch: 1,
						interestHash,
						kind: subscriptionKind,
						request: streamRequest,
						sourceGeneration: 1,
						streamSequence: 5,
						subscriptionId: opened.subscriptionId,
						subscriptionSequence: 4,
					}),
				);
				await reconciliation;
				await harness.server.waitForControlKind('subscription.open', 2);
				const replacement = harness.server.requiredControlRequest('subscription.open', 1);
				harness.server.emitMetadata(
					subscriptionAccepted({
						epoch: 2,
						interestHash,
						kind: subscriptionKind,
						request: streamRequest,
						streamSequence: 6,
						subscriptionId: replacement.subscriptionId,
					}),
				);
				harness.server.emitMetadata(
					makeDataFrame({
						epoch: 2,
						interestHash,
						request: streamRequest,
						streamSequence: 7,
						subscriptionId: replacement.subscriptionId,
						subscriptionSequence: 1,
					}),
				);
				await waitForCondition(() => publishedEventCount === 2);
				await harness.server.waitForFrameAcknowledgementCount(8);
				expect(harness.transport.metadataStreamDiagnostics?.()).toMatchObject({
					activeSubscriptionCount: 1,
					failureStage: null,
					lastAcknowledgedStreamSequence: 7,
					lifecycleState: 'reading',
					streamOpenCount: 1,
				});
			} finally {
				harness.server.shutdown();
				await reconciliation;
			}
		},
	);
});

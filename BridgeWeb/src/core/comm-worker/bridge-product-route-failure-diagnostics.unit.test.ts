import { afterEach, describe, expect, test, vi } from 'vitest';

import { bridgeProductReviewMetadataApplicationProtocol } from './bridge-product-metadata-application-registry.js';
import { bridgeProductControlRequestSchema } from './bridge-product-session-contracts.js';
import { bridgeProductMetadataFrameSchema } from './bridge-product-session-contracts.js';
import {
	BRIDGE_WORKER_WIRE_VERSION,
	bridgeWorkerHealthEventSchema,
} from './bridge-worker-contracts.js';
import {
	createTransportHarness,
	disposeTransportHarnesses,
	emptyInterestHash,
	metadataAccepted,
	reviewData,
	subscriptionAccepted,
	waitForCondition,
} from './test-fixtures/bridge-product-transport-metadata.test-support.js';

afterEach(async (): Promise<void> => {
	try {
		await disposeTransportHarnesses();
	} finally {
		vi.unstubAllGlobals();
	}
});

describe('Bridge product route failure diagnostics', () => {
	test.each([
		['interest', 'subscription_interest_mismatch'],
		['payload', 'subscription_payload_invalid'],
		['control', 'subscription_control_invalid_request'],
		['http', 'subscription_control_http_rejection'],
	] as const)(
		'retains the %s rejection when a later physical open is rejected',
		async (failure, expectedCode): Promise<void> => {
			// Arrange: transport has an accepted Review subscription with empty interests.
			const harness = createTransportHarness();
			const subscription = harness.transport.subscribe(
				bridgeProductReviewMetadataApplicationProtocol,
				{ interests: [] },
			);
			const terminal = subscription.events[Symbol.asyncIterator]().next();
			void terminal.catch((): void => {});
			await harness.server.waitForMetadataStream();
			const streamRequest = harness.server.requiredMetadataRequest();
			harness.server.emitMetadata(metadataAccepted(streamRequest, 0));
			await harness.server.waitForControlKind('subscription.open');
			const interestHash = emptyInterestHash('review.metadata');
			harness.server.emitMetadata(
				subscriptionAccepted({
					epoch: 0,
					interestHash,
					kind: 'review.metadata',
					request: streamRequest,
					streamSequence: 1,
					subscriptionId: subscription.subscriptionId,
				}),
			);
			await harness.server.waitForFrameAcknowledgementCount(2);
			const data = reviewData({
				epoch: 0,
				interestHash,
				request: streamRequest,
				streamSequence: 2,
				subscriptionId: subscription.subscriptionId,
				subscriptionSequence: 1,
			});

			// Act: a control failure may retire the subscription before its already
			// ordered frames drain; retain that cause ahead of unknown-subscription.
			if (failure === 'control' || failure === 'http') {
				vi.stubGlobal(
					'fetch',
					async (input: RequestInfo | URL, init?: RequestInit): Promise<Response> => {
						if (!(init?.body instanceof ArrayBuffer) && !ArrayBuffer.isView(init?.body))
							throw new Error('Expected encoded request body.');
						const request = bridgeProductControlRequestSchema.parse(
							JSON.parse(new TextDecoder().decode(init.body)),
						);
						if (request.kind !== 'subscription.updateBatch')
							return harness.server.fetch(input, init);
						if (failure === 'http') return new Response(null, { status: 409 });
						return new Response(
							JSON.stringify({
								kind: 'request.error',
								code: 'invalid_request',
								retryable: false,
								nextExpectedRequestSequence: request.requestSequence + 1,
								retryAfterMilliseconds: null,
								safeMessage: null,
								paneSessionId: request.paneSessionId,
								workerInstanceId: request.workerInstanceId,
								wireVersion: request.wireVersion,
								requestId: request.requestId,
								requestSequence: request.requestSequence,
							}),
							{ status: 200 },
						);
					},
				);
				await expect(
					subscription.update({ interests: [{ itemIds: ['item-1'], lane: 'foreground' }] }),
				).rejects.toThrow(failure === 'http' ? /409/iu : /invalid_request/iu);
				vi.stubGlobal('fetch', harness.server.fetch);
			}
			harness.server.emitMetadata(
				bridgeProductMetadataFrameSchema.parse({
					...data,
					...(failure === 'control' || failure === 'http'
						? {}
						: failure === 'interest'
							? { interestSha256: 'f'.repeat(64) }
							: {
									data: {
										subscriptionKind: 'review.metadata',
										event: { eventKind: 'not-a-review-event' },
									},
								}),
				}),
			);
			await expect(terminal).rejects.toThrow();
			vi.stubGlobal('fetch', async (): Promise<Response> => new Response(null, { status: 409 }));
			const retry = harness.transport.subscribe(bridgeProductReviewMetadataApplicationProtocol, {
				interests: [],
			});
			await expect(retry.events[Symbol.asyncIterator]().next()).rejects.toThrow(/409/iu);
			await waitForCondition(
				() => harness.transport.metadataStreamDiagnostics?.().lifecycleState === 'failed',
			);

			// Assert: report both the latest fetch failure and its preceding route cause,
			// using closed classifications rather than logging application payloads.
			expect(harness.transport.metadataStreamDiagnostics?.()).toMatchObject({
				failureStage: 'fetch',
				routeFailureCode: expectedCode,
				lastAcknowledgedStreamSequence: 1,
				streamOpenCount: 1,
			});
			if (failure === 'control' || failure === 'http') {
				expect(harness.transport.metadataStreamDiagnostics?.()).toMatchObject({
					routeFailureSubscriptionId: subscription.subscriptionId,
					lastSubscriptionTermination: {
						subscriptionId: subscription.subscriptionId,
						outcome: 'failed',
						reason: expectedCode,
					},
				});
			}
			expect(
				bridgeWorkerHealthEventSchema.safeParse({
					wireVersion: BRIDGE_WORKER_WIRE_VERSION,
					direction: 'serverWorkerToMain',
					transferDescriptors: [],
					kind: 'health',
					status: 'degraded',
					diagnostic: {
						kind: 'productMetadataStream',
						...harness.transport.metadataStreamDiagnostics?.(),
					},
				}).success,
			).toBe(true);

			// A replacement must deliver subscription data before clearing the cause;
			// an opening frame alone does not prove that routing recovered.
			vi.stubGlobal('fetch', harness.server.fetch);
			const recovered = harness.transport.subscribe(
				bridgeProductReviewMetadataApplicationProtocol,
				{
					interests: [],
				},
			);
			await harness.server.waitForMetadataStream(2);
			harness.server.emitMetadata(metadataAccepted(harness.server.requiredMetadataRequest(1), 0));
			await harness.server.waitForFrameAcknowledgementCount(3);
			expect(harness.transport.metadataStreamDiagnostics?.().routeFailureCode).toBe(expectedCode);
			await harness.server.waitForControlKind('subscription.open', 2);
			const recoveredStream = harness.server.requiredMetadataRequest(1);
			harness.server.emitMetadata(
				subscriptionAccepted({
					epoch: 0,
					interestHash,
					kind: 'review.metadata',
					request: recoveredStream,
					streamSequence: 1,
					subscriptionId: recovered.subscriptionId,
				}),
			);
			harness.server.emitMetadata(
				reviewData({
					epoch: 0,
					interestHash,
					request: recoveredStream,
					streamSequence: 2,
					subscriptionId: recovered.subscriptionId,
					subscriptionSequence: 1,
				}),
			);
			await recovered.events[Symbol.asyncIterator]().next();
			await harness.server.waitForFrameAcknowledgementCount(5);
			expect(harness.transport.metadataStreamDiagnostics?.()).toMatchObject({
				failureStage: null,
				routeFailureCode: null,
				streamOpenCount: 2,
			});
		},
	);
});

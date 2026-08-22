import { describe, expect, test } from 'vitest';

import type { BridgeTelemetrySample } from '../../foundation/telemetry/bridge-telemetry-event.js';
import {
	encodeBridgeWorkerMetadataInterestUpdateCommand,
	encodeBridgeWorkerReviewPublicationInstallAdmitCommand,
	encodeBridgeWorkerReviewPublicationInstalledCommand,
} from './bridge-comm-worker-protocol.js';
import {
	registerBridgeCommWorkerRuntimePortProtocol,
	type BridgeCommWorkerPreparationDrain,
} from './bridge-comm-worker-runtime-protocol.js';
import { reviewSnapshotEvent } from './bridge-comm-worker-runtime-protocol.review-product-fixtures.test-support.js';
import { makeReviewProductTransport } from './bridge-comm-worker-runtime-protocol.review-product-transport.test-support.js';
import {
	activateBridgeCommWorkerReviewViewerMode,
	createBridgeCommWorkerReviewProductTestSource,
	createRecordingBridgeCommWorkerPort,
	flushBridgeWorkerRuntimeContinuations,
} from './bridge-comm-worker-runtime-protocol.test-support.js';
import {
	BridgeProductBoundedAsyncQueue,
	createBridgeProductDeferred,
} from './bridge-product-async-queue.js';
import type { BridgeProductSubscriptionEvent } from './bridge-product-subscription-contracts.js';
import type { BridgeProductSubscription } from './bridge-product-transport-contract.js';
import type { BridgeProductWorktreeAnnotationEvent } from './bridge-product-worktree-annotation-contracts.js';

describe('Bridge comm worker Review product source projection', () => {
	test('re-exposes newest complete Review only after installed predecessor acknowledgment succeeds', async () => {
		// Arrange
		const reviewMetadataEvents = new BridgeProductBoundedAsyncQueue<
			BridgeProductSubscriptionEvent<'review.metadata'>
		>(64);
		const appliedCallStarted = createBridgeProductDeferred<void>();
		const appliedCallCompletion = createBridgeProductDeferred<void>();
		const subscribedKinds: string[] = [];
		const reviewSubscription: BridgeProductSubscription<'review.metadata'> = {
			cancel: async (): Promise<void> => {},
			events: reviewMetadataEvents,
			subscriptionId: 'review-successor-re-exposure',
			subscriptionKind: 'review.metadata',
			update: async (): Promise<void> => {},
		};
		const { dispatch, postedMessages } = createRecordingBridgeCommWorkerPort();
		registerBridgeCommWorkerRuntimePortProtocol(dispatch.port, {
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			budget: { className: 'interactive', maxBytes: 512 * 1024, maxWindowLines: 400 },
			productTransport: makeReviewProductTransport({
				onCall: async (method): Promise<unknown> => {
					if (method !== 'review.publication.applied') {
						return { reason: 'notConfigured', status: 'unavailable' };
					}
					appliedCallStarted.resolve();
					await appliedCallCompletion.promise;
					return null;
				},
				reviewSubscription,
				subscribedKinds,
			}),
		});
		activateBridgeCommWorkerReviewViewerMode(dispatch, 'successor-re-exposure');
		reviewMetadataEvents.push(reviewSnapshotEvent);
		reviewMetadataEvents.push(successorReviewSnapshotEvent());
		await flushBridgeWorkerRuntimeContinuations();
		const initialDisplayCount = messageCount(postedMessages, 'reviewDisplayPatch');
		const initialReadyCount = messageCount(postedMessages, 'reviewCandidateReady');

		// Act
		dispatch.message(
			encodeBridgeWorkerReviewPublicationInstalledCommand({
				epoch: 1,
				packageId: reviewSnapshotEvent.packageId,
				publicationId: reviewSnapshotEvent.publicationId,
				requestId: 'review-predecessor-installed',
				reviewGeneration: reviewSnapshotEvent.generation,
				revision: reviewSnapshotEvent.revision,
				sourceIdentity: reviewSnapshotEvent.sourceIdentity,
			}),
		);
		await appliedCallStarted.promise;
		await flushBridgeWorkerRuntimeContinuations();

		// Assert: worker-current C is not re-exposed before native accepts applied B.
		expect(messageCount(postedMessages, 'reviewDisplayPatch')).toBe(initialDisplayCount);
		expect(messageCount(postedMessages, 'reviewCandidateReady')).toBe(initialReadyCount);

		// Act
		appliedCallCompletion.resolve();
		await flushBridgeWorkerRuntimeContinuations();

		// Assert: full C display and ready precede the installed command's ready completion.
		expect(messageCount(postedMessages, 'reviewDisplayPatch')).toBe(initialDisplayCount + 1);
		expect(messageCount(postedMessages, 'reviewCandidateReady')).toBe(initialReadyCount + 1);
		const messageKinds = postedMessages.map(({ message }) => ({
			kind: message.kind,
			requestId: 'requestId' in message ? message.requestId : null,
		}));
		const reExposedDisplayIndex = messageKinds.findLastIndex(
			({ kind }): boolean => kind === 'reviewDisplayPatch',
		);
		const reExposedReadyIndex = messageKinds.findLastIndex(
			({ kind }): boolean => kind === 'reviewCandidateReady',
		);
		const installedReadyIndex = messageKinds.findIndex(
			({ requestId }): boolean => requestId === 'review-predecessor-installed',
		);
		expect(reExposedDisplayIndex).toBeLessThan(reExposedReadyIndex);
		expect(reExposedReadyIndex).toBeLessThan(installedReadyIndex);
	});

	test('retries failed successor admission once after its failure terminal reaches main', async () => {
		// Arrange
		const reviewMetadataEvents = new BridgeProductBoundedAsyncQueue<
			BridgeProductSubscriptionEvent<'review.metadata'>
		>(64);
		const reviewSubscription: BridgeProductSubscription<'review.metadata'> = {
			cancel: async (): Promise<void> => {},
			events: reviewMetadataEvents,
			subscriptionId: 'review-successor-admission-failure',
			subscriptionKind: 'review.metadata',
			update: async (): Promise<void> => {},
		};
		const { dispatch, postedMessages } = createRecordingBridgeCommWorkerPort();
		registerBridgeCommWorkerRuntimePortProtocol(dispatch.port, {
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			budget: { className: 'interactive', maxBytes: 512 * 1024, maxWindowLines: 400 },
			productTransport: makeReviewProductTransport({
				onCall: (method): null => {
					if (method === 'review.publication.install.admit') {
						throw new Error('injected admission transport failure');
					}
					return null;
				},
				reviewSubscription,
				subscribedKinds: [],
			}),
		});
		activateBridgeCommWorkerReviewViewerMode(dispatch, 'successor-admission-failure');
		reviewMetadataEvents.push(reviewSnapshotEvent);
		reviewMetadataEvents.push(successorReviewSnapshotEvent());
		await flushBridgeWorkerRuntimeContinuations();
		dispatch.message(installedPredecessorCommand('review-predecessor-applied-before-failure'));
		await flushBridgeWorkerRuntimeContinuations();
		const displayCountBeforeFailure = messageCount(postedMessages, 'reviewDisplayPatch');

		// Act
		const failedAdmission = successorAdmissionCommand('review-successor-admission-failed');
		dispatch.message(failedAdmission);
		await flushBridgeWorkerRuntimeContinuations();

		// Assert: main's failure terminal is posted before the one bounded retry exposure.
		expect(messageCount(postedMessages, 'reviewDisplayPatch')).toBe(displayCountBeforeFailure + 1);
		const messageKinds = postedMessages.map(({ message }) => ({
			kind: message.kind,
			requestId: 'requestId' in message ? message.requestId : null,
		}));
		const failureIndex = messageKinds.findIndex(
			({ requestId }): boolean => requestId === failedAdmission.requestId,
		);
		const retryDisplayIndex = messageKinds.findLastIndex(
			({ kind }): boolean => kind === 'reviewDisplayPatch',
		);
		expect(failureIndex).toBeLessThan(retryDisplayIndex);

		// Act: a repeated transport failure cannot create an unbounded retry loop.
		dispatch.message(successorAdmissionCommand('review-successor-admission-failed-again'));
		await flushBridgeWorkerRuntimeContinuations();

		// Assert
		expect(messageCount(postedMessages, 'reviewDisplayPatch')).toBe(displayCountBeforeFailure + 1);
	});

	test('activates Review annotation projection from accepted metadata without a fabricated active source', async () => {
		// Arrange
		const calledMethods: string[] = [];
		const reviewAnnotationEvents =
			new BridgeProductBoundedAsyncQueue<BridgeProductWorktreeAnnotationEvent>(8);
		const reviewMetadataEvents = new BridgeProductBoundedAsyncQueue<
			BridgeProductSubscriptionEvent<'review.metadata'>
		>(64);
		const reviewProjectionSourceGenerations: number[] = [];
		const reviewProjectionQueryStarted = createBridgeProductDeferred<void>();
		const subscribedKinds: string[] = [];
		const reviewAnnotationSubscription: BridgeProductSubscription<'review.annotations'> = {
			cancel: async (): Promise<void> => {},
			events: reviewAnnotationEvents,
			subscriptionId: 'review-annotations-no-fabricated-source',
			subscriptionKind: 'review.annotations',
			update: async (): Promise<void> => {},
		};
		const reviewMetadataSubscription: BridgeProductSubscription<'review.metadata'> = {
			cancel: async (): Promise<void> => {},
			events: reviewMetadataEvents,
			subscriptionId: 'review-metadata-no-fabricated-source',
			subscriptionKind: 'review.metadata',
			update: async (): Promise<void> => {},
		};
		const { dispatch } = createRecordingBridgeCommWorkerPort();
		registerBridgeCommWorkerRuntimePortProtocol(dispatch.port, {
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			budget: { className: 'interactive', maxBytes: 512 * 1024, maxWindowLines: 400 },
			productTransport: makeReviewProductTransport({
				calledMethods,
				onCalledMethod: (method, request): void => {
					if (method === 'review.annotations.projection.query') {
						if (
							typeof request !== 'object' ||
							request === null ||
							!('sourceGeneration' in request) ||
							typeof request.sourceGeneration !== 'number'
						) {
							throw new Error('Review annotation query requires an exact source generation.');
						}
						reviewProjectionSourceGenerations.push(request.sourceGeneration);
						reviewProjectionQueryStarted.resolve();
					}
				},
				reviewAnnotationSubscription,
				reviewSubscription: reviewMetadataSubscription,
				subscribedKinds,
			}),
		});

		// Act
		activateBridgeCommWorkerReviewViewerMode(dispatch, 'annotation-metadata-source');
		reviewAnnotationEvents.push({
			eventKind: 'snapshot.required',
			operationCorrelationId: 'a'.repeat(64),
			sourceGeneration: 0,
			worktreeId: 'worktree-1',
		});
		reviewMetadataEvents.push(reviewSnapshotEvent);
		await flushBridgeWorkerRuntimeContinuations();
		expect(reviewProjectionSourceGenerations).toEqual([]);
		dispatch.message(
			encodeBridgeWorkerReviewPublicationInstalledCommand({
				epoch: 1,
				packageId: reviewSnapshotEvent.packageId,
				publicationId: reviewSnapshotEvent.publicationId,
				requestId: 'review-publication-installed',
				reviewGeneration: reviewSnapshotEvent.generation,
				revision: reviewSnapshotEvent.revision,
				sourceIdentity: reviewSnapshotEvent.sourceIdentity,
			}),
		);
		await reviewProjectionQueryStarted.promise;

		// Assert
		expect(calledMethods).toContain('review.annotations.projection.query');
		expect(reviewProjectionSourceGenerations).toEqual([reviewSnapshotEvent.generation]);
	});

	test('projects typed Review subscription snapshots into worker-owned source truth', async () => {
		const operationCorrelationId = 'b'.repeat(64);
		const telemetrySamples: BridgeTelemetrySample[] = [];
		const events = new BridgeProductBoundedAsyncQueue<
			BridgeProductSubscriptionEvent<'review.metadata'>
		>(64);
		const scheduledDrains: BridgeCommWorkerPreparationDrain[] = [];
		const subscribedKinds: string[] = [];
		const reviewSubscription: BridgeProductSubscription<'review.metadata'> = {
			cancel: async (): Promise<void> => {},
			events,
			subscriptionId: 'review-subscription-1',
			subscriptionKind: 'review.metadata',
			update: async (): Promise<void> => {},
		};
		const { dispatch, postedMessages } = createRecordingBridgeCommWorkerPort();
		registerBridgeCommWorkerRuntimePortProtocol(dispatch.port, {
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			budget: { className: 'interactive', maxBytes: 512 * 1024, maxWindowLines: 400 },
			productTransport: makeReviewProductTransport({ reviewSubscription, subscribedKinds }),
			schedulePreparationDrain: (drain): void => {
				scheduledDrains.push(drain);
			},
			telemetryClient: {
				record: (sample): void => {
					telemetrySamples.push(sample);
				},
			},
		});
		activateBridgeCommWorkerReviewViewerMode(dispatch, 'source-truth');

		dispatch.message(
			encodeBridgeWorkerMetadataInterestUpdateCommand({
				epoch: 1,
				request: {
					generation: 7,
					itemIds: ['item-1'],
					lane: 'foreground',
					loaded_by: 'foreground',
					protocol: 'review',
					streamId: 'review-stream-1',
				},
				requestId: 'request-review-interest-1',
			}),
		);
		await flushBridgeWorkerRuntimeContinuations();
		expect(subscribedKinds).toEqual(['file.annotations', 'review.annotations', 'review.metadata']);
		events.push({ ...reviewSnapshotEvent, operationCorrelationId });
		await flushBridgeWorkerRuntimeContinuations();

		expect(scheduledDrains).toHaveLength(1);
		const reviewDisplayEvents = postedMessages
			.map(({ message }) => message as unknown as Readonly<Record<string, unknown>>)
			.filter((message) => message['kind'] === 'reviewDisplayPatch');
		expect(reviewDisplayEvents).toHaveLength(1);
		expect(reviewDisplayEvents[0]).toMatchObject({
			epoch: 1,
			kind: 'reviewDisplayPatch',
			reviewPublicationIdentity: {
				packageId: 'package-1',
				publicationId: '00000000-0000-7000-8000-000000000011',
				reviewGeneration: 7,
				revision: 11,
				sourceIdentity: 'source-1',
			},
			patches: [
				{
					operation: 'upsert',
					payload: {
						metadataWindowIdentity: JSON.stringify([
							'bridge-review-metadata-window-v1',
							'source-1',
							7,
							'00000000-0000-7000-8000-000000000011',
							11,
						]),
						status: 'ready',
						totalItemCount: 1,
						totalTreeRowCount: 1,
					},
					slice: 'reviewSource',
				},
				expect.objectContaining({ operation: 'replace', slice: 'reviewComparison' }),
				expect.objectContaining({ operation: 'batch', slice: 'reviewItem' }),
				expect.objectContaining({ operation: 'batch', slice: 'reviewTree' }),
			],
			projectionRevision: 1,
			surface: 'review',
		});
		const postedKinds = postedMessages.map(({ message }) => message.kind);
		expect(postedKinds.indexOf('reviewDisplayPatch')).toBeLessThan(
			postedKinds.indexOf('reviewCandidateReady'),
		);
		expect(
			postedMessages.find(({ message }) => message.kind === 'reviewCandidateReady')?.message,
		).toMatchObject({
			affectedStableFileIdentities: ['item-1'],
			kind: 'reviewCandidateReady',
			preDeliveryPresentationClass: { kind: 'ordinary' },
			publicationId: '00000000-0000-7000-8000-000000000011',
		});
		expect(JSON.stringify(reviewDisplayEvents)).not.toMatch(
			/"(?:capability|resourceUrl|contents|contentBody|sourceBytes)"/i,
		);
		const reviewLifecycleSamples = telemetrySamples.filter(
			(sample) =>
				sample.name === 'performance.bridge.web.operation_lifecycle' &&
				sample.stringAttributes['agentstudio.bridge.operation.id'] === operationCorrelationId,
		);
		expect(
			reviewLifecycleSamples.map((sample) => sample.stringAttributes['agentstudio.bridge.phase']),
		).toEqual([
			'worker_application_started',
			'panel_chrome_publish_started',
			'panel_chrome_publish_terminal',
			'worker_application_terminal',
		]);
	});

	test('publishes a ready empty Review source when the snapshot has no changed files', async () => {
		const scheduledDrains: BridgeCommWorkerPreparationDrain[] = [];
		const reviewProductSource = createBridgeCommWorkerReviewProductTestSource();
		const { dispatch, postedMessages } = createRecordingBridgeCommWorkerPort();
		registerBridgeCommWorkerRuntimePortProtocol(dispatch.port, {
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			budget: { className: 'interactive', maxBytes: 512 * 1024, maxWindowLines: 400 },
			productTransport: reviewProductSource.productTransport,
			schedulePreparationDrain: (drain): void => {
				scheduledDrains.push(drain);
			},
		});
		activateBridgeCommWorkerReviewViewerMode(dispatch, 'empty-source');

		dispatch.message(
			encodeBridgeWorkerMetadataInterestUpdateCommand({
				epoch: 1,
				request: {
					generation: 1,
					itemIds: [],
					lane: 'foreground',
					loaded_by: 'foreground',
					protocol: 'review',
					streamId: 'review-stream-empty-source',
				},
				requestId: 'request-review-interest-empty-source',
			}),
		);
		await flushBridgeWorkerRuntimeContinuations();
		reviewProductSource.publishSource(
			{
				contentItems: [],
				contentRequestDescriptors: [],
				renderSemantics: [],
				rows: [],
			},
			7,
		);
		await flushBridgeWorkerRuntimeContinuations();

		const reviewDisplayEvents = postedMessages
			.map(({ message }) => message as unknown as Readonly<Record<string, unknown>>)
			.filter((message) => message['kind'] === 'reviewDisplayPatch');
		expect(scheduledDrains).toHaveLength(1);
		expect(reviewDisplayEvents).toHaveLength(1);
		expect(reviewDisplayEvents[0]).toMatchObject({
			kind: 'reviewDisplayPatch',
			reviewPublicationIdentity: {
				packageId: 'review-product-test-package',
				publicationId: '00000000-0000-7000-8000-000000000007',
				reviewGeneration: 1,
				revision: 7,
				sourceIdentity: 'review-product-test-source',
			},
			patches: [
				{
					operation: 'upsert',
					payload: {
						status: 'ready',
						totalItemCount: 0,
						totalTreeRowCount: 0,
					},
					slice: 'reviewSource',
				},
				{ operation: 'replace', payload: null, slice: 'reviewComparison' },
				{
					operation: 'batch',
					payload: { items: [], operations: [], reset: true },
					slice: 'reviewItem',
				},
				{
					operation: 'batch',
					payload: { reset: true, windows: [{ rows: [] }] },
					slice: 'reviewTree',
				},
			],
			epoch: 1,
			surface: 'review',
		});
		reviewProductSource.close();
	});
});

function successorReviewSnapshotEvent(): BridgeProductSubscriptionEvent<'review.metadata'> {
	return {
		...reviewSnapshotEvent,
		generation: reviewSnapshotEvent.generation + 1,
		packageId: 'package-2',
		presentationRevision: reviewSnapshotEvent.presentationRevision + 1,
		publicationId: '00000000-0000-7000-8000-000000000012',
		revision: reviewSnapshotEvent.revision + 1,
		sourceIdentity: 'source-2',
	};
}

function installedPredecessorCommand(
	requestId: string,
): ReturnType<typeof encodeBridgeWorkerReviewPublicationInstalledCommand> {
	return encodeBridgeWorkerReviewPublicationInstalledCommand({
		epoch: 1,
		packageId: reviewSnapshotEvent.packageId,
		publicationId: reviewSnapshotEvent.publicationId,
		requestId,
		reviewGeneration: reviewSnapshotEvent.generation,
		revision: reviewSnapshotEvent.revision,
		sourceIdentity: reviewSnapshotEvent.sourceIdentity,
	});
}

function successorAdmissionCommand(
	requestId: string,
): ReturnType<typeof encodeBridgeWorkerReviewPublicationInstallAdmitCommand> {
	return encodeBridgeWorkerReviewPublicationInstallAdmitCommand({
		candidatePublicationId: successorReviewSnapshotEvent().publicationId,
		epoch: 1,
		expectedDisplayedPublicationId: reviewSnapshotEvent.publicationId,
		requestId,
	});
}

function messageCount(
	postedMessages: ReturnType<typeof createRecordingBridgeCommWorkerPort>['postedMessages'],
	kind: string,
): number {
	return postedMessages.filter(({ message }): boolean => message.kind === kind).length;
}

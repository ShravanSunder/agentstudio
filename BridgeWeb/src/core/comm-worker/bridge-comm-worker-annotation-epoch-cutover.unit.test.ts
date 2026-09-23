import { afterEach, describe, expect, test, vi } from 'vitest';

import { BridgeCommWorkerProductController } from './bridge-comm-worker-product-controller.js';
import { bridgeProductMetadataFrameSchema } from './bridge-product-session-contracts.js';
import type {
	BridgeProductControlRequest,
	BridgeProductMetadataFrame,
	BridgeProductMetadataStreamRequest,
} from './bridge-product-session-contracts.js';
import type { BridgeProductSubscriptionKind } from './bridge-product-subscription-contracts.js';
import { bridgeProductSubscriptionKindSchema } from './bridge-product-subscription-contracts.js';
import {
	createTransportHarness,
	disposeTransportHarnesses,
	emptyInterestHash,
	fileSourceConfiguration,
	metadataAccepted,
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

describe('Bridge annotation subscription worker-epoch cutover', () => {
	test('opens replacement File metadata without waiting for the annotation sibling, then moves annotations to the new epoch', async () => {
		// Arrange
		const harness = createTransportHarness();
		const publishedCatalogRevisions: number[] = [];
		const fileConvergenceStates: string[] = [];
		const controller = new BridgeCommWorkerProductController({
			callCurrentFileSource: async () => ({
				source: fileSourceConfiguration(),
				status: 'available',
			}),
			onAnnotationCatalog: ({ catalog, surface }): void => {
				if (surface === 'file') publishedCatalogRevisions.push(catalog.catalogRevision);
			},
			onAnnotationProjectionConvergence: ({ state, surface }): void => {
				if (surface !== 'file') return;
				fileConvergenceStates.push(
					state.kind === 'ready' ? 'ready' : `${state.kind}:${state.catalogAuthorityRetired}`,
				);
			},
			onFileMetadataEvent: (): void => {},
			onReviewMetadataEvent: (): void => {},
			productTransport: harness.transport,
		});
		const initialFileSource = controller.ensureFileSource();
		controller.ensureReviewMetadata();
		await harness.server.waitForMetadataStream();
		const streamRequest = harness.server.requiredMetadataRequest();
		harness.server.emitMetadata(metadataAccepted(streamRequest, 0));
		await harness.server.waitForControlKind('subscription.open', 2);
		const initialMetadataOpens = subscriptionOpenRequests(harness.server.controlRequests);
		for (const [index, request] of initialMetadataOpens.entries()) {
			const subscriptionKind = bridgeProductSubscriptionKindSchema.parse(
				request.subscription.subscriptionKind,
			);
			if (subscriptionKind !== 'file.metadata' && subscriptionKind !== 'review.metadata') {
				throw new Error('Expected both metadata sources to establish epoch-one authority first.');
			}
			harness.server.emitMetadata(
				subscriptionAccepted({
					epoch: 1,
					interestHash: emptyInterestHash(subscriptionKind),
					kind: subscriptionKind,
					request: streamRequest,
					streamSequence: index + 1,
					subscriptionId: request.subscriptionId,
				}),
			);
		}
		await initialFileSource;

		controller.ensureAnnotationSubscriptions();
		await harness.server.waitForControlKind('subscription.open', 4);

		const initialOpenByKind = new Map<BridgeProductSubscriptionKind, SubscriptionOpenRequest>();
		for (const [index, request] of subscriptionOpenRequests(
			harness.server.controlRequests,
		).entries()) {
			const subscriptionKind = bridgeProductSubscriptionKindSchema.parse(
				request.subscription.subscriptionKind,
			);
			initialOpenByKind.set(subscriptionKind, request);
			if (initialMetadataOpens.includes(request)) continue;
			harness.server.emitMetadata(
				subscriptionAccepted({
					epoch: 1,
					interestHash: emptyInterestHash(subscriptionKind),
					kind: subscriptionKind,
					request: streamRequest,
					streamSequence: index + 1,
					subscriptionId: request.subscriptionId,
				}),
			);
		}
		await harness.server.waitForFrameAcknowledgementCount(5);

		const initialFileAnnotation = requiredSubscriptionOpen(initialOpenByKind, 'file.annotations');
		const initialFileMetadata = requiredSubscriptionOpen(initialOpenByKind, 'file.metadata');
		const initialReviewAnnotation = requiredSubscriptionOpen(
			initialOpenByKind,
			'review.annotations',
		);
		const initialReviewMetadata = requiredSubscriptionOpen(initialOpenByKind, 'review.metadata');

		// Act
		const reconciliation = controller.reconcileAnnotationProjectionSourceAuthority({
			currentSourceGeneration: 2,
			requestedSourceGeneration: 1,
			surface: 'file',
		});

		let nextStreamSequence = 5;
		const drainedCancellationIds = new Set<string>();
		await drainSurfaceCancellationsUntilReplacementMetadataOpen({
			drainedCancellationIds,
			harness,
			initialFileAnnotation,
			initialFileMetadata,
			nextStreamSequence: (): number => nextStreamSequence,
			streamRequest,
			useNextStreamSequence: (): number => {
				nextStreamSequence += 1;
				return nextStreamSequence;
			},
		});

		const controlRequests = harness.server.controlRequests;
		const replacementFileMetadata = requiredReplacementOpen(
			controlRequests,
			'file.metadata',
			initialFileMetadata.subscriptionId,
		);

		// Assert: File content opened at the new epoch while the annotation sibling's
		// retirement was still undrained, so comments never delay the file itself.
		expect(drainedCancellationIds).not.toContain(initialFileAnnotation.subscriptionId);
		expect(replacementFileMetadata.workerDerivationEpoch).toBe(2);

		await waitForCondition(() =>
			hasReplacementOpen(
				harness.server.controlRequests,
				'file.annotations',
				initialFileAnnotation.subscriptionId,
			),
		);
		const replacementFileAnnotation = requiredReplacementOpen(
			harness.server.controlRequests,
			'file.annotations',
			initialFileAnnotation.subscriptionId,
		);
		expect(replacementFileAnnotation.workerDerivationEpoch).toBe(2);
		expect(
			requiredCancellation(controlRequests, initialFileAnnotation.subscriptionId).subscriptionKind,
		).toBe('file.annotations');
		// A routine refresh keeps comments visible as refreshing; it is never unavailable.
		expect(fileConvergenceStates).toContain('refreshing:true');
		expect(fileConvergenceStates.filter((state) => state.startsWith('unavailable'))).toEqual([]);

		for (const replacement of [replacementFileMetadata, replacementFileAnnotation]) {
			const subscriptionKind = bridgeProductSubscriptionKindSchema.parse(
				replacement.subscription.subscriptionKind,
			);
			harness.server.emitMetadata(
				subscriptionAccepted({
					epoch: 2,
					interestHash: emptyInterestHash(subscriptionKind),
					kind: subscriptionKind,
					request: streamRequest,
					streamSequence: nextStreamSequence,
					subscriptionId: replacement.subscriptionId,
				}),
			);
			nextStreamSequence += 1;
		}

		for (const frame of annotationCatalogFrames({
			epoch: 2,
			request: streamRequest,
			startStreamSequence: nextStreamSequence,
			subscriptionId: replacementFileAnnotation.subscriptionId,
		})) {
			harness.server.emitMetadata(frame);
			nextStreamSequence += 1;
		}
		await waitForCondition(() => publishedCatalogRevisions.includes(2));
		await reconciliation;

		expect(
			controlRequests.filter(
				(request) =>
					request.kind === 'subscription.cancel' &&
					(request.subscriptionId === initialReviewAnnotation.subscriptionId ||
						request.subscriptionId === initialReviewMetadata.subscriptionId),
			),
		).toEqual([]);
		expect(
			subscriptionOpenRequests(controlRequests).filter(
				(request) =>
					request.subscription.subscriptionKind === 'review.annotations' ||
					request.subscription.subscriptionKind === 'review.metadata',
			),
		).toEqual([initialReviewMetadata, initialReviewAnnotation]);
		expect(harness.transport.workerDerivationEpoch('review')).toBe(1);
	});

	test('advances the surface epoch when native resets the annotation sibling during its cutover cancellation', async () => {
		// Arrange: the File cutover retires metadata, then native resets the
		// annotation sibling (for example, its source is unavailable) while the
		// sibling's cancellation is pending.
		const scenario = await establishEpochOneSubscriptions();
		const initialFileAnnotation = requiredSubscriptionOpen(
			scenario.initialOpenByKind,
			'file.annotations',
		);
		const initialFileMetadata = requiredSubscriptionOpen(
			scenario.initialOpenByKind,
			'file.metadata',
		);
		const reconciliation = scenario.controller.reconcileAnnotationProjectionSourceAuthority({
			currentSourceGeneration: 2,
			requestedSourceGeneration: 1,
			surface: 'file',
		});
		await scenario.harness.server.waitForControlKind('subscription.cancel');
		const metadataCancellation = requiredCancellation(
			scenario.harness.server.controlRequests,
			initialFileMetadata.subscriptionId,
		);
		scenario.harness.server.emitMetadata(
			subscriptionCancelled({
				epoch: 1,
				interestHash: emptyInterestHash('file.metadata'),
				kind: 'file.metadata',
				request: scenario.streamRequest,
				sourceGeneration: 1,
				streamSequence: 5,
				subscriptionId: metadataCancellation.subscriptionId,
				subscriptionSequence: 1,
			}),
		);
		await scenario.harness.server.waitForFrameAcknowledgementCount(6);
		await scenario.harness.server.waitForControlKind('subscription.cancel', 2);
		const annotationCancellation = requiredCancellation(
			scenario.harness.server.controlRequests,
			initialFileAnnotation.subscriptionId,
		);

		// Act
		scenario.harness.server.emitMetadata(
			subscriptionResetFrame({
				epoch: 1,
				kind: 'file.annotations',
				request: scenario.streamRequest,
				streamSequence: 6,
				subscriptionId: annotationCancellation.subscriptionId,
			}),
		);
		await scenario.harness.server.waitForFrameAcknowledgementCount(7);
		await reconciliation;

		await waitForCondition(() =>
			hasReplacementOpen(
				scenario.harness.server.controlRequests,
				'file.annotations',
				initialFileAnnotation.subscriptionId,
			),
		);

		// Assert: the reset retired the sibling as completely as a cancellation, so
		// both File successors open at the advanced epoch without a second cancel.
		expect(scenario.harness.transport.workerDerivationEpoch('file')).toBe(2);
		expect(
			requiredReplacementOpen(
				scenario.harness.server.controlRequests,
				'file.metadata',
				initialFileMetadata.subscriptionId,
			).workerDerivationEpoch,
		).toBe(2);
		expect(
			requiredReplacementOpen(
				scenario.harness.server.controlRequests,
				'file.annotations',
				initialFileAnnotation.subscriptionId,
			).workerDerivationEpoch,
		).toBe(2);
		expect(
			cancellationRequests(scenario.harness.server.controlRequests).map(
				(request) => request.subscriptionId,
			),
		).toEqual([initialFileMetadata.subscriptionId, initialFileAnnotation.subscriptionId]);
	});

	test('a repeated annotation request during an epoch replacement opens no duplicate subscription', async () => {
		// Arrange: File advances to epoch 2 and its annotation replacement opens while
		// the retired epoch-1 sibling's cancellation is still pending.
		const scenario = await establishEpochOneSubscriptions();
		const initialFileAnnotation = requiredSubscriptionOpen(
			scenario.initialOpenByKind,
			'file.annotations',
		);
		const initialFileMetadata = requiredSubscriptionOpen(
			scenario.initialOpenByKind,
			'file.metadata',
		);
		const reconciliation = scenario.controller.reconcileAnnotationProjectionSourceAuthority({
			currentSourceGeneration: 2,
			requestedSourceGeneration: 1,
			surface: 'file',
		});
		await scenario.harness.server.waitForControlKind('subscription.cancel');
		scenario.harness.server.emitMetadata(
			subscriptionCancelled({
				epoch: 1,
				interestHash: emptyInterestHash('file.metadata'),
				kind: 'file.metadata',
				request: scenario.streamRequest,
				sourceGeneration: 1,
				streamSequence: 5,
				subscriptionId: requiredCancellation(
					scenario.harness.server.controlRequests,
					initialFileMetadata.subscriptionId,
				).subscriptionId,
				subscriptionSequence: 1,
			}),
		);
		await scenario.harness.server.waitForFrameAcknowledgementCount(6);
		await reconciliation;
		await waitForCondition(() =>
			hasReplacementOpen(
				scenario.harness.server.controlRequests,
				'file.annotations',
				initialFileAnnotation.subscriptionId,
			),
		);

		// Act: the runtime requests annotations again, then the retired sibling drains.
		scenario.controller.ensureAnnotationSubscriptions();
		scenario.harness.server.emitMetadata(
			subscriptionCancelled({
				epoch: 1,
				interestHash: emptyInterestHash('file.annotations'),
				kind: 'file.annotations',
				request: scenario.streamRequest,
				sourceGeneration: 1,
				streamSequence: 6,
				subscriptionId: requiredCancellation(
					scenario.harness.server.controlRequests,
					initialFileAnnotation.subscriptionId,
				).subscriptionId,
				subscriptionSequence: 1,
			}),
		);
		await scenario.harness.server.waitForFrameAcknowledgementCount(7);

		// Assert: one epoch-2 replacement, however the request and retirement interleave.
		expect(
			subscriptionOpenRequests(scenario.harness.server.controlRequests)
				.filter((request) => request.subscription.subscriptionKind === 'file.annotations')
				.map((request) => request.workerDerivationEpoch),
		).toEqual([1, 2]);
	});
});

type SubscriptionOpenRequest = Extract<BridgeProductControlRequest, { kind: 'subscription.open' }>;
type SubscriptionCancelRequest = Extract<
	BridgeProductControlRequest,
	{ kind: 'subscription.cancel' }
>;

interface EpochOneSubscriptionScenario {
	readonly controller: BridgeCommWorkerProductController;
	readonly harness: ReturnType<typeof createTransportHarness>;
	readonly initialOpenByKind: ReadonlyMap<BridgeProductSubscriptionKind, SubscriptionOpenRequest>;
	readonly streamRequest: BridgeProductMetadataStreamRequest;
}

async function establishEpochOneSubscriptions(): Promise<EpochOneSubscriptionScenario> {
	const harness = createTransportHarness();
	const controller = new BridgeCommWorkerProductController({
		callCurrentFileSource: async () => ({
			source: fileSourceConfiguration(),
			status: 'available',
		}),
		onFileMetadataEvent: (): void => {},
		onReviewMetadataEvent: (): void => {},
		productTransport: harness.transport,
	});
	const initialFileSource = controller.ensureFileSource();
	controller.ensureReviewMetadata();
	await harness.server.waitForMetadataStream();
	const streamRequest = harness.server.requiredMetadataRequest();
	harness.server.emitMetadata(metadataAccepted(streamRequest, 0));
	await harness.server.waitForControlKind('subscription.open', 2);
	let nextStreamSequence = 1;
	for (const request of subscriptionOpenRequests(harness.server.controlRequests)) {
		const subscriptionKind = bridgeProductSubscriptionKindSchema.parse(
			request.subscription.subscriptionKind,
		);
		harness.server.emitMetadata(
			subscriptionAccepted({
				epoch: 1,
				interestHash: emptyInterestHash(subscriptionKind),
				kind: subscriptionKind,
				request: streamRequest,
				streamSequence: nextStreamSequence,
				subscriptionId: request.subscriptionId,
			}),
		);
		nextStreamSequence += 1;
	}
	await initialFileSource;
	controller.ensureAnnotationSubscriptions();
	await harness.server.waitForControlKind('subscription.open', 4);
	const initialOpenByKind = new Map<BridgeProductSubscriptionKind, SubscriptionOpenRequest>();
	for (const request of subscriptionOpenRequests(harness.server.controlRequests)) {
		const subscriptionKind = bridgeProductSubscriptionKindSchema.parse(
			request.subscription.subscriptionKind,
		);
		initialOpenByKind.set(subscriptionKind, request);
		if (subscriptionKind === 'file.metadata' || subscriptionKind === 'review.metadata') continue;
		harness.server.emitMetadata(
			subscriptionAccepted({
				epoch: 1,
				interestHash: emptyInterestHash(subscriptionKind),
				kind: subscriptionKind,
				request: streamRequest,
				streamSequence: nextStreamSequence,
				subscriptionId: request.subscriptionId,
			}),
		);
		nextStreamSequence += 1;
	}
	await harness.server.waitForFrameAcknowledgementCount(5);
	return { controller, harness, initialOpenByKind, streamRequest };
}

function subscriptionOpenRequests(
	requests: readonly BridgeProductControlRequest[],
): readonly SubscriptionOpenRequest[] {
	return requests.filter(
		(request): request is SubscriptionOpenRequest => request.kind === 'subscription.open',
	);
}

function requiredSubscriptionOpen(
	requestsByKind: ReadonlyMap<BridgeProductSubscriptionKind, SubscriptionOpenRequest>,
	kind: BridgeProductSubscriptionKind,
): SubscriptionOpenRequest {
	const request = requestsByKind.get(kind);
	if (request === undefined) throw new Error(`Missing initial ${kind} subscription.`);
	return request;
}

function hasReplacementOpen(
	requests: readonly BridgeProductControlRequest[],
	kind: BridgeProductSubscriptionKind,
	initialSubscriptionId: string,
): boolean {
	return subscriptionOpenRequests(requests).some(
		(request) =>
			request.subscription.subscriptionKind === kind &&
			request.subscriptionId !== initialSubscriptionId,
	);
}

function requiredReplacementOpen(
	requests: readonly BridgeProductControlRequest[],
	kind: BridgeProductSubscriptionKind,
	initialSubscriptionId: string,
): SubscriptionOpenRequest {
	const request = subscriptionOpenRequests(requests).find(
		(candidate) =>
			candidate.subscription.subscriptionKind === kind &&
			candidate.subscriptionId !== initialSubscriptionId,
	);
	if (request === undefined) throw new Error(`Missing replacement ${kind} subscription.`);
	return request;
}

function cancellationRequests(
	requests: readonly BridgeProductControlRequest[],
): readonly SubscriptionCancelRequest[] {
	return requests.filter(
		(request): request is SubscriptionCancelRequest => request.kind === 'subscription.cancel',
	);
}

function requiredCancellation(
	requests: readonly BridgeProductControlRequest[],
	subscriptionId: string,
): SubscriptionCancelRequest {
	const request = requests.find(
		(candidate): candidate is SubscriptionCancelRequest =>
			candidate.kind === 'subscription.cancel' && candidate.subscriptionId === subscriptionId,
	);
	if (request === undefined) throw new Error(`Missing cancellation for ${subscriptionId}.`);
	return request;
}

async function drainSurfaceCancellationsUntilReplacementMetadataOpen(props: {
	readonly drainedCancellationIds: Set<string>;
	readonly harness: ReturnType<typeof createTransportHarness>;
	readonly initialFileAnnotation: SubscriptionOpenRequest;
	readonly initialFileMetadata: SubscriptionOpenRequest;
	readonly nextStreamSequence: () => number;
	readonly streamRequest: BridgeProductMetadataStreamRequest;
	readonly useNextStreamSequence: () => number;
}): Promise<void> {
	while (
		!hasReplacementOpen(
			props.harness.server.controlRequests,
			'file.metadata',
			props.initialFileMetadata.subscriptionId,
		)
	) {
		const cancellation = props.harness.server.controlRequests.find(
			(request): request is SubscriptionCancelRequest =>
				request.kind === 'subscription.cancel' &&
				!props.drainedCancellationIds.has(request.subscriptionId),
		);
		if (cancellation === undefined) {
			await waitForCondition(
				() =>
					hasReplacementOpen(
						props.harness.server.controlRequests,
						'file.metadata',
						props.initialFileMetadata.subscriptionId,
					) ||
					props.harness.server.controlRequests.some(
						(request) =>
							request.kind === 'subscription.cancel' &&
							!props.drainedCancellationIds.has(request.subscriptionId),
					),
			);
			continue;
		}

		if (cancellation.subscriptionId === props.initialFileAnnotation.subscriptionId) {
			props.harness.server.emitMetadata(
				annotationControlChangedFrame({
					epoch: 1,
					request: props.streamRequest,
					streamSequence: props.nextStreamSequence(),
					subscriptionId: props.initialFileAnnotation.subscriptionId,
				}),
			);
			props.useNextStreamSequence();
			await props.harness.server.waitForFrameAcknowledgementCount(props.nextStreamSequence());
		}
		const openRequest =
			cancellation.subscriptionId === props.initialFileAnnotation.subscriptionId
				? props.initialFileAnnotation
				: props.initialFileMetadata;
		props.harness.server.emitMetadata(
			subscriptionCancelled({
				epoch: 1,
				interestHash: emptyInterestHash(
					bridgeProductSubscriptionKindSchema.parse(openRequest.subscription.subscriptionKind),
				),
				kind: bridgeProductSubscriptionKindSchema.parse(openRequest.subscription.subscriptionKind),
				request: props.streamRequest,
				sourceGeneration: 1,
				streamSequence: props.nextStreamSequence(),
				subscriptionId: cancellation.subscriptionId,
				subscriptionSequence:
					cancellation.subscriptionId === props.initialFileAnnotation.subscriptionId ? 2 : 1,
			}),
		);
		props.drainedCancellationIds.add(cancellation.subscriptionId);
		props.useNextStreamSequence();
		await props.harness.server.waitForFrameAcknowledgementCount(props.nextStreamSequence());
	}
}

function annotationControlChangedFrame(props: {
	readonly epoch: number;
	readonly request: BridgeProductMetadataStreamRequest;
	readonly streamSequence: number;
	readonly subscriptionId: string;
}): BridgeProductMetadataFrame {
	return bridgeProductMetadataFrameSchema.parse({
		metadataStreamId: props.request.metadataStreamId,
		paneSessionId: props.request.paneSessionId,
		streamSequence: props.streamSequence,
		wireVersion: props.request.wireVersion,
		workerInstanceId: props.request.workerInstanceId,
		cursor: null,
		data: {
			event: {
				authority: { applicationSourceGeneration: 1, worktreeId: 'worktree-1' },
				kind: 'annotation.controlChanged',
				reason: 'discovery',
			},
			subscriptionKind: 'file.annotations',
		},
		interestRevision: 0,
		interestSha256: emptyInterestHash('file.annotations'),
		kind: 'subscription.data',
		operationCorrelationId: 'a'.repeat(64),
		sourceGeneration: 1,
		subscriptionId: props.subscriptionId,
		subscriptionKind: 'file.annotations',
		subscriptionSequence: 1,
		workerDerivationEpoch: props.epoch,
	});
}

function subscriptionResetFrame(props: {
	readonly epoch: number;
	readonly kind: BridgeProductSubscriptionKind;
	readonly request: BridgeProductMetadataStreamRequest;
	readonly streamSequence: number;
	readonly subscriptionId: string;
}): BridgeProductMetadataFrame {
	return bridgeProductMetadataFrameSchema.parse({
		metadataStreamId: props.request.metadataStreamId,
		paneSessionId: props.request.paneSessionId,
		streamSequence: props.streamSequence,
		wireVersion: props.request.wireVersion,
		workerInstanceId: props.request.workerInstanceId,
		cursor: null,
		interestRevision: 0,
		interestSha256: emptyInterestHash(props.kind),
		kind: 'subscription.reset',
		reason: 'stale_source',
		sourceGeneration: 1,
		subscriptionId: props.subscriptionId,
		subscriptionKind: props.kind,
		subscriptionSequence: 1,
		workerDerivationEpoch: props.epoch,
	});
}

function annotationCatalogFrames(props: {
	readonly epoch: number;
	readonly request: BridgeProductMetadataStreamRequest;
	readonly startStreamSequence: number;
	readonly subscriptionId: string;
}): readonly BridgeProductMetadataFrame[] {
	const transferId = 'file-annotation-catalog-after-epoch-cutover';
	const authority = { applicationSourceGeneration: 2, worktreeId: 'worktree-1' } as const;
	const events = [
		{
			authority,
			kind: 'annotation.catalog',
			transfer: {
				catalogRevision: 2,
				expectedEntryCount: 1,
				kind: 'catalog.begin',
				transferId,
			},
		},
		{
			authority,
			kind: 'annotation.catalog',
			transfer: {
				catalogRevision: 2,
				entries: [
					{
						kind: 'session',
						semanticRevision: 2,
						sessionId: '00000000-0000-7000-8000-000000000002',
					},
				],
				kind: 'catalog.window',
				transferId,
				windowOrdinal: 0,
			},
		},
		{
			authority,
			kind: 'annotation.catalog',
			transfer: {
				catalogRevision: 2,
				entryCount: 1,
				kind: 'catalog.commit',
				transferId,
				windowCount: 1,
			},
		},
	] as const;
	return events.map((event, index) =>
		bridgeProductMetadataFrameSchema.parse({
			metadataStreamId: props.request.metadataStreamId,
			paneSessionId: props.request.paneSessionId,
			streamSequence: props.startStreamSequence + index,
			wireVersion: props.request.wireVersion,
			workerInstanceId: props.request.workerInstanceId,
			cursor: null,
			data: { event, subscriptionKind: 'file.annotations' },
			interestRevision: 0,
			interestSha256: emptyInterestHash('file.annotations'),
			kind: 'subscription.data',
			operationCorrelationId: 'b'.repeat(64),
			sourceGeneration: 2,
			subscriptionId: props.subscriptionId,
			subscriptionKind: 'file.annotations',
			subscriptionSequence: index + 1,
			workerDerivationEpoch: props.epoch,
		}),
	);
}

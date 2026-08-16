import { describe, expect, test } from 'vitest';

import type { BridgeTelemetrySample } from '../../foundation/telemetry/bridge-telemetry-event.js';
import {
	encodeBridgeWorkerActiveViewerModeUpdateCommand,
	encodeBridgeWorkerReviewComparisonTargetsQueryCommand,
} from './bridge-comm-worker-protocol.js';
import { registerBridgeCommWorkerRuntimePortProtocol } from './bridge-comm-worker-runtime-protocol.js';
import {
	createIdleWorktreeAnnotationSubscription,
	createRecordingBridgeCommWorkerPort,
	flushBridgeWorkerRuntimeContinuations,
} from './bridge-comm-worker-runtime-protocol.test-support.js';
import { BridgeProductBoundedAsyncQueue } from './bridge-product-async-queue.js';
import type { BridgeProductReviewComparisonTargetsContentDescriptor } from './bridge-product-content-contracts.js';
import type { BridgeProductSubscriptionEvent } from './bridge-product-subscription-contracts.js';
import type {
	BridgeProductContentStream,
	BridgeProductSubscription,
} from './bridge-product-transport-contract.js';
import type {
	BridgeProductPanePresentationFrame,
	BridgeProductTransportSession,
} from './bridge-product-transport.js';
import type {
	BridgeWorkerPanelChromePatchPayload,
	BridgeWorkerServerToMainMessage,
} from './bridge-worker-contracts.js';

describe('Bridge comm worker updating panel chrome', () => {
	test('preserves a settled comparison-target query when native foreground is lost', async () => {
		// Arrange — retaining the completed request id makes foreground loss publish a false failure.
		const fileEvents = new BridgeProductBoundedAsyncQueue<
			BridgeProductSubscriptionEvent<'file.metadata'>
		>(16);
		const reviewEvents = new BridgeProductBoundedAsyncQueue<
			BridgeProductSubscriptionEvent<'review.metadata'>
		>(16);
		const presentation = createPanePresentationTestTransport({
			fileEvents,
			reviewEvents,
			supportsComparisonTargetContent: true,
		});
		const { dispatch, postedMessages } = createRecordingBridgeCommWorkerPort();
		registerBridgeCommWorkerRuntimePortProtocol(dispatch.port, {
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			budget: { className: 'interactive', maxBytes: 512 * 1024, maxWindowLines: 400 },
			productTransport: presentation.productTransport,
			sendProductControl: async (command): Promise<unknown> =>
				command.method === 'review.comparisonTargets.query'
					? { descriptor: comparisonTargetsDescriptor() }
					: null,
		});
		await flushBridgeWorkerRuntimeContinuations();
		presentation.publish({
			nativeActivity: 'foreground',
			presentationRevision: 1,
			refreshingLanes: [],
		});
		dispatch.message(
			encodeBridgeWorkerReviewComparisonTargetsQueryCommand({
				epoch: 1,
				requestId: 'comparison-targets-settled-before-foreground-loss',
			}),
		);
		await flushBridgeWorkerRuntimeContinuations();

		// Act
		presentation.publish({
			nativeActivity: 'loadedHidden',
			presentationRevision: 2,
			refreshingLanes: [],
		});
		await flushBridgeWorkerRuntimeContinuations();

		// Assert
		const queryEvents = postedMessages
			.map(({ message }) => message)
			.filter(
				(message) =>
					message.kind === 'reviewComparisonTargetsQuery' &&
					message.requestId === 'comparison-targets-settled-before-foreground-loss',
			);
		expect(queryEvents).toEqual([expect.objectContaining({ status: 'empty' })]);
	});

	test('settles the current comparison-target query when native foreground is lost', async () => {
		// Arrange
		const fileEvents = new BridgeProductBoundedAsyncQueue<
			BridgeProductSubscriptionEvent<'file.metadata'>
		>(16);
		const reviewEvents = new BridgeProductBoundedAsyncQueue<
			BridgeProductSubscriptionEvent<'review.metadata'>
		>(16);
		const presentation = createPanePresentationTestTransport({ fileEvents, reviewEvents });
		const { dispatch, postedMessages } = createRecordingBridgeCommWorkerPort();
		let resolveQuery!: (result: unknown) => void;
		const queryResult = new Promise<unknown>((resolve): void => {
			resolveQuery = resolve;
		});
		registerBridgeCommWorkerRuntimePortProtocol(dispatch.port, {
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			budget: { className: 'interactive', maxBytes: 512 * 1024, maxWindowLines: 400 },
			productTransport: presentation.productTransport,
			sendProductControl: async (command): Promise<unknown> =>
				command.method === 'review.comparisonTargets.query' ? queryResult : null,
		});
		await flushBridgeWorkerRuntimeContinuations();
		presentation.publish({
			nativeActivity: 'foreground',
			presentationRevision: 1,
			refreshingLanes: [],
		});
		dispatch.message(
			encodeBridgeWorkerReviewComparisonTargetsQueryCommand({
				epoch: 1,
				requestId: 'comparison-targets-before-foreground-loss',
			}),
		);
		await flushBridgeWorkerRuntimeContinuations();

		// Act
		presentation.publish({
			nativeActivity: 'loadedHidden',
			presentationRevision: 2,
			refreshingLanes: [],
		});
		resolveQuery({ descriptor: null });
		await flushBridgeWorkerRuntimeContinuations();

		// Assert
		const queryEvents = postedMessages
			.map(({ message }) => message)
			.filter(
				(message) =>
					message.kind === 'reviewComparisonTargetsQuery' &&
					message.requestId === 'comparison-targets-before-foreground-loss',
			);
		expect(queryEvents).toEqual([expect.objectContaining({ status: 'failed' })]);
	});

	test('reopens failed File metadata after the coalesced native File refresh settles', async () => {
		// Arrange — removing refresh-settlement recovery makes this test fail.
		const firstFileEvents = new BridgeProductBoundedAsyncQueue<
			BridgeProductSubscriptionEvent<'file.metadata'>
		>(16);
		const replacementFileEvents = new BridgeProductBoundedAsyncQueue<
			BridgeProductSubscriptionEvent<'file.metadata'>
		>(16);
		const reviewEvents = new BridgeProductBoundedAsyncQueue<
			BridgeProductSubscriptionEvent<'review.metadata'>
		>(16);
		const presentation = createPanePresentationTestTransport({
			fileEvents: firstFileEvents,
			replacementFileEvents,
			reviewEvents,
		});
		const { dispatch } = createRecordingBridgeCommWorkerPort();
		registerBridgeCommWorkerRuntimePortProtocol(dispatch.port, {
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			budget: { className: 'interactive', maxBytes: 512 * 1024, maxWindowLines: 400 },
			productTransport: presentation.productTransport,
			sendProductControl: async (): Promise<void> => {},
		});
		await flushBridgeWorkerRuntimeContinuations();
		firstFileEvents.fail(new Error('construction invalidated'), true);
		await flushBridgeWorkerRuntimeContinuations();

		// Act
		presentation.publish({
			presentationRevision: 1,
			nativeActivity: 'foreground',
			refreshingLanes: ['file'],
		});
		presentation.publish({
			presentationRevision: 2,
			nativeActivity: 'foreground',
			refreshingLanes: [],
		});
		await flushBridgeWorkerRuntimeContinuations();

		// Assert
		expect(presentation.fileSubscriptionCount()).toBe(2);
	});

	test('publishes updating state only for the native-foreground active surface', async () => {
		// Arrange
		const telemetrySamples: BridgeTelemetrySample[] = [];
		const fileEvents = new BridgeProductBoundedAsyncQueue<
			BridgeProductSubscriptionEvent<'file.metadata'>
		>(16);
		const reviewEvents = new BridgeProductBoundedAsyncQueue<
			BridgeProductSubscriptionEvent<'review.metadata'>
		>(16);
		const presentation = createPanePresentationTestTransport({ fileEvents, reviewEvents });
		const { dispatch, postedMessages } = createRecordingBridgeCommWorkerPort();
		registerBridgeCommWorkerRuntimePortProtocol(dispatch.port, {
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			budget: { className: 'interactive', maxBytes: 512 * 1024, maxWindowLines: 400 },
			productTransport: presentation.productTransport,
			sendProductControl: async (): Promise<void> => {},
			telemetryClient: {
				record: (sample): void => {
					telemetrySamples.push(sample);
				},
			},
		});
		await flushBridgeWorkerRuntimeContinuations();
		fileEvents.push({ eventKind: 'file.sourceAccepted', source: fileSource });
		reviewEvents.push(reviewSourceAcceptedEvent);
		await flushBridgeWorkerRuntimeContinuations();
		dispatch.message(activeViewerModeUpdateCommand('review', 1));
		await flushBridgeWorkerRuntimeContinuations();
		postedMessages.length = 0;

		// Act
		presentation.publish({
			presentationRevision: 1,
			nativeActivity: 'foreground',
			refreshingLanes: ['file', 'review'],
		});

		// Assert
		expect(panelChromePublications(postedMessages)).toEqual([
			{
				kind: 'reviewRenderPatch',
				operation: 'upsert',
				payload: { isLoading: true, message: 'Updating review…', reviewComparison: null },
				surface: 'review',
			},
		]);
		expect(telemetrySamples).toEqual(
			expect.arrayContaining([
				expect.objectContaining({
					name: 'performance.bridge.web.pane_presentation',
					stringAttributes: expect.objectContaining({
						'agentstudio.bridge.comparison.attempt.status': 'absent',
						'agentstudio.bridge.phase': 'pane_presentation_applied',
						'agentstudio.bridge.result': 'success',
					}),
					numericAttributes: expect.objectContaining({
						'agentstudio.bridge.presentation.revision': 1,
					}),
				}),
				expect.objectContaining({
					name: 'performance.bridge.web.pane_presentation',
					stringAttributes: expect.objectContaining({
						'agentstudio.bridge.panel.operation': 'upsert',
						'agentstudio.bridge.phase': 'panel_chrome_published',
						'agentstudio.bridge.viewer': 'review',
					}),
				}),
			]),
		);

		// Act
		const publicationCountBeforeReplay = panelChromePublications(postedMessages).length;
		presentation.publish({
			presentationRevision: 1,
			nativeActivity: 'foreground',
			refreshingLanes: ['file', 'review'],
		});

		// Assert
		expect(panelChromePublications(postedMessages)).toHaveLength(publicationCountBeforeReplay);

		// Act
		postedMessages.length = 0;
		dispatch.message(activeViewerModeUpdateCommand('file', 2));
		await flushBridgeWorkerRuntimeContinuations();

		// Assert
		const fileModePublications = panelChromePublications(postedMessages);
		expect(fileModePublications).toHaveLength(2);
		expect(fileModePublications).toEqual(
			expect.arrayContaining([
				{
					kind: 'fileRenderPatch',
					operation: 'upsert',
					payload: { isLoading: true, message: 'Updating files…' },
					surface: 'file',
				},
				{
					kind: 'reviewRenderPatch',
					operation: 'reset',
					payload: null,
					surface: 'review',
				},
			]),
		);
		expect(panelChromeStateAfterPublications(fileModePublications)).toEqual({
			file: { isLoading: true, message: 'Updating files…' },
			review: null,
		});

		// Act
		postedMessages.length = 0;
		presentation.publish({
			presentationRevision: 2,
			nativeActivity: 'foreground',
			refreshingLanes: [],
		});

		// Assert
		expect(panelChromePublications(postedMessages)).toEqual([
			{
				kind: 'fileRenderPatch',
				operation: 'reset',
				payload: null,
				surface: 'file',
			},
		]);

		// Arrange
		presentation.publish({
			presentationRevision: 3,
			nativeActivity: 'foreground',
			refreshingLanes: ['file'],
		});
		postedMessages.length = 0;

		// Act
		presentation.publish({
			presentationRevision: 4,
			nativeActivity: 'loadedHidden',
			refreshingLanes: ['file', 'review'],
		});

		// Assert
		const hiddenPublications = panelChromePublications(postedMessages);
		expect(hiddenPublications).toEqual([
			{
				kind: 'fileRenderPatch',
				operation: 'reset',
				payload: null,
				surface: 'file',
			},
		]);
		expect(hiddenPublications).not.toContainEqual(expect.objectContaining({ operation: 'upsert' }));

		postedMessages.length = 0;
		const reviewComparison = {
			activeTarget: { basis: 'commonCommit', kind: 'branch', name: 'feature/review' },
			attempt: { reviewGeneration: 6, status: 'pending' },
			displayedSnapshot: {
				packageId: 'package-predecessor',
				reviewGeneration: 5,
				revision: 2,
				status: 'stale',
			},
			repositoryDefaultTarget: null,
		} as const;
		presentation.publish({
			nativeActivity: 'foreground',
			presentationRevision: 5,
			refreshingLanes: [],
			reviewComparison,
		});

		expect(panelChromePublications(postedMessages)).toContainEqual({
			kind: 'reviewRenderPatch',
			operation: 'upsert',
			payload: { reviewComparison },
			surface: 'review',
		});
	});
});

interface PanePresentationPublicationProps {
	readonly presentationRevision: number;
	readonly nativeActivity: BridgeProductPanePresentationFrame['nativeActivity'];
	readonly refreshingLanes: BridgeProductPanePresentationFrame['refreshingLanes'];
	readonly reviewComparison?: BridgeProductPanePresentationFrame['reviewComparison'];
}

interface PanelChromePublication {
	readonly kind: 'fileRenderPatch' | 'reviewRenderPatch';
	readonly operation: 'reset' | 'upsert';
	readonly payload: BridgeWorkerPanelChromePatchPayload | null;
	readonly surface: 'file' | 'review';
}

function createPanePresentationTestTransport(props: {
	readonly fileEvents: BridgeProductBoundedAsyncQueue<
		BridgeProductSubscriptionEvent<'file.metadata'>
	>;
	readonly replacementFileEvents?: BridgeProductBoundedAsyncQueue<
		BridgeProductSubscriptionEvent<'file.metadata'>
	>;
	readonly reviewEvents: BridgeProductBoundedAsyncQueue<
		BridgeProductSubscriptionEvent<'review.metadata'>
	>;
	readonly supportsComparisonTargetContent?: boolean;
}): {
	readonly productTransport: BridgeProductTransportSession;
	readonly fileSubscriptionCount: () => number;
	readonly publish: (publication: PanePresentationPublicationProps) => void;
} {
	let fileEpoch = 0;
	let fileSubscriptionCount = 0;
	let reviewEpoch = 0;
	let panePresentationSink: ((frame: BridgeProductPanePresentationFrame) => void) | null = null;
	const fileSubscriptions: readonly BridgeProductSubscription<'file.metadata'>[] = [
		{
			cancel: async (): Promise<void> => {},
			events: props.fileEvents,
			subscriptionId: 'file-subscription-updating-chrome',
			subscriptionKind: 'file.metadata',
			update: async (): Promise<void> => {},
		},
		{
			cancel: async (): Promise<void> => {},
			events: props.replacementFileEvents ?? props.fileEvents,
			subscriptionId: 'file-subscription-updating-chrome-replacement',
			subscriptionKind: 'file.metadata',
			update: async (): Promise<void> => {},
		},
	];
	const reviewSubscription: BridgeProductSubscription<'review.metadata'> = {
		cancel: async (): Promise<void> => {},
		events: props.reviewEvents,
		subscriptionId: 'review-subscription-updating-chrome',
		subscriptionKind: 'review.metadata',
		update: async (): Promise<void> => {},
	};
	const productTransport: BridgeProductTransportSession = {
		bumpWorkerDerivationEpoch: (surface): number => {
			if (surface === 'file') fileEpoch += 1;
			if (surface === 'review') reviewEpoch += 1;
			return surface === 'file' ? fileEpoch : reviewEpoch;
		},
		call: async (...arguments_): Promise<never> => {
			const [method] = arguments_;
			if (method === 'file.source.current') {
				return { source: currentFileSourceConfiguration, status: 'available' } as never;
			}
			if (method === 'review.publication.applied') return null as never;
			throw new Error(`Unexpected updating-chrome product call ${method}.`);
		},
		openContent: (descriptor): never => {
			if (
				props.supportsComparisonTargetContent === true &&
				descriptor.contentKind === 'review.comparisonTargets'
			) {
				return comparisonTargetsContentStream(descriptor) as never;
			}
			throw new Error(`Unexpected updating-chrome content open ${descriptor.contentKind}.`);
		},
		setPanePresentationFrameSink: (sink): void => {
			panePresentationSink = sink;
		},
		subscribe: ((subscriptionKind: string): never => {
			if (subscriptionKind === 'file.annotations' || subscriptionKind === 'review.annotations') {
				return createIdleWorktreeAnnotationSubscription(subscriptionKind) as never;
			}
			if (subscriptionKind !== 'file.metadata') return reviewSubscription as never;
			const subscription = fileSubscriptions[fileSubscriptionCount];
			if (subscription === undefined) {
				throw new Error('Unexpected third File metadata subscription.');
			}
			fileSubscriptionCount += 1;
			return subscription as never;
		}) as BridgeProductTransportSession['subscribe'],
		workerDerivationEpoch: (surface): number => (surface === 'file' ? fileEpoch : reviewEpoch),
	};
	return {
		fileSubscriptionCount: (): number => fileSubscriptionCount,
		productTransport,
		publish: (publication): void => {
			if (panePresentationSink === null) {
				throw new Error('Expected Bridge pane presentation sink registration.');
			}
			panePresentationSink({
				...publication,
				kind: 'pane.presentation',
				metadataStreamId: 'metadata-stream-updating-chrome',
				paneSessionId: 'pane-session-updating-chrome',
				reviewComparison: publication.reviewComparison ?? null,
				streamSequence: publication.presentationRevision,
				wireVersion: 2,
				workerInstanceId: 'worker-instance-updating-chrome',
			});
		},
	};
}

function comparisonTargetsDescriptor(): BridgeProductReviewComparisonTargetsContentDescriptor {
	return {
		contentKind: 'review.comparisonTargets',
		descriptorId: 'comparison-targets-updating-chrome',
		maximumBytes: 1024 * 1024,
	};
}

function comparisonTargetsContentStream(
	descriptor: BridgeProductReviewComparisonTargetsContentDescriptor,
): BridgeProductContentStream<'review.comparisonTargets'> {
	const bytes = new TextEncoder().encode(
		JSON.stringify({
			branches: [],
			capturedAtUnixMilliseconds: 1_700_000_000_000,
			cutoffUnixMilliseconds: 1_697_408_000_000,
			currentTarget: null,
			defaultTarget: null,
			isTruncated: false,
		}),
	);
	return {
		contentKind: 'review.comparisonTargets',
		contentRequestId: 'comparison-targets-updating-chrome-content',
		frames: emptyComparisonTargetFrames(),
		terminal: Promise.resolve({
			bytes: bytes.buffer,
			contentKind: 'review.comparisonTargets',
			descriptorId: descriptor.descriptorId,
			endOfSource: true,
			kind: 'complete',
			observedByteLength: bytes.byteLength,
			observedSha256: 'a'.repeat(64),
		}),
	};
}

async function* emptyComparisonTargetFrames(): AsyncIterable<never> {}

function activeViewerModeUpdateCommand(mode: 'file' | 'review', sequence: number): unknown {
	return encodeBridgeWorkerActiveViewerModeUpdateCommand({
		epoch: sequence,
		requestId: `request-updating-chrome-${mode}-${sequence}`,
		update: {
			activeSource: null,
			mode,
			nativeSelectionRequestId: null,
			sequence,
			sessionId: 'updating-chrome-session',
		},
	});
}

function panelChromePublications(
	messages: readonly { readonly message: BridgeWorkerServerToMainMessage }[],
): readonly PanelChromePublication[] {
	return messages.flatMap(({ message }): readonly PanelChromePublication[] => {
		if (message.kind !== 'fileRenderPatch' && message.kind !== 'reviewRenderPatch') return [];
		return message.patches.flatMap((patch): readonly PanelChromePublication[] => {
			if (patch.slice !== 'panelChrome' || patch.operation === 'delete') return [];
			return [
				{
					kind: message.kind,
					operation: patch.operation,
					payload: patch.operation === 'upsert' ? patch.payload : null,
					surface: message.surface,
				},
			];
		});
	});
}

function panelChromeStateAfterPublications(
	publications: readonly PanelChromePublication[],
): Readonly<Record<'file' | 'review', PanelChromePublication['payload']>> {
	const state: Record<'file' | 'review', PanelChromePublication['payload']> = {
		file: null,
		review: null,
	};
	for (const publication of publications) {
		state[publication.surface] = publication.operation === 'upsert' ? publication.payload : null;
	}
	return state;
}

const fileSource = {
	repoId: '00000000-0000-4000-8000-000000000001',
	rootRevisionToken: 'root-revision-updating-chrome',
	sourceCursor: 'source-cursor-updating-chrome',
	sourceId: 'file-source-updating-chrome',
	subscriptionGeneration: 1,
	worktreeId: '00000000-0000-4000-8000-000000000002',
} as const;

const currentFileSourceConfiguration = {
	cwdScope: null,
	freshness: 'live',
	includeStatuses: true,
	repoId: fileSource.repoId,
	rootPathToken: 'root-token-updating-chrome',
	worktreeId: fileSource.worktreeId,
} as const;

const reviewSourceAcceptedEvent = {
	eventKind: 'review.sourceAccepted',
	generation: 1,
	packageId: 'review-package-updating-chrome',
	publicationId: '00000000-0000-7000-8000-000000000011',
	revision: 1,
	sourceIdentity: 'review-source-updating-chrome',
} satisfies BridgeProductSubscriptionEvent<'review.metadata'>;

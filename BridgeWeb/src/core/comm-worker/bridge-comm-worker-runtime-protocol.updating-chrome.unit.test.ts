import { describe, expect, test } from 'vitest';

import { encodeBridgeWorkerActiveViewerModeUpdateCommand } from './bridge-comm-worker-protocol.js';
import { registerBridgeCommWorkerRuntimePortProtocol } from './bridge-comm-worker-runtime-protocol.js';
import {
	createRecordingBridgeCommWorkerPort,
	flushBridgeWorkerRuntimeContinuations,
} from './bridge-comm-worker-runtime-protocol.test-support.js';
import { BridgeProductBoundedAsyncQueue } from './bridge-product-async-queue.js';
import type { BridgeProductSubscriptionEvent } from './bridge-product-subscription-contracts.js';
import type { BridgeProductSubscription } from './bridge-product-transport-contract.js';
import type {
	BridgeProductPanePresentationFrame,
	BridgeProductTransportSession,
} from './bridge-product-transport.js';
import type {
	BridgeWorkerPanelChromePatchPayload,
	BridgeWorkerServerToMainMessage,
} from './bridge-worker-contracts.js';

describe('Bridge comm worker updating panel chrome', () => {
	test('publishes updating state only for the native-foreground active surface', async () => {
		// Arrange
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
			activityRevision: 1,
			nativeActivity: 'foreground',
			refreshingLanes: ['file', 'review'],
		});

		// Assert
		expect(panelChromePublications(postedMessages)).toEqual([
			{
				kind: 'reviewRenderPatch',
				operation: 'upsert',
				payload: { isLoading: true, message: 'Updating review…' },
				surface: 'review',
			},
		]);

		// Act
		const publicationCountBeforeReplay = panelChromePublications(postedMessages).length;
		presentation.publish({
			activityRevision: 1,
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
		expect(fileModePublications).toEqual([
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
		]);
		expect(panelChromeStateAfterPublications(fileModePublications)).toEqual({
			file: { isLoading: true, message: 'Updating files…' },
			review: null,
		});

		// Act
		postedMessages.length = 0;
		presentation.publish({
			activityRevision: 2,
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
			activityRevision: 3,
			nativeActivity: 'foreground',
			refreshingLanes: ['file'],
		});
		postedMessages.length = 0;

		// Act
		presentation.publish({
			activityRevision: 4,
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
	});
});

interface PanePresentationPublicationProps {
	readonly activityRevision: number;
	readonly nativeActivity: BridgeProductPanePresentationFrame['nativeActivity'];
	readonly refreshingLanes: BridgeProductPanePresentationFrame['refreshingLanes'];
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
	readonly reviewEvents: BridgeProductBoundedAsyncQueue<
		BridgeProductSubscriptionEvent<'review.metadata'>
	>;
}): {
	readonly productTransport: BridgeProductTransportSession;
	readonly publish: (publication: PanePresentationPublicationProps) => void;
} {
	let fileEpoch = 0;
	let reviewEpoch = 0;
	let panePresentationSink: ((frame: BridgeProductPanePresentationFrame) => void) | null = null;
	const fileSubscription: BridgeProductSubscription<'file.metadata'> = {
		cancel: async (): Promise<void> => {},
		events: props.fileEvents,
		subscriptionId: 'file-subscription-updating-chrome',
		subscriptionKind: 'file.metadata',
		update: async (): Promise<void> => {},
	};
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
		openContent: (): never => {
			throw new Error('Updating chrome test must not open content.');
		},
		setPanePresentationFrameSink: (sink): void => {
			panePresentationSink = sink;
		},
		subscribe: ((subscriptionKind: string): never =>
			(subscriptionKind === 'file.metadata'
				? fileSubscription
				: reviewSubscription) as never) as BridgeProductTransportSession['subscribe'],
		workerDerivationEpoch: (surface): number => (surface === 'file' ? fileEpoch : reviewEpoch),
	};
	return {
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
				streamSequence: publication.activityRevision,
				wireVersion: 2,
				workerInstanceId: 'worker-instance-updating-chrome',
			});
		},
	};
}

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

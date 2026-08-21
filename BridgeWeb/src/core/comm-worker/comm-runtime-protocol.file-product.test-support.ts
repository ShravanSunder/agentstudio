import { expect } from 'vitest';

import type { BridgeCommWorkerPreparationDrain } from './bridge-comm-worker-runtime-protocol.js';
import {
	createIdleWorktreeAnnotationSubscription,
	flushBridgeWorkerRuntimeContinuations,
} from './bridge-comm-worker-runtime-protocol.test-support.js';
import { BridgeProductBoundedAsyncQueue } from './bridge-product-async-queue.js';
import type { BridgeProductSubscriptionEvent } from './bridge-product-subscription-contracts.js';
import type { BridgeProductSubscription } from './bridge-product-transport-contract.js';
import type {
	BridgeProductPanePresentationFrame,
	BridgeProductTransportSession,
} from './bridge-product-transport.js';

export const fileProductTestSource = {
	repoId: '00000000-0000-4000-8000-000000000001',
	rootRevisionToken: 'root-revision-1',
	sourceCursor: 'source-cursor-1',
	sourceId: 'file-source-1',
	subscriptionGeneration: 3,
	worktreeId: '00000000-0000-4000-8000-000000000002',
} as const;

export const fileViewProductTestBudget = {
	className: 'interactive',
	maxBytes: 2 * 1024 * 1024,
	maxWindowLines: 10_000,
} as const;

export function makeFileProductTestTransport(props: {
	readonly discoveryError?: Error;
	readonly onDiscoverSource: () => void;
	readonly onOpenDescriptor: (descriptorId: string) => void;
	readonly onPanePresentationSink?: (
		sink: (frame: BridgeProductPanePresentationFrame) => void,
	) => void;
	readonly onSubscribe?: () => void;
	readonly reviewEvents?: BridgeProductBoundedAsyncQueue<
		BridgeProductSubscriptionEvent<'review.metadata'>
	>;
	readonly subscription: BridgeProductSubscription<'file.metadata'>;
}): BridgeProductTransportSession {
	let fileEpoch = 0;
	let reviewEpoch = 0;
	const reviewEvents =
		props.reviewEvents ??
		new BridgeProductBoundedAsyncQueue<BridgeProductSubscriptionEvent<'review.metadata'>>(64);
	const reviewSubscription: BridgeProductSubscription<'review.metadata'> = {
		cancel: async (): Promise<void> => {},
		events: reviewEvents,
		subscriptionId: 'review-subscription-for-file-runtime-test',
		subscriptionKind: 'review.metadata',
		update: async (): Promise<void> => {},
	};
	return {
		bumpWorkerDerivationEpoch: (surface): number => {
			if (surface === 'file') fileEpoch += 1;
			if (surface === 'review') reviewEpoch += 1;
			return surface === 'file' ? fileEpoch : reviewEpoch;
		},
		call: async (...arguments_): Promise<never> => {
			const [method] = arguments_;
			if (method !== 'file.source.current') throw new Error('Unexpected product call.');
			if (props.discoveryError !== undefined) throw props.discoveryError;
			props.onDiscoverSource();
			// oxlint-disable-next-line typescript/no-unsafe-type-assertion -- The generic call fixture returns the exact File discovery branch requested above.
			return {
				source: currentFileSourceConfiguration,
				status: 'available',
			} as never;
		},
		openContent: (descriptor): never => {
			props.onOpenDescriptor(descriptor.descriptorId);
			const bytes = new TextEncoder().encode('file body\n').buffer;
			// oxlint-disable-next-line typescript/no-unsafe-type-assertion -- The fixture returns the exact File content stream requested above.
			return {
				contentKind: 'file.content',
				contentRequestId: 'content-request-1',
				frames: emptyFrames(),
				terminal: Promise.resolve({
					bytes,
					contentKind: 'file.content',
					descriptorId: descriptor.descriptorId,
					kind: 'complete',
					observedSha256: 'a'.repeat(64),
				}),
			} as never;
		},
		setPanePresentationFrameSink: (
			sink: (frame: BridgeProductPanePresentationFrame) => void,
		): void => {
			props.onPanePresentationSink?.(sink);
			sink(makeFilePanePresentationFrame(1, 'foreground'));
		},
		// oxlint-disable-next-line typescript/no-unsafe-type-assertion -- The fixture closes over the supported File/Review subscription variants.
		subscribe: ((subscriptionKind: string): never => {
			if (subscriptionKind === 'file.annotations' || subscriptionKind === 'review.annotations') {
				// oxlint-disable-next-line typescript/no-unsafe-type-assertion -- The branch closes over the requested annotation subscription kind.
				return createIdleWorktreeAnnotationSubscription(subscriptionKind) as never;
			}
			if (subscriptionKind === 'review.metadata') {
				// oxlint-disable-next-line typescript/no-unsafe-type-assertion -- The branch closes over Review metadata.
				return reviewSubscription as never;
			}
			props.onSubscribe?.();
			// oxlint-disable-next-line typescript/no-unsafe-type-assertion -- The remaining admitted branch is File metadata.
			return props.subscription as never;
		}) as BridgeProductTransportSession['subscribe'],
		workerDerivationEpoch: (surface): number => (surface === 'file' ? fileEpoch : reviewEpoch),
	};
}

export function requireFilePanePresentationSink(
	sink: ((frame: BridgeProductPanePresentationFrame) => void) | null,
): (frame: BridgeProductPanePresentationFrame) => void {
	if (sink === null) throw new Error('Expected Bridge File pane presentation sink registration.');
	return sink;
}

export function makeFilePanePresentationFrame(
	presentationRevision: number,
	nativeActivity: BridgeProductPanePresentationFrame['nativeActivity'],
): BridgeProductPanePresentationFrame {
	return {
		fileRefreshFailure: null,
		presentationRevision,
		kind: 'pane.presentation',

		operationCorrelationId: null,
		metadataStreamId: 'file-product-test-metadata-stream',
		nativeActivity,
		paneSessionId: 'file-product-test-pane-session',
		refreshingLanes: [],
		reviewComparison: null,
		streamSequence: presentationRevision,
		wireVersion: 2,
		workerInstanceId: 'file-product-test-worker-instance',
	};
}

export async function drainFilePreparationUntilIdle(
	scheduledDrains: BridgeCommWorkerPreparationDrain[],
): Promise<void> {
	const drainCompletions: Array<ReturnType<BridgeCommWorkerPreparationDrain>> = [];
	for (let drainRound = 0; drainRound < 16; drainRound += 1) {
		const drainsForRound = scheduledDrains.splice(0);
		if (drainsForRound.length > 0) {
			drainCompletions.push(...drainsForRound.map((drain) => drain()));
		}
		// oxlint-disable-next-line no-await-in-loop -- Each bounded round exposes event-scheduled continuation drains.
		await flushBridgeWorkerRuntimeContinuations();
		if (scheduledDrains.length === 0) break;
	}
	expect(scheduledDrains).toEqual([]);
	await Promise.all(drainCompletions);
	await flushBridgeWorkerRuntimeContinuations();
}

const currentFileSourceConfiguration = {
	cwdScope: null,
	freshness: 'live',
	includeStatuses: true,
	repoId: fileProductTestSource.repoId,
	rootPathToken: 'root-token-1',
	worktreeId: fileProductTestSource.worktreeId,
} as const;

export function makeTreeWindowEvent(): BridgeProductSubscriptionEvent<'file.metadata'> {
	return {
		eventKind: 'file.treeWindow',
		finalWindow: true,
		lineage: { lane: 'visible', loadedBy: 'startup_window' },
		pathScope: [],
		rows: [
			{
				changeStatus: 'modified',
				depth: 0,
				fileId: 'file-1',
				fileClass: 'source',
				isDirectory: false,
				lineCount: 1,
				name: 'File.swift',
				parentPath: null,
				path: 'Sources/File.swift',
				rowId: 'row-file-1',
				sizeBytes: 10,
			},
		],
		source: fileProductTestSource,
		startIndex: 0,
		totalRowCount: 1,
	};
}

export function makeDescriptorReadyEvent(): BridgeProductSubscriptionEvent<'file.metadata'> {
	return {
		availability: {
			availabilityKind: 'available',
			contentDescriptor: {
				contentKind: 'file.content',
				declaredByteLength: 10,
				descriptorId: 'descriptor-file-1',
				encoding: 'utf-8',
				expectedSha256: 'a'.repeat(64),
				fileId: 'file-1',
				maximumBytes: 10,
				source: fileProductTestSource,
				window: {
					kind: 'prefix',
					maximumBytes: 10,
					maximumLines: 1,
					startByte: 0,
				},
			},
		},
		encoding: 'utf-8',
		endsMidLine: false,
		endsWithNewline: true,
		estimatedContentHeightPixels: null,
		eventKind: 'file.descriptorReady',
		fileExtension: 'swift',
		fileId: 'file-1',
		language: 'swift',
		modifiedAtUnixMilliseconds: 1,
		path: 'Sources/File.swift',
		payloadByteCount: 10,
		payloadLineCount: 1,
		rowId: 'row-file-1',
		sizeBytes: 10,
		source: fileProductTestSource,
		totalLineCount: 1,
		truncationKind: 'none',
		virtualizedExtentKind: 'exactLineCount',
	};
}

async function* emptyFrames(): AsyncIterable<never> {}

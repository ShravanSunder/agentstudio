import { expect } from 'vitest';

import type { BridgeCommWorkerPort } from './bridge-comm-worker-entry.js';
import type { BridgeCommWorkerReviewRuntimeSource } from './bridge-comm-worker-review-source-diff.js';
import type { BridgeCommWorkerPreparationDrain } from './bridge-comm-worker-runtime-protocol.js';
import { BridgeProductBoundedAsyncQueue } from './bridge-product-async-queue.js';
import { bridgeProductReviewPublicationAppliedRequestSchema } from './bridge-product-call-contracts.js';
import { bridgeProductReviewMetadataEventSchema } from './bridge-product-review-metadata-contracts.js';
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
	BridgeWorkerFileViewContentMetadata,
	BridgeWorkerReviewContentMetadata,
	BridgeWorkerReviewContentRequestDescriptor,
	BridgeWorkerReviewRenderSemantics,
	BridgeWorkerServerToMainMessage,
} from './bridge-worker-contracts.js';
import type { BridgeWorkerReviewContentOpen } from './bridge-worker-review-content-fetch.js';

export interface PostedBridgeWorkerRuntimeMessage {
	readonly message: BridgeWorkerServerToMainMessage;
	readonly transferList: readonly Transferable[] | undefined;
}

export const reviewContentFixtureByDescriptorId = new Map<
	string,
	{ readonly itemId: string; readonly text: string }
>();

export function createRecordingBridgeCommWorkerPort(
	props: {
		readonly beforePostMessage?: (message: BridgeWorkerServerToMainMessage) => void;
	} = {},
): {
	readonly dispatch: {
		readonly message: (data: unknown) => void;
		readonly port: BridgeCommWorkerPort;
	};
	readonly postedMessages: PostedBridgeWorkerRuntimeMessage[];
} {
	const postedMessages: PostedBridgeWorkerRuntimeMessage[] = [];
	let listener: ((event: MessageEvent<unknown>) => void) | null = null;
	return {
		dispatch: {
			message: (data: unknown): void => {
				if (listener === null) {
					throw new Error('Bridge comm worker port listener was not registered.');
				}
				listener(new MessageEvent('message', { data }));
			},
			port: {
				postMessage: (
					message: BridgeWorkerServerToMainMessage,
					transferList?: Transferable[],
				): void => {
					props.beforePostMessage?.(message);
					postedMessages.push({ message, transferList });
				},
				addEventListener: (
					type: 'message',
					nextListener: (event: MessageEvent<unknown>) => void,
				): void => {
					expect(type).toBe('message');
					listener = nextListener;
				},
				start: (): void => {},
			},
		},
		postedMessages,
	};
}

export function createBridgeWorkerSequenceCounter(firstSequence: number): () => number {
	let nextSequence = firstSequence;
	return (): number => {
		const sequence = nextSequence;
		nextSequence += 1;
		return sequence;
	};
}

export function assertBridgeCommWorkerPreparationDrain(
	drain: BridgeCommWorkerPreparationDrain | undefined,
): BridgeCommWorkerPreparationDrain {
	if (drain === undefined) {
		throw new Error('Expected scheduled bridge comm worker preparation drain.');
	}
	return drain;
}

export async function flushBridgeWorkerRuntimeContinuations(): Promise<void> {
	await Array.from({ length: 50 }).reduce<Promise<void>>(
		(previousFlush) => previousFlush.then(() => Promise.resolve()),
		Promise.resolve(),
	);
}

export interface BridgeCommWorkerReviewProductTestSource {
	readonly close: () => void;
	readonly productTransport: BridgeProductTransportSession;
	readonly publishSource: (source: BridgeCommWorkerReviewRuntimeSource, revision?: number) => void;
	readonly publishSourceAndWaitForApplication: (
		source: BridgeCommWorkerReviewRuntimeSource,
		revision?: number,
	) => Promise<void>;
}

export function createBridgeCommWorkerReviewProductTestSource(): BridgeCommWorkerReviewProductTestSource {
	const events = new BridgeProductBoundedAsyncQueue<
		BridgeProductSubscriptionEvent<'review.metadata'>
	>(64);
	let currentWorkerDerivationEpoch = 0;
	let currentSnapshot: ReviewProductTestSnapshot | null = null;
	let currentRevision = 0;
	const pendingApplicationReceiptsByPublicationId = new Map<string, () => void>();
	const subscription: BridgeProductSubscription<'review.metadata'> = {
		cancel: async (): Promise<void> => {
			events.close(true);
		},
		events,
		subscriptionId: 'review-product-test-subscription',
		subscriptionKind: 'review.metadata',
		update: async (): Promise<void> => {},
	};
	const productTransport: BridgeProductTransportSession = {
		bumpWorkerDerivationEpoch: (surface): number => {
			if (surface === 'review') currentWorkerDerivationEpoch += 1;
			return surface === 'review' ? currentWorkerDerivationEpoch : 0;
		},
		call: async (...arguments_): Promise<never> => {
			const [method] = arguments_;
			if (method === 'file.source.current') {
				return { reason: 'review-product-test-source', status: 'unavailable' } as never;
			}
			if (method === 'review.publication.applied') {
				const request = bridgeProductReviewPublicationAppliedRequestSchema.parse(arguments_[1]);
				pendingApplicationReceiptsByPublicationId.get(request.publicationId)?.();
				pendingApplicationReceiptsByPublicationId.delete(request.publicationId);
				return null as never;
			}
			return undefined as never;
		},
		openContent: (): never => {
			throw new Error(
				'Review product test source requires the test to provide its content-open seam.',
			);
		},
		setPanePresentationFrameSink: (
			sink: (frame: BridgeProductPanePresentationFrame) => void,
		): void => {
			// This shared fixture models an already active Review pane. Hidden/dormant admission tests
			// install their own transport so suppression remains explicit and independently proven.
			sink({
				activityRevision: 1,
				kind: 'pane.presentation',
				metadataStreamId: 'review-product-test-metadata-stream',
				nativeActivity: 'foreground',
				paneSessionId: 'review-product-test-pane-session',
				refreshingLanes: [],
				streamSequence: 1,
				wireVersion: 2,
				workerInstanceId: 'review-product-test-worker-instance',
			});
		},
		subscribe: (...arguments_): never => {
			const [subscriptionKind] = arguments_;
			if (subscriptionKind !== 'review.metadata') {
				throw new Error(`Unexpected product subscription ${subscriptionKind}.`);
			}
			return subscription as never;
		},
		workerDerivationEpoch: (surface): number =>
			surface === 'review' ? currentWorkerDerivationEpoch : 0,
	};
	return {
		close: (): void => {
			events.close(true);
		},
		productTransport,
		publishSource: (source, revision): void => {
			void publishReviewProductTestSource(source, revision);
		},
		publishSourceAndWaitForApplication: publishReviewProductTestSource,
	};

	function publishReviewProductTestSource(
		source: BridgeCommWorkerReviewRuntimeSource,
		revision?: number,
	): Promise<void> {
		const nextRevision = Math.max(currentRevision + 1, revision ?? currentRevision + 1);
		const nextSnapshot = reviewProductSnapshotFromRuntimeSource(source, nextRevision);
		const applicationReceipt = new Promise<void>((resolve): void => {
			pendingApplicationReceiptsByPublicationId.set(nextSnapshot.publicationId, resolve);
		});
		events.push(
			currentSnapshot === null
				? nextSnapshot
				: reviewProductDeltaBetweenSnapshots(currentSnapshot, nextSnapshot),
		);
		currentSnapshot = nextSnapshot;
		currentRevision = nextRevision;
		return applicationReceipt;
	}
}

type ReviewProductTestSnapshot = Extract<
	BridgeProductSubscriptionEvent<'review.metadata'>,
	{ readonly eventKind: 'review.snapshot' }
>;

function reviewProductSnapshotFromRuntimeSource(
	source: BridgeCommWorkerReviewRuntimeSource,
	revision: number,
): ReviewProductTestSnapshot {
	const generation = 1;
	const packageId = 'review-product-test-package';
	const publicationId = reviewProductTestPublicationId(revision);
	const sourceIdentity = 'review-product-test-source';
	const contentSources = source.contentRequestDescriptors.map((descriptor) => ({
		contentDigest: descriptor.contentDigest,
		contentKind: 'review.content' as const,
		descriptorId: descriptor.descriptorId,
		encoding: descriptor.encoding,
		endpointId: descriptor.endpointId,
		handleId: descriptor.handleId,
		isBinary: descriptor.isBinary,
		itemId: descriptor.itemId,
		language: descriptor.language,
		mimeType: descriptor.mimeType,
		packageId,
		reviewGeneration: generation,
		role: descriptor.role,
		sourceIdentity,
		wholeByteLength: descriptor.wholeByteLength,
	}));
	const contentSourcesByItemId = new Map<string, Array<(typeof contentSources)[number]>>();
	for (const descriptor of contentSources) {
		const itemContentSources = contentSourcesByItemId.get(descriptor.itemId) ?? [];
		itemContentSources.push(descriptor);
		contentSourcesByItemId.set(descriptor.itemId, itemContentSources);
	}
	const semanticsByItemId = new Map(
		source.renderSemantics.map((semantics) => [semantics.itemId, semantics]),
	);
	const orderedContentItems = orderedReviewRuntimeContentItems(source);
	const itemMetadata = orderedContentItems.map((contentItem) => {
		const semantics = semanticsByItemId.get(contentItem.itemId);
		const itemContentSources = contentSourcesByItemId.get(contentItem.itemId) ?? [];
		const contentDescriptorIdsByRole = Object.fromEntries(
			itemContentSources.map((descriptor) => [descriptor.role, descriptor.descriptorId]),
		);
		const contentHashesByRole = Object.fromEntries(
			itemContentSources.map((descriptor) => [descriptor.role, descriptor.contentDigest.value]),
		);
		const contentRoles = itemContentSources.map((descriptor) => descriptor.role);
		const displayPath = semantics?.displayPath ?? contentItem.path;
		return {
			basePath: semantics?.basePath ?? displayPath,
			changeKind: semantics?.changeKind ?? 'modified',
			contentDescriptorIdsByRole,
			contentHashesByRole,
			contentRoles,
			extension: reviewProductTestPathExtension(displayPath),
			fileClass: 'source' as const,
			headPath: semantics?.headPath ?? displayPath,
			isHiddenByDefault: false,
			itemId: contentItem.itemId,
			language: contentItem.language,
			mimeTypes: ['text/plain'],
			provenance: { agentSessionIds: [], operationIds: [], promptIds: [] },
			reviewPriority: 'normal' as const,
			reviewState: 'unreviewed' as const,
		};
	});
	const treeRows = orderedReviewRuntimeRows(source).map((row) => {
		const contentItem = source.contentItems.find((candidate) => candidate.itemId === row.id);
		return {
			depth: reviewRuntimeRowDepth(source, row.id),
			isDirectory: contentItem === undefined,
			itemId: contentItem?.itemId ?? null,
			path: contentItem?.path ?? row.id,
			rowId: row.id,
		};
	});
	const extentFacts = orderedContentItems.flatMap((contentItem) =>
		Object.entries(contentItem.contentLineCountsByRole).flatMap(([contentRole, lineCount]) =>
			lineCount === undefined || lineCount === null
				? []
				: [{ contentRole, itemId: contentItem.itemId, lineCount }],
		),
	);
	const event = {
		baseEndpoint: {
			createdAtUnixMilliseconds: 1,
			endpointId: 'review-product-test-base',
			kind: 'gitRef',
			label: 'base',
			providerIdentity: 'review-product-test-provider',
			repoId: 'review-product-test-repo',
			worktreeId: 'review-product-test-worktree',
		},
		contentSources,
		eventKind: 'review.snapshot',
		extentFacts,
		generation,
		headEndpoint: {
			createdAtUnixMilliseconds: 1,
			endpointId: 'review-product-test-head',
			kind: 'workingTree',
			label: 'head',
			providerIdentity: 'review-product-test-provider',
			repoId: 'review-product-test-repo',
			worktreeId: 'review-product-test-worktree',
		},
		itemMetadata,
		itemWindow: {
			finalWindow: true,
			itemCount: itemMetadata.length,
			startIndex: 0,
			totalItemCount: itemMetadata.length,
		},
		packageId,
		publicationId,
		query: {
			baseEndpointId: 'review-product-test-base',
			comparisonSemantics: 'threeDot',
			fileTarget: null,
			grouping: { kind: 'folder' },
			headEndpointId: 'review-product-test-head',
			pathScope: [],
			provenanceFilter: {
				agentSessionIds: [],
				operationIds: [],
				paneIds: [],
				promptIds: [],
				sourceKinds: [],
			},
			queryId: 'review-product-test-query',
			queryKind: 'compare',
			repoId: 'review-product-test-repo',
			viewFilter: {
				changeKinds: [],
				excludedExtensions: [],
				excludedFileClasses: [],
				excludedPathGlobs: [],
				includedExtensions: [],
				includedFileClasses: [],
				includedPathGlobs: [],
				reviewStates: [],
				showBinaryFiles: true,
				showHiddenFiles: false,
				showLargeFiles: true,
			},
			worktreeId: 'review-product-test-worktree',
		},
		revision,
		sourceIdentity,
		summary: {
			additions: 0,
			deletions: 0,
			filesChanged: itemMetadata.length,
			hiddenFileCount: 0,
			visibleFileCount: itemMetadata.length,
		},
		treeRows,
		treeWindow: {
			finalWindow: true,
			rowCount: treeRows.length,
			startIndex: 0,
			totalRowCount: treeRows.length,
		},
	};
	return bridgeProductReviewMetadataEventSchema.parse(event) as ReviewProductTestSnapshot;
}

function reviewProductDeltaBetweenSnapshots(
	previousSnapshot: ReviewProductTestSnapshot,
	nextSnapshot: ReviewProductTestSnapshot,
): BridgeProductSubscriptionEvent<'review.metadata'> {
	const previousItemsById = new Map(
		previousSnapshot.itemMetadata.map((item) => [item.itemId, item]),
	);
	const nextItemsById = new Map(nextSnapshot.itemMetadata.map((item) => [item.itemId, item]));
	const previousContentSourcesById = new Map(
		previousSnapshot.contentSources.map((source) => [source.descriptorId, source]),
	);
	const nextContentSourcesById = new Map(
		nextSnapshot.contentSources.map((source) => [source.descriptorId, source]),
	);
	const removedItemIds = [...previousItemsById.keys()].filter(
		(itemId) => !nextItemsById.has(itemId),
	);
	const removedDescriptorIds = [...previousContentSourcesById.keys()].filter(
		(descriptorId) => !nextContentSourcesById.has(descriptorId),
	);
	const changedItems = nextSnapshot.itemMetadata.filter(
		(item) => !sameReviewProductTestValue(item, previousItemsById.get(item.itemId)),
	);
	const changedContentSources = nextSnapshot.contentSources.filter(
		(source) =>
			!sameReviewProductTestValue(source, previousContentSourcesById.get(source.descriptorId)),
	);
	const previousExtentFactsByKey = new Map(
		previousSnapshot.extentFacts.map((fact) => [reviewProductTestExtentFactKey(fact), fact]),
	);
	const changedExtentFacts = nextSnapshot.extentFacts.filter(
		(fact) =>
			!sameReviewProductTestValue(
				fact,
				previousExtentFactsByKey.get(reviewProductTestExtentFactKey(fact)),
			),
	);
	const previousItemOrder = previousSnapshot.itemMetadata.map((item) => item.itemId);
	const nextItemOrder = nextSnapshot.itemMetadata.map((item) => item.itemId);
	const operations = [
		...changedItems.map((item) => ({ operationKind: 'upsertItem' as const, item })),
		...(removedItemIds.length === 0
			? []
			: [{ operationKind: 'removeItems' as const, itemIds: removedItemIds }]),
		...(sameReviewProductTestValue(previousItemOrder, nextItemOrder)
			? []
			: [{ operationKind: 'replaceItemOrder' as const, itemIds: nextItemOrder }]),
		...(sameReviewProductTestValue(previousSnapshot.treeRows, nextSnapshot.treeRows)
			? []
			: [
					{
						deleteCount: previousSnapshot.treeRows.length,
						operationKind: 'spliceTreeRows' as const,
						rows: nextSnapshot.treeRows,
						startIndex: 0,
					},
				]),
		...(changedExtentFacts.length === 0
			? []
			: [{ operationKind: 'upsertExtentFacts' as const, facts: changedExtentFacts }]),
		...(removedDescriptorIds.length === 0
			? []
			: [
					{
						descriptorIds: removedDescriptorIds,
						operationKind: 'invalidateContentSources' as const,
					},
				]),
	];
	return bridgeProductReviewMetadataEventSchema.parse({
		contentSources: changedContentSources,
		eventKind: 'review.delta',
		fromRevision: previousSnapshot.revision,
		generation: nextSnapshot.generation,
		operations,
		packageId: nextSnapshot.packageId,
		publicationId: nextSnapshot.publicationId,
		revision: nextSnapshot.revision,
		sourceIdentity: nextSnapshot.sourceIdentity,
		summary: nextSnapshot.summary,
		toRevision: nextSnapshot.revision,
	});
}

function reviewProductTestPublicationId(revision: number): string {
	const revisionSuffix = revision.toString(16).padStart(12, '0').slice(-12);
	return `00000000-0000-7000-8000-${revisionSuffix}`;
}

function reviewProductTestExtentFactKey(fact: {
	readonly contentRole: string;
	readonly itemId: string;
}): string {
	return `${fact.itemId}:${fact.contentRole}`;
}

function sameReviewProductTestValue(left: unknown, right: unknown): boolean {
	return JSON.stringify(left) === JSON.stringify(right);
}

function orderedReviewRuntimeRows(
	source: BridgeCommWorkerReviewRuntimeSource,
): BridgeCommWorkerReviewRuntimeSource['rows'] {
	return source.rows.toSorted((left, right) => left.index - right.index);
}

function orderedReviewRuntimeContentItems(
	source: BridgeCommWorkerReviewRuntimeSource,
): BridgeCommWorkerReviewRuntimeSource['contentItems'] {
	const contentItemsById = new Map(source.contentItems.map((item) => [item.itemId, item]));
	const orderedItemIds = orderedReviewRuntimeRows(source).flatMap((row) =>
		contentItemsById.has(row.id) ? [row.id] : [],
	);
	for (const contentItem of source.contentItems) {
		if (!orderedItemIds.includes(contentItem.itemId)) orderedItemIds.push(contentItem.itemId);
	}
	return orderedItemIds.flatMap((itemId) => {
		const contentItem = contentItemsById.get(itemId);
		return contentItem === undefined ? [] : [contentItem];
	});
}

function reviewRuntimeRowDepth(source: BridgeCommWorkerReviewRuntimeSource, rowId: string): number {
	const rowsById = new Map(source.rows.map((row) => [row.id, row]));
	const visitedRowIds = new Set<string>();
	let depth = 0;
	let currentRow = rowsById.get(rowId);
	while (currentRow?.parentId !== null && currentRow?.parentId !== undefined) {
		if (visitedRowIds.has(currentRow.parentId)) break;
		visitedRowIds.add(currentRow.parentId);
		depth += 1;
		currentRow = rowsById.get(currentRow.parentId);
	}
	return depth;
}

function reviewProductTestPathExtension(path: string): string | null {
	const fileName = path.split('/').at(-1) ?? path;
	const extensionSeparatorIndex = fileName.lastIndexOf('.');
	return extensionSeparatorIndex <= 0 || extensionSeparatorIndex === fileName.length - 1
		? null
		: fileName.slice(extensionSeparatorIndex + 1);
}

export interface DeferredReviewContentStream {
	readonly stream: BridgeProductContentStream<'review.content'>;
	readonly resolve: (text: string) => void;
}

export function createDeferredReviewContentStream(
	descriptor: BridgeWorkerReviewContentRequestDescriptor,
): DeferredReviewContentStream {
	let resolveTerminal: ((text: string) => void) | null = null;
	const terminal: BridgeProductContentStream<'review.content'>['terminal'] = new Promise(
		(resolve) => {
			resolveTerminal = (text: string): void => {
				resolve(completedReviewContentTerminal(descriptor, text));
			};
		},
	);
	return {
		stream: {
			contentKind: 'review.content',
			contentRequestId: `content-request-${descriptor.descriptorId}`,
			frames: emptyReviewContentFrames(),
			terminal,
		},
		resolve: (text: string): void => {
			if (resolveTerminal === null) {
				throw new Error('Deferred Review content resolver was not initialized.');
			}
			resolveTerminal(text);
		},
	};
}

export function makeImmediateReviewContentStream(
	descriptor: BridgeWorkerReviewContentRequestDescriptor,
	text: string,
): BridgeProductContentStream<'review.content'> {
	return {
		contentKind: 'review.content',
		contentRequestId: `content-request-${descriptor.descriptorId}`,
		frames: emptyReviewContentFrames(),
		terminal: Promise.resolve(completedReviewContentTerminal(descriptor, text)),
	};
}

export const openReviewContentFromDescriptorMap: BridgeWorkerReviewContentOpen = (descriptor) => {
	const fixture = reviewContentFixtureByDescriptorId.get(descriptor.descriptorId);
	if (fixture === undefined) {
		throw new Error(`Unexpected Review content descriptor ${descriptor.descriptorId}.`);
	}
	return makeImmediateReviewContentStream(descriptor, fixture.text);
};

function completedReviewContentTerminal(
	descriptor: BridgeWorkerReviewContentRequestDescriptor,
	text: string,
): Awaited<BridgeProductContentStream<'review.content'>['terminal']> {
	return {
		bytes: new TextEncoder().encode(text).buffer,
		contentKind: 'review.content',
		descriptorId: descriptor.descriptorId,
		endOfSource: true,
		kind: 'complete',
		observedSha256: 'a'.repeat(64),
	};
}

async function* emptyReviewContentFrames(): AsyncIterable<never> {}

export function makeWorkerReviewContentMetadata(
	props: { readonly itemId?: string } = {},
): BridgeWorkerReviewContentMetadata {
	const itemId = props.itemId ?? 'item-1';
	return {
		itemId,
		path: `Sources/App/${itemId}.swift`,
		language: 'swift',
		cacheKey: `${itemId}:base|${itemId}:head`,
		sizeBytes: 1024,
		availableContentRoles: ['base', 'head'],
		contentLineCountsByRole: { base: 100, head: 80 },
	};
}

export function makeWorkerFileViewContentMetadata(): BridgeWorkerFileViewContentMetadata {
	return {
		metadataKind: 'fileView',
		itemId: 'file-1',
		path: 'Sources/App/file-1.swift',
		language: 'swift',
		cacheKey: 'file-view:metadata-cache:file-1',
		sizeBytes: 128,
		descriptorId: 'descriptor-file-1',
		contentHash: 'sha256:file-1',
		encoding: 'utf-8',
		endsMidLine: false,
		endsWithNewline: true,
		virtualizedExtentKind: 'exactLineCount',
		payloadByteCount: 128,
		payloadLineCount: 1,
		totalLineCount: 1,
		truncationKind: 'none',
		isBinary: false,
		canFetchContent: true,
	};
}

export function makeRenderSemantics(
	props: { readonly itemId?: string } = {},
): BridgeWorkerReviewRenderSemantics {
	const itemId = props.itemId ?? 'item-1';
	return {
		itemId,
		itemKind: 'diff',
		changeKind: 'modified',
		displayPath: `Sources/App/${itemId}.swift`,
		basePath: `Sources/App/${itemId}.swift`,
		headPath: `Sources/App/${itemId}.swift`,
		language: 'swift',
		contentLineCountsByRole: { base: 100, head: 80 },
	};
}

export function makeContentRequestDescriptor(props: {
	readonly generation?: number;
	readonly itemId?: string;
	readonly role: BridgeWorkerReviewContentRequestDescriptor['role'];
	readonly text: string;
}): BridgeWorkerReviewContentRequestDescriptor {
	const generation = props.generation ?? 4;
	const itemId = props.itemId ?? 'item-1';
	const textByteLength = new TextEncoder().encode(props.text).byteLength;
	const maximumBytes = Math.max(textByteLength, 1);
	const descriptor: BridgeWorkerReviewContentRequestDescriptor = {
		contentDigest: {
			algorithm: 'fixture-preview',
			authority: 'provisional',
			value: `sha256:${itemId}:${props.role}:generation-${generation}`,
		},
		contentKind: 'review.content',
		declaredByteLength: textByteLength,
		descriptorId: `descriptor-${itemId}-${props.role}-${generation}`,
		encoding: 'utf-8',
		endpointId: `endpoint-${itemId}`,
		expectedSha256: null,
		handleId: `handle-${itemId}-${props.role}`,
		isBinary: false,
		itemId,
		language: 'swift',
		maximumBytes,
		mimeType: 'text/plain',
		packageId: `package-${itemId}-${generation}`,
		reviewGeneration: generation,
		role: props.role,
		sourceIdentity: `source-${itemId}-${generation}`,
		wholeByteLength: textByteLength,
		window: { kind: 'byteRange', maximumBytes, startByte: 0 },
	};
	reviewContentFixtureByDescriptorId.set(descriptor.descriptorId, { itemId, text: props.text });
	return descriptor;
}

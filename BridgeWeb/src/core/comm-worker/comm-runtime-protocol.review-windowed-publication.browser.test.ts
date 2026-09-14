import { describe, expect, test } from 'vitest';

import { encodeBridgeWorkerActiveViewerModeUpdateCommand } from './bridge-comm-worker-protocol.js';
import { BRIDGE_PRODUCT_MAXIMUM_METADATA_FRAME_BYTES } from './bridge-product-contract-primitives.js';
import type { BridgeProductMetadataApplicationEvent } from './bridge-product-metadata-application-protocol.js';
import { bridgeProductReviewMetadataApplicationProtocol } from './bridge-product-metadata-application-registry.js';
import {
	bridgeProductReviewMetadataEventSchema,
	type BridgeProductReviewMetadataEvent,
} from './bridge-product-review-metadata-contracts.js';
import {
	type BridgeWorkerReviewDisplayPatchEvent,
	type BridgeWorkerServerToMainMessage,
} from './bridge-worker-contracts.js';
import { WindowedReviewWorkerHarness } from './test-fixtures/comm-runtime-protocol.review-windowed-publication.worker-harness.browser.test-support.js';
import type {
	WindowedReviewMetadataFrame,
	WindowedReviewMetadataInterestUpdate,
} from './test-fixtures/comm-runtime-protocol.review-windowed-publication.worker-test-fixture.js';

type ReviewMetadataProtocol = typeof bridgeProductReviewMetadataApplicationProtocol;
type ReviewMetadataEvent = BridgeProductMetadataApplicationEvent<ReviewMetadataProtocol>;
type ReviewMetadataFrame = WindowedReviewMetadataFrame;
type ReviewMetadataInterestUpdate = WindowedReviewMetadataInterestUpdate;
type ReviewPublicationPhase = 'beforeSource' | 'finalWindow' | 'partialWindows';

const reviewItemCount = 1_699;
const itemWindowSize = 32;
const treeWindowSize = 64;
const reviewIdentity = {
	generation: 1,
	operationCorrelationId: null,
	packageId: 'review-windowed-runtime-package',
	publicationId: '00000000-0000-7000-8000-000000001699',
	revision: 0,
	sourceIdentity: 'review-windowed-runtime-source',
} as const;
describe('Bridge comm worker windowed Review publication runtime', () => {
	test('publishes one complete 1,699-item candidate after every bounded window', async () => {
		// Arrange
		const harness = new WindowedReviewWorkerHarness();
		let publicationPhase: ReviewPublicationPhase = 'beforeSource';
		const interestUpdates: Array<{
			readonly phase: ReviewPublicationPhase;
			readonly update: ReviewMetadataInterestUpdate;
		}> = [];
		harness.onInterestUpdate = (update): void => {
			interestUpdates.push({ phase: publicationPhase, update });
		};

		try {
			await harness.installed;
			harness.worker.postMessage(
				activeReviewModeCommand({
					epoch: 1,
					requestId: 'windowed-review-mode-initial',
					sequence: 1,
				}),
			);
			await harness.waitForMessage(
				(message) =>
					message.kind === 'health' && message.requestId === 'windowed-review-mode-initial',
			);
			const publicationEvents = windowedReviewPublicationEvents();
			const metadataWindows = publicationEvents.slice(1);
			expect(metadataWindows).toHaveLength(Math.ceil(reviewItemCount / itemWindowSize));
			for (const event of metadataWindows) {
				if (event.eventKind !== 'review.snapshot' && event.eventKind !== 'review.window') {
					throw new Error('Expected only Review snapshot and window payloads after acceptance.');
				}
				expect(event.itemMetadata.length).toBeLessThanOrEqual(itemWindowSize);
				expect(event.treeRows.length).toBeLessThanOrEqual(treeWindowSize);
				expect(new TextEncoder().encode(JSON.stringify(event)).byteLength).toBeLessThanOrEqual(
					BRIDGE_PRODUCT_MAXIMUM_METADATA_FRAME_BYTES - 4_096,
				);
			}
			const sourceAcceptedFrame = reviewMetadataFrame(publicationEvents[0], 1);
			harness.publishMetadata(sourceAcceptedFrame);
			await harness.waitForMessage((message) => message.kind === 'reviewCandidateStarted');
			await harness.waitUntilProcessed(sourceAcceptedFrame.streamSequence);
			const finalEvent = publicationEvents.at(-1);
			if (finalEvent === undefined) throw new Error('Expected a final Review metadata window.');
			const partialEvents = publicationEvents.slice(1, -1);
			publicationPhase = 'partialWindows';
			let nextStreamSequence = 2;
			for (const event of partialEvents) {
				harness.publishMetadata(reviewMetadataFrame(event, nextStreamSequence));
				nextStreamSequence += 1;
			}
			await harness.waitUntilProcessed(nextStreamSequence - 1);
			harness.worker.postMessage(
				activeReviewModeCommand({
					epoch: 2,
					requestId: 'windowed-review-mode-barrier',
					sequence: 2,
				}),
			);
			await harness.waitForMessage(
				(message) =>
					message.kind === 'health' && message.requestId === 'windowed-review-mode-barrier',
			);

			// Assert — native-shaped partial windows remain an unpublished candidate.
			const observedMessages = harness.observedMessages;
			expect(messagesOfKind(observedMessages, 'reviewCandidateStarted')).toHaveLength(1);
			expect(messagesOfKind(observedMessages, 'reviewDisplayPatch')).toEqual([]);
			expect(messagesOfKind(observedMessages, 'reviewCandidateReady')).toEqual([]);
			expect(messagesOfKind(observedMessages, 'reviewCandidateFailed')).toEqual([]);
			expect(interestUpdates).toEqual([]);

			// Act — the final barrier must traverse the real mapper, store, display schema,
			// Worker structured clone, and candidate publication callbacks.
			publicationPhase = 'finalWindow';
			const finalFrame = reviewMetadataFrame(finalEvent, nextStreamSequence);
			harness.publishMetadata(finalFrame);
			await harness.waitForMessage((message) => message.kind === 'reviewCandidateReady');
			await harness.waitUntilProcessed(finalFrame.streamSequence);
			await harness.waitForInterestUpdate();

			// Assert
			const candidateStartedMessages = messagesOfKind(observedMessages, 'reviewCandidateStarted');
			const displayMessages = messagesOfKind(observedMessages, 'reviewDisplayPatch');
			const candidateReadyMessages = messagesOfKind(observedMessages, 'reviewCandidateReady');
			expect(candidateStartedMessages).toHaveLength(1);
			expect(displayMessages).toHaveLength(1);
			expect(candidateReadyMessages).toHaveLength(1);
			expect(messagesOfKind(observedMessages, 'reviewCandidateFailed')).toEqual([]);
			expect(
				observedMessages.filter(
					(message) => message.kind === 'health' && message.status === 'degraded',
				),
			).toEqual([]);
			expect(interestUpdates[0]).toEqual({
				phase: 'finalWindow',
				update: {
					interests: [
						{
							itemIds: Array.from(
								{ length: 9 },
								(_, itemIndex) => `item-git-diff-${sha256Fixture(itemIndex)}`,
							),
							lane: 'idle',
						},
					],
				},
			});
			expect(interestUpdates.every(({ phase }) => phase === 'finalWindow')).toBe(true);
			expect(candidateStartedMessages[0]).toMatchObject({
				packageId: reviewIdentity.packageId,
				publicationId: reviewIdentity.publicationId,
				reviewGeneration: reviewIdentity.generation,
				revision: reviewIdentity.revision,
				sourceIdentity: reviewIdentity.sourceIdentity,
			});
			expect(candidateReadyMessages[0]).toMatchObject({
				packageId: reviewIdentity.packageId,
				publicationId: reviewIdentity.publicationId,
				reviewGeneration: reviewIdentity.generation,
				revision: reviewIdentity.revision,
				sourceIdentity: reviewIdentity.sourceIdentity,
			});
			assertCompleteDisplayPublication(displayMessages[0]);
			const startedMessage = candidateStartedMessages[0];
			const displayMessage = displayMessages[0];
			const readyMessage = candidateReadyMessages[0];
			if (
				startedMessage === undefined ||
				displayMessage === undefined ||
				readyMessage === undefined
			) {
				throw new Error('Expected one started, display, and ready Review publication.');
			}
			const startedIndex = observedMessages.indexOf(startedMessage);
			const displayIndex = observedMessages.indexOf(displayMessage);
			const readyIndex = observedMessages.indexOf(readyMessage);
			expect(startedIndex).toBeLessThan(displayIndex);
			expect(displayIndex).toBeLessThan(readyIndex);
		} finally {
			harness.terminate();
		}
	});
});

function activeReviewModeCommand(props: {
	readonly epoch: number;
	readonly requestId: string;
	readonly sequence: number;
}): ReturnType<typeof encodeBridgeWorkerActiveViewerModeUpdateCommand> {
	return encodeBridgeWorkerActiveViewerModeUpdateCommand({
		epoch: props.epoch,
		requestId: props.requestId,
		update: {
			activeSource: null,
			mode: 'review',
			nativeSelectionRequestId: null,
			sequence: props.sequence,
			sessionId: 'windowed-review-runtime-session',
		},
	});
}

function windowedReviewPublicationEvents(): readonly ReviewMetadataEvent[] {
	const fixture = reviewFixture();
	const events: ReviewMetadataEvent[] = [
		bridgeProductReviewMetadataEventSchema.parse({
			...reviewIdentity,
			eventKind: 'review.sourceAccepted',
		}),
	];
	let itemStartIndex = 0;
	let treeStartIndex = 0;
	let isSnapshot = true;
	while (itemStartIndex < fixture.items.length || treeStartIndex < fixture.treeRows.length) {
		const itemMetadata = fixture.items.slice(itemStartIndex, itemStartIndex + itemWindowSize);
		const treeRows = fixture.treeRows.slice(treeStartIndex, treeStartIndex + treeWindowSize);
		const nextItemStartIndex = itemStartIndex + itemMetadata.length;
		const nextTreeStartIndex = treeStartIndex + treeRows.length;
		const finalWindow =
			nextItemStartIndex === fixture.items.length && nextTreeStartIndex === fixture.treeRows.length;
		const contentSources = itemMetadata.flatMap(
			(item) => fixture.contentSourcesByItemId.get(item.itemId) ?? [],
		);
		const common = {
			...reviewIdentity,
			contentSources,
			extentFacts: [],
			itemMetadata,
			itemWindow: {
				finalWindow: nextItemStartIndex === fixture.items.length,
				itemCount: itemMetadata.length,
				startIndex: itemStartIndex,
				totalItemCount: fixture.items.length,
			},
			summary: {
				additions: reviewItemCount,
				deletions: reviewItemCount,
				filesChanged: reviewItemCount,
				hiddenFileCount: 0,
				visibleFileCount: reviewItemCount,
			},
			treeRows,
			treeWindow: {
				finalWindow: nextTreeStartIndex === fixture.treeRows.length,
				rowCount: treeRows.length,
				startIndex: treeStartIndex,
				totalRowCount: fixture.treeRows.length,
			},
			...(finalWindow ? { presentationRevision: 1, reviewComparison: null } : {}),
		};
		events.push(
			bridgeProductReviewMetadataEventSchema.parse(
				isSnapshot
					? {
							...common,
							baseEndpoint: reviewEndpoint('base', 'gitRef'),
							eventKind: 'review.snapshot',
							headEndpoint: reviewEndpoint('head', 'workingTree'),
							query: reviewQuery(),
						}
					: { ...common, eventKind: 'review.window' },
			),
		);
		itemStartIndex = nextItemStartIndex;
		treeStartIndex = nextTreeStartIndex;
		isSnapshot = false;
	}
	return events;
}

function reviewFixture(): {
	readonly contentSourcesByItemId: ReadonlyMap<string, ReviewMetadataSnapshot['contentSources']>;
	readonly items: ReviewMetadataSnapshot['itemMetadata'];
	readonly treeRows: ReviewMetadataSnapshot['treeRows'];
} {
	const contentSourcesByItemId = new Map<string, ReviewMetadataEventContentSources>();
	const items: ReviewMetadataEventItems = [];
	const treeRows: ReviewMetadataEventTreeRows = [
		{
			depth: 0,
			isDirectory: true,
			itemId: null,
			lane: 'foreground',
			loadedBy: 'startup_window',
			path: 'nested',
			rowId: 'directory-nested',
		},
	];
	let currentGroup = -1;
	for (let itemIndex = 0; itemIndex < reviewItemCount; itemIndex += 1) {
		const groupIndex = Math.floor(itemIndex / 6);
		const groupName = `group-${String(groupIndex + 1).padStart(2, '0')}`;
		if (groupIndex !== currentGroup) {
			currentGroup = groupIndex;
			treeRows.push({
				depth: 1,
				isDirectory: true,
				itemId: null,
				lane: 'foreground',
				loadedBy: 'startup_window',
				path: `nested/${groupName}`,
				rowId: `directory-${groupName}`,
			});
		}
		const path = `nested/${groupName}/file-${String(itemIndex + 1).padStart(2, '0')}.ts`;
		const itemId = `item-git-diff-${sha256Fixture(itemIndex)}`;
		const baseDescriptorId = `descriptor-${itemIndex}-base`;
		const headDescriptorId = `descriptor-${itemIndex}-head`;
		const baseHash = sha256Fixture(itemIndex * 2);
		const headHash = sha256Fixture(itemIndex * 2 + 1);
		contentSourcesByItemId.set(itemId, [
			reviewContentSource({
				descriptorId: baseDescriptorId,
				hash: baseHash,
				itemId,
				role: 'base',
			}),
			reviewContentSource({
				descriptorId: headDescriptorId,
				hash: headHash,
				itemId,
				role: 'head',
			}),
		]);
		items.push({
			additions: 1,
			basePath: path,
			changeKind: 'modified',
			contentDescriptorIdsByRole: { base: baseDescriptorId, head: headDescriptorId },
			contentHashesByRole: { base: `sha256:${baseHash}`, head: `sha256:${headHash}` },
			contentRoles: ['base', 'head'],
			deletions: 1,
			extension: 'ts',
			fileClass: 'source',
			headPath: path,
			isHiddenByDefault: false,
			itemId,
			lane: 'foreground',
			language: 'typescript',
			loadedBy: 'startup_window',
			mimeTypes: ['text/typescript'],
			provenance: { agentSessionIds: [], operationIds: [], promptIds: [] },
			reviewPriority: 'normal',
			reviewState: 'unreviewed',
		});
		treeRows.push({
			depth: 2,
			isDirectory: false,
			itemId,
			lane: 'foreground',
			loadedBy: 'startup_window',
			path,
			rowId: itemId,
		});
	}
	return { contentSourcesByItemId, items, treeRows };
}

type ReviewMetadataSnapshot = Extract<
	BridgeProductReviewMetadataEvent,
	{ readonly eventKind: 'review.snapshot' }
>;
type ReviewMetadataEventContentSources = ReviewMetadataSnapshot['contentSources'][number][];
type ReviewMetadataEventItems = ReviewMetadataSnapshot['itemMetadata'][number][];
type ReviewMetadataEventTreeRows = ReviewMetadataSnapshot['treeRows'][number][];
type ReviewSourceDisplayPatch = Extract<
	BridgeWorkerReviewDisplayPatchEvent['patches'][number],
	{ readonly operation: 'upsert'; readonly slice: 'reviewSource' }
>;
type ReviewItemDisplayPatch = Extract<
	BridgeWorkerReviewDisplayPatchEvent['patches'][number],
	{ readonly operation: 'batch'; readonly slice: 'reviewItem' }
>;
type ReviewTreeDisplayPatch = Extract<
	BridgeWorkerReviewDisplayPatchEvent['patches'][number],
	{ readonly operation: 'batch'; readonly slice: 'reviewTree' }
>;

function reviewContentSource(props: {
	readonly descriptorId: string;
	readonly hash: string;
	readonly itemId: string;
	readonly role: 'base' | 'head';
}): ReviewMetadataEventContentSources[number] {
	return {
		contentDigest: { algorithm: 'sha256', authority: 'authoritative', value: props.hash },
		contentKind: 'review.content',
		descriptorId: props.descriptorId,
		encoding: 'utf-8',
		endpointId: props.role,
		handleId: `handle-${props.descriptorId}`,
		isBinary: false,
		itemId: props.itemId,
		language: 'typescript',
		mimeType: 'text/typescript',
		packageId: reviewIdentity.packageId,
		reviewGeneration: reviewIdentity.generation,
		role: props.role,
		sourceIdentity: reviewIdentity.sourceIdentity,
		wholeByteLength: 154,
	};
}

function reviewEndpoint(
	endpointId: 'base' | 'head',
	kind: 'gitRef' | 'workingTree',
): ReviewMetadataSnapshot['baseEndpoint'] {
	return {
		createdAtUnixMilliseconds: 1,
		endpointId,
		kind,
		label: endpointId,
		providerIdentity: `${endpointId}-provider`,
		repoId: '00000000-0000-4000-8000-000000000001',
		worktreeId: '00000000-0000-4000-8000-000000000002',
	};
}

function reviewQuery(): ReviewMetadataSnapshot['query'] {
	return {
		baseEndpointId: 'base',
		comparisonSemantics: 'threeDot',
		fileTarget: null,
		grouping: { kind: 'folder' },
		headEndpointId: 'head',
		pathScope: [],
		provenanceFilter: {
			agentSessionIds: [],
			operationIds: [],
			paneIds: [],
			promptIds: [],
			sourceKinds: [],
		},
		queryId: 'review-windowed-runtime-query',
		queryKind: 'compare',
		repoId: '00000000-0000-4000-8000-000000000001',
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
		worktreeId: '00000000-0000-4000-8000-000000000002',
	};
}

function reviewMetadataFrame(
	event: ReviewMetadataEvent | undefined,
	streamSequence: number,
): ReviewMetadataFrame {
	if (event === undefined) throw new Error('Expected Review metadata event.');
	return {
		data: event,
		metadataStreamId: 'review-windowed-runtime-stream',
		operationCorrelationId: event.operationCorrelationId,
		sourceGeneration: event.generation,
		streamSequence,
		subscriptionId: 'review-windowed-runtime-subscription',
		subscriptionKind: 'review.metadata',
		subscriptionSequence: streamSequence,
		workerDerivationEpoch: 1,
	} satisfies ReviewMetadataFrame;
}

function assertCompleteDisplayPublication(
	displayMessage: BridgeWorkerReviewDisplayPatchEvent | undefined,
): void {
	if (displayMessage === undefined) throw new Error('Expected one Review display publication.');
	const sourcePatch = displayMessage.patches.find(
		(patch): patch is ReviewSourceDisplayPatch =>
			patch.slice === 'reviewSource' && patch.operation === 'upsert',
	);
	const itemPatch = displayMessage.patches.find(
		(patch): patch is ReviewItemDisplayPatch =>
			patch.slice === 'reviewItem' && patch.operation === 'batch',
	);
	const treePatch = displayMessage.patches.find(
		(patch): patch is ReviewTreeDisplayPatch =>
			patch.slice === 'reviewTree' && patch.operation === 'batch',
	);
	expect(displayMessage.reviewPublicationIdentity).toEqual({
		packageId: reviewIdentity.packageId,
		publicationId: reviewIdentity.publicationId,
		reviewGeneration: reviewIdentity.generation,
		revision: reviewIdentity.revision,
		sourceIdentity: reviewIdentity.sourceIdentity,
	});
	expect(sourcePatch?.payload).toMatchObject({
		totalItemCount: reviewItemCount,
		totalTreeRowCount: reviewItemCount + Math.ceil(reviewItemCount / 6) + 1,
	});
	expect(itemPatch?.payload.items).toHaveLength(reviewItemCount);
	expect(itemPatch?.payload.reset).toBe(true);
	expect(treePatch?.payload.windows).toHaveLength(1);
	expect(treePatch?.payload.windows[0]?.rows).toHaveLength(
		reviewItemCount + Math.ceil(reviewItemCount / 6) + 1,
	);
}

function messagesOfKind<TKind extends BridgeWorkerServerToMainMessage['kind']>(
	messages: readonly BridgeWorkerServerToMainMessage[],
	kind: TKind,
): Array<Extract<BridgeWorkerServerToMainMessage, { readonly kind: TKind }>> {
	return messages.filter(
		(message): message is Extract<BridgeWorkerServerToMainMessage, { readonly kind: TKind }> =>
			message.kind === kind,
	);
}

function sha256Fixture(value: number): string {
	return value.toString(16).padStart(64, '0');
}

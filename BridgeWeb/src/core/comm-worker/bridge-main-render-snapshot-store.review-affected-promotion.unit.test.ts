import { describe, expect, test, vi } from 'vitest';

import {
	createBridgeMainRenderSnapshotStore,
	type BridgeMainCodeViewItem,
	type BridgeMainReviewPublicationIdentity,
} from './bridge-main-render-snapshot-store.js';
import {
	BRIDGE_WORKER_WIRE_VERSION,
	type BridgeWorkerReviewDisplayItem,
	type BridgeWorkerReviewDisplayPatchEvent,
} from './bridge-worker-contracts.js';
import { bridgeWorkerReviewSourceContext } from './bridge-worker-review-display.test-support.js';

describe('Bridge main render snapshot store Review affected promotion', () => {
	test('promotes one same-source change through a 4,096-item catalog with keyed notifications', () => {
		// Arrange
		const itemCount = 4_096;
		const windowItemCount = 64;
		const changedItemIndex = 2_048;
		const changedItemId = largeReviewItemId(changedItemIndex);
		const unchangedItemId = largeReviewItemId(changedItemIndex + 1);
		const activeIdentity = sameSourceReviewIdentity(1, '41');
		const candidateIdentity = sameSourceReviewIdentity(2, '42');
		const store = createBridgeMainRenderSnapshotStore();
		expect(
			store.startReviewCandidate({
				disposition: { kind: 'replacement' },
				identity: activeIdentity,
			}),
		).toBe(true);
		for (let startIndex = 0; startIndex < itemCount; startIndex += windowItemCount) {
			const itemIds = Array.from(
				{ length: Math.min(windowItemCount, itemCount - startIndex) },
				(_, itemOffset) => largeReviewItemId(startIndex + itemOffset),
			);
			expect(
				store.stageReviewCandidateDisplayEvent({
					event: largeReviewDisplayEvent({
						identity: activeIdentity,
						itemCount,
						itemIds,
						projectionRevision: startIndex / windowItemCount + 1,
						reset: startIndex === 0,
						startIndex,
					}),
					identity: activeIdentity,
				}),
			).toBe(true);
		}
		expect(store.markReviewCandidateReady({ identity: activeIdentity, role: 'provisional' })).toBe(
			true,
		);
		expect(store.promoteReviewCandidate(activeIdentity)).toBe(true);
		const changedCodeViewItem = reviewCodeViewItem(changedItemId, `${changedItemId}.ts`);
		const unchangedCodeViewItem = reviewCodeViewItem(unchangedItemId, `${unchangedItemId}.ts`);
		store.setWorkerCodeViewItem({ item: changedCodeViewItem, itemId: changedItemId });
		store.setWorkerCodeViewItem({ item: unchangedCodeViewItem, itemId: unchangedItemId });
		for (const itemId of [changedItemId, unchangedItemId]) {
			store.applyWorkerPatch({
				itemId,
				operation: 'upsert',
				payload: { state: 'ready' },
				slice: 'contentAvailability',
			});
		}
		const changedItemListener = vi.fn();
		const unchangedItemListener = vi.fn();
		const changedCodeViewListener = vi.fn();
		const unchangedCodeViewListener = vi.fn();
		store.subscribeReviewItem(changedItemId, changedItemListener);
		store.subscribeReviewItem(unchangedItemId, unchangedItemListener);
		store.subscribeReviewCodeViewItem(changedItemId, changedCodeViewListener);
		store.subscribeReviewCodeViewItem(unchangedItemId, unchangedCodeViewListener);
		const catalogCursorBeforePromotion = store.getReviewCatalogSnapshot().changeCursor;
		startCandidate(store, candidateIdentity, [changedItemId]);
		expect(
			store.stageReviewCandidateDisplayEvent({
				event: largeReviewDisplayEvent({
					contentRevision: 'changed',
					identity: candidateIdentity,
					itemCount,
					itemIds: [changedItemId],
					projectionRevision: itemCount / windowItemCount + 1,
					reset: false,
					startIndex: null,
				}),
				identity: candidateIdentity,
			}),
		).toBe(true);
		expect(
			store.markReviewCandidateReady({ identity: candidateIdentity, role: 'provisional' }),
		).toBe(true);

		// Act
		expect(store.promoteReviewCandidate(candidateIdentity)).toBe(true);

		// Assert
		expect(store.readReviewCatalogChangesAfter(catalogCursorBeforePromotion)).toEqual({
			changes: [
				{
					cursor: catalogCursorBeforePromotion + 1,
					itemIds: [changedItemId],
					itemOrderMutations: [],
					reset: false,
					treeRowIds: [],
					treeRowOrderMutations: [],
				},
			],
			resetRequired: false,
		});
		expect(changedItemListener).toHaveBeenCalledTimes(1);
		expect(unchangedItemListener).not.toHaveBeenCalled();
		expect(changedCodeViewListener).toHaveBeenCalledTimes(1);
		expect(unchangedCodeViewListener).not.toHaveBeenCalled();
		expect(store.getReviewCodeViewItemSnapshot(changedItemId)).toBeUndefined();
		expect(store.getReviewCodeViewItemSnapshot(unchangedItemId)).toBe(unchangedCodeViewItem);
		expect(store.getReviewCodeViewItemSnapshot(unchangedItemId)?.version).toBe(
			unchangedCodeViewItem.version,
		);
	});

	test('preserves same-source item and tree order mutations through promotion', () => {
		// Arrange
		const activeIdentity = sameSourceReviewIdentity(1, '51');
		const candidateIdentity = sameSourceReviewIdentity(2, '52');
		const store = createBridgeMainRenderSnapshotStore();
		installReview(
			store,
			activeIdentity,
			largeReviewDisplayEvent({
				identity: activeIdentity,
				itemCount: 1,
				itemIds: ['ordered-item-a'],
				projectionRevision: 1,
				reset: true,
				startIndex: 0,
			}),
		);
		const catalogCursorBeforePromotion = store.getReviewCatalogSnapshot().changeCursor;
		startCandidate(store, candidateIdentity, ['ordered-item-b']);
		expect(
			store.stageReviewCandidateDisplayEvent({
				event: largeReviewDisplayEvent({
					identity: candidateIdentity,
					itemCount: 2,
					itemIds: ['ordered-item-b'],
					projectionRevision: 2,
					reset: false,
					startIndex: 1,
				}),
				identity: candidateIdentity,
			}),
		).toBe(true);
		expect(
			store.markReviewCandidateReady({ identity: candidateIdentity, role: 'provisional' }),
		).toBe(true);

		// Act
		expect(store.promoteReviewCandidate(candidateIdentity)).toBe(true);

		// Assert
		expect(store.readReviewCatalogChangesAfter(catalogCursorBeforePromotion)).toEqual({
			changes: [
				{
					cursor: catalogCursorBeforePromotion + 1,
					itemIds: ['ordered-item-b'],
					itemOrderMutations: [{ kind: 'setRange', length: 1, startIndex: 1 }],
					reset: false,
					treeRowIds: ['row-ordered-item-b'],
					treeRowOrderMutations: [{ kind: 'setRange', length: 1, startIndex: 1 }],
				},
			],
			resetRequired: false,
		});
		expect(store.getReviewItemIdAtIndex(1)).toBe('ordered-item-b');
		expect(store.getReviewTreeRowAtIndex(1)?.itemId).toBe('ordered-item-b');
	});

	test('treats promoted unknown affectedness as a complete promotion', () => {
		// Arrange
		const activeIdentity = sameSourceReviewIdentity(1, '61');
		const candidateIdentity = sameSourceReviewIdentity(2, '62');
		const store = createBridgeMainRenderSnapshotStore();
		installReview(
			store,
			activeIdentity,
			largeReviewDisplayEvent({
				identity: activeIdentity,
				itemCount: 2,
				itemIds: ['unknown-item-a', 'unknown-item-b'],
				projectionRevision: 1,
				reset: true,
				startIndex: 0,
			}),
		);
		const firstItemListener = vi.fn();
		const secondItemListener = vi.fn();
		store.subscribeReviewItem('unknown-item-a', firstItemListener);
		store.subscribeReviewItem('unknown-item-b', secondItemListener);
		const catalogCursorBeforePromotion = store.getReviewCatalogSnapshot().changeCursor;
		expect(
			store.startReviewCandidate({
				disposition: {
					affectedStableFileIdentities: [],
					kind: 'sameSource',
					presentationClass: { kind: 'promoted', reason: 'unknown' },
				},
				identity: candidateIdentity,
			}),
		).toBe(true);
		expect(
			store.stageReviewCandidateDisplayEvent({
				event: largeReviewDisplayEvent({
					contentRevision: 'changed',
					identity: candidateIdentity,
					itemCount: 2,
					itemIds: ['unknown-item-a'],
					projectionRevision: 2,
					reset: false,
					startIndex: null,
				}),
				identity: candidateIdentity,
			}),
		).toBe(true);
		expect(
			store.markReviewCandidateReady({ identity: candidateIdentity, role: 'provisional' }),
		).toBe(true);

		// Act
		expect(store.promoteReviewCandidate(candidateIdentity)).toBe(true);

		// Assert
		expect(store.readReviewCatalogChangesAfter(catalogCursorBeforePromotion)).toMatchObject({
			changes: [
				{
					itemIds: ['unknown-item-a', 'unknown-item-b'],
					reset: true,
				},
			],
			resetRequired: false,
		});
		expect(firstItemListener).toHaveBeenCalledTimes(1);
		expect(secondItemListener).toHaveBeenCalledTimes(1);
	});
});

function installReview(
	store: ReturnType<typeof createBridgeMainRenderSnapshotStore>,
	identity: BridgeMainReviewPublicationIdentity,
	event: BridgeWorkerReviewDisplayPatchEvent,
): void {
	expect(store.startReviewCandidate({ disposition: { kind: 'replacement' }, identity })).toBe(true);
	expect(store.stageReviewCandidateDisplayEvent({ event, identity })).toBe(true);
	expect(store.markReviewCandidateReady({ identity, role: 'provisional' })).toBe(true);
	expect(store.promoteReviewCandidate(identity)).toBe(true);
}

function startCandidate(
	store: ReturnType<typeof createBridgeMainRenderSnapshotStore>,
	identity: BridgeMainReviewPublicationIdentity,
	affectedStableFileIdentities: readonly string[],
): void {
	expect(
		store.startReviewCandidate({
			disposition: {
				affectedStableFileIdentities,
				kind: 'sameSource',
				presentationClass: { kind: 'ordinary' },
			},
			identity,
		}),
	).toBe(true);
}

function largeReviewItemId(itemIndex: number): string {
	return `large-review-item-${itemIndex.toString().padStart(4, '0')}`;
}

function sameSourceReviewIdentity(
	revision: number,
	publicationLabel: string,
): BridgeMainReviewPublicationIdentity {
	return {
		generation: 41,
		packageId: 'large-review-package',
		publicationId: publicationId(publicationLabel),
		revision,
		sourceIdentity: 'large-review-source',
	};
}

function publicationId(suffix: string): string {
	return `00000000-0000-7000-8000-${suffix.padStart(12, '0')}`;
}

function largeReviewDisplayEvent(props: {
	readonly contentRevision?: 'changed';
	readonly identity: BridgeMainReviewPublicationIdentity;
	readonly itemCount: number;
	readonly itemIds: readonly string[];
	readonly projectionRevision: number;
	readonly reset: boolean;
	readonly startIndex: number | null;
}): BridgeWorkerReviewDisplayPatchEvent {
	return {
		direction: 'serverWorkerToMain',
		epoch: 1,
		kind: 'reviewDisplayPatch',
		patches: [
			{
				operation: 'upsert',
				payload: {
					...bridgeWorkerReviewSourceContext(props.identity.packageId),
					metadataSourceId: props.identity.sourceIdentity,
					metadataWindowIdentity: `large-window-${props.identity.publicationId}`,
					packageId: props.identity.packageId,
					reviewGeneration: props.identity.generation,
					revision: props.identity.revision,
					status: 'ready',
					summary: {
						additions: 1,
						deletions: 1,
						filesChanged: props.itemCount,
						hiddenFileCount: 0,
						visibleFileCount: props.itemCount,
					},
					totalItemCount: props.itemCount,
					totalTreeRowCount: props.itemCount,
				},
				slice: 'reviewSource',
			},
			{
				operation: 'batch',
				payload: {
					items: props.itemIds.map((itemId) =>
						largeReviewDisplayItem(itemId, props.contentRevision),
					),
					operations: [],
					reset: props.reset,
					startIndex: props.startIndex,
				},
				slice: 'reviewItem',
			},
			...(props.startIndex === null
				? []
				: [
						{
							operation: 'batch' as const,
							payload: {
								reset: props.reset,
								windows: [
									{
										rows: props.itemIds.map((itemId) => ({
											depth: 0,
											isDirectory: false,
											itemId,
											path: `${itemId}.ts`,
											rowId: `row-${itemId}`,
										})),
										startIndex: props.startIndex,
									},
								],
							},
							slice: 'reviewTree' as const,
						},
					]),
		],
		projectionRevision: props.projectionRevision,
		reviewPublicationIdentity: {
			packageId: props.identity.packageId,
			publicationId: props.identity.publicationId,
			reviewGeneration: props.identity.generation,
			revision: props.identity.revision,
			sourceIdentity: props.identity.sourceIdentity,
		},
		sequence: props.projectionRevision,
		surface: 'review',
		transferDescriptors: [],
		wireVersion: BRIDGE_WORKER_WIRE_VERSION,
	};
}

function largeReviewDisplayItem(
	itemId: string,
	contentRevision?: 'changed',
): BridgeWorkerReviewDisplayItem {
	const activeItem = reviewDisplayItem(itemId);
	return {
		...activeItem,
		contentFacts: [
			{
				contentDigest: {
					algorithm: 'sha256',
					authority: 'authoritative',
					value: (contentRevision === 'changed' ? 'b' : 'a').repeat(64),
				},
				role: 'head',
				semanticDocumentRevision: `${itemId}:${contentRevision ?? 'active'}`,
			},
		],
		metadata: {
			...activeItem.metadata,
			contentDescriptorIdsByRole: { head: `descriptor-${itemId}-${contentRevision ?? 'active'}` },
			contentHashesByRole: { head: (contentRevision === 'changed' ? 'b' : 'a').repeat(64) },
			contentRoles: ['head'],
		},
		metadataWindowIdentity: `window-${itemId}-${contentRevision ?? 'active'}`,
	};
}

function reviewDisplayItem(itemId: string): BridgeWorkerReviewDisplayItem {
	return {
		contentFacts: [],
		extentFacts: [],
		metadata: {
			additions: 1,
			basePath: `${itemId}.ts`,
			changeKind: 'modified',
			contentDescriptorIdsByRole: {},
			contentHashesByRole: {},
			contentRoles: [],
			deletions: 1,
			extension: 'ts',
			fileClass: 'source',
			headPath: `${itemId}.ts`,
			isHiddenByDefault: false,
			itemId,
			language: 'typescript',
			mimeTypes: ['text/typescript'],
			provenance: { agentSessionIds: [], operationIds: [], promptIds: [] },
			reviewPriority: 'normal',
			reviewState: 'unreviewed',
		},
		metadataWindowIdentity: `window-${itemId}`,
	};
}

function reviewCodeViewItem(itemId: string, displayPath: string): BridgeMainCodeViewItem {
	return {
		bridgeMetadata: {
			cacheKey: `cache-${itemId}`,
			contentRoles: ['head'],
			contentState: 'hydrated',
			displayPath,
			itemId,
			lineCount: 1,
		},
		file: { cacheKey: `cache-${itemId}`, contents: 'export {};', name: displayPath },
		id: itemId,
		type: 'file',
	};
}

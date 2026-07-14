import { describe, expect, test } from 'vitest';

import { bridgeCommWorkerReviewDisplayPatches } from './bridge-comm-worker-review-display-projection.js';
import type {
	BridgeCommWorkerReviewMetadataApplyResult,
	BridgeCommWorkerReviewMetadataSnapshot,
} from './bridge-comm-worker-review-metadata-projection.js';
import type { BridgeProductReviewContentSourceDescriptor } from './bridge-product-content-contracts.js';
import type {
	BridgeProductReviewExtentFact,
	BridgeProductReviewItemMetadata,
	BridgeProductReviewMetadataEvent,
} from './bridge-product-review-metadata-contracts.js';

type ReviewDeltaEvent = Extract<
	BridgeProductReviewMetadataEvent,
	{ readonly eventKind: 'review.delta' }
>;

describe('Bridge comm worker Review display projection', () => {
	test('preserves Review delta operations in canonical source order', () => {
		// Arrange
		const firstItem = reviewItemMetadata(0);
		const secondItem = reviewItemMetadata(1);
		const operations: ReviewDeltaEvent['operations'] = [
			{ itemIds: [firstItem.itemId], operationKind: 'removeItems' },
			{
				itemIds: [secondItem.itemId, firstItem.itemId],
				operationKind: 'replaceItemOrder',
			},
			{ itemIds: [secondItem.itemId], operationKind: 'removeItems' },
			{ itemIds: [firstItem.itemId], operationKind: 'replaceItemOrder' },
		];
		const event: ReviewDeltaEvent = {
			...reviewIdentity,
			contentSources: [],
			eventKind: 'review.delta',
			fromRevision: 11,
			operations,
			revision: 12,
			summary: reviewSummary(1),
			toRevision: 12,
		};
		const snapshot: BridgeCommWorkerReviewMetadataSnapshot = {
			baseEndpoint: reviewEndpoint('base', 'gitRef'),
			contentSources: [reviewContentSource(firstItem)],
			extentFacts: [reviewExtentFact(firstItem)],
			headEndpoint: reviewEndpoint('head', 'workingTree'),
			identity: reviewIdentity,
			itemMetadata: [firstItem],
			orderedItemIds: [firstItem.itemId],
			query: reviewQuery(),
			revision: 12,
			summary: reviewSummary(1),
			totalItemCount: 1,
			totalTreeRowCount: 0,
			treeRows: [],
		};

		// Act
		const patches = bridgeCommWorkerReviewDisplayPatches({
			event,
			projectionResult: {
				affectedItemIds: [firstItem.itemId, secondItem.itemId],
				invalidation: null,
				projectionRevision: 12,
				reset: false,
			},
			snapshot,
			sourceStatus: 'ready',
		});

		// Assert
		expect(reviewDisplayOperationKinds(patches)).toEqual(
			operations.map((operation) => operation.operationKind),
		);
	});

	test('projects a large snapshot with touched-key work bounded to one linear scan', () => {
		// Arrange
		const totalItemCount = 4_096;
		const touchedItemCount = 64;
		const itemMetadata = Array.from({ length: totalItemCount }, (_, index) =>
			reviewItemMetadata(index),
		);
		const firstItem = itemMetadata[0];
		if (firstItem === undefined) throw new Error('Expected a large Review fixture.');
		const contentSources = [
			...itemMetadata.map(reviewContentSource),
			{ ...reviewContentSource(firstItem), descriptorId: 'descriptor-unreferenced' },
		];
		const extentFacts = itemMetadata.map(reviewExtentFact);
		const countedItemMetadata = countArrayIndexReads(itemMetadata);
		const countedContentSources = countArrayIndexReads(contentSources);
		const countedExtentFacts = countArrayIndexReads(extentFacts);
		const touchedItems = itemMetadata.slice(0, touchedItemCount);
		const event: ReviewDeltaEvent = {
			...reviewIdentity,
			contentSources: [],
			eventKind: 'review.delta',
			fromRevision: 11,
			operations: touchedItems.map((item) => ({ item, operationKind: 'upsertItem' })),
			revision: 12,
			summary: reviewSummary(totalItemCount),
			toRevision: 12,
		};
		const projectionResult: BridgeCommWorkerReviewMetadataApplyResult = {
			affectedItemIds: touchedItems.map((item) => item.itemId),
			invalidation: null,
			projectionRevision: 12,
			reset: false,
		};
		const snapshot: BridgeCommWorkerReviewMetadataSnapshot = {
			baseEndpoint: reviewEndpoint('base', 'gitRef'),
			contentSources: countedContentSources.values,
			extentFacts: countedExtentFacts.values,
			headEndpoint: reviewEndpoint('head', 'workingTree'),
			identity: {
				generation: reviewIdentity.generation,
				packageId: reviewIdentity.packageId,
				sourceIdentity: reviewIdentity.sourceIdentity,
			},
			itemMetadata: countedItemMetadata.values,
			orderedItemIds: itemMetadata.map((item) => item.itemId),
			query: reviewQuery(),
			revision: 12,
			summary: reviewSummary(totalItemCount),
			totalItemCount,
			totalTreeRowCount: 0,
			treeRows: [],
		};

		// Act
		const patches = bridgeCommWorkerReviewDisplayPatches({
			event,
			projectionResult,
			snapshot,
			sourceStatus: 'ready',
		});

		// Assert
		const itemPatch = patches.find(
			(patch) => patch.slice === 'reviewItem' && patch.operation === 'batch',
		);
		if (itemPatch?.slice !== 'reviewItem' || itemPatch.operation !== 'batch') {
			throw new Error('Expected Review item display patch.');
		}
		expect(itemPatch.payload.items.map((item) => item.metadata.itemId)).toEqual(
			touchedItems.map((item) => item.itemId),
		);
		const firstProjectedItem = itemPatch.payload.items[0] as unknown;
		if (!isReadonlyRecord(firstProjectedItem)) {
			throw new Error('Expected the first Review display item.');
		}
		expect(firstProjectedItem['contentFacts']).toEqual([
			{
				contentDigest: reviewContentSource(firstItem).contentDigest,
				role: 'head',
				semanticDocumentRevision: expect.stringMatching(/\S/u),
			},
		]);
		expect(firstProjectedItem['metadataWindowIdentity']).toEqual(expect.stringMatching(/\S/u));
		expect(firstProjectedItem).not.toHaveProperty('contentSources');
		expect(firstProjectedItem).not.toHaveProperty('windowKey');
		const totalArrayIndexReads =
			countedItemMetadata.readCount() +
			countedContentSources.readCount() +
			countedExtentFacts.readCount();
		expect(countedItemMetadata.readCount()).toBeLessThanOrEqual(totalItemCount + 1);
		expect(countedContentSources.readCount()).toBeLessThanOrEqual(totalItemCount + 2);
		expect(countedExtentFacts.readCount()).toBeLessThanOrEqual(totalItemCount + 1);
		expect(totalArrayIndexReads).toBeLessThan(totalItemCount * 4);
		expect(totalArrayIndexReads).toBeLessThan(totalItemCount * touchedItemCount);
	});
});

function reviewDisplayOperationKinds(patches: readonly unknown[]): readonly string[] {
	return patches.flatMap((patch): readonly string[] => {
		if (!isReadonlyRecord(patch) || !isReadonlyRecord(patch['payload'])) return [];
		const operations = patch['payload']['operations'];
		if (!Array.isArray(operations)) return [];
		return operations.flatMap((operation): readonly string[] => {
			if (!isReadonlyRecord(operation) || typeof operation['operationKind'] !== 'string') {
				return [];
			}
			return [operation['operationKind']];
		});
	});
}

function isReadonlyRecord(value: unknown): value is Readonly<Record<string, unknown>> {
	return typeof value === 'object' && value !== null;
}

interface CountedArray<TValue> {
	readonly readCount: () => number;
	readonly values: readonly TValue[];
}

function countArrayIndexReads<TValue>(values: readonly TValue[]): CountedArray<TValue> {
	let readCount = 0;
	const countedValues = new Proxy([...values], {
		get: (target, property, receiver): unknown => {
			const numericProperty = typeof property === 'string' ? Number(property) : Number.NaN;
			if (Number.isInteger(numericProperty) && numericProperty >= 0) readCount += 1;
			return Reflect.get(target, property, receiver);
		},
	});
	return {
		readCount: (): number => readCount,
		values: countedValues,
	};
}

const reviewIdentity = {
	generation: 7,
	packageId: 'package-1',
	sourceIdentity: 'source-1',
} as const;

function reviewItemMetadata(index: number): BridgeProductReviewItemMetadata {
	const itemId = `item-${index.toString().padStart(4, '0')}`;
	const path = `Sources/${itemId}.swift`;
	return {
		basePath: path,
		changeKind: 'modified',
		contentDescriptorIdsByRole: { head: `descriptor-${itemId}` },
		contentHashesByRole: { head: 'a'.repeat(64) },
		contentRoles: ['head'],
		extension: 'swift',
		fileClass: 'source',
		headPath: path,
		isHiddenByDefault: false,
		itemId,
		language: 'swift',
		mimeTypes: ['text/plain'],
		provenance: { agentSessionIds: [], operationIds: [], promptIds: [] },
		reviewPriority: 'normal',
		reviewState: 'unreviewed',
	};
}

function reviewContentSource(
	item: BridgeProductReviewItemMetadata,
): BridgeProductReviewContentSourceDescriptor {
	return {
		contentDigest: { algorithm: 'sha256', authority: 'authoritative', value: 'a'.repeat(64) },
		contentKind: 'review.content',
		descriptorId: `descriptor-${item.itemId}`,
		encoding: 'utf-8',
		endpointId: 'head',
		handleId: `handle-${item.itemId}`,
		isBinary: false,
		itemId: item.itemId,
		language: 'swift',
		mimeType: 'text/plain',
		packageId: reviewIdentity.packageId,
		reviewGeneration: reviewIdentity.generation,
		role: 'head',
		sourceIdentity: reviewIdentity.sourceIdentity,
		wholeByteLength: 128,
	};
}

function reviewExtentFact(item: BridgeProductReviewItemMetadata): BridgeProductReviewExtentFact {
	return { contentRole: 'head', itemId: item.itemId, lineCount: 4 };
}

function reviewEndpoint(
	endpointId: string,
	kind: 'gitRef' | 'workingTree',
): NonNullable<BridgeCommWorkerReviewMetadataSnapshot['baseEndpoint']> {
	return {
		createdAtUnixMilliseconds: 1,
		endpointId,
		kind,
		label: endpointId,
		providerIdentity: endpointId,
		repoId: 'repo-1',
		worktreeId: 'worktree-1',
	};
}

function reviewQuery(): NonNullable<BridgeCommWorkerReviewMetadataSnapshot['query']> {
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
		queryId: 'query-1',
		queryKind: 'compare',
		repoId: 'repo-1',
		viewFilter: {
			changeKinds: [],
			excludedExtensions: [],
			excludedFileClasses: [],
			excludedPathGlobs: [],
			includedExtensions: [],
			includedFileClasses: [],
			includedPathGlobs: [],
			reviewStates: [],
			showBinaryFiles: false,
			showHiddenFiles: false,
			showLargeFiles: false,
		},
		worktreeId: 'worktree-1',
	};
}

function reviewSummary(
	totalItemCount: number,
): NonNullable<BridgeCommWorkerReviewMetadataSnapshot['summary']> {
	return {
		additions: totalItemCount,
		deletions: 0,
		filesChanged: totalItemCount,
		hiddenFileCount: 0,
		visibleFileCount: totalItemCount,
	};
}

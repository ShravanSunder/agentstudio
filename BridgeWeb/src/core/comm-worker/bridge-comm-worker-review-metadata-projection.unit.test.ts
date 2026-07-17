import { describe, expect, test } from 'vitest';

import { BridgeCommWorkerReviewMetadataProjection } from './bridge-comm-worker-review-metadata-projection.js';
import type { BridgeProductReviewContentSourceDescriptor } from './bridge-product-content-contracts.js';
import type {
	BridgeProductReviewItemMetadata,
	BridgeProductReviewMetadataEvent,
	BridgeProductReviewTreeRow,
} from './bridge-product-review-metadata-contracts.js';

type ReviewSnapshotEvent = Extract<
	BridgeProductReviewMetadataEvent,
	{ readonly eventKind: 'review.snapshot' }
>;

describe('Bridge comm worker Review metadata projection', () => {
	test('assembles ordered snapshot windows without a main-thread package owner', () => {
		// Arrange
		const projection = new BridgeCommWorkerReviewMetadataProjection();
		projection.apply(reviewSourceAccepted());

		// Act
		const firstResult = projection.apply(reviewSnapshot());
		const finalResult = projection.apply(
			reviewWindow({ itemId: 'item-2', itemStartIndex: 1, rowId: 'row-2', treeStartIndex: 1 }),
		);

		// Assert
		expect(firstResult).toMatchObject({ affectedItemIds: ['item-1'], reset: true });
		expect(finalResult).toMatchObject({ affectedItemIds: ['item-2'], reset: false });
		expect(projection.snapshot()).toMatchObject({
			identity: {
				generation: 7,
				packageId: 'package-1',
				publicationId: '00000000-0000-7000-8000-000000000011',
				sourceIdentity: 'source-1',
			},
			orderedItemIds: ['item-1', 'item-2'],
			totalItemCount: 2,
			totalTreeRowCount: 2,
		});
		expect(projection.snapshot().treeRows.map((row) => row.rowId)).toEqual(['row-1', 'row-2']);
		expect(() =>
			projection.apply(
				reviewWindow({ itemId: 'item-2', itemStartIndex: 0, rowId: 'row-2', treeStartIndex: 0 }),
			),
		).toThrow(/ordered identity/i);
	});

	test('applies typed deltas and rejects ambiguous or stale state transitions', () => {
		// Arrange
		const projection = new BridgeCommWorkerReviewMetadataProjection();
		projection.apply(reviewSnapshot());

		// Act
		const deltaResult = projection.apply({
			...reviewIdentity,
			contentSources: [],
			eventKind: 'review.delta',
			fromRevision: 11,
			operations: [
				{ item: reviewItem('item-1', 'src/renamed.ts'), operationKind: 'upsertItem' },
				{
					deleteCount: 1,
					operationKind: 'spliceTreeRows',
					rows: [reviewTreeRow('row-replaced', 'item-1', 'src/renamed.ts')],
					startIndex: 0,
				},
			],
			publicationId: '00000000-0000-7000-8000-000000000012',
			revision: 12,
			summary: reviewSummary,
			toRevision: 12,
		});

		// Assert
		expect(deltaResult.affectedItemIds).toEqual(['item-1']);
		expect(projection.snapshot().revision).toBe(12);
		expect(projection.snapshot().itemMetadata[0]?.headPath).toBe('src/renamed.ts');
		expect(projection.snapshot().treeRows[0]?.rowId).toBe('row-replaced');
		expect(() =>
			projection.apply({
				...reviewWindow({
					itemId: 'item-2',
					itemStartIndex: 1,
					rowId: 'row-2',
					treeStartIndex: 1,
				}),
				publicationId: '00000000-0000-7000-8000-000000000012',
				revision: 11,
			}),
		).toThrow(/revision/i);
		expect(() =>
			projection.apply({
				...reviewWindow({
					itemId: 'item-2',
					itemStartIndex: 1,
					rowId: 'row-2',
					treeStartIndex: 1,
				}),
				packageId: 'package-other',
				revision: 12,
			}),
		).toThrow(/source/i);
	});

	test('keeps projection revisions monotonic across consecutive successor clones', () => {
		// Arrange
		const projection = new BridgeCommWorkerReviewMetadataProjection();
		projection.apply(reviewSnapshot());
		projection.apply(
			reviewWindow({ itemId: 'item-2', itemStartIndex: 1, rowId: 'row-2', treeStartIndex: 1 }),
		);
		const completedProjection = projection.cloneComplete();

		// Act
		const firstSuccessorResult = completedProjection.apply({
			...reviewIdentity,
			contentSources: [],
			eventKind: 'review.delta',
			fromRevision: 11,
			operations: [],
			publicationId: '00000000-0000-7000-8000-000000000012',
			revision: 12,
			summary: reviewSummary,
			toRevision: 12,
		});
		const secondSuccessorResult = completedProjection.cloneComplete().apply({
			...reviewIdentity,
			contentSources: [],
			eventKind: 'review.delta',
			fromRevision: 12,
			operations: [],
			publicationId: '00000000-0000-7000-8000-000000000013',
			revision: 13,
			summary: reviewSummary,
			toRevision: 13,
		});

		// Assert
		expect(firstSuccessorResult.projectionRevision).toBe(3);
		expect(secondSuccessorResult.projectionRevision).toBe(4);
	});

	test('resets all product state on explicit Review reset', () => {
		// Arrange
		const projection = new BridgeCommWorkerReviewMetadataProjection();
		projection.apply(reviewSnapshot());

		// Act
		const result = projection.apply({
			...reviewIdentity,
			eventKind: 'review.reset',
			reason: 'subscriptionReset',
			revision: 12,
		});

		// Assert
		expect(result).toMatchObject({ affectedItemIds: [], reset: true });
		expect(projection.snapshot()).toMatchObject({
			contentSources: [],
			itemMetadata: [],
			orderedItemIds: [],
			revision: 12,
			treeRows: [],
		});
	});

	test('retains early middle and final identity across a 3,420-file window stream', () => {
		// Arrange
		const projection = new BridgeCommWorkerReviewMetadataProjection();
		const totalItemCount = 3_420;
		const windowItemCount = 64;
		const firstWindow = reviewMetadataWindowRange({
			count: windowItemCount,
			startIndex: 0,
			totalItemCount,
		});
		projection.apply({
			...firstWindow,
			baseEndpoint: reviewEndpoint('base', 'gitRef'),
			eventKind: 'review.snapshot',
			headEndpoint: reviewEndpoint('head', 'workingTree'),
			query: reviewQuery(),
		});

		// Act
		for (
			let startIndex = windowItemCount;
			startIndex < totalItemCount;
			startIndex += windowItemCount
		) {
			projection.apply(
				reviewMetadataWindowRange({
					count: Math.min(windowItemCount, totalItemCount - startIndex),
					startIndex,
					totalItemCount,
				}),
			);
		}
		const deltaResult = projection.apply({
			...reviewIdentity,
			contentSources: [],
			eventKind: 'review.delta',
			fromRevision: 11,
			operations: [
				{
					item: reviewItem('item-1700', 'src/changed-1700.ts'),
					operationKind: 'upsertItem',
				},
			],
			publicationId: '00000000-0000-7000-8000-000000000012',
			revision: 12,
			summary: { ...reviewSummary, filesChanged: totalItemCount, visibleFileCount: totalItemCount },
			toRevision: 12,
		});
		const snapshot = projection.snapshot();

		// Assert
		expect(snapshot.orderedItemIds).toHaveLength(totalItemCount);
		expect(snapshot.orderedItemIds[0]).toBe('item-0000');
		expect(snapshot.orderedItemIds[1_700]).toBe('item-1700');
		expect(snapshot.orderedItemIds.at(-1)).toBe('item-3419');
		expect(snapshot.itemMetadata[1_700]?.headPath).toBe('src/changed-1700.ts');
		expect(deltaResult.affectedItemIds).toEqual(['item-1700']);
	});

	test('rejects a final barrier when cumulative item and tree windows still contain holes', () => {
		// Arrange
		const projection = new BridgeCommWorkerReviewMetadataProjection();
		projection.apply({
			...reviewSnapshot(),
			itemWindow: { finalWindow: false, itemCount: 1, startIndex: 0, totalItemCount: 3 },
			treeWindow: { finalWindow: false, rowCount: 1, startIndex: 0, totalRowCount: 3 },
		});

		// Act
		projection.apply({
			...reviewWindow({
				itemId: 'item-3',
				itemStartIndex: 2,
				rowId: 'row-3',
				treeStartIndex: 2,
			}),
			itemWindow: { finalWindow: true, itemCount: 1, startIndex: 2, totalItemCount: 3 },
			treeWindow: { finalWindow: true, rowCount: 1, startIndex: 2, totalRowCount: 3 },
		});
		const snapshot = projection.snapshot();

		// Assert
		expect(projection.isComplete()).toBe(false);
		expect(snapshot).toMatchObject({
			orderedItemIds: ['item-1', 'item-3'],
			totalItemCount: 3,
			totalTreeRowCount: 3,
		});
		expect(() => projection.assertCompleteFinalBarrier()).toThrow(/incomplete|hole/iu);
	});
});

const reviewIdentity = {
	generation: 7,
	packageId: 'package-1',
	publicationId: '00000000-0000-7000-8000-000000000011',
	revision: 11,
	sourceIdentity: 'source-1',
} as const;

const reviewSummary = {
	additions: 1,
	deletions: 1,
	filesChanged: 2,
	hiddenFileCount: 0,
	visibleFileCount: 2,
} as const;

function reviewSourceAccepted(): BridgeProductReviewMetadataEvent {
	return { ...reviewIdentity, eventKind: 'review.sourceAccepted' };
}

function reviewSnapshot(): ReviewSnapshotEvent {
	return {
		...reviewIdentity,
		baseEndpoint: reviewEndpoint('base', 'gitRef'),
		contentSources: [reviewContentSource('descriptor-1', 'item-1')],
		eventKind: 'review.snapshot',
		extentFacts: [{ contentRole: 'head', itemId: 'item-1', lineCount: 10 }],
		headEndpoint: reviewEndpoint('head', 'workingTree'),
		itemMetadata: [reviewItem('item-1', 'src/one.ts')],
		itemWindow: { finalWindow: false, itemCount: 1, startIndex: 0, totalItemCount: 2 },
		query: reviewQuery(),
		summary: reviewSummary,
		treeRows: [reviewTreeRow('row-1', 'item-1', 'src/one.ts')],
		treeWindow: { finalWindow: false, rowCount: 1, startIndex: 0, totalRowCount: 2 },
	};
}

function reviewWindow(props: {
	readonly itemId: string;
	readonly itemStartIndex: number;
	readonly rowId: string;
	readonly treeStartIndex: number;
}): Extract<BridgeProductReviewMetadataEvent, { readonly eventKind: 'review.window' }> {
	const path = `src/${props.itemId}.ts`;
	return {
		...reviewIdentity,
		contentSources: [reviewContentSource(`descriptor-${props.itemId}`, props.itemId)],
		eventKind: 'review.window',
		extentFacts: [{ contentRole: 'head', itemId: props.itemId, lineCount: 20 }],
		itemMetadata: [reviewItem(props.itemId, path)],
		itemWindow: {
			finalWindow: true,
			itemCount: 1,
			startIndex: props.itemStartIndex,
			totalItemCount: 2,
		},
		summary: reviewSummary,
		treeRows: [reviewTreeRow(props.rowId, props.itemId, path)],
		treeWindow: {
			finalWindow: true,
			rowCount: 1,
			startIndex: props.treeStartIndex,
			totalRowCount: 2,
		},
	};
}

function reviewMetadataWindowRange(props: {
	readonly count: number;
	readonly startIndex: number;
	readonly totalItemCount: number;
}): Extract<BridgeProductReviewMetadataEvent, { readonly eventKind: 'review.window' }> {
	const items = Array.from({ length: props.count }, (_, offset) => {
		const itemIndex = props.startIndex + offset;
		const itemId = `item-${itemIndex.toString().padStart(4, '0')}`;
		return reviewItem(itemId, `src/${itemId}.ts`);
	});
	const finalWindow = props.startIndex + props.count === props.totalItemCount;
	return {
		...reviewIdentity,
		contentSources: [],
		eventKind: 'review.window',
		extentFacts: items.map((item) => ({
			contentRole: 'head',
			itemId: item.itemId,
			lineCount: 30,
		})),
		itemMetadata: items,
		itemWindow: {
			finalWindow,
			itemCount: items.length,
			startIndex: props.startIndex,
			totalItemCount: props.totalItemCount,
		},
		summary: {
			...reviewSummary,
			filesChanged: props.totalItemCount,
			visibleFileCount: props.totalItemCount,
		},
		treeRows: items.map((item) =>
			reviewTreeRow(`row-${item.itemId}`, item.itemId, item.headPath ?? item.itemId),
		),
		treeWindow: {
			finalWindow,
			rowCount: items.length,
			startIndex: props.startIndex,
			totalRowCount: props.totalItemCount,
		},
	};
}

function reviewItem(itemId: string, path: string): BridgeProductReviewItemMetadata {
	return {
		basePath: path,
		changeKind: 'modified' as const,
		contentDescriptorIdsByRole: { head: `descriptor-${itemId}` },
		contentHashesByRole: { head: 'a'.repeat(64) },
		contentRoles: ['head' as const],
		extension: 'ts',
		fileClass: 'source' as const,
		headPath: path,
		isHiddenByDefault: false,
		itemId,
		language: 'typescript',
		mimeTypes: ['text/plain'],
		provenance: { agentSessionIds: [], operationIds: [], promptIds: [] },
		reviewPriority: 'normal' as const,
		reviewState: 'unreviewed' as const,
	};
}

function reviewTreeRow(rowId: string, itemId: string, path: string): BridgeProductReviewTreeRow {
	return { depth: 0, isDirectory: false, itemId, path, rowId };
}

function reviewContentSource(
	descriptorId: string,
	itemId: string,
): BridgeProductReviewContentSourceDescriptor {
	return {
		contentDigest: {
			algorithm: 'sha256' as const,
			authority: 'authoritative' as const,
			value: 'a'.repeat(64),
		},
		contentKind: 'review.content' as const,
		descriptorId,
		encoding: 'utf-8' as const,
		endpointId: 'head',
		handleId: `handle-${itemId}`,
		isBinary: false,
		itemId,
		language: 'typescript',
		mimeType: 'text/plain',
		packageId: 'package-1',
		reviewGeneration: 7,
		role: 'head' as const,
		sourceIdentity: 'source-1',
		wholeByteLength: 100,
	};
}

function reviewEndpoint(
	endpointId: string,
	kind: 'gitRef' | 'workingTree',
): ReviewSnapshotEvent['baseEndpoint'] {
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

function reviewQuery(): ReviewSnapshotEvent['query'] {
	return {
		baseEndpointId: 'base',
		comparisonSemantics: 'threeDot' as const,
		fileTarget: null,
		grouping: { kind: 'folder' as const },
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
		queryKind: 'compare' as const,
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
			showBinaryFiles: true,
			showHiddenFiles: false,
			showLargeFiles: true,
		},
		worktreeId: 'worktree-1',
	};
}

import { describe, expect, test } from 'vitest';

import { BridgeCommWorkerReviewQueryProjection } from './bridge-comm-worker-review-query-projection.js';
import type {
	BridgeWorkerReviewDisplayItem,
	BridgeWorkerReviewDisplayPatch,
} from './bridge-worker-contracts.js';

describe('Bridge comm worker Review query projection', () => {
	test('hides Binary and Large before the surface installs its default visibility', () => {
		// Arrange
		const projection = new BridgeCommWorkerReviewQueryProjection();

		// Act
		const initialPatches = projection.applyDisplayPatches(reviewSnapshotPatches());

		// Assert
		expect(projectedItemIds(initialPatches)).toEqual(['item-added', 'item-modified']);
	});

	test('filters files with required ancestors and Clear restores canonical order', () => {
		// Arrange
		const projection = new BridgeCommWorkerReviewQueryProjection();
		projection.applyDisplayPatches(reviewSnapshotPatches());

		// Act
		const addedPatches = projection.updateQuery({
			categoryFilter: 'all',
			gitStatusFilter: 'added',
			showBinary: false,
			showLarge: false,
		});
		const clearedPatches = projection.updateQuery({
			categoryFilter: 'all',
			gitStatusFilter: 'all',
			showBinary: false,
			showLarge: false,
		});

		// Assert
		expect(projectedItemIds(addedPatches)).toEqual(['item-added']);
		expect(projectedTreePaths(addedPatches)).toEqual([
			'Sources',
			'Sources/Group01',
			'Sources/Group01/Added.swift',
		]);
		expect(projectedItemIds(clearedPatches)).toEqual(['item-added', 'item-modified']);
		expect(projectedTreePaths(clearedPatches)).toEqual([
			'Sources',
			'Sources/Group01',
			'Sources/Group01/Added.swift',
			'Sources/Group02',
			'Sources/Group02/Modified.swift',
		]);
	});

	test('composes Git status and file class filters deterministically', () => {
		// Arrange
		const projection = new BridgeCommWorkerReviewQueryProjection();
		projection.applyDisplayPatches(reviewSnapshotPatches());

		// Act
		const sourceAddedPatches = projection.updateQuery({
			categoryFilter: 'source',
			gitStatusFilter: 'added',
			showBinary: false,
			showLarge: false,
		});
		const testAddedPatches = projection.updateQuery({
			categoryFilter: 'test',
			gitStatusFilter: 'added',
			showBinary: false,
			showLarge: false,
		});

		// Assert
		expect(projectedItemIds(sourceAddedPatches)).toEqual(['item-added']);
		expect(projectedItemIds(testAddedPatches)).toEqual([]);
		expect(projectedTreePaths(testAddedPatches)).toEqual([]);
	});

	test('keeps Binary and Large visibility independent from the exclusive category filter', () => {
		// Arrange
		const projection = new BridgeCommWorkerReviewQueryProjection();
		projection.applyDisplayPatches(reviewSnapshotPatches());

		// Act
		const binaryVisiblePatches = projection.updateQuery({
			categoryFilter: 'all',
			gitStatusFilter: 'all',
			showBinary: true,
			showLarge: false,
		});
		const largeVisiblePatches = projection.updateQuery({
			categoryFilter: 'all',
			gitStatusFilter: 'all',
			showBinary: false,
			showLarge: true,
		});

		// Assert
		expect(projectedItemIds(binaryVisiblePatches)).toEqual([
			'item-added',
			'item-modified',
			'item-binary',
		]);
		expect(projectedItemIds(largeVisiblePatches)).toEqual([
			'item-added',
			'item-modified',
			'item-large',
		]);
	});

	test('does not replay a retained comparison while rebuilding query-controlled slices', () => {
		// Arrange
		const projection = new BridgeCommWorkerReviewQueryProjection();
		projection.applyDisplayPatches([
			...reviewSnapshotPatches(),
			{ operation: 'replace', payload: null, slice: 'reviewComparison' },
		]);

		// Act
		const sourceOnlyProjection = projection.applyDisplayPatches(reviewSnapshotPatches());
		const queryProjection = projection.updateQuery({
			categoryFilter: 'source',
			gitStatusFilter: 'all',
			showBinary: false,
			showLarge: false,
		});

		// Assert
		expect(sourceOnlyProjection.some((patch) => patch.slice === 'reviewComparison')).toBe(false);
		expect(queryProjection.some((patch) => patch.slice === 'reviewComparison')).toBe(false);
	});
});

function reviewSnapshotPatches(): readonly BridgeWorkerReviewDisplayPatch[] {
	const items = [
		reviewDisplayItem({
			changeKind: 'added',
			fileClass: 'source',
			itemId: 'item-added',
			path: 'Sources/Group01/Added.swift',
		}),
		reviewDisplayItem({
			changeKind: 'modified',
			fileClass: 'test',
			itemId: 'item-modified',
			path: 'Sources/Group02/Modified.swift',
		}),
		reviewDisplayItem({
			changeKind: 'modified',
			fileClass: 'binary',
			itemId: 'item-binary',
			path: 'Sources/Group02/Asset.bin',
		}),
		reviewDisplayItem({
			changeKind: 'modified',
			fileClass: 'large',
			itemId: 'item-large',
			path: 'Sources/Group02/Large.txt',
		}),
	];
	return [
		{
			operation: 'batch',
			payload: { items, operations: [], reset: true, startIndex: 0 },
			slice: 'reviewItem',
		},
		{
			operation: 'batch',
			payload: {
				reset: true,
				windows: [
					{
						rows: [
							{ depth: 0, isDirectory: true, itemId: null, path: 'Sources', rowId: 'dir-sources' },
							{
								depth: 1,
								isDirectory: true,
								itemId: null,
								path: 'Sources/Group01',
								rowId: 'dir-group-01',
							},
							{
								depth: 2,
								isDirectory: false,
								itemId: 'item-added',
								path: 'Sources/Group01/Added.swift',
								rowId: 'row-added',
							},
							{
								depth: 1,
								isDirectory: true,
								itemId: null,
								path: 'Sources/Group02',
								rowId: 'dir-group-02',
							},
							{
								depth: 2,
								isDirectory: false,
								itemId: 'item-modified',
								path: 'Sources/Group02/Modified.swift',
								rowId: 'row-modified',
							},
						],
						startIndex: 0,
					},
				],
			},
			slice: 'reviewTree',
		},
	];
}

function reviewDisplayItem(props: {
	readonly changeKind: 'added' | 'modified';
	readonly fileClass: 'source' | 'test' | 'binary' | 'large';
	readonly itemId: string;
	readonly path: string;
}): BridgeWorkerReviewDisplayItem {
	return {
		contentFacts: [],
		extentFacts: [],
		metadata: {
			additions: 1,
			deletions: 1,
			basePath: props.path,
			changeKind: props.changeKind,
			contentDescriptorIdsByRole: {},
			contentHashesByRole: {},
			contentRoles: [],
			extension: 'swift',
			fileClass: props.fileClass,
			headPath: props.path,
			isHiddenByDefault: false,
			itemId: props.itemId,
			language: 'swift',
			mimeTypes: ['text/plain'],
			provenance: { agentSessionIds: [], operationIds: [], promptIds: [] },
			reviewPriority: 'normal',
			reviewState: 'unreviewed',
		},
		metadataWindowIdentity: `metadata-window-${props.itemId}`,
	};
}

function projectedItemIds(patches: readonly BridgeWorkerReviewDisplayPatch[]): readonly string[] {
	const itemPatch = patches.find((patch) => patch.slice === 'reviewItem');
	return itemPatch?.operation === 'batch'
		? itemPatch.payload.items.map((item) => item.metadata.itemId)
		: [];
}

function projectedTreePaths(patches: readonly BridgeWorkerReviewDisplayPatch[]): readonly string[] {
	const treePatch = patches.find((patch) => patch.slice === 'reviewTree');
	return treePatch?.operation === 'batch'
		? treePatch.payload.windows.flatMap((window) => window.rows.map((row) => row.path))
		: [];
}

import { describe, expect, test } from 'vitest';

import {
	applyBridgeCommWorkerReviewMetadataApplication,
	BridgeCommWorkerReviewMetadataApplicator,
	type BridgeCommWorkerReviewMetadataApplication,
} from './bridge-comm-worker-review-metadata-applicator.js';
import type { BridgeCommWorkerReviewRuntimeSource } from './bridge-comm-worker-review-source-diff.js';
import {
	makeContentRequestDescriptor,
	makeRenderSemantics,
	makeWorkerReviewContentMetadata,
} from './bridge-comm-worker-runtime-protocol.test-support.js';
import { createBridgeCommWorkerStore } from './bridge-comm-worker-store.js';
import type { BridgeProductReviewMetadataEvent } from './bridge-product-review-metadata-contracts.js';

type ReviewSnapshotEvent = Extract<
	BridgeProductReviewMetadataEvent,
	{ readonly eventKind: 'review.snapshot' }
>;
type ReviewWindowEvent = Extract<
	BridgeProductReviewMetadataEvent,
	{ readonly eventKind: 'review.window' }
>;

describe('Bridge comm worker Review metadata applicator', () => {
	test('drops a stale worker derivation before it can mutate the projection', () => {
		// Arrange
		const applications: BridgeCommWorkerReviewMetadataApplication[] = [];
		const applicator = new BridgeCommWorkerReviewMetadataApplicator({
			applyRuntimeSource: (application): void => {
				applications.push(application);
			},
			currentWorkerDerivationEpoch: (): number => 2,
		});

		// Act
		applicator.apply(reviewSnapshotEvent(), 1);
		applicator.apply(reviewSnapshotEvent(), 2);

		// Assert
		expect(applications).toHaveLength(1);
		expect(applications[0]).toMatchObject({
			reset: true,
			sourceEpoch: 1,
			workerDerivationEpoch: 2,
		});
	});

	test('keeps the source epoch stable and suppresses churn for an identical incremental window', () => {
		// Arrange
		const applications: BridgeCommWorkerReviewMetadataApplication[] = [];
		const applicator = new BridgeCommWorkerReviewMetadataApplicator({
			applyRuntimeSource: (application): void => {
				applications.push(application);
			},
			currentWorkerDerivationEpoch: (): number => 4,
		});
		applicator.apply(reviewSnapshotEvent(), 4);

		// Act
		applicator.apply(reviewWindowEvent(), 4);

		// Assert
		expect(applications.map(({ sourceEpoch }) => sourceEpoch)).toEqual([1, 1]);
		expect(applications[1]).toMatchObject({
			affectedItemIds: [],
			affectedRowIds: ['item-1'],
			reset: false,
			workerDerivationEpoch: 4,
		});
		expect(applications[1]?.source.rows).toEqual([{ id: 'item-1', index: 0, parentId: null }]);
	});

	test('maps a 3,420-item window stream with linear item-scoped operations', () => {
		// Arrange
		const mappedItemCounts: number[] = [];
		const applicator = new BridgeCommWorkerReviewMetadataApplicator({
			applyRuntimeSource: (): void => {},
			currentWorkerDerivationEpoch: (): number => 9,
			recordIncrementalItemMapping: (itemCount): void => {
				mappedItemCounts.push(itemCount);
			},
		});
		applicator.apply(
			{
				...reviewSnapshotEvent(),
				itemWindow: { finalWindow: false, itemCount: 1, startIndex: 0, totalItemCount: 3_420 },
				treeWindow: { finalWindow: false, rowCount: 1, startIndex: 0, totalRowCount: 3_420 },
			},
			9,
		);

		// Act
		for (let index = 1; index < 3_420; index += 1) {
			const itemId = `item-${index + 1}`;
			applicator.apply(
				{
					...reviewWindowEvent(),
					itemMetadata: [
						{
							...reviewItemMetadata,
							basePath: `${itemId}.swift`,
							headPath: `${itemId}.swift`,
							itemId,
						},
					],
					itemWindow: {
						finalWindow: index === 3_419,
						itemCount: 1,
						startIndex: index,
						totalItemCount: 3_420,
					},
					treeRows: [
						{ ...reviewTreeRow, itemId, path: `${itemId}.swift`, rowId: `row-${index + 1}` },
					],
					treeWindow: {
						finalWindow: index === 3_419,
						rowCount: 1,
						startIndex: index,
						totalRowCount: 3_420,
					},
				},
				9,
			);
		}

		// Assert
		expect(mappedItemCounts).toHaveLength(3_419);
		expect(mappedItemCounts.reduce((total, itemCount) => total + itemCount, 0)).toBe(3_419);
		expect(Math.max(...mappedItemCounts)).toBe(1);
	});

	test('keeps directory rows separate from complete content item identity', () => {
		// Arrange
		const store = createBridgeCommWorkerStore({ contentItems: [], rows: [], surface: 'review' });
		let runtimeSource: BridgeCommWorkerReviewRuntimeSource = {
			contentItems: [],
			contentRequestDescriptors: [],
			renderSemantics: [],
			rows: [],
		};
		const applicator = new BridgeCommWorkerReviewMetadataApplicator({
			applyRuntimeSource: (application): void => {
				applyBridgeCommWorkerReviewMetadataApplication({
					application,
					createSequence: (): number => 1,
					readRuntimeSource: (): BridgeCommWorkerReviewRuntimeSource => runtimeSource,
					scheduleSelectedPreparation: (): void => {},
					store,
					updateRuntimeSource: (source): void => {
						runtimeSource = source;
					},
				});
			},
			currentWorkerDerivationEpoch: (): number => 10,
		});

		// Act
		applicator.apply(
			{
				...reviewSnapshotEvent(),
				treeRows: [
					{
						depth: 0,
						isDirectory: true,
						itemId: null,
						path: 'Sources',
						rowId: 'directory-sources',
					},
					{ ...reviewTreeRow, depth: 1 },
				],
				treeWindow: { finalWindow: true, rowCount: 2, startIndex: 0, totalRowCount: 2 },
			},
			10,
		);

		// Assert
		expect([...store.getState().rowById.keys()]).toEqual(['directory-sources', 'item-1']);
		expect(store.getState().childrenByParentId.get('directory-sources')).toEqual(
			new Set(['item-1']),
		);
		expect(store.getState().contentMetadataByItemId.has('item-1')).toBe(true);

		// Act — remove only the file content identity and its file row.
		applicator.apply(
			{
				...reviewPayloadIdentity,
				contentSources: [],
				eventKind: 'review.delta',
				fromRevision: 11,
				operations: [
					{ itemIds: ['item-1'], operationKind: 'removeItems' },
					{ deleteCount: 1, operationKind: 'spliceTreeRows', rows: [], startIndex: 1 },
				],
				publicationId: '00000000-0000-7000-8000-000000000012',
				revision: 12,
				toRevision: 12,
			},
			10,
		);

		// Assert — the directory row remains independent from removed file content.
		expect([...store.getState().rowById.keys()]).toEqual(['directory-sources']);
		expect(store.getState().contentMetadataByItemId.has('item-1')).toBe(false);
	});

	test('stages a fresh replay until its complete snapshot and publishes one reset epoch', () => {
		// Arrange
		const applications: BridgeCommWorkerReviewMetadataApplication[] = [];
		const applicator = new BridgeCommWorkerReviewMetadataApplicator({
			applyRuntimeSource: (application): void => {
				applications.push(application);
			},
			currentWorkerDerivationEpoch: (): number => 12,
		});

		// Act
		applicator.apply(
			{
				eventKind: 'review.sourceAccepted',
				generation: 7,
				packageId: 'package-1',
				publicationId: '00000000-0000-7000-8000-000000000011',
				revision: 11,
				sourceIdentity: 'source-1',
			},
			12,
		);
		applicator.apply(reviewSnapshotEvent(), 12);

		// Assert
		expect(applications).toHaveLength(1);
		expect(applications[0]).toMatchObject({ reset: true, sourceEpoch: 1 });
	});

	test('applies structural deltas as closed row removal and upsert mutations', () => {
		// Arrange
		const applications: BridgeCommWorkerReviewMetadataApplication[] = [];
		const applicator = new BridgeCommWorkerReviewMetadataApplicator({
			applyRuntimeSource: (application): void => {
				applications.push(application);
			},
			currentWorkerDerivationEpoch: (): number => 14,
		});
		applicator.apply(reviewSnapshotEvent(), 14);

		// Act
		applicator.apply(
			{
				...reviewPayloadIdentity,
				contentSources: [],
				eventKind: 'review.delta',
				fromRevision: 11,
				operations: [
					{
						deleteCount: 1,
						operationKind: 'spliceTreeRows',
						rows: [{ ...reviewTreeRow, rowId: 'row-replaced' }],
						startIndex: 0,
					},
				],
				publicationId: '00000000-0000-7000-8000-000000000012',
				revision: 12,
				toRevision: 12,
			},
			14,
		);

		// Assert
		expect(applications[1]?.rowMutation).toEqual({
			removedRowIds: ['item-1'],
			rowUpserts: [{ id: 'item-1', index: 0, parentId: null }],
		});
		expect(applications[1]?.reset).toBe(false);
	});

	test('removes deleted items from worker runtime content state', () => {
		// Arrange
		const applications: BridgeCommWorkerReviewMetadataApplication[] = [];
		const applicator = new BridgeCommWorkerReviewMetadataApplicator({
			applyRuntimeSource: (application): void => {
				applications.push(application);
			},
			currentWorkerDerivationEpoch: (): number => 14,
		});
		applicator.apply(reviewSnapshotEvent(), 14);

		// Act
		applicator.apply(
			{
				...reviewPayloadIdentity,
				contentSources: [],
				eventKind: 'review.delta',
				fromRevision: 11,
				operations: [
					{ itemIds: ['item-1'], operationKind: 'removeItems' },
					{ deleteCount: 1, operationKind: 'spliceTreeRows', rows: [], startIndex: 0 },
				],
				publicationId: '00000000-0000-7000-8000-000000000012',
				revision: 12,
				toRevision: 12,
			},
			14,
		);

		// Assert
		expect(applications[1]).toMatchObject({
			affectedItemIds: ['item-1'],
			removedItemIds: ['item-1'],
			rowMutation: { removedRowIds: ['item-1'], rowUpserts: [] },
			source: {
				contentItems: [],
				contentRequestDescriptors: [],
				renderSemantics: [],
				rows: [],
			},
		});
	});

	test('retains prior item identity while a same-source metadata reset is pending', () => {
		// Arrange
		const applications: BridgeCommWorkerReviewMetadataApplication[] = [];
		const applicator = new BridgeCommWorkerReviewMetadataApplicator({
			applyRuntimeSource: (application): void => {
				applications.push(application);
			},
			currentWorkerDerivationEpoch: (): number => 14,
		});
		applicator.apply(reviewSnapshotEvent(), 14);

		// Act
		applicator.apply(
			{
				...reviewPayloadIdentity,
				eventKind: 'review.reset',
				publicationId: '00000000-0000-7000-8000-000000000012',
				reason: 'subscriptionReset',
				revision: 12,
			},
			14,
		);

		// Assert
		expect(applications).toHaveLength(1);
		expect(applications[0]).toMatchObject({
			reset: true,
			source: { contentItems: [{ itemId: 'item-1' }], rows: [{ id: 'item-1' }] },
		});
	});

	test('rejects a conflicting delta before publishing partial runtime state', () => {
		// Arrange
		const applications: BridgeCommWorkerReviewMetadataApplication[] = [];
		const applicator = new BridgeCommWorkerReviewMetadataApplicator({
			applyRuntimeSource: (application): void => {
				applications.push(application);
			},
			currentWorkerDerivationEpoch: (): number => 15,
		});
		applicator.apply(reviewSnapshotEvent(), 15);

		// Act / Assert
		expect(() =>
			applicator.apply(
				{
					...reviewPayloadIdentity,
					contentSources: [],
					eventKind: 'review.delta',
					fromRevision: 10,
					operations: [],
					publicationId: '00000000-0000-7000-8000-000000000012',
					revision: 12,
					toRevision: 12,
				},
				15,
			),
		).toThrow(/does not continue/iu);
		expect(applications).toHaveLength(1);
	});

	test('prepares existing selected demand when metadata makes its descriptors executable', () => {
		// Arrange
		const contentMetadata = makeWorkerReviewContentMetadata({ itemId: 'item-1' });
		const renderSemantics = makeRenderSemantics({ itemId: 'item-1' });
		const baseDescriptor = makeContentRequestDescriptor({
			generation: 2,
			itemId: 'item-1',
			role: 'base',
			text: 'base\n',
		});
		const executableSource = reviewRuntimeSource({
			contentMetadata,
			contentRequestDescriptors: [
				baseDescriptor,
				makeContentRequestDescriptor({
					generation: 2,
					itemId: 'item-1',
					role: 'head',
					text: 'head\n',
				}),
			],
			renderSemantics,
		});
		const store = createBridgeCommWorkerStore({
			surface: 'review',
			contentItems: [contentMetadata],
			rows: executableSource.rows,
		});
		store.actions.applySelectedFact({ epoch: 7, itemId: 'item-1' });
		const scheduledPreparations: Array<{ readonly epoch: number; readonly itemId: string }> = [];

		// Act
		applyBridgeCommWorkerReviewMetadataApplication({
			application: reviewMetadataApplication({ source: executableSource, sourceEpoch: 2 }),
			createSequence: (): number => 1,
			readRuntimeSource: () =>
				reviewRuntimeSource({
					contentMetadata,
					contentRequestDescriptors: [baseDescriptor],
					renderSemantics,
				}),
			scheduleSelectedPreparation: ({ epoch, itemId }): void => {
				scheduledPreparations.push({ epoch, itemId });
			},
			store,
			updateRuntimeSource: (): void => {},
		});

		// Assert
		expect(store.getState().demandByKey.get('item-1')).toBe('selected:7');
		expect(scheduledPreparations).toEqual([{ epoch: 7, itemId: 'item-1' }]);
	});

	test('arms selected demand when executable metadata arrives on an independent source epoch', () => {
		// Arrange
		const contentMetadata = makeWorkerReviewContentMetadata({ itemId: 'item-1' });
		const renderSemantics = makeRenderSemantics({ itemId: 'item-1' });
		const executableSource = reviewRuntimeSource({
			contentMetadata,
			contentRequestDescriptors: [
				makeContentRequestDescriptor({
					generation: 2,
					itemId: 'item-1',
					role: 'base',
					text: 'base\n',
				}),
				makeContentRequestDescriptor({
					generation: 2,
					itemId: 'item-1',
					role: 'head',
					text: 'head\n',
				}),
			],
			renderSemantics,
		});
		const store = createBridgeCommWorkerStore({
			surface: 'review',
			contentItems: [],
			rows: executableSource.rows,
		});
		store.actions.applySelectedFact({ epoch: 7, itemId: 'item-1' });
		const scheduledPreparations: Array<{ readonly epoch: number; readonly itemId: string }> = [];

		// Act
		applyBridgeCommWorkerReviewMetadataApplication({
			application: reviewMetadataApplication({ source: executableSource, sourceEpoch: 2 }),
			createSequence: (): number => 1,
			readRuntimeSource: () =>
				reviewRuntimeSource({
					contentMetadata: null,
					contentRequestDescriptors: [],
					renderSemantics: null,
				}),
			scheduleSelectedPreparation: ({ epoch, itemId }): void => {
				scheduledPreparations.push({ epoch, itemId });
			},
			store,
			updateRuntimeSource: (): void => {},
		});

		// Assert
		expect(store.getState().demandByKey.get('item-1')).toBe('selected:7');
		expect(scheduledPreparations).toEqual([{ epoch: 7, itemId: 'item-1' }]);
	});

	test('removes deleted content facts from the Review store', () => {
		// Arrange
		const contentMetadata = makeWorkerReviewContentMetadata({ itemId: 'item-1' });
		const store = createBridgeCommWorkerStore({
			surface: 'review',
			contentItems: [contentMetadata],
			rows: [{ id: 'item-1', index: 0, parentId: null }],
		});

		// Act
		applyBridgeCommWorkerReviewMetadataApplication({
			application: {
				affectedItemIds: ['item-1'],
				affectedRowIds: ['item-1'],
				projectionRevision: 2,
				removedItemIds: ['item-1'],
				reset: false,
				rowMutation: { removedRowIds: ['item-1'], rowUpserts: [] },
				source: { contentItems: [], contentRequestDescriptors: [], renderSemantics: [], rows: [] },
				sourceEpoch: 1,
				workerDerivationEpoch: 1,
			},
			createSequence: (): number => 1,
			readRuntimeSource: () =>
				reviewRuntimeSource({
					contentMetadata,
					contentRequestDescriptors: [],
					renderSemantics: makeRenderSemantics({ itemId: 'item-1' }),
				}),
			scheduleSelectedPreparation: (): void => {},
			store,
			updateRuntimeSource: (): void => {},
		});

		// Assert
		expect(store.getState().contentMetadataByItemId.has('item-1')).toBe(false);
		expect(store.getState().rowById.has('item-1')).toBe(false);
	});
});

function reviewRuntimeSource(props: {
	readonly contentMetadata: ReturnType<typeof makeWorkerReviewContentMetadata> | null;
	readonly contentRequestDescriptors: BridgeCommWorkerReviewRuntimeSource['contentRequestDescriptors'];
	readonly renderSemantics: ReturnType<typeof makeRenderSemantics> | null;
}): BridgeCommWorkerReviewRuntimeSource {
	return {
		contentItems: props.contentMetadata === null ? [] : [props.contentMetadata],
		contentRequestDescriptors: props.contentRequestDescriptors,
		renderSemantics: props.renderSemantics === null ? [] : [props.renderSemantics],
		rows: [{ id: 'item-1', index: 0, parentId: null }],
	};
}

function reviewMetadataApplication(props: {
	readonly source: BridgeCommWorkerReviewRuntimeSource;
	readonly sourceEpoch: number;
}): BridgeCommWorkerReviewMetadataApplication {
	return {
		affectedItemIds: ['item-1'],
		affectedRowIds: [],
		projectionRevision: 1,
		removedItemIds: [],
		reset: false,
		rowMutation: { removedRowIds: [], rowUpserts: [] },
		source: props.source,
		sourceEpoch: props.sourceEpoch,
		workerDerivationEpoch: 1,
	};
}

function reviewSnapshotEvent(): ReviewSnapshotEvent {
	return {
		...reviewPayloadIdentity,
		contentSources: [],
		eventKind: 'review.snapshot',
		extentFacts: [],
		itemMetadata: [reviewItemMetadata],
		itemWindow: { finalWindow: true, itemCount: 1, startIndex: 0, totalItemCount: 1 },
		revision: 11,
		treeRows: [reviewTreeRow],
		treeWindow: { finalWindow: true, rowCount: 1, startIndex: 0, totalRowCount: 1 },
	};
}

function reviewWindowEvent(): ReviewWindowEvent {
	return {
		...reviewPayloadIdentity,
		contentSources: [],
		eventKind: 'review.window',
		extentFacts: [],
		itemMetadata: [reviewItemMetadata],
		itemWindow: { finalWindow: false, itemCount: 1, startIndex: 0, totalItemCount: 1 },
		revision: 11,
		treeRows: [reviewTreeRow],
		treeWindow: { finalWindow: false, rowCount: 1, startIndex: 0, totalRowCount: 1 },
	};
}

const reviewPayloadIdentity = {
	baseEndpoint: {
		createdAtUnixMilliseconds: 1,
		endpointId: 'base',
		kind: 'gitRef',
		label: 'base',
		providerIdentity: 'base-provider',
		repoId: 'repo-1',
		worktreeId: 'worktree-1',
	},
	generation: 7,
	headEndpoint: {
		createdAtUnixMilliseconds: 1,
		endpointId: 'head',
		kind: 'workingTree',
		label: 'head',
		providerIdentity: 'head-provider',
		repoId: 'repo-1',
		worktreeId: 'worktree-1',
	},
	packageId: 'package-1',
	publicationId: '00000000-0000-7000-8000-000000000011',
	query: {
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
			showBinaryFiles: true,
			showHiddenFiles: false,
			showLargeFiles: true,
		},
		worktreeId: 'worktree-1',
	},
	sourceIdentity: 'source-1',
	summary: {
		additions: 1,
		deletions: 1,
		filesChanged: 1,
		hiddenFileCount: 0,
		visibleFileCount: 1,
	},
} as const;

const reviewItemMetadata = {
	basePath: 'Sources/App.swift',
	changeKind: 'modified',
	contentDescriptorIdsByRole: {},
	contentHashesByRole: {},
	contentRoles: [],
	extension: 'swift',
	fileClass: 'source',
	headPath: 'Sources/App.swift',
	isHiddenByDefault: false,
	itemId: 'item-1',
	language: 'swift',
	mimeTypes: ['text/plain'],
	provenance: { agentSessionIds: [], operationIds: [], promptIds: [] },
	reviewPriority: 'normal',
	reviewState: 'unreviewed',
} as const;

const reviewTreeRow = {
	depth: 0,
	isDirectory: false,
	itemId: 'item-1',
	path: 'Sources/App.swift',
	rowId: 'row-1',
} as const;

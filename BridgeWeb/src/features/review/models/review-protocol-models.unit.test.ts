import { describe, expect, test } from 'vitest';

import { bridgeIntakeFrameSchema } from '../../../core/models/bridge-intake-frame.js';
import type {
	BridgeAttachedResourceDescriptor,
	BridgeResourceDescriptor,
} from '../../../core/models/bridge-resource-descriptor.js';
import type {
	BridgeReviewPackageSummary,
	BridgeSourceEndpoint,
} from '../../../foundation/review-package/bridge-review-package.js';
import type { BridgeReviewProjectionInputItem } from '../../../review-viewer/models/review-projection-models.js';
import reviewMetadataSnapshotIntakeFrameFixture from '../../../test-fixtures/bridge-contract-fixtures/valid/review-metadata-snapshot-intake-frame.json' with { type: 'json' };
import {
	reviewDemandStimulusSchema,
	reviewMetadataDeltaFrameSchema,
	reviewMetadataSnapshotFrameSchema,
	reviewProtocolFrameSchema,
	reviewTreeRowMetadataSchema,
	reviewResetFrameSchema,
} from './review-protocol-models.js';

describe('review protocol models', () => {
	test('parses Swift native review metadata snapshot intake fixture', () => {
		const intakeFrame = bridgeIntakeFrameSchema.parse(reviewMetadataSnapshotIntakeFrameFixture);
		expect(intakeFrame.kind).toBe('snapshot');
		if (intakeFrame.kind !== 'snapshot') {
			throw new Error(`Expected Swift native review fixture to parse as a snapshot intake frame`);
		}
		const reviewProtocolFrame = reviewProtocolFrameSchema.parse(intakeFrame.payload);
		const reviewMetadataSnapshotFrame =
			reviewMetadataSnapshotFrameSchema.parse(reviewProtocolFrame);
		const contentDescriptor = reviewMetadataSnapshotFrame.comparison.contentDescriptors?.[0];

		expect(intakeFrame).toMatchObject({
			kind: 'snapshot',
			streamId: 'review:pane-1',
			generation: 3,
			sequence: 0,
		});
		expect(reviewMetadataSnapshotFrame).toMatchObject({
			kind: 'metadataSnapshot',
			frameKind: 'review.metadataSnapshot',
			comparison: {
				packageId: 'package-1',
				sourceIdentity: 'query',
				generation: 3,
				revision: 0,
				baseEndpoint: {
					endpointId: 'base',
					kind: 'gitRef',
					label: 'base',
				},
				headEndpoint: {
					endpointId: 'head',
					kind: 'workingTree',
					label: 'head',
				},
			},
			selectedItemId: 'item-source',
			visibleItemIds: ['item-source'],
		});
		expect(contentDescriptor?.descriptor.protocol).toBe('review');
		expect(contentDescriptor?.descriptor.resourceKind).toBe('content');
		expect(contentDescriptor?.descriptor.content.encoding).toBe('utf-8');
		expect(bridgeIntakeFrameSchema.safeParse(reviewMetadataSnapshotFrame).success).toBe(false);
	});

	test('parses review metadata snapshot frames with inline projection facts', () => {
		const attachedDescriptor = makeAttachedDescriptor();

		expect(
			reviewMetadataSnapshotFrameSchema.parse({
				kind: 'metadataSnapshot',
				streamId: 'stream-1',
				generation: 1,
				sequence: 0,
				frameKind: 'review.metadataSnapshot',
				comparison: {
					packageId: 'package-1',
					sourceIdentity: 'review:source-1',
					generation: 1,
					revision: 1,
					baseEndpoint: makeSourceEndpoint({
						endpointId: 'baseline-main',
						kind: 'gitRef',
						label: 'main',
						providerIdentity: 'main',
					}),
					headEndpoint: makeSourceEndpoint({
						endpointId: 'working-tree',
						kind: 'workingTree',
						label: 'Working tree',
						providerIdentity: 'working-tree:worktree-1',
					}),
					contentDescriptors: [attachedDescriptor],
					changesetCluster: {
						clusterId: 'cluster-1',
						sourceId: 'review-source-1',
						algorithm: 'idleDebounce',
						lifecycle: 'live',
						confidence: 'freshScan',
						baselineCursor: 'cursor-a',
						headCursor: 'cursor-b',
						includedPathHints: ['Sources/App/View.swift'],
						groupingReason: 'agent idle debounce closed the batch',
						limitations: ['overflowRecovered'],
					},
				},
				selectedItemId: 'item-source',
				visibleItemIds: ['item-source'],
				itemMetadata: [
					{
						itemId: 'item-source',
						basePath: 'Sources/App/View.swift',
						headPath: 'Sources/App/View.swift',
						changeKind: 'modified',
						fileClass: 'source',
						language: 'swift',
						extension: 'swift',
						isHiddenByDefault: false,
						reviewPriority: 'normal',
						reviewState: 'unreviewed',
						contentRoles: ['diff'],
						mimeTypes: ['text/x-diff'],
						provenance: {
							promptIds: [],
							agentSessionIds: [],
							operationIds: [],
						},
					},
				],
				treeRows: [
					{
						rowId: 'row-source',
						itemId: 'item-source',
						path: 'Sources/App/View.swift',
						depth: 2,
						isDirectory: false,
					},
				],
				extentFacts: [
					{
						itemId: 'item-source',
						contentRole: 'diff',
						lineCount: 42,
					},
				],
				summary: makeReviewSummary(),
			}),
		).toMatchObject({
			frameKind: 'review.metadataSnapshot',
			comparison: {
				packageId: 'package-1',
				contentDescriptors: [attachedDescriptor],
				changesetCluster: {
					clusterId: 'cluster-1',
					sourceId: 'review-source-1',
					algorithm: 'idleDebounce',
					lifecycle: 'live',
					confidence: 'freshScan',
					baselineCursor: 'cursor-a',
					headCursor: 'cursor-b',
					includedPathHints: ['Sources/App/View.swift'],
					groupingReason: 'agent idle debounce closed the batch',
					limitations: ['overflowRecovered'],
				},
			},
			selectedItemId: 'item-source',
			visibleItemIds: ['item-source'],
			itemMetadata: [{ itemId: 'item-source' }],
			treeRows: [{ rowId: 'row-source' }],
			extentFacts: [{ itemId: 'item-source', lineCount: 42 }],
		});
	});

	test('rejects loose demand stimuli and raw descriptor strings', () => {
		expect(
			reviewDemandStimulusSchema.safeParse({
				kind: 'reviewItemSelected',
				descriptorRef: makeAttachedDescriptor().ref,
			}).success,
		).toBe(true);
		expect(
			reviewDemandStimulusSchema.safeParse({
				kind: 'reviewItemSelected',
				descriptorId: 'descriptor-1',
			}).success,
		).toBe(false);
		expect(
			reviewDemandStimulusSchema.safeParse({
				kind: 'reviewDescriptorInvalidated',
				descriptorRef: makeAttachedDescriptor().ref,
				isSelected: true,
			}).success,
		).toBe(false);
	});

	test('rejects extra top-level review frame fields', () => {
		expect(
			reviewMetadataSnapshotFrameSchema.safeParse({
				kind: 'metadataSnapshot',
				streamId: 'stream-1',
				generation: 1,
				sequence: 0,
				frameKind: 'review.metadataSnapshot',
				comparison: {
					packageId: 'package-1',
					sourceIdentity: 'review:source-1',
					generation: 1,
					revision: 1,
					baseEndpoint: makeSourceEndpoint({
						endpointId: 'baseline-main',
						kind: 'gitRef',
						label: 'main',
						providerIdentity: 'main',
					}),
					headEndpoint: makeSourceEndpoint({
						endpointId: 'working-tree',
						kind: 'workingTree',
						label: 'Working tree',
						providerIdentity: 'working-tree:worktree-1',
					}),
				},
				selectedItemId: null,
				visibleItemIds: [],
				itemMetadata: [],
				treeRows: [],
				extentFacts: [],
				summary: makeReviewSummary(),
				legacyPayload: true,
			}).success,
		).toBe(false);
		expect(
			reviewMetadataDeltaFrameSchema.safeParse({
				kind: 'metadataDelta',
				streamId: 'stream-1',
				generation: 1,
				sequence: 1,
				frameKind: 'review.metadataDelta',
				packageId: 'package-1',
				fromRevision: 1,
				toRevision: 2,
				operations: [],
				summary: makeReviewSummary(),
				legacyPayload: true,
			}).success,
		).toBe(false);
		expect(
			reviewResetFrameSchema.safeParse({
				kind: 'reset',
				streamId: 'stream-1',
				generation: 2,
				sequence: 2,
				frameKind: 'review.reset',
				reason: 'authorityChanged',
				sourceIdentity: 'review:source-1',
				legacyPayload: true,
			}).success,
		).toBe(false);
	});

	test('accepts semantic metadata delta operations', () => {
		const semanticDelta = reviewMetadataDeltaFrameSchema.safeParse({
			kind: 'metadataDelta',
			streamId: 'stream-1',
			generation: 1,
			sequence: 2,
			frameKind: 'review.metadataDelta',
			packageId: 'package-1',
			fromRevision: 1,
			toRevision: 2,
			operations: [
				{
					kind: 'upsertItemMetadata',
					item: makeProjectionInputItem('item-source'),
				},
				{
					kind: 'movePathPrefix',
					fromPath: 'Sources/App',
					toPath: 'Sources/UI',
					affectedItemIds: ['item-source'],
				},
				{
					kind: 'upsertTreeRows',
					rows: [
						{
							rowId: 'row-source',
							itemId: 'item-source',
							path: 'Sources/UI/View.swift',
							depth: 2,
							isDirectory: false,
						},
					],
				},
				{
					kind: 'upsertExtentFacts',
					facts: [
						{
							itemId: 'item-source',
							contentRole: 'diff',
							lineCount: 42,
						},
					],
				},
				{
					kind: 'selectItem',
					itemId: 'item-source',
				},
			],
			summary: makeReviewSummary(),
		});

		expect(semanticDelta.success).toBe(true);
	});

	test('parses shared demand-lane lineage on review tree rows', () => {
		const parsedFrame = reviewMetadataSnapshotFrameSchema.parse({
			kind: 'metadataSnapshot',
			streamId: 'stream-1',
			generation: 1,
			sequence: 0,
			frameKind: 'review.metadataSnapshot',
			comparison: {
				packageId: 'package-1',
				sourceIdentity: 'review:source-1',
				generation: 1,
				revision: 1,
				baseEndpoint: makeSourceEndpoint({
					endpointId: 'baseline-main',
					kind: 'gitRef',
					label: 'main',
					providerIdentity: 'main',
				}),
				headEndpoint: makeSourceEndpoint({
					endpointId: 'working-tree',
					kind: 'workingTree',
					label: 'Working tree',
					providerIdentity: 'working-tree:worktree-1',
				}),
			},
			selectedItemId: 'item-source',
			visibleItemIds: ['item-source'],
			itemMetadata: [
				{
					...makeProjectionInputItem('item-source'),
					loaded_by: 'foreground',
					lane: 'foreground',
				},
			],
			treeRows: [],
			extentFacts: [],
			summary: makeReviewSummary(),
		});
		const parsedRow = reviewTreeRowMetadataSchema.parse({
			rowId: 'row-source',
			itemId: 'item-source',
			path: 'Sources/App/View.swift',
			depth: 2,
			isDirectory: false,
			loaded_by: 'visible',
			lane: 'visible',
		});

		expect(parsedFrame.itemMetadata[0]?.loaded_by).toBe('foreground');
		expect(parsedFrame.itemMetadata[0]?.lane).toBe('foreground');
		expect(parsedRow.loaded_by).toBe('visible');
		expect(parsedRow.lane).toBe('visible');
		expect(
			reviewTreeRowMetadataSchema.safeParse({
				...parsedRow,
				loaded_by: 'worktree_visible',
			}).success,
		).toBe(false);
	});
});

function makeProjectionInputItem(itemId: string): BridgeReviewProjectionInputItem {
	return {
		itemId,
		basePath: 'Sources/App/View.swift',
		headPath: 'Sources/App/View.swift',
		changeKind: 'modified',
		fileClass: 'source',
		language: 'swift',
		extension: 'swift',
		isHiddenByDefault: false,
		reviewPriority: 'normal',
		reviewState: 'unreviewed',
		contentRoles: ['diff'],
		mimeTypes: ['text/x-diff'],
		provenance: {
			promptIds: [],
			agentSessionIds: [],
			operationIds: [],
		},
	};
}

function makeReviewSummary(): BridgeReviewPackageSummary {
	return {
		filesChanged: 1,
		additions: 2,
		deletions: 3,
		visibleFileCount: 1,
		hiddenFileCount: 0,
	};
}

function makeSourceEndpoint(props: {
	readonly endpointId: string;
	readonly kind: BridgeSourceEndpoint['kind'];
	readonly label: string;
	readonly providerIdentity: string;
}): BridgeSourceEndpoint {
	return {
		endpointId: props.endpointId,
		kind: props.kind,
		repoId: 'repo-1',
		worktreeId: 'worktree-1',
		label: props.label,
		createdAtUnixMilliseconds: 1,
		contentSetHash: null,
		providerIdentity: props.providerIdentity,
	};
}

function makeAttachedDescriptor(): BridgeAttachedResourceDescriptor {
	const identity = {
		paneId: 'pane-1',
		protocol: 'review',
		sourceId: 'source-1',
		packageId: 'package-1',
		generation: 1,
		revision: 1,
		streamId: 'stream-1',
	};
	const descriptor = {
		descriptorId: 'descriptor-1',
		protocol: 'review',
		resourceKind: 'content',
		resourceUrl: 'agentstudio://resource/review/content/descriptor-1?generation=1&revision=1',
		identity,
		content: {
			mediaType: 'application/json',
			encoding: 'utf-8',
			expectedBytes: 128,
			maxBytes: 1024,
		},
	} satisfies BridgeResourceDescriptor;
	return {
		ref: {
			descriptorId: descriptor.descriptorId,
			expectedProtocol: descriptor.protocol,
			expectedResourceKind: descriptor.resourceKind,
			expectedIdentity: identity,
		},
		descriptor,
	};
}

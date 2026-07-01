import { describe, expect, test } from 'vitest';

import { makeBridgeReviewPackage } from '../../../foundation/review-package/bridge-review-package-test-support.js';
import type {
	BridgeContentHandle,
	BridgeReviewItemDescriptor,
	BridgeReviewPackage,
} from '../../../foundation/review-package/bridge-review-package.js';
import {
	buildReviewMetadataDeltaFrame,
	buildReviewMetadataSnapshotFrame,
	buildReviewMetadataWindowFrame,
} from './review-metadata-frame-builder.js';

describe('review metadata frame builder', () => {
	test('builds metadata snapshots with inline projection facts and content descriptors only', () => {
		const reviewPackage = makeBridgeReviewPackage();

		const frame = buildReviewMetadataSnapshotFrame({
			package: reviewPackage,
			paneId: 'pane-1',
			sourceIdentity: reviewPackage.query.queryId,
			streamId: 'review:pane-1',
			sequence: reviewPackage.revision,
			selectedItemId: reviewPackage.orderedItemIds[0] ?? null,
			visibleItemIds: reviewPackage.orderedItemIds.slice(0, 2),
		});

		expect(frame.frameKind).toBe('review.metadataSnapshot');
		expect(frame.kind).toBe('metadataSnapshot');
		expect(frame.comparison.packageId).toBe(reviewPackage.packageId);
		expect(frame.summary).toEqual(reviewPackage.summary);
		expect(frame.comparison).not.toHaveProperty('rootDescriptor');
		expect(frame.itemMetadata.map((item) => item.itemId)).toEqual(
			reviewPackage.orderedItemIds.slice(0, 2),
		);
		expect(frame.treeRows.map((row) => row.itemId)).toEqual(
			reviewPackage.orderedItemIds.slice(0, 2),
		);
		expect(uniqueExtentFactItemIds(frame.extentFacts)).toEqual(
			reviewPackage.orderedItemIds.slice(0, 2),
		);
		expect(
			new Set(
				frame.comparison.contentDescriptors?.map(
					(attachedDescriptor) => attachedDescriptor.descriptor.resourceKind,
				),
			),
		).toEqual(new Set(['content']));
	});

	test('keeps the startup metadata snapshot bounded to selected and visible items', () => {
		const reviewPackage = makeBridgeReviewPackage();
		const selectedItemId = reviewPackage.orderedItemIds[2] ?? null;
		const visibleItemIds = reviewPackage.orderedItemIds.slice(0, 1);

		const frame = buildReviewMetadataSnapshotFrame({
			package: reviewPackage,
			paneId: 'pane-1',
			sourceIdentity: reviewPackage.query.queryId,
			streamId: 'review:pane-1',
			sequence: reviewPackage.revision,
			selectedItemId,
			visibleItemIds,
		});

		expect(frame.itemMetadata.map((item) => item.itemId)).toEqual([
			...visibleItemIds,
			...(selectedItemId === null || visibleItemIds.includes(selectedItemId)
				? []
				: [selectedItemId]),
		]);
		expect(frame.treeRows.map((row) => row.itemId)).toEqual(
			frame.itemMetadata.map((item) => item.itemId),
		);
		expect(uniqueExtentFactItemIds(frame.extentFacts)).toEqual(
			frame.itemMetadata.map((item) => item.itemId),
		);
		expect(
			frame.comparison.contentDescriptors?.every((attachedDescriptor) =>
				frame.itemMetadata.some((item) =>
					Object.values(item.contentDescriptorIdsByRole ?? {}).includes(
						attachedDescriptor.ref.descriptorId,
					),
				),
			),
		).toBe(true);
	});

	test('emits exact extent facts for each available content role', () => {
		const reviewPackage = makePackageWithExactRoleLineCounts();

		const frame = buildReviewMetadataSnapshotFrame({
			package: reviewPackage,
			paneId: 'pane-1',
			sourceIdentity: reviewPackage.query.queryId,
			streamId: 'review:pane-1',
			sequence: reviewPackage.revision,
			selectedItemId: 'item-source',
			visibleItemIds: ['item-source'],
		});

		expect(frame.extentFacts).toEqual([
			{ itemId: 'item-source', contentRole: 'base', lineCount: 17 },
			{ itemId: 'item-source', contentRole: 'head', lineCount: 19 },
		]);
	});

	test('omits browser integrity for host content hashes the browser cannot verify', () => {
		const reviewPackage = makePackageWithHostContentHashAlgorithm();

		const frame = buildReviewMetadataSnapshotFrame({
			package: reviewPackage,
			paneId: 'pane-1',
			sourceIdentity: reviewPackage.query.queryId,
			streamId: 'review:pane-1',
			sequence: reviewPackage.revision,
			selectedItemId: reviewPackage.orderedItemIds[0] ?? null,
			visibleItemIds: reviewPackage.orderedItemIds.slice(0, 2),
		});

		const descriptor = frame.comparison.contentDescriptors?.find(
			(attachedDescriptor) => attachedDescriptor.ref.descriptorId === 'handle-item-source-head',
		);
		expect(descriptor?.descriptor.content.integrity).toBeUndefined();
	});

	test('preserves browser-verifiable sha256 integrity values with their algorithm prefix', () => {
		const reviewPackage = makePackageWithBrowserVerifiableContentHash();

		const frame = buildReviewMetadataSnapshotFrame({
			package: reviewPackage,
			paneId: 'pane-1',
			sourceIdentity: reviewPackage.query.queryId,
			streamId: 'review:pane-1',
			sequence: reviewPackage.revision,
			selectedItemId: reviewPackage.orderedItemIds[0] ?? null,
			visibleItemIds: reviewPackage.orderedItemIds.slice(0, 2),
		});

		const descriptor = frame.comparison.contentDescriptors?.find(
			(attachedDescriptor) => attachedDescriptor.ref.descriptorId === 'handle-item-source-head',
		);
		expect(descriptor?.descriptor.content.integrity).toEqual({
			kind: 'wholeHash',
			algorithm: 'sha256',
			value: 'sha256:1fd3b09376e42af78657b7cb28d101699a1ac7ff4bc9232f32e71bcbdff17b7c',
		});
	});

	test('preserves builder-supplied changeset cluster metadata', () => {
		const reviewPackage = makeBridgeReviewPackage();

		const frame = buildReviewMetadataSnapshotFrame({
			package: reviewPackage,
			paneId: 'pane-1',
			sourceIdentity: reviewPackage.query.queryId,
			streamId: 'review:pane-1',
			sequence: reviewPackage.revision,
			selectedItemId: reviewPackage.orderedItemIds[0] ?? null,
			visibleItemIds: reviewPackage.orderedItemIds.slice(0, 2),
			changesetCluster: {
				clusterId: 'cluster-1',
				sourceId: reviewPackage.query.queryId,
				algorithm: 'idleDebounce',
				lifecycle: 'live',
				confidence: 'freshScan',
				baselineCursor: 'cursor-a',
				headCursor: 'cursor-b',
				includedPathHints: ['Sources/App/View.swift'],
				groupingReason: 'agent idle debounce closed the batch',
				limitations: ['overflowRecovered'],
			},
		});

		expect(frame.comparison.changesetCluster).toEqual({
			clusterId: 'cluster-1',
			sourceId: reviewPackage.query.queryId,
			algorithm: 'idleDebounce',
			lifecycle: 'live',
			confidence: 'freshScan',
			baselineCursor: 'cursor-a',
			headCursor: 'cursor-b',
			includedPathHints: ['Sources/App/View.swift'],
			groupingReason: 'agent idle debounce closed the batch',
			limitations: ['overflowRecovered'],
		});
	});

	test('builds metadata deltas with inline operations and no operations body descriptor', () => {
		const reviewPackage = makeBridgeReviewPackage();

		const frame = buildReviewMetadataDeltaFrame({
			package: reviewPackage,
			paneId: 'pane-1',
			sourceIdentity: reviewPackage.query.queryId,
			streamId: 'review:pane-1',
			sequence: reviewPackage.revision,
			fromRevision: reviewPackage.revision - 1,
			toRevision: reviewPackage.revision,
			operations: [{ kind: 'replaceItemOrder', itemIds: reviewPackage.orderedItemIds }],
		});

		expect(frame.frameKind).toBe('review.metadataDelta');
		expect(frame.kind).toBe('metadataDelta');
		expect(frame.packageId).toBe(reviewPackage.packageId);
		expect(frame.fromRevision).toBe(reviewPackage.revision - 1);
		expect(frame.toRevision).toBe(reviewPackage.revision);
		expect(frame.summary).toEqual(reviewPackage.summary);
		expect(frame.operations).toEqual([
			{ kind: 'replaceItemOrder', itemIds: reviewPackage.orderedItemIds },
		]);
		expect(frame).not.toHaveProperty('operationsDescriptor');
		expect(frame.contentDescriptors).toBeUndefined();
	});

	test('builds bounded metadata windows with content descriptors only for window items', () => {
		const reviewPackage = makeBridgeReviewPackage();
		const itemIds = reviewPackage.orderedItemIds.filter((itemId) => {
			const item = reviewPackage.itemsById[itemId];
			return (
				item !== undefined &&
				Object.values(item.contentRoles).some((handle) => handle !== null && handle !== undefined)
			);
		});

		const frame = buildReviewMetadataWindowFrame({
			package: reviewPackage,
			paneId: 'pane-1',
			sourceIdentity: reviewPackage.query.queryId,
			streamId: 'review:pane-1',
			sequence: reviewPackage.revision + 1,
			itemIds,
		});

		expect(frame.frameKind).toBe('review.metadataWindow');
		expect(frame.kind).toBe('metadataWindow');
		expect(frame.packageId).toBe(reviewPackage.packageId);
		expect(frame.summary).toEqual(reviewPackage.summary);
		expect(frame.itemMetadata.map((item) => item.itemId)).toEqual(itemIds);
		expect(frame.treeRows.map((row) => row.itemId)).toEqual(itemIds);
		expect(uniqueExtentFactItemIds(frame.extentFacts)).toEqual(itemIds);
		expect(frame.contentDescriptors?.length).toBeGreaterThan(0);
		expect(
			frame.contentDescriptors?.every((attachedDescriptor) =>
				frame.itemMetadata.some((item) =>
					Object.values(item.contentDescriptorIdsByRole ?? {}).includes(
						attachedDescriptor.ref.descriptorId,
					),
				),
			),
		).toBe(true);
	});
});

function makePackageWithExactRoleLineCounts(): BridgeReviewPackage {
	const reviewPackage = makeBridgeReviewPackage();
	const item = reviewPackage.itemsById['item-source'];
	if (item === undefined) {
		throw new Error('Expected item-source review item');
	}
	const updatedItem: BridgeReviewItemDescriptor = {
		...item,
		contentLineCountsByRole: {
			base: 17,
			head: 19,
		},
	};
	return {
		...reviewPackage,
		itemsById: { ...reviewPackage.itemsById, [updatedItem.itemId]: updatedItem },
	};
}

function uniqueExtentFactItemIds(
	extentFacts: readonly { readonly itemId: string }[],
): readonly string[] {
	return [...new Set(extentFacts.map((fact) => fact.itemId))];
}

function makePackageWithHostContentHashAlgorithm(): BridgeReviewPackage {
	const reviewPackage = makeBridgeReviewPackage();
	const item = reviewPackage.itemsById['item-source'];
	if (
		item === undefined ||
		item.contentRoles.head === null ||
		item.contentRoles.head === undefined
	) {
		throw new Error('Expected item-source head content handle');
	}
	const head: BridgeContentHandle = {
		...item.contentRoles.head,
		contentHash: 'git-oid:abc123',
		contentHashAlgorithm: 'git-oid',
	};
	const updatedItem: BridgeReviewItemDescriptor = {
		...item,
		contentHashAlgorithm: 'git-oid',
		headContentHash: head.contentHash,
		contentRoles: { ...item.contentRoles, head },
	};
	return {
		...reviewPackage,
		itemsById: { ...reviewPackage.itemsById, [updatedItem.itemId]: updatedItem },
	};
}

function makePackageWithBrowserVerifiableContentHash(): BridgeReviewPackage {
	const reviewPackage = makeBridgeReviewPackage();
	const item = reviewPackage.itemsById['item-source'];
	if (
		item === undefined ||
		item.contentRoles.head === null ||
		item.contentRoles.head === undefined
	) {
		throw new Error('Expected item-source head content handle');
	}
	const head: BridgeContentHandle = {
		...item.contentRoles.head,
		contentHash: 'sha256:1fd3b09376e42af78657b7cb28d101699a1ac7ff4bc9232f32e71bcbdff17b7c',
		contentHashAlgorithm: 'sha256',
	};
	const updatedItem: BridgeReviewItemDescriptor = {
		...item,
		contentHashAlgorithm: 'sha256',
		headContentHash: head.contentHash,
		contentRoles: { ...item.contentRoles, head },
	};
	return {
		...reviewPackage,
		itemsById: { ...reviewPackage.itemsById, [updatedItem.itemId]: updatedItem },
	};
}

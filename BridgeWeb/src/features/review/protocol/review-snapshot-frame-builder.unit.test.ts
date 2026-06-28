import { describe, expect, test } from 'vitest';

import { makeBridgeReviewPackage } from '../../../foundation/review-package/bridge-review-package-test-support.js';
import type {
	BridgeContentHandle,
	BridgeReviewItemDescriptor,
	BridgeReviewPackage,
} from '../../../foundation/review-package/bridge-review-package.js';
import {
	buildReviewDeltaFrame,
	buildReviewSnapshotFrame,
} from './review-snapshot-frame-builder.js';

describe('review snapshot frame builder', () => {
	test('attaches root and content descriptors for browser dev hosts', () => {
		const reviewPackage = makeBridgeReviewPackage();

		const frame = buildReviewSnapshotFrame({
			package: reviewPackage,
			paneId: 'pane-1',
			sourceIdentity: reviewPackage.query.queryId,
			streamId: 'review:pane-1',
			sequence: reviewPackage.revision,
		});

		expect(frame.package.rootDescriptor.descriptor.resourceKind).toBe('review-package');
		const packageByteLength = new TextEncoder().encode(JSON.stringify(reviewPackage)).byteLength;
		expect(frame.package.rootDescriptor.descriptor.content.expectedBytes).toBe(packageByteLength);
		expect(frame.package.rootDescriptor.descriptor.content.maxBytes).toBe(packageByteLength);
		expect(frame.package.contentDescriptors?.length).toBeGreaterThan(0);
		expect(frame.package.contentDescriptors?.[0]?.descriptor.resourceKind).toBe('content');
		expect(frame.package.contentDescriptors?.[0]?.ref.expectedIdentity.paneId).toBe('pane-1');
	});

	test('emits preview-only integrity for host content hashes the browser cannot verify', () => {
		const reviewPackage = makePackageWithHostContentHashAlgorithm();

		const frame = buildReviewSnapshotFrame({
			package: reviewPackage,
			paneId: 'pane-1',
			sourceIdentity: reviewPackage.query.queryId,
			streamId: 'review:pane-1',
			sequence: reviewPackage.revision,
		});

		const descriptor = frame.package.contentDescriptors?.find(
			(attachedDescriptor) =>
				attachedDescriptor.descriptor.content.integrity?.kind === 'previewOnly',
		);
		expect(descriptor?.descriptor.content.integrity).toEqual({ kind: 'previewOnly' });
	});

	test('preserves builder-supplied changeset cluster metadata', () => {
		const reviewPackage = makeBridgeReviewPackage();

		const frame = buildReviewSnapshotFrame({
			package: reviewPackage,
			paneId: 'pane-1',
			sourceIdentity: reviewPackage.query.queryId,
			streamId: 'review:pane-1',
			sequence: reviewPackage.revision,
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

		expect(frame.package.changesetCluster).toEqual({
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

	test('builds delta frames with operations and content descriptors', () => {
		const reviewPackage = makeBridgeReviewPackage();

		const frame = buildReviewDeltaFrame({
			package: reviewPackage,
			paneId: 'pane-1',
			sourceIdentity: reviewPackage.query.queryId,
			streamId: 'review:pane-1',
			sequence: reviewPackage.revision,
			fromRevision: reviewPackage.revision - 1,
			toRevision: reviewPackage.revision,
		});

		expect(frame.frameKind).toBe('review.delta');
		expect(frame.kind).toBe('delta');
		expect(frame.packageId).toBe(reviewPackage.packageId);
		expect(frame.fromRevision).toBe(reviewPackage.revision - 1);
		expect(frame.toRevision).toBe(reviewPackage.revision);
		expect(frame.operationsDescriptor.descriptor.resourceKind).toBe('review-delta');
		expect(frame.operationsDescriptor.descriptor.content.maxBytes).toBe(768 * 1024);
		expect(frame.contentDescriptors?.length).toBeGreaterThan(0);
		expect(frame.contentDescriptors?.[0]?.ref.expectedIdentity.paneId).toBe('pane-1');
	});
});

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

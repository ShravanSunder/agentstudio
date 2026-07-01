import { describe, expect, test } from 'vitest';

import type {
	BridgeAttachedResourceDescriptor,
	BridgeResourceDescriptor,
} from '../../../core/models/bridge-resource-descriptor.js';
import { createBridgeResourceDescriptorRegistry } from '../../../core/resources/bridge-resource-registry.js';
import type { BridgeSourceEndpoint } from '../../../foundation/review-package/bridge-review-package.js';
import type {
	ReviewMetadataDeltaFrame,
	ReviewMetadataSnapshotFrame,
} from '../models/review-protocol-models.js';
import { applyReviewProtocolFrame } from './review-materializer.js';

describe('review materializer', () => {
	test('materializes metadata snapshots without a package body descriptor', () => {
		const registry = createBridgeResourceDescriptorRegistry({
			allowedResourceKindsByProtocol: { review: new Set(['content']) },
		});
		const contentDescriptor = makeAttachedContentDescriptor('descriptor-content');
		const frame = makeMetadataSnapshotFrame({ contentDescriptors: [contentDescriptor] });

		const result = applyReviewProtocolFrame({
			frame,
			paneId: 'pane-1',
			registry,
		});

		expect(result).toEqual({
			ok: true,
			delta: {
				kind: 'metadataSnapshot',
				packageId: 'package-1',
				sourceIdentity: 'review:source-1',
				generation: 1,
				revision: 1,
				baseEndpoint: frame.comparison.baseEndpoint,
				headEndpoint: frame.comparison.headEndpoint,
				selectedItemId: 'item-source',
				visibleItemIds: ['item-source'],
				projectionInput: {
					packageId: 'package-1',
					reviewGeneration: 1,
					revision: 1,
					orderedItems: [frame.itemMetadata[0]],
				},
				treeRows: frame.treeRows,
				extentFacts: frame.extentFacts,
				summary: frame.summary,
				registeredContentDescriptorRefs: [contentDescriptor.ref],
				contentDescriptors: [contentDescriptor],
				changesetCluster: null,
			},
		});
		expect(registry.lookup(contentDescriptor.ref)?.descriptorId).toBe('descriptor-content');
	});

	test('rejects metadata snapshots when an attached descriptor is not content', () => {
		const registry = createBridgeResourceDescriptorRegistry({
			allowedResourceKindsByProtocol: { review: new Set(['content']) },
		});
		const rejectedDescriptor = makeAttachedContentDescriptor('descriptor-rejected', {
			refResourceKind: 'review-package',
		});
		const frame = makeMetadataSnapshotFrame({ contentDescriptors: [rejectedDescriptor] });

		const result = applyReviewProtocolFrame({
			frame,
			paneId: 'pane-1',
			registry,
		});

		expect(result).toEqual({ ok: false, reason: 'descriptor_rejected' });
		expect(registry.lookup(rejectedDescriptor.ref)).toBeNull();
	});

	test('materializes metadata deltas with inline operations and content descriptors only', () => {
		const registry = createBridgeResourceDescriptorRegistry({
			allowedResourceKindsByProtocol: { review: new Set(['content']) },
		});
		const contentDescriptor = makeAttachedContentDescriptor('descriptor-delta-content');
		const frame: ReviewMetadataDeltaFrame = {
			kind: 'metadataDelta',
			streamId: 'stream-1',
			generation: 1,
			sequence: 1,
			frameKind: 'review.metadataDelta',
			packageId: 'package-1',
			fromRevision: 1,
			toRevision: 2,
			operations: [
				{
					kind: 'upsertItemMetadata',
					item: makeProjectionInputItem('item-source'),
				},
			],
			summary: makeReviewSummary(),
			contentDescriptors: [contentDescriptor],
		};

		const result = applyReviewProtocolFrame({
			frame,
			paneId: 'pane-1',
			registry,
		});

		expect(result).toEqual({
			ok: true,
			delta: {
				kind: 'metadataDelta',
				packageId: 'package-1',
				fromRevision: 1,
				toRevision: 2,
				operations: frame.operations,
				summary: frame.summary,
				registeredContentDescriptorRefs: [contentDescriptor.ref],
				contentDescriptors: [contentDescriptor],
			},
		});
		expect(registry.lookup(contentDescriptor.ref)?.descriptorId).toBe('descriptor-delta-content');
	});

	test('materializes metadata windows with content descriptors only', () => {
		const registry = createBridgeResourceDescriptorRegistry({
			allowedResourceKindsByProtocol: { review: new Set(['content']) },
		});
		const contentDescriptor = makeAttachedContentDescriptor('descriptor-window-content');

		const result = applyReviewProtocolFrame({
			frame: {
				kind: 'metadataWindow',
				streamId: 'stream-1',
				generation: 1,
				sequence: 2,
				frameKind: 'review.metadataWindow',
				packageId: 'package-1',
				revision: 1,
				itemMetadata: [makeProjectionInputItem('item-window')],
				treeRows: [
					{
						rowId: 'row-window',
						itemId: 'item-window',
						path: 'Sources/App/Window.swift',
						depth: 2,
						isDirectory: false,
					},
				],
				extentFacts: [
					{
						itemId: 'item-window',
						contentRole: 'diff',
						lineCount: 8,
					},
				],
				summary: makeReviewSummary(),
				contentDescriptors: [contentDescriptor],
			},
			paneId: 'pane-1',
			registry,
		});

		expect(result).toEqual({
			ok: true,
			delta: {
				kind: 'metadataWindow',
				packageId: 'package-1',
				generation: 1,
				revision: 1,
				itemMetadata: [makeProjectionInputItem('item-window')],
				treeRows: [
					{
						rowId: 'row-window',
						itemId: 'item-window',
						path: 'Sources/App/Window.swift',
						depth: 2,
						isDirectory: false,
					},
				],
				extentFacts: [
					{
						itemId: 'item-window',
						contentRole: 'diff',
						lineCount: 8,
					},
				],
				summary: makeReviewSummary(),
				registeredContentDescriptorRefs: [contentDescriptor.ref],
				contentDescriptors: [contentDescriptor],
			},
		});
		expect(registry.lookup(contentDescriptor.ref)?.descriptorId).toBe('descriptor-window-content');
	});

	test('resets source identity and revokes stale content descriptors', () => {
		const registry = createBridgeResourceDescriptorRegistry({
			allowedResourceKindsByProtocol: { review: new Set(['content']) },
		});
		const contentDescriptor = makeAttachedContentDescriptor('descriptor-content');
		const frame = makeMetadataSnapshotFrame({ contentDescriptors: [contentDescriptor] });
		applyReviewProtocolFrame({ frame, paneId: 'pane-1', registry });

		const resetResult = applyReviewProtocolFrame({
			frame: {
				kind: 'reset',
				streamId: 'stream-1',
				generation: 2,
				sequence: 0,
				frameKind: 'review.reset',
				reason: 'authorityChanged',
				sourceIdentity: 'review:source-1',
			},
			paneId: 'pane-1',
			registry,
		});

		expect(resetResult).toEqual({
			ok: true,
			delta: {
				kind: 'reset',
				reason: 'authorityChanged',
				sourceIdentity: 'review:source-1',
			},
		});
		expect(registry.lookup(contentDescriptor.ref)).toBeNull();
	});

	test('materializes invalidation frames as metadata-only facts', () => {
		const registry = createBridgeResourceDescriptorRegistry({
			allowedResourceKindsByProtocol: { review: new Set(['content']) },
		});

		const result = applyReviewProtocolFrame({
			frame: {
				kind: 'delta',
				streamId: 'stream-1',
				generation: 2,
				sequence: 2,
				frameKind: 'review.invalidate',
				invalidation: {
					scope: 'items',
					itemIds: ['item-a'],
					reason: 'watchEvent',
				},
			},
			paneId: 'pane-1',
			registry,
		});

		expect(result).toEqual({
			ok: true,
			delta: {
				kind: 'invalidate',
				scope: 'items',
				itemIds: ['item-a'],
				reason: 'watchEvent',
			},
		});
	});
});

function makeMetadataSnapshotFrame(props?: {
	readonly contentDescriptors?: ReviewMetadataSnapshotFrame['comparison']['contentDescriptors'];
}): ReviewMetadataSnapshotFrame {
	return {
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
			...(props?.contentDescriptors === undefined
				? {}
				: { contentDescriptors: props.contentDescriptors }),
		},
		selectedItemId: 'item-source',
		visibleItemIds: ['item-source'],
		itemMetadata: [makeProjectionInputItem('item-source')],
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
	};
}

function makeReviewSummary(): ReviewMetadataSnapshotFrame['summary'] {
	return {
		filesChanged: 9,
		additions: 17,
		deletions: 5,
		visibleFileCount: 8,
		hiddenFileCount: 1,
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

function makeProjectionInputItem(
	itemId: string,
): ReviewMetadataSnapshotFrame['itemMetadata'][number] {
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

function makeAttachedContentDescriptor(
	descriptorId: string,
	props?: { readonly refResourceKind?: string },
): BridgeAttachedResourceDescriptor {
	const identity = {
		paneId: 'pane-1',
		protocol: 'review',
		sourceId: 'review:source-1',
		packageId: 'package-1',
		generation: 1,
		revision: 1,
		streamId: 'stream-1',
	};
	const descriptor = {
		descriptorId,
		protocol: 'review',
		resourceKind: 'content',
		resourceUrl: `agentstudio://resource/review/content/${descriptorId}?generation=1&revision=1`,
		identity,
		content: {
			mediaType: 'text/x-diff',
			encoding: 'utf-8',
			expectedBytes: 128,
			maxBytes: 1024,
		},
	} satisfies BridgeResourceDescriptor;
	return {
		ref: {
			descriptorId: descriptor.descriptorId,
			expectedProtocol: descriptor.protocol,
			expectedResourceKind: props?.refResourceKind ?? descriptor.resourceKind,
			expectedIdentity: identity,
		},
		descriptor,
	};
}

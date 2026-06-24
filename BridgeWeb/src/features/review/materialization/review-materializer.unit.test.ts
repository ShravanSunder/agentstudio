import { describe, expect, test } from 'vitest';

import type { BridgeResourceDescriptor } from '../../../core/models/bridge-resource-descriptor.js';
import { createBridgeResourceDescriptorRegistry } from '../../../core/resources/bridge-resource-registry.js';
import type { ReviewDeltaFrame, ReviewSnapshotFrame } from '../models/review-protocol-models.js';
import { applyReviewProtocolFrame } from './review-materializer.js';

describe('review materializer', () => {
	test('registers attached descriptors before publishing snapshot facts', () => {
		const registry = createBridgeResourceDescriptorRegistry({
			allowedResourceKindsByProtocol: { review: new Set(['content', 'review-package']) },
		});
		const frame = makeSnapshotFrame();
		const contentDescriptor = makeAttachedDescriptor({
			descriptorId: 'descriptor-content',
			resourceKind: 'content',
		});
		const frameWithContentDescriptor: ReviewSnapshotFrame = {
			...frame,
			package: {
				...frame.package,
				contentDescriptors: [contentDescriptor],
			},
		};

		const result = applyReviewProtocolFrame({
			frame: frameWithContentDescriptor,
			paneId: 'pane-1',
			registry,
		});

		expect(result).toEqual({
			ok: true,
			delta: {
				kind: 'snapshot',
				packageId: 'package-1',
				sourceIdentity: 'review:source-1',
				generation: 1,
				revision: 1,
				rootDescriptorRef: frameWithContentDescriptor.package.rootDescriptor.ref,
				registeredContentDescriptorRefs: [contentDescriptor.ref],
				changesetCluster: null,
			},
		});
		expect(
			registry.lookup(frameWithContentDescriptor.package.rootDescriptor.ref)?.descriptorId,
		).toBe('descriptor-1');
		expect(registry.lookup(contentDescriptor.ref)?.descriptorId).toBe('descriptor-content');
	});

	test('resets source identity and revokes stale descriptors', () => {
		const registry = createBridgeResourceDescriptorRegistry({
			allowedResourceKindsByProtocol: { review: new Set(['content', 'review-package']) },
		});
		const frame = makeSnapshotFrame();
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
				packageId: 'package-1',
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
				packageId: 'package-1',
			},
		});
		expect(registry.lookup(frame.package.rootDescriptor.ref)).toBeNull();
	});

	test('registers reset replacement descriptor after revoking stale authority', () => {
		const registry = createBridgeResourceDescriptorRegistry({
			allowedResourceKindsByProtocol: { review: new Set(['content', 'review-package']) },
		});
		const frame = makeSnapshotFrame();
		applyReviewProtocolFrame({ frame, paneId: 'pane-1', registry });
		const replacementDescriptor = makeAttachedDescriptor({
			descriptorId: 'descriptor-replacement',
			resourceKind: 'review-package',
			generation: 2,
			revision: 2,
		});

		const resetResult = applyReviewProtocolFrame({
			frame: {
				kind: 'reset',
				streamId: 'stream-1',
				generation: 2,
				sequence: 1,
				frameKind: 'review.reset',
				reason: 'authorityChanged',
				sourceIdentity: 'review:source-1',
				packageId: 'package-1',
				replacementDescriptor,
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
				packageId: 'package-1',
				replacementDescriptorRef: replacementDescriptor.ref,
			},
		});
		expect(registry.lookup(frame.package.rootDescriptor.ref)).toBeNull();
		expect(registry.lookup(replacementDescriptor.ref)?.descriptorId).toBe('descriptor-replacement');
	});

	test('rolls back descriptors when snapshot materialization rejects a later descriptor', () => {
		const registry = createBridgeResourceDescriptorRegistry({
			allowedResourceKindsByProtocol: { review: new Set(['content', 'review-package']) },
		});
		const frame = makeSnapshotFrame();
		const acceptedContentDescriptor = makeAttachedDescriptor({
			descriptorId: 'descriptor-content',
			resourceKind: 'content',
		});
		const rejectedContentDescriptor = {
			...makeAttachedDescriptor({
				descriptorId: 'descriptor-rejected',
				resourceKind: 'content',
			}),
			ref: {
				...acceptedContentDescriptor.ref,
				descriptorId: 'descriptor-rejected',
				expectedResourceKind: 'review-package',
			},
		};
		const frameWithRejectedContentDescriptor: ReviewSnapshotFrame = {
			...frame,
			package: {
				...frame.package,
				contentDescriptors: [acceptedContentDescriptor, rejectedContentDescriptor],
			},
		};

		const result = applyReviewProtocolFrame({
			frame: frameWithRejectedContentDescriptor,
			paneId: 'pane-1',
			registry,
		});

		expect(result).toEqual({ ok: false, reason: 'descriptor_rejected' });
		expect(registry.lookup(frame.package.rootDescriptor.ref)).toBeNull();
		expect(registry.lookup(acceptedContentDescriptor.ref)).toBeNull();
		expect(registry.lookup(rejectedContentDescriptor.ref)).toBeNull();
	});

	test('registers delta operations and content descriptors without snapshot fallback', () => {
		const registry = createBridgeResourceDescriptorRegistry({
			allowedResourceKindsByProtocol: {
				review: new Set(['content', 'review-package', 'review-delta']),
			},
		});
		const frame = makeDeltaFrame();
		const contentDescriptor = makeAttachedDescriptor({
			descriptorId: 'descriptor-delta-content',
			resourceKind: 'content',
		});
		const frameWithContentDescriptor: ReviewDeltaFrame = {
			...frame,
			contentDescriptors: [contentDescriptor],
		};

		const result = applyReviewProtocolFrame({
			frame: frameWithContentDescriptor,
			paneId: 'pane-1',
			registry,
		});

		expect(result).toEqual({
			ok: true,
			delta: {
				kind: 'delta',
				packageId: 'package-1',
				fromRevision: 1,
				toRevision: 2,
				operationsDescriptorRef: frame.operationsDescriptor.ref,
				registeredContentDescriptorRefs: [contentDescriptor.ref],
			},
		});
		expect(registry.lookup(frame.operationsDescriptor.ref)?.descriptorId).toBe(
			'descriptor-delta-operations',
		);
		expect(registry.lookup(contentDescriptor.ref)?.descriptorId).toBe('descriptor-delta-content');
	});

	test('rolls back delta descriptors when a later delta content descriptor is rejected', () => {
		const registry = createBridgeResourceDescriptorRegistry({
			allowedResourceKindsByProtocol: {
				review: new Set(['content', 'review-package', 'review-delta']),
			},
		});
		const frame = makeDeltaFrame();
		const acceptedContentDescriptor = makeAttachedDescriptor({
			descriptorId: 'descriptor-delta-content',
			resourceKind: 'content',
		});
		const rejectedContentDescriptor = {
			...makeAttachedDescriptor({
				descriptorId: 'descriptor-delta-rejected',
				resourceKind: 'content',
			}),
			ref: {
				...acceptedContentDescriptor.ref,
				descriptorId: 'descriptor-delta-rejected',
				expectedResourceKind: 'review-package',
			},
		};
		const frameWithRejectedContentDescriptor: ReviewDeltaFrame = {
			...frame,
			contentDescriptors: [acceptedContentDescriptor, rejectedContentDescriptor],
		};

		const result = applyReviewProtocolFrame({
			frame: frameWithRejectedContentDescriptor,
			paneId: 'pane-1',
			registry,
		});

		expect(result).toEqual({ ok: false, reason: 'descriptor_rejected' });
		expect(registry.lookup(frame.operationsDescriptor.ref)).toBeNull();
		expect(registry.lookup(acceptedContentDescriptor.ref)).toBeNull();
		expect(registry.lookup(rejectedContentDescriptor.ref)).toBeNull();
	});

	test('materializes invalidation frames as metadata-only facts', () => {
		const registry = createBridgeResourceDescriptorRegistry({
			allowedResourceKindsByProtocol: { review: new Set(['content', 'review-package']) },
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

function makeSnapshotFrame(): ReviewSnapshotFrame {
	const rootDescriptor = makeAttachedDescriptor({
		descriptorId: 'descriptor-1',
		resourceKind: 'review-package',
	});
	return {
		kind: 'snapshot',
		streamId: 'stream-1',
		generation: 1,
		sequence: 0,
		frameKind: 'review.snapshot',
		package: {
			packageId: 'package-1',
			sourceIdentity: 'review:source-1',
			generation: 1,
			revision: 1,
			rootDescriptor,
		},
	};
}

function makeDeltaFrame(): ReviewDeltaFrame {
	return {
		kind: 'delta',
		streamId: 'stream-1',
		generation: 1,
		sequence: 1,
		frameKind: 'review.delta',
		packageId: 'package-1',
		fromRevision: 1,
		toRevision: 2,
		operationsDescriptor: makeAttachedDescriptor({
			descriptorId: 'descriptor-delta-operations',
			resourceKind: 'review-delta',
		}),
	};
}

function makeAttachedDescriptor(props: {
	readonly descriptorId: string;
	readonly resourceKind: 'content' | 'review-package' | 'review-delta';
	readonly generation?: number;
	readonly revision?: number;
}): ReviewSnapshotFrame['package']['rootDescriptor'] {
	const identity = {
		paneId: 'pane-1',
		protocol: 'review',
		sourceId: 'review:source-1',
		packageId: 'package-1',
		generation: props.generation ?? 1,
		revision: props.revision ?? 1,
		streamId: 'stream-1',
	};
	const descriptor = {
		descriptorId: props.descriptorId,
		protocol: 'review',
		resourceKind: props.resourceKind,
		resourceUrl: `agentstudio://resource/review/${props.resourceKind}/${props.descriptorId}?generation=${identity.generation}&revision=${identity.revision}`,
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

import { describe, expect, test } from 'vitest';

import type {
	BridgeAttachedResourceDescriptor,
	BridgeResourceDescriptor,
} from '../../../core/models/bridge-resource-descriptor.js';
import {
	reviewDemandStimulusSchema,
	reviewDeltaFrameSchema,
	reviewResetFrameSchema,
	reviewSnapshotFrameSchema,
} from './review-protocol-models.js';

describe('review protocol models', () => {
	test('parses review snapshot frames with attached descriptors', () => {
		const attachedDescriptor = makeAttachedDescriptor();

		expect(
			reviewSnapshotFrameSchema.parse({
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
					rootDescriptor: attachedDescriptor,
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
			}),
		).toMatchObject({
			frameKind: 'review.snapshot',
			package: {
				packageId: 'package-1',
				rootDescriptor: attachedDescriptor,
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
		const attachedDescriptor = makeAttachedDescriptor();

		expect(
			reviewSnapshotFrameSchema.safeParse({
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
					rootDescriptor: attachedDescriptor,
				},
				legacyPayload: true,
			}).success,
		).toBe(false);
		expect(
			reviewDeltaFrameSchema.safeParse({
				kind: 'delta',
				streamId: 'stream-1',
				generation: 1,
				sequence: 1,
				frameKind: 'review.delta',
				packageId: 'package-1',
				fromRevision: 1,
				toRevision: 2,
				operationsDescriptor: attachedDescriptor,
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
});

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

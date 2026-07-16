import { describe, expect, test } from 'vitest';

import {
	makeContentRequestDescriptor,
	makeImmediateReviewContentStream,
} from './bridge-comm-worker-runtime-protocol.test-support.js';
import type { BridgeProductContentStream } from './bridge-product-transport-contract.js';
import type { BridgeWorkerReviewContentRequestDescriptor } from './bridge-worker-contracts.js';
import { fetchBridgeWorkerReviewContentResource } from './bridge-worker-review-content-fetch.js';

describe('Bridge worker review content fetch', () => {
	test('opens typed Review content descriptors through the product content stream', async () => {
		const descriptor = makeContentRequestDescriptor({
			role: 'head',
			text: 'hello bridge worker',
		});
		const openedDescriptorIds: string[] = [];

		const result = await fetchBridgeWorkerReviewContentResource({
			descriptor,
			openContent: (openedDescriptor) => {
				openedDescriptorIds.push(openedDescriptor.descriptorId);
				return makeImmediateReviewContentStream(openedDescriptor, 'hello bridge worker');
			},
		});

		expect(openedDescriptorIds).toEqual([descriptor.descriptorId]);
		expect(result).toMatchObject({
			byteLength: 19,
			contentHash: 'sha256:item-1:head:generation-4',
			contentHashAlgorithm: 'fixture-preview',
			descriptorId: descriptor.descriptorId,
			itemId: descriptor.itemId,
			language: 'swift',
			observedSha256: 'a'.repeat(64),
			requestId: `content-request-${descriptor.descriptorId}`,
			role: descriptor.role,
			sourceGeneration: descriptor.reviewGeneration,
			sourceIdentity: descriptor.sourceIdentity,
			sourcePosition: 'whole',
		});
		expect(result.textBytes.byteLength).toBe(19);
		expect(new TextDecoder().decode(result.textBytes)).toBe('hello bridge worker');
	});

	test('accepts a completed stream for an inexact Review byte range', async () => {
		const descriptor = makeContentRequestDescriptor({ role: 'head', text: 'fixture' });
		const maximumBytes = 64;
		const startByte = 128;
		const result = await fetchBridgeWorkerReviewContentResource({
			descriptor: {
				...descriptor,
				declaredByteLength: null,
				maximumBytes,
				wholeByteLength: null,
				window: { ...descriptor.window, maximumBytes, startByte },
			},
			openContent: (openedDescriptor) =>
				makeImmediateReviewContentStream(openedDescriptor, 'hello bridge worker'),
		});

		expect(result).toMatchObject({
			byteLength: 19,
			contentHash: descriptor.contentDigest.value,
			descriptorId: descriptor.descriptorId,
			itemId: descriptor.itemId,
			observedSha256: 'a'.repeat(64),
			requestId: `content-request-${descriptor.descriptorId}`,
			role: descriptor.role,
			sourceGeneration: descriptor.reviewGeneration,
			sourceIdentity: descriptor.sourceIdentity,
			sourcePosition: 'byteRange:128:19',
			text: 'hello bridge worker',
		});
	});

	test('rejects an error terminal from the Review content transport', async () => {
		const descriptor = makeContentRequestDescriptor({ role: 'head', text: 'fixture' });

		await expect(
			fetchBridgeWorkerReviewContentResource({
				descriptor,
				openContent: (openedDescriptor) =>
					makeReviewContentErrorStream(openedDescriptor, 'Review content length mismatch.'),
			}),
		).rejects.toThrow(/length mismatch/i);
	});

	test('rejects a completed stream whose descriptor identity does not match demand', async () => {
		const descriptor = makeContentRequestDescriptor({ role: 'head', text: 'fixture' });
		const mismatchedDescriptor = {
			...descriptor,
			descriptorId: 'descriptor-stale-head-3',
		};

		await expect(
			fetchBridgeWorkerReviewContentResource({
				descriptor,
				openContent: () => makeImmediateReviewContentStream(mismatchedDescriptor, 'stale'),
			}),
		).rejects.toThrow(/terminal descriptor does not match demand/i);
	});

	test('rejects binary descriptors before opening a text content stream', async () => {
		const descriptor = makeContentRequestDescriptor({ role: 'head', text: 'fixture' });
		let openCallCount = 0;

		await expect(
			fetchBridgeWorkerReviewContentResource({
				descriptor: {
					...descriptor,
					encoding: null,
					isBinary: true,
				} as unknown as BridgeWorkerReviewContentRequestDescriptor,
				openContent: (openedDescriptor) => {
					openCallCount += 1;
					return makeImmediateReviewContentStream(openedDescriptor, 'must not open');
				},
			}),
		).rejects.toThrow();
		expect(openCallCount).toBe(0);
	});
});

function makeReviewContentErrorStream(
	descriptor: BridgeWorkerReviewContentRequestDescriptor,
	safeMessage: string,
): BridgeProductContentStream<'review.content'> {
	return {
		contentKind: 'review.content',
		contentRequestId: 'content-request-error',
		frames: emptyContentFrames(),
		terminal: Promise.resolve({
			code: 'invalid_request',
			contentKind: 'review.content',
			descriptorId: descriptor.descriptorId,
			kind: 'error',
			retryable: false,
			safeMessage,
		}),
	};
}

async function* emptyContentFrames(): AsyncIterable<never> {}

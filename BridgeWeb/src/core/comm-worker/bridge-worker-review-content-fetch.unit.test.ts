import { describe, expect, test } from 'vitest';

import {
	makeContentRequestDescriptor,
	makeImmediateReviewContentStream,
} from './bridge-comm-worker-runtime-protocol.test-support.js';
import type { BridgeProductContentStream } from './bridge-product-transport-contract.js';
import type { BridgeWorkerReviewContentRequestDescriptor } from './bridge-worker-contracts.js';
import {
	createSharedBridgeWorkerReviewContentResourceFetch,
	fetchBridgeWorkerReviewContentResource,
} from './bridge-worker-review-content-fetch.js';

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

	test('does not reuse an aborted shared fetch for a new activity signal', async () => {
		// Arrange
		const descriptor = makeContentRequestDescriptor({ role: 'head', text: 'fixture' });
		const openedSignals: AbortSignal[] = [];
		const fetchReviewContentResource = createSharedBridgeWorkerReviewContentResourceFetch({
			openContent: (openedDescriptor, abortSignal) => {
				openedSignals.push(abortSignal);
				if (openedSignals.length > 1) {
					return makeImmediateReviewContentStream(openedDescriptor, 'fresh foreground content');
				}
				return makeAbortRejectedReviewContentStream(abortSignal);
			},
		});
		const hiddenActivity = new AbortController();
		const foregroundActivity = new AbortController();
		const hiddenFetch = fetchReviewContentResource(descriptor, hiddenActivity.signal);
		expect(openedSignals).toEqual([hiddenActivity.signal]);

		// Act
		hiddenActivity.abort('pane-hidden');
		const foregroundFetch = fetchReviewContentResource(descriptor, foregroundActivity.signal);
		const [hiddenResult, foregroundResult] = await Promise.allSettled([
			hiddenFetch,
			foregroundFetch,
		]);

		// Assert
		expect(openedSignals).toEqual([hiddenActivity.signal, foregroundActivity.signal]);
		expect(hiddenResult.status).toBe('rejected');
		expect(foregroundResult.status).toBe('fulfilled');
	});

	test('does not share in-flight Review resources across review generations', async () => {
		// Arrange
		const generationADescriptor = makeContentRequestDescriptor({
			generation: 4,
			role: 'head',
			text: 'unchanged content',
		});
		const generationBDescriptor: BridgeWorkerReviewContentRequestDescriptor = {
			...generationADescriptor,
			reviewGeneration: generationADescriptor.reviewGeneration + 1,
		};
		const generationAStream = createDeferredReviewContentErrorStream(
			generationADescriptor,
			'Review generation authority retired.',
		);
		const openedReviewGenerations: number[] = [];
		const fetchReviewContentResource = createSharedBridgeWorkerReviewContentResourceFetch({
			openContent: (openedDescriptor) => {
				openedReviewGenerations.push(openedDescriptor.reviewGeneration);
				return openedDescriptor.reviewGeneration === generationADescriptor.reviewGeneration
					? generationAStream.stream
					: makeImmediateReviewContentStream(openedDescriptor, 'unchanged content');
			},
		});
		const generationAFetch = fetchReviewContentResource(generationADescriptor);
		const generationBFetch = fetchReviewContentResource(generationBDescriptor);

		// Act
		generationAStream.resolve();
		const [generationAResult, generationBResult] = await Promise.allSettled([
			generationAFetch,
			generationBFetch,
		]);

		// Assert
		expect(openedReviewGenerations).toEqual([
			generationADescriptor.reviewGeneration,
			generationBDescriptor.reviewGeneration,
		]);
		expect(generationAResult.status).toBe('rejected');
		expect(generationBResult).toMatchObject({
			status: 'fulfilled',
			value: {
				descriptorId: generationBDescriptor.descriptorId,
				sourceGeneration: generationBDescriptor.reviewGeneration,
			},
		});
	});
});

interface DeferredReviewContentErrorStream {
	readonly stream: BridgeProductContentStream<'review.content'>;
	readonly resolve: () => void;
}

function createDeferredReviewContentErrorStream(
	descriptor: BridgeWorkerReviewContentRequestDescriptor,
	safeMessage: string,
): DeferredReviewContentErrorStream {
	let resolveTerminal: (() => void) | null = null;
	const terminal: BridgeProductContentStream<'review.content'>['terminal'] = new Promise(
		(resolve) => {
			resolveTerminal = (): void => {
				resolve({
					code: 'invalid_request',
					contentKind: 'review.content',
					descriptorId: descriptor.descriptorId,
					kind: 'error',
					retryable: false,
					safeMessage,
				});
			};
		},
	);
	return {
		stream: {
			contentKind: 'review.content',
			contentRequestId: `content-request-${descriptor.descriptorId}`,
			frames: emptyContentFrames(),
			terminal,
		},
		resolve: (): void => {
			if (resolveTerminal === null) {
				throw new Error('Deferred Review content error resolver was not initialized.');
			}
			resolveTerminal();
		},
	};
}

function makeAbortRejectedReviewContentStream(
	abortSignal: AbortSignal,
): BridgeProductContentStream<'review.content'> {
	return {
		contentKind: 'review.content',
		contentRequestId: 'content-request-aborted-activity',
		frames: emptyContentFrames(),
		terminal: new Promise((_, reject): void => {
			abortSignal.addEventListener('abort', (): void => reject(abortSignal.reason), {
				once: true,
			});
		}),
	};
}

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

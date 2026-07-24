import { describe, expect, test } from 'vitest';

import { createBridgeBodyRegistry } from '../demand/bridge-body-registry.js';
import {
	createDeferredReviewContentStream,
	makeContentRequestDescriptor,
	makeImmediateReviewContentStream,
} from './bridge-comm-worker-runtime-protocol.test-support.js';
import type { BridgeProductContentStream } from './bridge-product-transport-contract.js';
import type { BridgeWorkerReviewContentRequestDescriptor } from './bridge-worker-contracts.js';
import {
	createSharedBridgeWorkerReviewContentResourceFetch,
	fetchBridgeWorkerReviewContentResource,
	type BridgeWorkerResidentReviewContentBody,
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
			contentRequestId: `content-request-${descriptor.descriptorId}`,
			descriptorId: descriptor.descriptorId,
			disposition: 'ready',
			itemId: descriptor.itemId,
			language: 'swift',
			observedSha256: 'a'.repeat(64),
			requestId: `content-request-${descriptor.descriptorId}`,
			role: descriptor.role,
			sourceGeneration: descriptor.reviewGeneration,
			sourceIdentity: descriptor.sourceIdentity,
			sourcePosition: 'whole',
			terminal: {
				descriptorId: descriptor.descriptorId,
				kind: 'complete',
			},
		});
		if (result.disposition !== 'ready') {
			throw new Error('Expected ready Review content.');
		}
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

	test('preserves a non-retryable transport error beside its terminal disposition', async () => {
		const descriptor = makeContentRequestDescriptor({ role: 'head', text: 'fixture' });

		const result = await fetchBridgeWorkerReviewContentResource({
			descriptor,
			openContent: (openedDescriptor) =>
				makeReviewContentErrorStream(openedDescriptor, 'Review content length mismatch.', false),
		});

		expect(result).toMatchObject({
			contentRequestId: 'content-request-error',
			disposition: 'terminal',
			terminal: {
				code: 'invalid_request',
				descriptorId: descriptor.descriptorId,
				kind: 'error',
				retryable: false,
				safeMessage: 'Review content length mismatch.',
			},
		});
	});

	test('preserves a retryable transport error beside its retry-wait disposition', async () => {
		const descriptor = makeContentRequestDescriptor({ role: 'head', text: 'fixture' });

		const result = await fetchBridgeWorkerReviewContentResource({
			descriptor,
			openContent: (openedDescriptor) =>
				makeReviewContentErrorStream(openedDescriptor, 'Review content is temporarily busy.', true),
		});

		expect(result).toMatchObject({
			contentRequestId: 'content-request-error',
			disposition: 'retryWait',
			terminal: {
				code: 'invalid_request',
				descriptorId: descriptor.descriptorId,
				kind: 'error',
				retryable: true,
				safeMessage: 'Review content is temporarily busy.',
			},
		});
	});

	test('preserves a transport reset reason beside its retry-wait disposition', async () => {
		const descriptor = makeContentRequestDescriptor({ role: 'head', text: 'fixture' });

		const result = await fetchBridgeWorkerReviewContentResource({
			descriptor,
			openContent: makeReviewContentResetStream,
		});

		expect(result).toMatchObject({
			contentRequestId: 'content-request-reset',
			disposition: 'retryWait',
			terminal: {
				descriptorId: descriptor.descriptorId,
				kind: 'reset',
				reason: 'stale_source',
				retryable: true,
			},
		});
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
		).resolves.toMatchObject({
			disposition: 'terminal',
			localFailure: {
				code: 'terminal_descriptor_mismatch',
				kind: 'validation',
			},
		});
	});

	test('returns a bounded validation outcome before opening an invalid text descriptor', async () => {
		const descriptor = makeContentRequestDescriptor({ role: 'head', text: 'fixture' });
		let openCallCount = 0;

		const result = await fetchBridgeWorkerReviewContentResource({
			descriptor: {
				...descriptor,
				encoding: null,
				isBinary: true,
			} as unknown as BridgeWorkerReviewContentRequestDescriptor,
			openContent: (openedDescriptor) => {
				openCallCount += 1;
				return makeImmediateReviewContentStream(openedDescriptor, 'must not open');
			},
		});

		expect(result).toMatchObject({
			disposition: 'terminal',
			localFailure: {
				code: 'descriptor_invalid',
				descriptorId: descriptor.descriptorId,
				kind: 'validation',
			},
		});
		expect(openCallCount).toBe(0);
	});

	test('returns a bounded internal outcome when opening the local transport fails', async () => {
		const descriptor = makeContentRequestDescriptor({ role: 'head', text: 'fixture' });

		const result = await fetchBridgeWorkerReviewContentResource({
			descriptor,
			openContent: () => {
				throw new Error('unbounded local failure detail');
			},
		});

		expect(result).toMatchObject({
			disposition: 'terminal',
			localFailure: {
				code: 'internal_failure',
				descriptorId: descriptor.descriptorId,
				kind: 'internal',
				safeMessage: 'Bridge worker Review content failed internally.',
			},
		});
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
		expect(hiddenResult).toMatchObject({
			status: 'fulfilled',
			value: {
				disposition: 'discarded',
				localFailure: { code: 'aborted', kind: 'abort' },
			},
		});
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
		expect(generationAResult).toMatchObject({
			status: 'fulfilled',
			value: {
				disposition: 'terminal',
				terminal: { kind: 'error', retryable: false },
			},
		});
		expect(generationBResult).toMatchObject({
			status: 'fulfilled',
			value: {
				descriptorId: generationBDescriptor.descriptorId,
				sourceGeneration: generationBDescriptor.reviewGeneration,
			},
		});
	});

	test('reuses one resident body across metadata-only authorization reissue', async () => {
		const descriptor = makeContentRequestDescriptor({ role: 'head', text: 'resident body' });
		const reissuedDescriptor: BridgeWorkerReviewContentRequestDescriptor = {
			...descriptor,
			descriptorId: 'descriptor-reissued-authorization',
			endpointId: 'endpoint-reissued-authorization',
			handleId: 'handle-reissued-authorization',
		};
		let openCallCount = 0;
		const fetchReviewContentResource = createSharedBridgeWorkerReviewContentResourceFetch({
			bodyRegistry: createBridgeBodyRegistry({ maxBytes: 1024 }),
			openContent: (openedDescriptor) => {
				openCallCount += 1;
				return makeImmediateReviewContentStream(openedDescriptor, 'resident body');
			},
		});

		const firstResource = await fetchReviewContentResource(descriptor);
		const reissuedResource = await fetchReviewContentResource(reissuedDescriptor);
		if (firstResource.disposition !== 'ready' || reissuedResource.disposition !== 'ready') {
			throw new Error('Expected resident Review content.');
		}

		expect(openCallCount).toBe(1);
		expect(reissuedResource).toMatchObject({
			descriptorId: reissuedDescriptor.descriptorId,
			sourceGeneration: reissuedDescriptor.reviewGeneration,
			sourceIdentity: reissuedDescriptor.sourceIdentity,
			text: firstResource.text,
		});
		expect(reissuedResource.requestId).not.toBe(firstResource.requestId);
		expect(reissuedResource.textBytes).toBe(firstResource.textBytes);
	});

	test('serves an exact resident body without reopening the native content stream', async () => {
		const descriptor = makeContentRequestDescriptor({ role: 'head', text: 'exact resident body' });
		let openCallCount = 0;
		const fetchReviewContentResource = createSharedBridgeWorkerReviewContentResourceFetch({
			bodyRegistry: createBridgeBodyRegistry({ maxBytes: 1024 }),
			openContent: (openedDescriptor) => {
				openCallCount += 1;
				return makeImmediateReviewContentStream(openedDescriptor, 'exact resident body');
			},
		});

		await fetchReviewContentResource(descriptor);
		const residentResource = await fetchReviewContentResource(descriptor);
		if (residentResource.disposition !== 'ready') {
			throw new Error('Expected exact resident Review content.');
		}

		expect(openCallCount).toBe(1);
		expect(residentResource.text).toBe('exact resident body');
	});

	test('reuses one resident diff side and fetches only the changed side', async () => {
		const baseDescriptor = makeContentRequestDescriptor({ role: 'base', text: 'resident base' });
		const originalHeadDescriptor = makeContentRequestDescriptor({
			role: 'head',
			text: 'original head',
		});
		const changedHeadDescriptor: BridgeWorkerReviewContentRequestDescriptor = {
			...originalHeadDescriptor,
			contentDigest: {
				...originalHeadDescriptor.contentDigest,
				value: 'sha256:item-1:head:changed',
			},
		};
		const openedRoles: BridgeWorkerReviewContentRequestDescriptor['role'][] = [];
		const fetchReviewContentResource = createSharedBridgeWorkerReviewContentResourceFetch({
			bodyRegistry: createBridgeBodyRegistry({ maxBytes: 1024 }),
			openContent: (openedDescriptor) => {
				openedRoles.push(openedDescriptor.role);
				return makeImmediateReviewContentStream(
					openedDescriptor,
					openedDescriptor.role === 'base' ? 'resident base' : 'changed head',
				);
			},
		});

		await Promise.all([
			fetchReviewContentResource(baseDescriptor),
			fetchReviewContentResource(originalHeadDescriptor),
		]);
		openedRoles.splice(0);
		const [baseResource, headResource] = await Promise.all([
			fetchReviewContentResource(baseDescriptor),
			fetchReviewContentResource(changedHeadDescriptor),
		]);
		if (baseResource.disposition !== 'ready' || headResource.disposition !== 'ready') {
			throw new Error('Expected reusable Review diff content.');
		}

		expect(openedRoles).toEqual(['head']);
		expect(baseResource.text).toBe('resident base');
		expect(headResource.text).toBe('changed head');
	});

	test('does not reuse a resident body after freshness changes', async () => {
		const descriptor = makeContentRequestDescriptor({ role: 'head', text: 'generation four' });
		const changedDescriptor: BridgeWorkerReviewContentRequestDescriptor = {
			...descriptor,
			contentDigest: {
				...descriptor.contentDigest,
				value: 'sha256:item-1:head:generation-5',
			},
			reviewGeneration: descriptor.reviewGeneration + 1,
			sourceIdentity: 'source-item-1-generation-5',
		};
		const openedGenerations: number[] = [];
		const fetchReviewContentResource = createSharedBridgeWorkerReviewContentResourceFetch({
			bodyRegistry: createBridgeBodyRegistry({ maxBytes: 1024 }),
			openContent: (openedDescriptor) => {
				openedGenerations.push(openedDescriptor.reviewGeneration);
				return makeImmediateReviewContentStream(openedDescriptor, 'fresh body');
			},
		});

		await fetchReviewContentResource(descriptor);
		await fetchReviewContentResource(changedDescriptor);

		expect(openedGenerations).toEqual([4, 5]);
	});

	test('does not retain reset or aborted fetches as resident bodies', async () => {
		const resetDescriptor = makeContentRequestDescriptor({ role: 'base', text: 'reset body' });
		const abortedDescriptor = makeContentRequestDescriptor({ role: 'head', text: 'aborted body' });
		const registry = createBridgeBodyRegistry<BridgeWorkerResidentReviewContentBody>({
			maxBytes: 1024,
		});
		let resetOpenCount = 0;
		let abortedOpenCount = 0;
		const fetchReviewContentResource = createSharedBridgeWorkerReviewContentResourceFetch({
			bodyRegistry: registry,
			openContent: (openedDescriptor, abortSignal) => {
				if (openedDescriptor.role === 'base') {
					resetOpenCount += 1;
					return makeReviewContentResetStream(openedDescriptor);
				}
				abortedOpenCount += 1;
				return makeAbortRejectedReviewContentStream(abortSignal);
			},
		});
		const abortedFetchController = new AbortController();

		await expect(fetchReviewContentResource(resetDescriptor)).resolves.toMatchObject({
			disposition: 'retryWait',
			terminal: { kind: 'reset', reason: 'stale_source' },
		});
		await expect(fetchReviewContentResource(resetDescriptor)).resolves.toMatchObject({
			disposition: 'retryWait',
			terminal: { kind: 'reset', reason: 'stale_source' },
		});
		const abortedFetch = fetchReviewContentResource(
			abortedDescriptor,
			abortedFetchController.signal,
		);
		abortedFetchController.abort('pane-hidden');
		await expect(abortedFetch).resolves.toMatchObject({
			disposition: 'discarded',
			localFailure: { code: 'aborted', kind: 'abort' },
		});

		expect(resetOpenCount).toBe(2);
		expect(abortedOpenCount).toBe(1);
		expect(registry.snapshot()).toEqual({ entryCount: 0, totalBytes: 0 });
	});

	test('does not retain an abort-insensitive late completion as a resident body', async () => {
		const descriptor = makeContentRequestDescriptor({ role: 'head', text: 'late stale body' });
		const registry = createBridgeBodyRegistry<BridgeWorkerResidentReviewContentBody>({
			maxBytes: 1024,
		});
		const lateStream = createDeferredReviewContentStream(descriptor);
		let openCallCount = 0;
		const fetchReviewContentResource = createSharedBridgeWorkerReviewContentResourceFetch({
			bodyRegistry: registry,
			openContent: (openedDescriptor) => {
				openCallCount += 1;
				return openCallCount === 1
					? lateStream.stream
					: makeImmediateReviewContentStream(openedDescriptor, 'fresh body');
			},
		});
		const staleDemand = new AbortController();
		const staleFetch = fetchReviewContentResource(descriptor, staleDemand.signal);

		staleDemand.abort('review-invalidated');
		lateStream.resolve('late stale body');

		await expect(staleFetch).resolves.toMatchObject({
			disposition: 'discarded',
			localFailure: { code: 'aborted', kind: 'abort' },
		});
		expect(registry.snapshot()).toEqual({ entryCount: 0, totalBytes: 0 });
		await expect(fetchReviewContentResource(descriptor)).resolves.toMatchObject({
			text: 'fresh body',
		});
		expect(openCallCount).toBe(2);
	});

	test('does not serve a resident body to an already-aborted demand', async () => {
		const descriptor = makeContentRequestDescriptor({ role: 'head', text: 'resident body' });
		let openCallCount = 0;
		const fetchReviewContentResource = createSharedBridgeWorkerReviewContentResourceFetch({
			bodyRegistry: createBridgeBodyRegistry({ maxBytes: 1024 }),
			openContent: (openedDescriptor) => {
				openCallCount += 1;
				return makeImmediateReviewContentStream(openedDescriptor, 'resident body');
			},
		});
		await fetchReviewContentResource(descriptor);
		const abortedDemand = new AbortController();
		abortedDemand.abort('pane-hidden');

		await expect(
			fetchReviewContentResource(descriptor, abortedDemand.signal),
		).resolves.toMatchObject({
			disposition: 'discarded',
			localFailure: { code: 'aborted', kind: 'abort' },
		});
		expect(openCallCount).toBe(1);
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
	retryable = false,
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
			retryable,
			safeMessage,
		}),
	};
}

function makeReviewContentResetStream(
	descriptor: BridgeWorkerReviewContentRequestDescriptor,
): BridgeProductContentStream<'review.content'> {
	return {
		contentKind: 'review.content',
		contentRequestId: 'content-request-reset',
		frames: emptyContentFrames(),
		terminal: Promise.resolve({
			contentKind: 'review.content',
			descriptorId: descriptor.descriptorId,
			kind: 'reset',
			reason: 'stale_source',
			retryable: true,
		}),
	};
}

async function* emptyContentFrames(): AsyncIterable<never> {}

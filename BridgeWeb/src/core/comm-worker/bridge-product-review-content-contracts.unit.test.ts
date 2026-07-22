import { describe, expect, test } from 'vitest';

import {
	BRIDGE_PRODUCT_MAXIMUM_REVIEW_CONTENT_RANGE_BYTES,
	bridgeProductContentIdentityFromDescriptor,
	bridgeProductContentRequestSchema,
	bridgeProductReviewContentDescriptorSchema,
	bridgeProductReviewContentSourceDescriptorSchema,
	bridgeProductSurfaceForContentKind,
} from './bridge-product-content-contracts.js';
import { BridgeProductContentStreamValidator } from './bridge-product-content-frame-codec.js';

const abcSha256 = 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad';

const reviewContentSource = {
	contentDigest: {
		algorithm: 'git-oid',
		authority: 'provisional',
		value: '0123456789abcdef0123456789abcdef01234567',
	},
	contentKind: 'review.content',
	descriptorId: 'review-descriptor-1',
	encoding: 'utf-8',
	endpointId: 'review-endpoint-1',
	handleId: 'review-handle-1',
	isBinary: false,
	itemId: 'review-item-1',
	language: 'typescript',
	mimeType: 'text/plain',
	packageId: 'review-package-1',
	reviewGeneration: 7,
	role: 'head',
	sourceIdentity: 'review-query-1',
	wholeByteLength: 2_400_000,
} as const;

const reviewContentDescriptor = {
	...reviewContentSource,
	declaredByteLength: null,
	expectedSha256: null,
	maximumBytes: BRIDGE_PRODUCT_MAXIMUM_REVIEW_CONTENT_RANGE_BYTES,
	window: {
		kind: 'byteRange',
		maximumBytes: BRIDGE_PRODUCT_MAXIMUM_REVIEW_CONTENT_RANGE_BYTES,
		startByte: 0,
	},
} as const;

describe('Bridge product Review content contracts', () => {
	test('admits immutable source identity separately from a comm-selected byte range', () => {
		// Arrange / Act
		const source = bridgeProductReviewContentSourceDescriptorSchema.parse(reviewContentSource);
		const descriptor = bridgeProductReviewContentDescriptorSchema.parse(reviewContentDescriptor);
		const identity = bridgeProductContentIdentityFromDescriptor(descriptor);

		// Assert
		expect(source).toEqual(reviewContentSource);
		expect(identity).toEqual({
			contentDigest: reviewContentSource.contentDigest,
			contentKind: 'review.content',
			descriptorId: reviewContentSource.descriptorId,
			endpointId: reviewContentSource.endpointId,
			handleId: reviewContentSource.handleId,
			itemId: reviewContentSource.itemId,
			packageId: reviewContentSource.packageId,
			reviewGeneration: reviewContentSource.reviewGeneration,
			role: reviewContentSource.role,
			sourceIdentity: reviewContentSource.sourceIdentity,
			wholeByteLength: reviewContentSource.wholeByteLength,
			window: reviewContentDescriptor.window,
		});
		expect(bridgeProductSurfaceForContentKind('review.content')).toBe('review');
	});

	test('admits a provisional range request while preserving strict request correlation', () => {
		// Arrange / Act
		const request = bridgeProductContentRequestSchema.parse({
			contentKind: 'review.content',
			contentRequestId: 'review-content-request-1',
			descriptor: reviewContentDescriptor,
			kind: 'content.open',
			leaseId: 'review-content-lease-1',
			paneSessionId: 'pane-session-1',
			wireVersion: 2,
			workerDerivationEpoch: 4,
			workerInstanceId: 'worker-instance-1',
		});

		// Assert
		expect(request.contentKind).toBe('review.content');
		expect(request.descriptor.declaredByteLength).toBeNull();
		expect(request.descriptor.expectedSha256).toBeNull();
	});

	test('validates a complete provisional Review range through the shared content lifecycle', async () => {
		// Arrange
		const request = bridgeProductContentRequestSchema.parse({
			contentKind: 'review.content',
			contentRequestId: 'review-content-request-1',
			descriptor: reviewContentDescriptor,
			kind: 'content.open',
			leaseId: 'review-content-lease-1',
			paneSessionId: 'pane-session-1',
			wireVersion: 2,
			workerDerivationEpoch: 4,
			workerInstanceId: 'worker-instance-1',
		});
		if (request.contentKind !== 'review.content') {
			throw new Error('Expected a Review content request.');
		}
		const validator = new BridgeProductContentStreamValidator<'review.content'>(request);
		const identity = bridgeProductContentIdentityFromDescriptor(request.descriptor);

		// Act
		await validator.accept({
			header: {
				contentRequestId: request.contentRequestId,
				contentSequence: 0,
				declaredByteLength: null,
				expectedSha256: null,
				identity,
				kind: 'content.accepted',
				leaseId: request.leaseId,
				maximumBytes: request.descriptor.maximumBytes,
				paneSessionId: request.paneSessionId,
				wireVersion: 2,
				workerDerivationEpoch: request.workerDerivationEpoch,
				workerInstanceId: request.workerInstanceId,
			},
			payload: new Uint8Array(),
		});
		await validator.accept({
			header: { contentSequence: 1, kind: 'content.data', offsetBytes: 0 },
			payload: Uint8Array.from([97, 98, 99]),
		});
		const terminal = await validator.accept({
			header: {
				contentSequence: 2,
				endOfSource: true,
				kind: 'content.end',
				observedByteLength: 3,
				observedSha256: abcSha256,
			},
			payload: new Uint8Array(),
		});

		// Assert
		expect(terminal).toMatchObject({
			contentKind: 'review.content',
			descriptorId: reviewContentDescriptor.descriptorId,
			kind: 'complete',
			observedSha256: abcSha256,
		});
		expect(terminal?.kind === 'complete' ? new Uint8Array(terminal.bytes) : null).toEqual(
			Uint8Array.from([97, 98, 99]),
		);
	});

	test('rejects Review ranges beyond the courier window policies', () => {
		// Arrange / Act / Assert
		expect(() =>
			bridgeProductReviewContentDescriptorSchema.parse({
				...reviewContentDescriptor,
				maximumBytes: BRIDGE_PRODUCT_MAXIMUM_REVIEW_CONTENT_RANGE_BYTES + 1,
				window: {
					...reviewContentDescriptor.window,
					maximumBytes: BRIDGE_PRODUCT_MAXIMUM_REVIEW_CONTENT_RANGE_BYTES + 1,
				},
			}),
		).toThrow();
	});

	test('rejects binary and non-UTF-8 sources from the text continuation request', () => {
		// Arrange / Act / Assert
		expect(() =>
			bridgeProductReviewContentDescriptorSchema.parse({
				...reviewContentDescriptor,
				isBinary: true,
			}),
		).toThrow();
		expect(() =>
			bridgeProductReviewContentDescriptorSchema.parse({
				...reviewContentDescriptor,
				encoding: null,
			}),
		).toThrow();
	});
});

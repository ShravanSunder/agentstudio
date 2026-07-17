import { describe, expect, test } from 'vitest';

import type { BridgeCommWorkerReviewMetadataSnapshot } from './bridge-comm-worker-review-metadata-projection.js';
import { bridgeCommWorkerReviewRuntimeSourceFromMetadataSnapshot } from './bridge-comm-worker-review-runtime-source-mapper.js';
import type { BridgeProductReviewContentSourceDescriptor } from './bridge-product-content-contracts.js';
import type {
	BridgeProductReviewItemMetadata,
	BridgeProductReviewTreeRow,
} from './bridge-product-review-metadata-contracts.js';

describe('Bridge comm worker Review runtime source mapper', () => {
	test('derives ordered rows, content metadata, request descriptors, and render semantics', () => {
		// Arrange
		const snapshot = reviewMetadataSnapshot({
			contentSources: [
				reviewContentSource({ role: 'head', wholeByteLength: 700_000 }),
				reviewContentSource({ role: 'base', wholeByteLength: 120 }),
			],
			extentFacts: [
				{ contentRole: 'head', itemId: 'item-1', lineCount: 33 },
				{ contentRole: 'base', itemId: 'item-1', lineCount: 21 },
			],
			itemMetadata: [reviewItem()],
			treeRows: [
				reviewTreeRow({
					depth: 0,
					isDirectory: true,
					itemId: null,
					path: 'Sources',
					rowId: 'dir-1',
				}),
				reviewTreeRow({
					depth: 1,
					isDirectory: false,
					itemId: 'item-1',
					path: 'Sources/App.swift',
					rowId: 'row-1',
				}),
			],
		});

		// Act
		const source = bridgeCommWorkerReviewRuntimeSourceFromMetadataSnapshot(snapshot);

		// Assert
		expect(source.rows).toEqual([
			{ id: 'dir-1', index: 0, parentId: null },
			{ id: 'item-1', index: 1, parentId: 'dir-1' },
		]);
		expect(source.contentItems).toEqual([
			{
				availableContentRoles: ['base', 'head'],
				cacheKey: `review:diff:base:sha256:authoritative:${reviewDigestForRole('base')}|head:sha256:authoritative:${reviewDigestForRole('head')}`,
				contentLineCountsByRole: { base: 21, head: 33 },
				itemId: 'item-1',
				language: 'swift',
				path: 'Sources/App.swift',
				sizeBytes: 700_000,
			},
		]);
		expect(source.contentRequestDescriptors).toEqual([
			{
				contentDigest: {
					algorithm: 'sha256',
					authority: 'authoritative',
					value: reviewDigestForRole('base'),
				},
				contentKind: 'review.content',
				declaredByteLength: 120,
				descriptorId: 'descriptor-item-1-base',
				encoding: 'utf-8',
				endpointId: 'base-endpoint',
				expectedSha256: reviewDigestForRole('base'),
				handleId: 'handle-item-1-base',
				isBinary: false,
				itemId: 'item-1',
				language: 'swift',
				maximumBytes: 512 * 1024,
				mimeType: 'text/plain',
				packageId: 'package-1',
				reviewGeneration: 7,
				role: 'base',
				sourceIdentity: 'source-1',
				wholeByteLength: 120,
				window: { kind: 'byteRange', maximumBytes: 512 * 1024, startByte: 0 },
			},
			{
				contentDigest: {
					algorithm: 'sha256',
					authority: 'authoritative',
					value: reviewDigestForRole('head'),
				},
				contentKind: 'review.content',
				declaredByteLength: null,
				descriptorId: 'descriptor-item-1-head',
				encoding: 'utf-8',
				endpointId: 'head-endpoint',
				expectedSha256: null,
				handleId: 'handle-item-1-head',
				isBinary: false,
				itemId: 'item-1',
				language: 'swift',
				maximumBytes: 512 * 1024,
				mimeType: 'text/plain',
				packageId: 'package-1',
				reviewGeneration: 7,
				role: 'head',
				sourceIdentity: 'source-1',
				wholeByteLength: 700_000,
				window: { kind: 'byteRange', maximumBytes: 512 * 1024, startByte: 0 },
			},
		]);
		expect(source.renderSemantics).toEqual([
			{
				basePath: 'Sources/App.swift',
				changeKind: 'modified',
				contentLineCountsByRole: { base: 21, head: 33 },
				displayPath: 'Sources/App.swift',
				headPath: 'Sources/App.swift',
				itemId: 'item-1',
				itemKind: 'diff',
				language: 'swift',
			},
		]);
	});

	test('keeps semantic cache identity stable across transport generation retouch', () => {
		// Arrange
		const originalSnapshot = reviewMetadataSnapshot({
			contentSources: [reviewContentSource({ role: 'file', reviewGeneration: 7 })],
			itemMetadata: [reviewItem({ contentRoles: ['file'] })],
		});
		const retouchedSnapshot = reviewMetadataSnapshot({
			contentSources: [reviewContentSource({ role: 'file', reviewGeneration: 8 })],
			generation: 8,
			itemMetadata: [reviewItem({ contentRoles: ['file'] })],
		});

		// Act
		const originalSource =
			bridgeCommWorkerReviewRuntimeSourceFromMetadataSnapshot(originalSnapshot);
		const retouchedSource =
			bridgeCommWorkerReviewRuntimeSourceFromMetadataSnapshot(retouchedSnapshot);

		// Assert
		expect(retouchedSource.contentItems[0]?.cacheKey).toBe(
			originalSource.contentItems[0]?.cacheKey,
		);
		expect(retouchedSource.renderSemantics[0]?.itemKind).toBe('file');
		expect(retouchedSource.contentRequestDescriptors[0]?.reviewGeneration).toBe(8);
	});

	test('keeps a modified head-only comparison item classified as a diff', () => {
		// Arrange
		const snapshot = reviewMetadataSnapshot({
			contentSources: [reviewContentSource({ role: 'head' })],
			itemMetadata: [reviewItem({ contentRoles: ['head'] })],
		});

		// Act
		const source = bridgeCommWorkerReviewRuntimeSourceFromMetadataSnapshot(snapshot);

		// Assert
		expect(source.renderSemantics[0]?.itemKind).toBe('diff');
	});

	test('does not expose absent, mismatched, or binary sources as renderable roles', () => {
		// Arrange
		const snapshot = reviewMetadataSnapshot({
			contentSources: [
				reviewContentSource({ descriptorId: 'descriptor-foreign', itemId: 'foreign-item' }),
				reviewContentSource({ encoding: null, isBinary: true, role: 'head' }),
			],
			itemMetadata: [reviewItem()],
		});

		// Act
		const source = bridgeCommWorkerReviewRuntimeSourceFromMetadataSnapshot(snapshot);

		// Assert
		expect(source.contentItems[0]?.availableContentRoles).toEqual([]);
		expect(source.contentRequestDescriptors).toEqual([]);
		expect(source.contentItems[0]?.cacheKey).toBe(
			'review:diff:base:metadata:base-item-hash|head:metadata:head-item-hash',
		);
	});
});

function reviewMetadataSnapshot(
	props: {
		readonly contentSources?: readonly BridgeProductReviewContentSourceDescriptor[];
		readonly extentFacts?: BridgeCommWorkerReviewMetadataSnapshot['extentFacts'];
		readonly generation?: number;
		readonly itemMetadata?: readonly BridgeProductReviewItemMetadata[];
		readonly treeRows?: readonly BridgeProductReviewTreeRow[];
	} = {},
): BridgeCommWorkerReviewMetadataSnapshot {
	const itemMetadata = props.itemMetadata ?? [];
	return {
		baseEndpoint: null,
		contentSources: props.contentSources ?? [],
		extentFacts: props.extentFacts ?? [],
		headEndpoint: null,
		identity: {
			generation: props.generation ?? 7,
			packageId: 'package-1',
			publicationId: '00000000-0000-7000-8000-000000000011',
			sourceIdentity: 'source-1',
		},
		itemMetadata,
		orderedItemIds: itemMetadata.map((item) => item.itemId),
		query: null,
		revision: 11,
		summary: null,
		totalItemCount: itemMetadata.length,
		totalTreeRowCount: props.treeRows?.length ?? 0,
		treeRows: props.treeRows ?? [],
	};
}

function reviewItem(
	props: { readonly contentRoles?: BridgeProductReviewItemMetadata['contentRoles'] } = {},
): BridgeProductReviewItemMetadata {
	const contentRoles = props.contentRoles ?? ['base', 'head'];
	return {
		basePath: 'Sources/App.swift',
		changeKind: 'modified',
		contentDescriptorIdsByRole: Object.fromEntries(
			contentRoles.map((role) => [role, `descriptor-item-1-${role}`]),
		),
		contentHashesByRole: Object.fromEntries(
			contentRoles.map((role) => [role, `${role}-item-hash`]),
		),
		contentRoles,
		extension: 'swift',
		fileClass: 'source',
		headPath: 'Sources/App.swift',
		isHiddenByDefault: false,
		itemId: 'item-1',
		language: 'swift',
		mimeTypes: ['text/plain'],
		provenance: { agentSessionIds: [], operationIds: [], promptIds: [] },
		reviewPriority: 'normal',
		reviewState: 'unreviewed',
	};
}

function reviewContentSource(
	props: {
		readonly descriptorId?: string;
		readonly encoding?: 'utf-8' | null;
		readonly isBinary?: boolean;
		readonly itemId?: string;
		readonly reviewGeneration?: number;
		readonly role?: BridgeProductReviewContentSourceDescriptor['role'];
		readonly wholeByteLength?: number | null;
	} = {},
): BridgeProductReviewContentSourceDescriptor {
	const itemId = props.itemId ?? 'item-1';
	const role = props.role ?? 'base';
	return {
		contentDigest: {
			algorithm: 'sha256',
			authority: 'authoritative',
			value: reviewDigestForRole(role),
		},
		contentKind: 'review.content',
		descriptorId: props.descriptorId ?? `descriptor-${itemId}-${role}`,
		encoding: props.encoding === undefined ? 'utf-8' : props.encoding,
		endpointId: role === 'base' ? 'base-endpoint' : 'head-endpoint',
		handleId: `handle-${itemId}-${role}`,
		isBinary: props.isBinary ?? false,
		itemId,
		language: 'swift',
		mimeType: 'text/plain',
		packageId: 'package-1',
		reviewGeneration: props.reviewGeneration ?? 7,
		role,
		sourceIdentity: 'source-1',
		wholeByteLength: props.wholeByteLength === undefined ? 120 : props.wholeByteLength,
	};
}

function reviewDigestForRole(role: BridgeProductReviewContentSourceDescriptor['role']): string {
	const hexadecimalCharacterByRole = {
		base: 'a',
		diff: 'd',
		file: 'f',
		head: 'b',
	} as const;
	return hexadecimalCharacterByRole[role].repeat(64);
}

function reviewTreeRow(props: BridgeProductReviewTreeRow): BridgeProductReviewTreeRow {
	return props;
}

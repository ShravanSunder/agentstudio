import { describe, expect, test } from 'vitest';

import { selectedReviewPreparationIdentity } from './bridge-comm-worker-review-preparation.js';
import type { BridgeCommWorkerReviewRuntimeSource } from './bridge-comm-worker-review-source-diff.js';
import {
	makeContentRequestDescriptor,
	makeRenderSemantics,
	makeWorkerReviewContentMetadata,
} from './bridge-comm-worker-runtime-protocol.test-support.js';

describe('selected Review preparation identity', () => {
	test('is stable for cloned inputs and reordered unrelated source entries', () => {
		const source = makeReviewRuntimeSource();
		const clonedSource = cloneReviewRuntimeSource(source);
		const equivalentSource: BridgeCommWorkerReviewRuntimeSource = {
			contentItems: clonedSource.contentItems.toReversed(),
			contentRequestDescriptors: [
				...clonedSource.contentRequestDescriptors.filter(
					(descriptor) => descriptor.itemId === 'item-2',
				),
				...clonedSource.contentRequestDescriptors.filter(
					(descriptor) => descriptor.itemId === 'item-1',
				),
			],
			renderSemantics: clonedSource.renderSemantics.toReversed(),
			rows: clonedSource.rows.toReversed(),
		};

		expect(identityFor(equivalentSource)).toBe(identityFor(source));
	});

	test('changes when the selected preparation epoch changes', () => {
		const source = makeReviewRuntimeSource();

		expect(identityFor(source, 8)).not.toBe(identityFor(source, 7));
	});

	test('changes when selected item content metadata changes', () => {
		const source = makeReviewRuntimeSource();
		const changedSource: BridgeCommWorkerReviewRuntimeSource = {
			...source,
			contentItems: source.contentItems.map((metadata) =>
				metadata.itemId === 'item-1'
					? { ...metadata, cacheKey: `${metadata.cacheKey}:retouched` }
					: metadata,
			),
		};

		expect(identityFor(changedSource)).not.toBe(identityFor(source));
	});

	test('changes when a selected item content descriptor changes', () => {
		const source = makeReviewRuntimeSource();
		const changedSource: BridgeCommWorkerReviewRuntimeSource = {
			...source,
			contentRequestDescriptors: source.contentRequestDescriptors.map((descriptor) =>
				descriptor.itemId === 'item-1' && descriptor.role === 'head'
					? {
							...descriptor,
							contentDigest: {
								...descriptor.contentDigest,
								value: `${descriptor.contentDigest.value}:retouched`,
							},
						}
					: descriptor,
			),
		};

		expect(identityFor(changedSource)).not.toBe(identityFor(source));
	});

	test('changes when selected item render semantics change', () => {
		const source = makeReviewRuntimeSource();
		const changedSource: BridgeCommWorkerReviewRuntimeSource = {
			...source,
			renderSemantics: source.renderSemantics.map((semantics) =>
				semantics.itemId === 'item-1'
					? { ...semantics, changeKind: 'renamed' as const }
					: semantics,
			),
		};

		expect(identityFor(changedSource)).not.toBe(identityFor(source));
	});

	test('ignores changes scoped to another Review item', () => {
		const source = makeReviewRuntimeSource();
		const changedSource: BridgeCommWorkerReviewRuntimeSource = {
			contentItems: source.contentItems.map((metadata) =>
				metadata.itemId === 'item-2'
					? { ...metadata, cacheKey: `${metadata.cacheKey}:retouched` }
					: metadata,
			),
			contentRequestDescriptors: source.contentRequestDescriptors.map((descriptor) =>
				descriptor.itemId === 'item-2'
					? { ...descriptor, sourceIdentity: `${descriptor.sourceIdentity}:retouched` }
					: descriptor,
			),
			renderSemantics: source.renderSemantics.map((semantics) =>
				semantics.itemId === 'item-2'
					? { ...semantics, displayPath: 'Sources/Other/retouched.swift' }
					: semantics,
			),
			rows: source.rows.map((row) =>
				row.id === 'item-2' ? { ...row, parentId: 'different-directory' } : row,
			),
		};

		expect(identityFor(changedSource)).toBe(identityFor(source));
	});
});

function identityFor(source: BridgeCommWorkerReviewRuntimeSource, epoch = 7): string {
	return selectedReviewPreparationIdentity({
		epoch,
		itemId: 'item-1',
		source,
		workerDerivationEpoch: epoch,
	});
}

function makeReviewRuntimeSource(): BridgeCommWorkerReviewRuntimeSource {
	return {
		contentItems: [
			makeWorkerReviewContentMetadata({ itemId: 'item-1' }),
			makeWorkerReviewContentMetadata({ itemId: 'item-2' }),
		],
		contentRequestDescriptors: [
			makeContentRequestDescriptor({ itemId: 'item-1', role: 'base', text: 'base one\n' }),
			makeContentRequestDescriptor({ itemId: 'item-1', role: 'head', text: 'head one\n' }),
			makeContentRequestDescriptor({ itemId: 'item-2', role: 'base', text: 'base two\n' }),
			makeContentRequestDescriptor({ itemId: 'item-2', role: 'head', text: 'head two\n' }),
		],
		renderSemantics: [
			makeRenderSemantics({ itemId: 'item-1' }),
			makeRenderSemantics({ itemId: 'item-2' }),
		],
		rows: [
			{ id: 'item-1', index: 0, parentId: null },
			{ id: 'item-2', index: 1, parentId: null },
		],
	};
}

function cloneReviewRuntimeSource(
	source: BridgeCommWorkerReviewRuntimeSource,
): BridgeCommWorkerReviewRuntimeSource {
	return {
		contentItems: source.contentItems.map((metadata) => ({
			...metadata,
			availableContentRoles: [...metadata.availableContentRoles],
			contentLineCountsByRole: { ...metadata.contentLineCountsByRole },
		})),
		contentRequestDescriptors: source.contentRequestDescriptors.map((descriptor) => ({
			...descriptor,
			contentDigest: { ...descriptor.contentDigest },
			window: { ...descriptor.window },
		})),
		renderSemantics: source.renderSemantics.map((semantics) => ({
			...semantics,
			contentLineCountsByRole: { ...semantics.contentLineCountsByRole },
		})),
		rows: source.rows.map((row) => ({ ...row })),
	};
}

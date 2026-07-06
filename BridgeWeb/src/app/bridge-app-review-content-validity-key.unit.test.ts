import { describe, expect, test } from 'vitest';

import type { ReviewMaterializerDelta } from '../features/review/materialization/review-materializer.js';
import { makeBridgeReviewPackage } from '../foundation/review-package/bridge-review-package-test-support.js';
import type { BridgeReviewPackage } from '../foundation/review-package/bridge-review-package.js';
import { makeSelectedContentResourcesKey } from './bridge-app-review-selection-state.js';
import { applyReviewMetadataDeltaToReviewPackage } from './bridge-app.js';

type ReviewDeltaMaterializerDelta = Extract<
	ReviewMaterializerDelta,
	{ readonly kind: 'metadataDelta' }
>;

function extentFactDelta(props: {
	readonly packageId: string;
	readonly fromRevision: number;
	readonly facts: readonly {
		readonly itemId: string;
		readonly contentRole: 'base' | 'head';
		readonly lineCount: number;
	}[];
	readonly summary: BridgeReviewPackage['summary'];
}): ReviewDeltaMaterializerDelta {
	return {
		kind: 'metadataDelta',
		packageId: props.packageId,
		fromRevision: props.fromRevision,
		toRevision: props.fromRevision + 1,
		operations: [{ kind: 'upsertExtentFacts', facts: [...props.facts] }],
		summary: props.summary,
		registeredContentDescriptorRefs: [],
		contentDescriptors: [],
	};
}

describe('selected review content key', () => {
	test('stays stable across a metadata-only revision bump', () => {
		const reviewPackage = makeBridgeReviewPackage();
		const keyAtLoadStart = makeSelectedContentResourcesKey(reviewPackage, 'item-source');
		const nextReviewPackage = applyReviewMetadataDeltaToReviewPackage({
			reviewPackage,
			deltaFrame: extentFactDelta({
				packageId: reviewPackage.packageId,
				fromRevision: reviewPackage.revision,
				facts: [{ itemId: 'item-source', contentRole: 'head', lineCount: 41 }],
				summary: reviewPackage.summary,
			}),
		});
		if (nextReviewPackage === null) {
			throw new Error('Expected extent-fact delta to apply');
		}

		expect(makeSelectedContentResourcesKey(nextReviewPackage, 'item-source')).toBe(keyAtLoadStart);
	});

	test('changes when selected content hash changes', () => {
		const reviewPackage = makeBridgeReviewPackage();
		const keyAtLoadStart = makeSelectedContentResourcesKey(reviewPackage, 'item-source');
		const item = reviewPackage.itemsById['item-source'];
		const headHandle = item?.contentRoles.head ?? null;
		if (item === undefined || headHandle === null) {
			throw new Error('Expected modified item with head handle');
		}
		const changedPackage = {
			...reviewPackage,
			itemsById: {
				...reviewPackage.itemsById,
				[item.itemId]: {
					...item,
					contentRoles: {
						...item.contentRoles,
						head: {
							...headHandle,
							contentHash: `${headHandle.contentHash}:changed`,
						},
					},
				},
			},
		} satisfies BridgeReviewPackage;

		expect(makeSelectedContentResourcesKey(changedPackage, 'item-source')).not.toBe(keyAtLoadStart);
	});

	test('changes when review generation rotates', () => {
		const reviewPackage = makeBridgeReviewPackage();
		const keyAtLoadStart = makeSelectedContentResourcesKey(reviewPackage, 'item-source');
		const nextGenerationPackage = {
			...reviewPackage,
			reviewGeneration: reviewPackage.reviewGeneration + 1,
		} satisfies BridgeReviewPackage;

		expect(makeSelectedContentResourcesKey(nextGenerationPackage, 'item-source')).not.toBe(
			keyAtLoadStart,
		);
	});
});

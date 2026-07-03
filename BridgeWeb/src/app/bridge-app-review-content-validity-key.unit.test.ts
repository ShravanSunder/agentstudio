import { describe, expect, test } from 'vitest';

import type { ReviewMaterializerDelta } from '../features/review/materialization/review-materializer.js';
import { makeBridgeReviewPackage } from '../foundation/review-package/bridge-review-package-test-support.js';
import {
	makeSelectedContentResourcesKey,
	selectedContentResourcesForCurrentSelection,
} from './bridge-app-review-selection-state.js';
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
	readonly summary: ReturnType<typeof makeBridgeReviewPackage>['summary'];
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

// The review content-validity key must be content-addressed: benign metadata re-delivery (extent
// facts, path/summary/tree updates) bumps the package revision constantly in a busy multi-worktree
// workspace, but must NOT invalidate already-loaded content whose contentHash is unchanged. A real
// contentHash change or a generation rotation must still invalidate. See
// makeReviewItemContentResourcesKey.
describe('review content-validity key is content-addressed, not revision-stamped', () => {
	test('keeps loaded selected content across an extent-fact revision bump (contentHash unchanged)', () => {
		const reviewPackage = makeBridgeReviewPackage();
		const item = reviewPackage.itemsById['item-source'];
		const baseHandle = item?.contentRoles.base ?? null;
		const headHandle = item?.contentRoles.head ?? null;
		if (item === undefined || baseHandle === null || headHandle === null) {
			throw new Error('Expected modified item with base/head handles');
		}
		const loadedState = {
			itemId: 'item-source',
			contentKey: makeSelectedContentResourcesKey(reviewPackage, 'item-source'),
			status: 'ready' as const,
			resources: {
				base: { handle: baseHandle, readText: (): string => 'base body' },
				head: { handle: headHandle, readText: (): string => 'head body' },
			},
		};
		expect(
			selectedContentResourcesForCurrentSelection({
				reviewPackage,
				selectedItemId: 'item-source',
				selectedContentResourcesState: loadedState,
			}),
		).not.toBeNull();

		const nextReviewPackage = applyReviewMetadataDeltaToReviewPackage({
			reviewPackage,
			deltaFrame: extentFactDelta({
				packageId: reviewPackage.packageId,
				fromRevision: reviewPackage.revision,
				facts: [
					{ itemId: 'item-source', contentRole: 'base', lineCount: 17 },
					{ itemId: 'item-source', contentRole: 'head', lineCount: 23 },
				],
				summary: reviewPackage.summary,
			}),
		});
		if (nextReviewPackage === null) {
			throw new Error('Expected extent-fact delta to apply');
		}
		// Extent facts preserve the content handles / contentHash (only line counts + cacheKey move).
		expect(nextReviewPackage.itemsById['item-source']?.contentRoles.head?.contentHash).toBe(
			headHandle.contentHash,
		);
		// The loaded content must survive the revision bump because the key is content-addressed.
		expect(
			selectedContentResourcesForCurrentSelection({
				reviewPackage: nextReviewPackage,
				selectedItemId: 'item-source',
				selectedContentResourcesState: loadedState,
			}),
		).not.toBeNull();
	});

	test('keeps the content key stable when a load lands after a revision bump (same contentHash)', () => {
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
		// A load started at the old revision still matches when it lands at the new revision.
		expect(makeSelectedContentResourcesKey(nextReviewPackage, 'item-source')).toBe(keyAtLoadStart);
	});

	test('invalidates loaded selected content when the contentHash actually changes', () => {
		const reviewPackage = makeBridgeReviewPackage();
		const item = reviewPackage.itemsById['item-source'];
		const headHandle = item?.contentRoles.head ?? null;
		if (item === undefined || headHandle === null) {
			throw new Error('Expected modified item with head handle');
		}
		const loadedState = {
			itemId: 'item-source',
			contentKey: makeSelectedContentResourcesKey(reviewPackage, 'item-source'),
			status: 'ready' as const,
			resources: { head: { handle: headHandle, readText: (): string => 'head body' } },
		};
		const changedPackage = {
			...reviewPackage,
			itemsById: {
				...reviewPackage.itemsById,
				'item-source': {
					...item,
					contentRoles: {
						...item.contentRoles,
						head: { ...headHandle, contentHash: `${headHandle.contentHash}:changed` },
					},
				},
			},
		};
		expect(
			selectedContentResourcesForCurrentSelection({
				reviewPackage: changedPackage,
				selectedItemId: 'item-source',
				selectedContentResourcesState: loadedState,
			}),
		).toBeNull();
	});

	test('invalidates loaded selected content when the review generation rotates', () => {
		const reviewPackage = makeBridgeReviewPackage();
		const item = reviewPackage.itemsById['item-source'];
		const headHandle = item?.contentRoles.head ?? null;
		if (item === undefined || headHandle === null) {
			throw new Error('Expected modified item with head handle');
		}
		const loadedState = {
			itemId: 'item-source',
			contentKey: makeSelectedContentResourcesKey(reviewPackage, 'item-source'),
			status: 'ready' as const,
			resources: { head: { handle: headHandle, readText: (): string => 'head body' } },
		};
		const rotatedPackage = {
			...reviewPackage,
			reviewGeneration: reviewPackage.reviewGeneration + 1,
		};
		expect(
			selectedContentResourcesForCurrentSelection({
				reviewPackage: rotatedPackage,
				selectedItemId: 'item-source',
				selectedContentResourcesState: loadedState,
			}),
		).toBeNull();
	});
});

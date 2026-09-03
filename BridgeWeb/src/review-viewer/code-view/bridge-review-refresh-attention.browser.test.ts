import { describe, expect, test } from 'vitest';

import { makeBridgeReviewPackage } from '../../foundation/review-package/bridge-review-package-test-support.js';
import type { WorktreeAnnotationThreadProjection } from '../../worktree-annotations/worktree-annotation-surface-client.js';
import { bridgeCodeViewReadingPositionItemId } from './bridge-code-view-panel-support.js';
import { reviewItemIdForAnnotationThread } from './use-bridge-code-view-worktree-annotations.js';

describe('Bridge Review refresh semantic attention', () => {
	test('uses the item crossing the leading edge, then the nearest following visible item', () => {
		const scrollOwner = elementWithBounds({ bottom: 300, top: 0 });
		const crossingItem = elementWithBounds({ bottom: 120, top: -80 });
		const followingItem = elementWithBounds({ bottom: 240, top: 120 });

		expect(
			bridgeCodeViewReadingPositionItemId({
				renderedItems: [
					{ element: crossingItem, id: 'item-crossing' },
					{ element: followingItem, id: 'item-following' },
				],
				scrollOwner,
			}),
		).toBe('item-crossing');

		crossingItem.getBoundingClientRect = (): DOMRect => bounds({ bottom: -8, top: -80 });
		expect(
			bridgeCodeViewReadingPositionItemId({
				renderedItems: [
					{ element: crossingItem, id: 'item-before' },
					{ element: followingItem, id: 'item-following' },
				],
				scrollOwner,
			}),
		).toBe('item-following');
	});

	test('publishes no reading owner when no Review item is visible', () => {
		expect(
			bridgeCodeViewReadingPositionItemId({
				renderedItems: [
					{ element: elementWithBounds({ bottom: -1, top: -100 }), id: 'item-before' },
					{ element: elementWithBounds({ bottom: 500, top: 400 }), id: 'item-after' },
				],
				scrollOwner: elementWithBounds({ bottom: 300, top: 0 }),
			}),
		).toBeNull();
	});

	test('maps active Review head and base thread owners to exact package item identities', () => {
		const reviewPackage = makeBridgeReviewPackage();
		const itemId = reviewPackage.orderedItemIds.find((candidateItemId): boolean => {
			const item = reviewPackage.itemsById[candidateItemId];
			return item?.headPath !== null && item?.basePath !== null;
		});
		if (itemId === undefined) throw new Error('Expected one two-sided Review item.');
		const item = reviewPackage.itemsById[itemId];
		if (
			item?.headPath === null ||
			item?.headPath === undefined ||
			item.basePath === null ||
			item.basePath === undefined
		) {
			throw new Error('Expected exact Review base/head paths.');
		}

		expect(
			reviewItemIdForAnnotationThread({
				context: threadContext({ path: item.headPath, sourceRole: 'review_head' }),
				reviewPackage,
			}),
		).toBe(itemId);
		expect(
			reviewItemIdForAnnotationThread({
				context: threadContext({ path: item.basePath, sourceRole: 'review_base' }),
				reviewPackage,
			}),
		).toBe(itemId);
	});
});

function elementWithBounds(input: { readonly bottom: number; readonly top: number }): HTMLElement {
	const element = document.createElement('div');
	element.getBoundingClientRect = (): DOMRect => bounds(input);
	return element;
}

function bounds(input: { readonly bottom: number; readonly top: number }): DOMRect {
	return new DOMRect(0, input.top, 100, input.bottom - input.top);
}

function threadContext(props: {
	readonly path: string;
	readonly sourceRole: 'review_base' | 'review_head';
}): WorktreeAnnotationThreadProjection['context'] {
	const common = {
		endLine: 3,
		path: props.path,
		placement: 'exact',
		resolution: 'open',
		scope: 'located',
		sourceIdentity: 'source-identity',
		startLine: 2,
		threadId: '00000000-0000-7000-8000-000000000001',
	} as const;
	return props.sourceRole === 'review_base'
		? { ...common, diffSide: 'deletions', sourceRole: 'review_base' }
		: { ...common, diffSide: 'additions', sourceRole: 'review_head' };
}

import type { CodeViewHandle } from '@pierre/diffs/react';
import type { MutableRefObject } from 'react';
import { describe, expect, test, vi } from 'vitest';

import { buildBridgeReviewProjection } from '../navigation/review-projection.js';
import { makeBridgeViewerProjectionFixture } from '../test-support/review-viewer-fixtures.js';
import {
	consumeBridgeCodeViewPendingHydrationAnchor,
	type ConsumeBridgeCodeViewPendingHydrationAnchorProps,
} from './bridge-code-view-hydration-anchor.js';
import { createBridgeCodeViewInitialItems } from './bridge-code-view-materialization.js';

describe('Bridge CodeView hydration anchor', () => {
	test('consumes one matching obligation only after selected content is materialized', () => {
		// Arrange
		const fixture = hydrationAnchorFixture();
		const scheduleRetarget = vi.fn();
		const props = hydrationAnchorProps({
			contentState: 'hydrated',
			fixture,
			scheduleRetarget,
		});

		// Act
		const didConsume = consumeBridgeCodeViewPendingHydrationAnchor(props);
		const didConsumeAgain = consumeBridgeCodeViewPendingHydrationAnchor(props);

		// Assert
		expect(didConsume).toBe(true);
		expect(didConsumeAgain).toBe(false);
		expect(props.pendingPreHydrationSelectionScrollKeyRef.current).toBeNull();
		expect(props.completedSelectionScrollKeyRef.current).toBe(fixture.selectionScrollKey);
		expect(props.settledInstantSelectionRevealKeyRef.current).toBeNull();
		expect(props.recentInstantSelectionRevealRef.current).toEqual({
			itemId: fixture.itemId,
			revealedAtMilliseconds: 1_500,
			selectionScrollKey: fixture.selectionScrollKey,
		});
		expect(scheduleRetarget).toHaveBeenCalledTimes(1);
	});

	test('retains the obligation while the selected record is still a placeholder', () => {
		// Arrange
		const fixture = hydrationAnchorFixture();
		const scheduleRetarget = vi.fn();
		const props = hydrationAnchorProps({
			contentState: 'placeholder',
			fixture,
			scheduleRetarget,
		});

		// Act
		const didConsume = consumeBridgeCodeViewPendingHydrationAnchor(props);

		// Assert
		expect(didConsume).toBe(false);
		expect(props.pendingPreHydrationSelectionScrollKeyRef.current).toBe(
			fixture.selectionScrollKey,
		);
		expect(scheduleRetarget).not.toHaveBeenCalled();
	});

	test('does not consume an obligation from another source, mount, or selection', () => {
		// Arrange
		const fixture = hydrationAnchorFixture();
		const scheduleRetarget = vi.fn();
		const props = hydrationAnchorProps({
			contentState: 'windowed',
			fixture,
			scheduleRetarget,
		});
		props.pendingPreHydrationSelectionScrollKeyRef.current = 'other-source:4:other-item';

		// Act
		const didConsume = consumeBridgeCodeViewPendingHydrationAnchor(props);

		// Assert
		expect(didConsume).toBe(false);
		expect(scheduleRetarget).not.toHaveBeenCalled();
	});
});

function hydrationAnchorFixture(): { readonly itemId: string; readonly selectionScrollKey: string } {
	const reviewPackage = makeBridgeViewerProjectionFixture();
	const itemId = reviewPackage.orderedItemIds[0];
	if (itemId === undefined) throw new Error('Hydration-anchor fixture requires one Review item.');
	return { itemId, selectionScrollKey: `source:3:${itemId}` };
}

function hydrationAnchorProps(props: {
	readonly contentState: 'hydrated' | 'placeholder' | 'windowed';
	readonly fixture: ReturnType<typeof hydrationAnchorFixture>;
	readonly scheduleRetarget: () => void;
}): ConsumeBridgeCodeViewPendingHydrationAnchorProps {
	const reviewPackage = makeBridgeViewerProjectionFixture();
	const projection = buildBridgeReviewProjection({
		request: { facets: [], mode: { kind: 'normalReview' } },
		reviewPackage,
	});
	const initialItem = createBridgeCodeViewInitialItems({ projection, reviewPackage }).find(
		(item): boolean => item.id === props.fixture.itemId,
	);
	if (initialItem === undefined) throw new Error('Hydration-anchor fixture item is missing.');
	const item = {
		...initialItem,
		bridgeMetadata: { ...initialItem.bridgeMetadata, contentState: props.contentState },
	};
	const codeViewHandle = {
		getItem: (itemId: string) => (itemId === props.fixture.itemId ? item : undefined),
	} as unknown as CodeViewHandle<undefined>;
	return {
		codeViewHandle,
		completedSelectionScrollKeyRef: mutableRef<string | null>(null),
		itemId: props.fixture.itemId,
		nowMilliseconds: 1_500,
		pendingPreHydrationSelectionScrollKeyRef: mutableRef<string | null>(
			props.fixture.selectionScrollKey,
		),
		pendingSelectionRevealBehaviorRef: mutableRef<'instant' | null>('instant'),
		pendingSmoothSelectionScrollKeyRef: mutableRef<string | null>(null),
		recentInstantSelectionRevealRef: mutableRef(null),
		scheduleRetarget: props.scheduleRetarget,
		selectionScrollKey: props.fixture.selectionScrollKey,
		settledInstantSelectionRevealKeyRef: mutableRef<string | null>(props.fixture.selectionScrollKey),
	};
}

function mutableRef<TValue>(current: TValue): MutableRefObject<TValue> {
	return { current };
}

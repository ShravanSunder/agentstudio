import { describe, expect, test } from 'vitest';

import { shouldApplyBridgeCodeViewCurrentWindowMaterialization } from './bridge-code-view-panel-support.js';

describe('Bridge CodeView live viewport materialization gate', () => {
	test('applies in-viewport materialization while the settled rendered window is stale', () => {
		expect(
			shouldApplyBridgeCodeViewCurrentWindowMaterialization({
				currentRenderedItemIds: new Set(['stale-above-window']),
				itemId: 'visible-now',
				liveRenderedItemIds: ['visible-now', 'visible-neighbor'],
				orderedItemIds: ['stale-above-window', 'visible-now', 'visible-neighbor', 'below-now'],
				selectedItemId: 'selected-off-window',
			}),
		).toBe(true);
	});

	test('applies below-viewport materialization from the live rendered window top', () => {
		expect(
			shouldApplyBridgeCodeViewCurrentWindowMaterialization({
				currentRenderedItemIds: new Set(['stale-above-window']),
				itemId: 'below-now',
				liveRenderedItemIds: ['visible-now', 'visible-neighbor'],
				orderedItemIds: ['stale-above-window', 'visible-now', 'visible-neighbor', 'below-now'],
				selectedItemId: 'selected-off-window',
			}),
		).toBe(true);
	});

	test('allows a deferred above item when the live range moves back to it', () => {
		const orderedItemIds = ['deferred-above', 'visible-now', 'visible-neighbor'];

		expect(
			shouldApplyBridgeCodeViewCurrentWindowMaterialization({
				currentRenderedItemIds: new Set(['visible-now', 'visible-neighbor']),
				itemId: 'deferred-above',
				liveRenderedItemIds: ['visible-now', 'visible-neighbor'],
				orderedItemIds,
				selectedItemId: 'selected-off-window',
			}),
		).toBe(false);
		expect(
			shouldApplyBridgeCodeViewCurrentWindowMaterialization({
				currentRenderedItemIds: new Set(['visible-now', 'visible-neighbor']),
				itemId: 'deferred-above',
				liveRenderedItemIds: ['deferred-above', 'visible-now'],
				orderedItemIds,
				selectedItemId: 'selected-off-window',
			}),
		).toBe(true);
	});
});

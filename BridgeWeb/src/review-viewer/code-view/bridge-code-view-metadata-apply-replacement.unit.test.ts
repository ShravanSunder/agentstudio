import { describe, expect, test } from 'vitest';

import { bridgeContentDemandExecutionPolicy } from '../../core/demand/bridge-content-demand-policy.js';
import { makeBridgeViewerProjectionFixture } from '../test-support/review-viewer-fixtures.js';
import type { BridgeCodeViewItem } from './bridge-code-view-materialization.js';
import { materializeBridgeCodeViewLoadingItem } from './bridge-code-view-materialization.js';
import { runBridgeCodeViewMetadataApplyInChunks } from './bridge-code-view-metadata-apply.js';

describe('Bridge CodeView metadata apply replacement', () => {
	test('uses setItems replacement for non-reset metadata items that cannot update in place', () => {
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const sourceItem = reviewPackage.itemsById['source-high'];
		if (sourceItem === undefined) {
			throw new Error('expected source fixture item');
		}
		const filePresentationItem = materializeBridgeCodeViewLoadingItem(sourceItem, {
			kind: 'file',
			version: 'head',
		});
		const scheduledTurns: Array<() => void> = [];
		const appliedItemIds: string[] = [];
		const setItemsCalls: Array<readonly BridgeCodeViewItem[]> = [];

		runBridgeCodeViewMetadataApplyInChunks({
			applyItemUpdate: (item): void => {
				appliedItemIds.push(item.id);
			},
			frameBudgetMilliseconds: bridgeContentDemandExecutionPolicy.applyPumpFrameBudgetMilliseconds,
			isStale: (): boolean => false,
			items: [filePresentationItem],
			maxUnitsPerFrame: bridgeContentDemandExecutionPolicy.applyPumpMaxUnitsPerFrame,
			noStarvationSelectedBatchLimit:
				bridgeContentDemandExecutionPolicy.applyPumpNoStarvationSelectedBatchLimit,
			now: (): number => 0,
			onComplete: (): void => {},
			rankForItem: (): 'selected' => 'selected',
			replacementItemsForItem: (): readonly BridgeCodeViewItem[] => [filePresentationItem],
			scheduleNextTurn: (callback): void => {
				scheduledTurns.push(callback);
			},
			setItems: (items): void => {
				setItemsCalls.push(items);
			},
			staleScanLimit: bridgeContentDemandExecutionPolicy.applyPumpStaleScanLimit,
		});

		expect(appliedItemIds).toEqual([]);
		expect(setItemsCalls).toEqual([]);
		scheduledTurns.shift()?.();
		expect(appliedItemIds).toEqual([]);
		expect(setItemsCalls).toEqual([[filePresentationItem]]);
	});
});

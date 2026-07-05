import { readFileSync } from 'node:fs';

import { describe, expect, test } from 'vitest';

import type { BridgeRPCClient, BridgeRPCCommand } from '../bridge/bridge-rpc-client.js';
import {
	createBridgeReviewSelectionControllerInteractionContract,
	scheduleReviewMarkFileViewedCommand,
} from './bridge-app-review-selection-controller.js';

describe('Bridge review selection controller command scheduling', () => {
	test('foreground selection callback stays stable across viewport visibility churn', () => {
		const source = readFileSync(
			new URL('./bridge-app-review-selection-controller.ts', import.meta.url),
			'utf8',
		);
		const callbackSource = source.slice(
			source.indexOf('const beginForegroundReviewSelection = useCallback'),
			source.indexOf('const selectReviewItem = useCallback'),
		);

		expect(callbackSource).not.toContain('viewportSlice.visibleItemIds');
	});

	test('selection interaction cannot subscribe to review root snapshot', () => {
		const contract = createBridgeReviewSelectionControllerInteractionContract();

		expect(contract.subscribedSlices).toEqual([
			'selectionSlice',
			'rowPaintSlice',
			'contentAvailabilitySlice',
			'panelChromeSlice',
		]);
		expect(contract.subscribedSlices).not.toContain('rootSnapshot');
		expect(contract.subscribedSlices).not.toContain('projection');
	});

	test('selection path cannot start FE content retry or parking', () => {
		const source = readFileSync(
			new URL('./bridge-app-review-selection-controller.ts', import.meta.url),
			'utf8',
		);
		const callbackSource = source.slice(
			source.indexOf('const beginForegroundReviewSelection = useCallback'),
			source.indexOf('const selectReviewItem = useCallback'),
		);

		expect(callbackSource).not.toMatch(
			/startSelectedReviewContentDemand|setSelectedContentResourcesState|setForegroundSelectedContentKey|selectedContentAbortControllerRef|selectedContentActiveLoadKeyRef|cancelReviewItemDemand|resourceExecutor/,
		);
	});

	test('selection path commits selected item through the render snapshot callback', () => {
		const source = readFileSync(
			new URL('./bridge-app-review-selection-controller.ts', import.meta.url),
			'utf8',
		);
		const callbackSource = source.slice(
			source.indexOf('const beginForegroundReviewSelection = useCallback'),
			source.indexOf('const selectReviewItem = useCallback'),
		);

		expect(callbackSource).toContain('setSelectedReviewItemId(itemId)');
		expect(callbackSource).toContain('setReviewRenderModeCodeView()');
		expect(callbackSource).not.toContain('viewerActions.setSelectedItemId');
		expect(callbackSource).not.toContain('viewerActions.setRenderMode');
	});

	test('review mode wiring does not pass content-demand owners into selection controller', () => {
		const source = readFileSync(
			new URL('./bridge-app-review-viewer-mode.tsx', import.meta.url),
			'utf8',
		);
		const hookCallSource = source.slice(
			source.indexOf('const {'),
			source.indexOf('useBridgeReviewProjectionCoordinator'),
		);

		expect(hookCallSource).not.toMatch(
			/cancelForegroundSelectionRelease|resourceExecutor|reviewContentDescriptorRefsByHandleIdRef|selectedContentAbortControllerRef|selectedContentActiveLoadKeyRef|setForegroundSelectedContentKey|setSelectedContentResourcesState|startSelectedReviewContentDemand/,
		);
	});

	test('defers markFileViewed RPC dispatch outside the selection call stack', async () => {
		const sentCommands: BridgeRPCCommand[] = [];
		const rpcClient: BridgeRPCClient = {
			sendCommand: (command: BridgeRPCCommand): boolean => {
				sentCommands.push(command);
				return true;
			},
		};

		scheduleReviewMarkFileViewedCommand({
			itemId: 'async-target-item',
			rpcClient,
		});

		expect(sentCommands).toEqual([]);

		await Promise.resolve();

		expect(sentCommands).toEqual([
			{
				method: 'review.markFileViewed',
				params: { fileId: 'async-target-item' },
			},
		]);
	});
});

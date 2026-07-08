import { readFileSync } from 'node:fs';

import { describe, expect, test } from 'vitest';

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

	test('selection path exposes click start for selected content paint telemetry', () => {
		const source = readFileSync(
			new URL('./bridge-app-review-selection-controller.ts', import.meta.url),
			'utf8',
		);
		const controllerContractSource = source.slice(
			source.indexOf('export interface BridgeReviewSelectionController'),
			source.indexOf('export function useBridgeReviewSelectionController'),
		);
		const callbackSource = source.slice(
			source.indexOf('const beginForegroundReviewSelection = useCallback'),
			source.indexOf('const selectReviewItem = useCallback'),
		);

		expect(controllerContractSource).toContain('selectedContentPaintTelemetryStart');
		expect(callbackSource).toContain('setSelectedContentPaintTelemetryStart');
		expect(callbackSource).toContain('startedAtMilliseconds');
		expect(callbackSource).toContain('actionTraceContext');
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

	test('defers markFileViewed worker dispatch outside the selection call stack', async () => {
		const markedItemIds: string[] = [];
		let receivedFailureCallback: (() => void) | undefined;
		let deliveryFailureCount = 0;

		scheduleReviewMarkFileViewedCommand({
			itemId: 'async-target-item',
			markFileViewed: (itemId, onDeliveryFailure): void => {
				markedItemIds.push(itemId);
				receivedFailureCallback = onDeliveryFailure;
			},
			onDeliveryFailure: (): void => {
				deliveryFailureCount += 1;
			},
		});

		expect(markedItemIds).toEqual([]);

		await Promise.resolve();

		expect(markedItemIds).toEqual(['async-target-item']);
		expect(receivedFailureCallback).toBeTypeOf('function');
		receivedFailureCallback?.();
		expect(deliveryFailureCount).toBe(1);
	});
});

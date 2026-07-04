import { describe, expect, test } from 'vitest';

import type { BridgeContentResource } from '../../foundation/content/content-resource-loader.js';
import {
	makeBridgeContentHandle,
	makeBridgeReviewPackage,
} from '../../foundation/review-package/bridge-review-package-test-support.js';
import type {
	BridgeTelemetryBatch,
	BridgeTelemetrySample,
} from '../../foundation/telemetry/bridge-telemetry-event.js';
import { createBridgeTelemetryRecorder } from '../../foundation/telemetry/bridge-telemetry-recorder.js';
import type { BridgeTelemetryRecorder } from '../../foundation/telemetry/bridge-telemetry-recorder.js';
import { buildBridgeReviewProjection } from '../navigation/review-projection.js';
import { makeBridgeViewerProjectionFixture } from '../test-support/review-viewer-fixtures.js';
import { materializeBridgeCodeViewLoadingItem } from './bridge-code-view-materialization.js';
import {
	bridgeCodeViewRenderedHeaderCorrectionTargetPosition,
	shouldApplyBridgeCodeViewRenderedHeaderCorrection,
	shouldRearmCodeViewInstantRevealForMaterialization,
} from './bridge-code-view-panel-support.js';
import {
	makeBridgeCodeViewSourceKey,
	reconcileBridgeCodeViewMetadataItems,
	scheduleSelectedContentPaintedTelemetry,
	selectedContentSummaryForPanel,
	shouldApplyBridgeCodeViewMaterialization,
} from './bridge-code-view-panel.js';

describe('BridgeCodeViewPanel diagnostics', () => {
	test('keys the mounted Pierre viewer by review source and projection identity', () => {
		const reviewPackage = makeBridgeReviewPackage();
		const sameSourceNextRevision = {
			...reviewPackage,
			revision: reviewPackage.revision + 1,
		};
		const differentGeneration = {
			...reviewPackage,
			reviewGeneration: reviewPackage.reviewGeneration + 1,
		};
		const projection = buildBridgeReviewProjection({
			reviewPackage,
			request: { mode: { kind: 'normalReview' }, facets: [] },
		});
		const differentProjection = buildBridgeReviewProjection({
			reviewPackage,
			request: { mode: { kind: 'plansAndSpecs' }, facets: [] },
		});

		expect(makeBridgeCodeViewSourceKey({ projection, reviewPackage: sameSourceNextRevision })).toBe(
			makeBridgeCodeViewSourceKey({ projection, reviewPackage }),
		);
		expect(
			makeBridgeCodeViewSourceKey({ projection, reviewPackage: differentGeneration }),
		).not.toBe(makeBridgeCodeViewSourceKey({ projection, reviewPackage }));
		expect(
			makeBridgeCodeViewSourceKey({ projection: differentProjection, reviewPackage }),
		).not.toBe(makeBridgeCodeViewSourceKey({ projection, reviewPackage }));
	});

	test('reconciles metadata projection changes without blanking hydrated CodeView items', () => {
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const sourceItem = reviewPackage.itemsById['source-high'];
		if (sourceItem === undefined) {
			throw new Error('expected source fixture item');
		}
		const projection = buildBridgeReviewProjection({
			reviewPackage,
			request: { mode: { kind: 'normalReview' }, facets: [] },
		});
		const metadataPlaceholder = materializeBridgeCodeViewLoadingItem(sourceItem);
		const hydratedItem = {
			...metadataPlaceholder,
			bridgeMetadata: {
				...metadataPlaceholder.bridgeMetadata,
				contentState: 'hydrated' as const,
			},
			version: (metadataPlaceholder.version ?? 0) + 1,
		};
		const [metadataItem] = projection.orderedItemIds
			.filter((itemId: string): boolean => itemId === sourceItem.itemId)
			.map(() => metadataPlaceholder);
		if (metadataItem === undefined) {
			throw new Error('expected metadata item');
		}

		const reconciledItems = reconcileBridgeCodeViewMetadataItems({
			getCurrentItem: (itemId: string) => (itemId === sourceItem.itemId ? hydratedItem : undefined),
			metadataItems: [metadataItem],
		});

		expect(reconciledItems).toEqual([hydratedItem]);
	});

	test('keeps selected hydrated CodeView item when metadata window does not include it', () => {
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const sourceItem = reviewPackage.itemsById['source-high'];
		const selectedOffWindowItem = reviewPackage.itemsById['docs-plan'];
		if (sourceItem === undefined || selectedOffWindowItem === undefined) {
			throw new Error('expected source fixture items');
		}
		const metadataItem = materializeBridgeCodeViewLoadingItem(sourceItem);
		const selectedHydratedItem = {
			...materializeBridgeCodeViewLoadingItem(selectedOffWindowItem),
			bridgeMetadata: {
				...materializeBridgeCodeViewLoadingItem(selectedOffWindowItem).bridgeMetadata,
				contentState: 'hydrated' as const,
			},
			version: selectedOffWindowItem.itemVersion + 1,
		};

		const reconciledItems = reconcileBridgeCodeViewMetadataItems({
			getCurrentItem: (itemId: string) =>
				itemId === selectedOffWindowItem.itemId ? selectedHydratedItem : undefined,
			metadataItems: [metadataItem],
			preserveItemIds: [selectedOffWindowItem.itemId],
		});

		expect(reconciledItems.map((item) => item.id)).toEqual([
			sourceItem.itemId,
			selectedOffWindowItem.itemId,
		]);
		expect(reconciledItems[1]).toBe(selectedHydratedItem);
	});

	test('does not read large selected content bodies to build panel summary attributes', () => {
		let readTextCallCount = 0;
		const resource: BridgeContentResource = {
			authoritative: true,
			byteLength: 512_000,
			handle: makeBridgeContentHandle('source-high', 'head'),
			readText: (): string => {
				readTextCallCount += 1;
				return 'large body\n'.repeat(50_000);
			},
		};

		const summary = selectedContentSummaryForPanel({
			selectedContentResources: { head: resource },
		});

		expect(summary.cacheKeyCount).toBe(1);
		expect(summary.characterCount).toBe(512_000);
		expect(summary.lineCount).toBe(0);
		expect(readTextCallCount).toBe(0);
	});

	test('blocks non-selected CodeView materialization while review scroll is active', () => {
		expect(
			shouldApplyBridgeCodeViewMaterialization({
				isScrollActive: true,
				itemId: 'visible-neighbor',
				selectedItemId: 'selected-item',
			}),
		).toBe(false);
		expect(
			shouldApplyBridgeCodeViewMaterialization({
				isScrollActive: true,
				itemId: 'selected-item',
				selectedItemId: 'selected-item',
			}),
		).toBe(true);
		expect(
			shouldApplyBridgeCodeViewMaterialization({
				isScrollActive: false,
				itemId: 'visible-neighbor',
				selectedItemId: 'selected-item',
			}),
		).toBe(true);
	});

	test('re-arms a recent instant reveal when an above-target item materializes', () => {
		const recentReveal = {
			itemId: 'selected-target',
			revealedAtMilliseconds: 1_000,
			selectionScrollKey: 'source:1:selected-target',
		};

		expect(
			shouldRearmCodeViewInstantRevealForMaterialization({
				isSelectedRevealSettled: false,
				materializedItemIds: ['above-target'],
				nowMilliseconds: 1_300,
				orderedItemIds: ['above-target', 'selected-target', 'below-target'],
				rearmWindowMilliseconds: 2_000,
				recentReveal,
				selectedItemId: 'selected-target',
				selectionScrollKey: 'source:1:selected-target',
			}),
		).toBe(true);
		expect(
			shouldRearmCodeViewInstantRevealForMaterialization({
				isSelectedRevealSettled: false,
				materializedItemIds: ['below-target'],
				nowMilliseconds: 1_300,
				orderedItemIds: ['above-target', 'selected-target', 'below-target'],
				rearmWindowMilliseconds: 2_000,
				recentReveal,
				selectedItemId: 'selected-target',
				selectionScrollKey: 'source:1:selected-target',
			}),
		).toBe(false);
		expect(
			shouldRearmCodeViewInstantRevealForMaterialization({
				isSelectedRevealSettled: false,
				materializedItemIds: ['above-target'],
				nowMilliseconds: 3_500,
				orderedItemIds: ['above-target', 'selected-target', 'below-target'],
				rearmWindowMilliseconds: 2_000,
				recentReveal,
				selectedItemId: 'selected-target',
				selectionScrollKey: 'source:1:selected-target',
			}),
		).toBe(false);
	});

	test('does not re-arm a settled selected reveal when another above-target item materializes', () => {
		const recentReveal = {
			itemId: 'selected-target',
			revealedAtMilliseconds: 1_000,
			selectionScrollKey: 'source:1:selected-target',
		};

		expect(
			shouldRearmCodeViewInstantRevealForMaterialization({
				isSelectedRevealSettled: true,
				materializedItemIds: ['above-target'],
				nowMilliseconds: 1_300,
				orderedItemIds: ['above-target', 'selected-target', 'below-target'],
				rearmWindowMilliseconds: 2_000,
				recentReveal,
				selectedItemId: 'selected-target',
				selectionScrollKey: 'source:1:selected-target',
			}),
		).toBe(false);
	});

	test('compensates Pierre position targets for sticky header subtraction', () => {
		expect(
			bridgeCodeViewRenderedHeaderCorrectionTargetPosition({
				currentScrollTop: 1_000,
				renderedHeaderOffset: {
					offsetPixels: 24,
					stickyCompensationPixels: 32,
				},
			}),
		).toBe(1_056);
	});

	test('allows rendered-header correction while selected content is still pending', () => {
		expect(
			shouldApplyBridgeCodeViewRenderedHeaderCorrection({
				didApplyRenderedHeaderCorrection: false,
				isSelectedContentMaterialized: false,
				renderedHeaderOffset: {
					offsetPixels: 24,
					stickyCompensationPixels: 32,
				},
				tolerancePixels: 1,
			}),
		).toBe(true);
	});

	test('emits selected content painted telemetry on the frame after materialization', () => {
		const samples: BridgeTelemetrySample[] = [];
		const frameCallbacks: FrameRequestCallback[] = [];
		const telemetryRecorder = enabledTelemetryRecorder(samples);
		let nowMilliseconds = 130;

		scheduleSelectedContentPaintedTelemetry({
			telemetryRecorder,
			traceContext: null,
			selectionDemandStartedAtMilliseconds: 100,
			materializationStartedAtMilliseconds: 120,
			materializationCompletedAtMilliseconds: 130,
			now: (): number => nowMilliseconds,
			requestAnimationFrame: (callback): number => {
				frameCallbacks.push(callback);
				return frameCallbacks.length;
			},
		});

		expect(samples).toEqual([]);

		nowMilliseconds = 150;
		frameCallbacks[0]?.(150);

		expect(samples).toHaveLength(1);
		expect(samples[0]).toMatchObject({
			name: 'performance.bridge.web.selected_content_painted',
			durationMilliseconds: 50,
			stringAttributes: {
				'agentstudio.bridge.phase': 'selected_content_painted',
				'agentstudio.bridge.viewer': 'review',
			},
			numericAttributes: {
				'agentstudio.bridge.selected_content.click_to_paint_ms': 50,
				'agentstudio.bridge.selected_content.frame_wait_ms': 20,
				'agentstudio.bridge.selected_content.materialize_ms': 30,
			},
		});
	});

	test('force flushes selected content painted telemetry through recorder burst throttling', () => {
		const batches: BridgeTelemetryBatch[] = [];
		const frameCallbacks: FrameRequestCallback[] = [];
		let nowMilliseconds = 1_000;
		const telemetryRecorder = createBridgeTelemetryRecorder(
			{
				enabledScopes: new Set(['web']),
				maxSamplesPerBatch: 4,
				maxEncodedBatchBytes: 16_384,
				minimumFlushIntervalMilliseconds: 250,
				rpcMethodName: 'system.bridgeTelemetry',
				scenario: 'package_apply_content_fetch_v1',
			},
			{
				flush: (batch: BridgeTelemetryBatch): boolean => {
					batches.push(batch);
					return true;
				},
			},
			(): number => nowMilliseconds,
		);
		telemetryRecorder.record({
			scope: 'web',
			name: 'performance.bridge.web.code_view_item_materialize',
			durationMilliseconds: 12,
			traceContext: null,
			stringAttributes: {},
			numericAttributes: {},
			booleanAttributes: {},
		});
		expect(telemetryRecorder.flush()).toBe(true);

		nowMilliseconds = 1_020;
		scheduleSelectedContentPaintedTelemetry({
			telemetryRecorder,
			traceContext: null,
			selectionDemandStartedAtMilliseconds: 900,
			materializationStartedAtMilliseconds: 1_000,
			materializationCompletedAtMilliseconds: 1_010,
			now: (): number => nowMilliseconds,
			requestAnimationFrame: (callback): number => {
				frameCallbacks.push(callback);
				return frameCallbacks.length;
			},
		});
		frameCallbacks[0]?.(1_020);

		expect(batches.map((batch) => batch.samples.map((sample) => sample.name))).toEqual([
			['performance.bridge.web.code_view_item_materialize'],
			['performance.bridge.web.selected_content_painted'],
		]);
	});
});

function enabledTelemetryRecorder(samples: BridgeTelemetrySample[]): BridgeTelemetryRecorder {
	return {
		isEnabled: (scope): boolean => scope === 'web',
		record: (sample): void => {
			samples.push(sample);
		},
		measure: <TResult>(props: { readonly operation: () => TResult }): TResult => props.operation(),
		flush: (): boolean => true,
	};
}

import type { RenderFileResult } from '@pierre/diffs';
import { WorkerPoolManager, type FileRendererInstance } from '@pierre/diffs/worker';
import { describe, expect, test, vi } from 'vitest';

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
import { BridgeCodeViewController } from './bridge-code-view-controller.js';
import {
	type BridgeCodeViewContentResources,
	type BridgeCodeViewItem,
	materializeBridgeCodeViewItem,
	materializeBridgeCodeViewLoadingItem,
} from './bridge-code-view-materialization.js';
import { applyBridgeCodeViewMetadataItems } from './bridge-code-view-metadata-apply.js';
import {
	bridgeCodeViewInitialItemsWithWorkerPreparedCodeViewItems,
	bridgeCodeViewLoadingMaterializationItemIdsForPanel,
	bridgeCodeViewRenderedHeaderCorrectionTargetPosition,
	runBridgeCodeViewMaterializationInChunks,
	recordBridgeCodeViewItemMaterializeTelemetryForPanel,
	shouldSkipBridgeCodeViewItemMaterializationBeforeWork,
	shouldApplyBridgeCodeViewRenderedHeaderCorrection,
	shouldRearmCodeViewInstantRevealForMaterialization,
} from './bridge-code-view-panel-support.js';
import {
	makeBridgeCodeViewSourceKey,
	type BridgeSelectedContentPaintedProbe,
	recordBridgeSelectedContentPaintedProbeAnchoredDelivery,
	reconcileBridgeCodeViewMetadataItems,
	scheduleSelectedContentPaintedTelemetry,
	selectedContentSummaryForPanel,
	shouldScheduleSelectedContentPaintedTelemetry,
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

	test('replaces selected metadata placeholder with worker-prepared CodeView item', () => {
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const sourceItem = reviewPackage.itemsById['source-high'];
		if (sourceItem === undefined) {
			throw new Error('expected source fixture item');
		}
		const placeholderItem = materializeBridgeCodeViewLoadingItem(sourceItem);
		const workerPreparedItem: BridgeCodeViewItem = {
			...placeholderItem,
			bridgeMetadata: {
				...placeholderItem.bridgeMetadata,
				contentState: 'hydrated',
			},
			version: (placeholderItem.version ?? 0) + 1,
		};

		const nextItems = bridgeCodeViewInitialItemsWithWorkerPreparedCodeViewItems({
			initialItems: [placeholderItem],
			selectedCodeViewItem: workerPreparedItem,
			selectedItemId: sourceItem.itemId,
		});

		expect(nextItems).toEqual([workerPreparedItem]);
	});

	test('materializes only selected loading placeholder from worker availability', () => {
		const loadingItemIds = bridgeCodeViewLoadingMaterializationItemIdsForPanel({
			selectedContentLoadingItemId: 'selected-item',
		});

		expect(loadingItemIds).toEqual(['selected-item']);
	});

	test('uses append and patch updates for projection deltas and reserves setItems for source reset', () => {
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const sourceItem = reviewPackage.itemsById['source-high'];
		if (sourceItem === undefined) {
			throw new Error('expected source fixture item');
		}
		const firstItem = materializeBridgeCodeViewLoadingItem(sourceItem);
		const patchedItem: BridgeCodeViewItem = {
			...firstItem,
			version: (firstItem.version ?? 0) + 1,
		};
		const appendedItem: BridgeCodeViewItem = {
			...firstItem,
			id: 'appended-item',
			bridgeMetadata: {
				...firstItem.bridgeMetadata,
				itemId: 'appended-item',
			},
		};
		const model = new RecordingMetadataApplyModel([firstItem]);

		applyBridgeCodeViewMetadataItems({
			applyItemUpdate: (item: BridgeCodeViewItem): void => {
				model.applyItemUpdate(item);
			},
			getCurrentItem: (itemId: string) => model.getItem(itemId),
			items: [patchedItem, appendedItem],
			setItems: (items: readonly BridgeCodeViewItem[]): void => {
				model.setItems(items);
			},
			sourceReset: false,
		});

		expect(model.setItemsCalls).toEqual([]);
		expect(model.appliedItemIds).toEqual([firstItem.id, 'appended-item']);

		applyBridgeCodeViewMetadataItems({
			applyItemUpdate: (item: BridgeCodeViewItem): void => {
				model.applyItemUpdate(item);
			},
			getCurrentItem: (itemId: string) => model.getItem(itemId),
			items: [patchedItem],
			setItems: (items: readonly BridgeCodeViewItem[]): void => {
				model.setItems(items);
			},
			sourceReset: true,
		});

		expect(model.setItemsCalls).toHaveLength(1);
		expect(model.setItemsCalls[0]?.map((item) => item.id)).toEqual([firstItem.id]);
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

	test('emits materialize telemetry for visible non-selected item paints', () => {
		const reviewPackage = makeBridgeReviewPackage();
		const item = reviewPackage.itemsById['item-source'];
		const headHandle = item?.contentRoles.head ?? null;
		if (item === undefined || headHandle === null) {
			throw new Error('Expected modified item with head handle');
		}
		const projection = buildBridgeReviewProjection({
			reviewPackage,
			request: { mode: { kind: 'normalReview' }, facets: [] },
		});
		const samples: BridgeTelemetrySample[] = [];

		recordBridgeCodeViewItemMaterializeTelemetryForPanel({
			durationMilliseconds: 8,
			item,
			parentTraceContext: null,
			projection,
			resources: {
				head: { handle: headHandle, readText: (): string => 'head body' },
			},
			result: 'updated',
			selectedItemId: 'different-selected-item',
			telemetryRecorder: enabledTelemetryRecorder(samples),
		});

		expect(samples).toHaveLength(1);
		expect(samples[0]).toMatchObject({
			name: 'performance.bridge.web.code_view_item_materialize',
			booleanAttributes: {
				'agentstudio.bridge.selected': false,
			},
		});
	});

	test('skips unchanged materialized items before reading content resources', () => {
		const reviewPackage = makeBridgeReviewPackage();
		const item = reviewPackage.itemsById['item-source'];
		const headHandle = item?.contentRoles.head ?? null;
		if (item === undefined || headHandle === null) {
			throw new Error('Expected modified item with head handle');
		}
		let readTextCallCount = 0;
		const resources: BridgeCodeViewContentResources = {
			head: {
				handle: headHandle,
				readText: (): string => {
					readTextCallCount += 1;
					return 'head body';
				},
			},
		};
		const existingItem = materializeBridgeCodeViewItem({ item, resources });
		if (existingItem === null) {
			throw new Error('Expected item to materialize');
		}
		readTextCallCount = 0;

		expect(
			shouldSkipBridgeCodeViewItemMaterializationBeforeWork({
				collapsed: false,
				existingItem,
				item,
				presentation: null,
				resources,
			}),
		).toBe(true);
		expect(readTextCallCount).toBe(0);
	});

	test('runs large materialization sets across multiple event-loop turns', () => {
		const visitedEntries: number[] = [];
		const scheduledTurns: Array<() => void> = [];
		const nowValues = [0, 2, 4, 6, 8, 10, 12];

		runBridgeCodeViewMaterializationInChunks({
			entries: [0, 1, 2, 3, 4, 5],
			frameBudgetMilliseconds: 4,
			isStale: (): boolean => false,
			now: (): number => nowValues.shift() ?? 12,
			onComplete: (): void => {
				visitedEntries.push(99);
			},
			runEntry: (entry): void => {
				visitedEntries.push(entry);
			},
			scheduleNextTurn: (callback): void => {
				scheduledTurns.push(callback);
			},
		});

		expect(scheduledTurns).toHaveLength(1);
		scheduledTurns.shift()?.();
		expect(visitedEntries).toEqual([0, 1]);
		expect(scheduledTurns).toHaveLength(1);
		scheduledTurns.shift()?.();
		expect(visitedEntries).toEqual([0, 1, 2, 3]);
		expect(scheduledTurns).toHaveLength(1);
		scheduledTurns.shift()?.();
		expect(visitedEntries).toEqual([0, 1, 2, 3, 4, 5, 99]);
		expect(scheduledTurns).toHaveLength(0);
	});

	test('does not retokenize same content-hash descriptor file on chunked re-exposure', () => {
		vi.stubGlobal('requestAnimationFrame', (callback: FrameRequestCallback): number => {
			callback(0);
			return 1;
		});
		vi.stubGlobal('cancelAnimationFrame', (_frameId: number): void => {});
		try {
			const reviewPackage = makeBridgeReviewPackage();
			const item = reviewPackage.itemsById['item-source'];
			const headHandle = item?.contentRoles.head ?? null;
			if (item === undefined || headHandle === null) {
				throw new Error('Expected modified item with head handle');
			}
			const model = new VersionKeyedCodeViewModel();
			const controller = new BridgeCodeViewController({ model });
			const workerPoolManager = new WorkerPoolManager(
				{
					poolSize: 0,
					totalASTLRUCacheSize: 4,
					workerFactory: (): Worker => {
						throw new Error('worker should not be constructed for re-exposure test');
					},
				},
				{},
			);
			const highlightSpy = vi.spyOn(workerPoolManager, 'highlightFileAST');
			const rendererInstance = makeFileRendererInstance('r46-reexposure');
			let readTextCallCount = 0;
			const resources: BridgeCodeViewContentResources = {
				head: {
					authoritative: true,
					byteLength: 42,
					handle: {
						...headHandle,
						contentHash: 'sha256:same-r46-content',
						contentHashAlgorithm: 'sha256',
						cacheKey: 'item-source:head:revision-46',
						sizeBytes: 42,
					},
					readText: (): string => {
						readTextCallCount += 1;
						return 'struct SameR46Content {}\n';
					},
				},
			};
			const appliedEntries: string[] = [];
			const skippedEntries: string[] = [];
			const scheduledTurns: Array<() => void> = [];

			runBridgeCodeViewMaterializationInChunks({
				entries: ['initial-exposure', 'second-exposure'],
				frameBudgetMilliseconds: 8,
				isStale: (): boolean => false,
				maxUnitsPerFrame: 1,
				now: (): number => 0,
				onComplete: (): void => {
					appliedEntries.push('drained');
				},
				rankForEntry: (): 'selected' => 'selected',
				runEntry: (entry): void => {
					const existingItem = model.getItem(item.itemId);
					if (
						shouldSkipBridgeCodeViewItemMaterializationBeforeWork({
							collapsed: false,
							existingItem,
							item,
							presentation: { kind: 'file', version: 'head' },
							resources,
						})
					) {
						skippedEntries.push(entry);
						return;
					}
					const materializedItem = materializeBridgeCodeViewItem({
						contentDemandRole: 'selected',
						item,
						presentation: { kind: 'file', version: 'head' },
						resources,
					});
					if (materializedItem?.type !== 'file') {
						throw new Error('Expected descriptor-backed file materialization');
					}
					const cacheKey = materializedItem.file.cacheKey;
					if (cacheKey === undefined) {
						throw new Error('Expected descriptor-backed file cache key');
					}
					appliedEntries.push(`${entry}:${controller.applyItemUpdate(materializedItem)}`);
					workerPoolManager.highlightFileAST(rendererInstance, materializedItem.file);
					workerPoolManager
						.inspectCaches()
						.fileCache.set(cacheKey, cachedRenderFileResultFor(workerPoolManager));
				},
				scheduleNextTurn: (callback): void => {
					scheduledTurns.push(callback);
				},
			});

			scheduledTurns.shift()?.();
			expect(readTextCallCount).toBe(1);
			expect(highlightSpy).toHaveBeenCalledTimes(1);
			expect(workerPoolManager.getStats().queuedTasks).toBe(1);
			scheduledTurns.shift()?.();

			expect(appliedEntries).toEqual(['initial-exposure:added', 'drained']);
			expect(skippedEntries).toEqual(['second-exposure']);
			expect(readTextCallCount).toBe(1);
			expect(highlightSpy).toHaveBeenCalledTimes(1);
			expect(workerPoolManager.getStats()).toMatchObject({
				fileCacheSize: 1,
				queuedTasks: 1,
			});
		} finally {
			vi.unstubAllGlobals();
		}
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
		resetSelectedContentPaintedProbe();

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
				'agentstudio.bridge.selected_content.materialize_ms': 10,
			},
		});
		expect(readSelectedContentPaintedProbe()).toMatchObject({
			scheduleEnteredCount: 1,
			rafScheduledCount: 1,
			rafFiredCount: 1,
			sampleRecordedCount: 1,
			flushCalledCount: 1,
			lastReason: 'flush_called',
			lastScheduleEarlyReturnReason: 'none',
		});
	});

	test('records selected content painted probe delivery and scheduler gate counters', () => {
		const samples: BridgeTelemetrySample[] = [];
		const frameCallbacks: FrameRequestCallback[] = [];
		const telemetryRecorder = enabledTelemetryRecorder(samples);
		let nowMilliseconds = 16;
		resetSelectedContentPaintedProbe();

		recordBridgeSelectedContentPaintedProbeAnchoredDelivery({
			hasAnchor: true,
			isSelectedItem: true,
			hasTelemetryRecorder: true,
			didFindMatchingPaintedContent: true,
		});
		scheduleSelectedContentPaintedTelemetry({
			telemetryRecorder,
			traceContext: null,
			selectionDemandStartedAtMilliseconds: 10,
			materializationStartedAtMilliseconds: 12,
			materializationCompletedAtMilliseconds: 14,
			now: (): number => nowMilliseconds,
			requestAnimationFrame: (callback): number => {
				frameCallbacks.push(callback);
				return frameCallbacks.length;
			},
		});
		scheduleSelectedContentPaintedTelemetry({
			telemetryRecorder,
			traceContext: null,
			selectionDemandStartedAtMilliseconds: 10,
			materializationStartedAtMilliseconds: 12,
			materializationCompletedAtMilliseconds: 14,
			now: (): number => nowMilliseconds,
			requestAnimationFrame: (callback): number => {
				frameCallbacks.push(callback);
				return frameCallbacks.length;
			},
		});

		nowMilliseconds = 20;
		frameCallbacks[0]?.(20);

		expect(readSelectedContentPaintedProbe()).toMatchObject({
			anchoredDeliveryEntryCount: 1,
			anchoredDeliveryAnchorPresentCount: 1,
			anchoredDeliverySelectedMatchCount: 1,
			anchoredDeliveryTelemetryRecorderPresentCount: 1,
			alreadyPaintedByHydrationCount: 1,
			scheduleEnteredCount: 2,
			earlyReturnCount: 1,
			rafScheduledCount: 1,
			rafFiredCount: 1,
			sampleRecordedCount: 1,
			flushCalledCount: 1,
			lastAnchoredDeliveryHadAnchor: true,
			lastAnchoredDeliverySelectedMatched: true,
			lastAnchoredDeliveryHadTelemetryRecorder: true,
			lastReason: 'flush_called',
			lastScheduleEarlyReturnReason: 'duplicate_selection_demand',
		});
	});

	test('records selected content painted when hydration paints before the selected anchor arrives', () => {
		const reviewPackage = makeBridgeReviewPackage();
		const selectedItem = reviewPackage.itemsById['item-source'];
		const baseHandle = selectedItem?.contentRoles.base ?? null;
		const headHandle = selectedItem?.contentRoles.head ?? null;
		if (selectedItem === undefined || baseHandle === null || headHandle === null) {
			throw new Error('Expected modified item with base/head handles');
		}
		const resources: BridgeCodeViewContentResources = {
			base: { handle: baseHandle, readText: (): string => 'base body' },
			head: { handle: headHandle, readText: (): string => 'head body' },
		};
		const materializedItem = materializeBridgeCodeViewItem({ item: selectedItem, resources });
		if (materializedItem === null) {
			throw new Error('Expected selected item to materialize');
		}
		const samples: BridgeTelemetrySample[] = [];
		const frameCallbacks: FrameRequestCallback[] = [];
		const telemetryRecorder = enabledTelemetryRecorder(samples);
		const controller = new BridgeCodeViewController({ model: new VersionKeyedCodeViewModel() });
		let nowMilliseconds = 160;

		const hydrationApplyResult = controller.applyItemUpdate(materializedItem);
		expect(hydrationApplyResult).toBe('added');

		const anchoredDeliveryApplyResult = controller.applyItemUpdate(materializedItem);
		expect(anchoredDeliveryApplyResult).toBe('unchanged');
		if (
			shouldScheduleSelectedContentPaintedTelemetry({
				didFindMatchingPaintedContent: true,
				selectionDemandStartedAtMilliseconds: 100,
				updateResult: anchoredDeliveryApplyResult,
			})
		) {
			scheduleSelectedContentPaintedTelemetry({
				telemetryRecorder,
				traceContext: null,
				selectionDemandStartedAtMilliseconds: 100,
				materializationStartedAtMilliseconds: 150,
				materializationCompletedAtMilliseconds: 160,
				now: (): number => nowMilliseconds,
				requestAnimationFrame: (callback): number => {
					frameCallbacks.push(callback);
					return frameCallbacks.length;
				},
			});
		}

		nowMilliseconds = 176;
		frameCallbacks[0]?.(176);

		expect(samples).toHaveLength(1);
		expect(samples[0]).toMatchObject({
			name: 'performance.bridge.web.selected_content_painted',
			numericAttributes: {
				'agentstudio.bridge.selected_content.click_to_paint_ms': 76,
				'agentstudio.bridge.selected_content.frame_wait_ms': 16,
				'agentstudio.bridge.selected_content.materialize_ms': 10,
			},
		});
	});

	test('idle flushes selected content painted telemetry after recorder burst throttling', () => {
		const batches: BridgeTelemetryBatch[] = [];
		const frameCallbacks: FrameRequestCallback[] = [];
		const idleCallbacks: Array<() => void> = [];
		let nowMilliseconds = 1_000;
		const telemetryRecorder = createBridgeTelemetryRecorder(
			{
				enabledScopes: new Set(['web']),
				maxSamplesPerBatch: 4,
				maxEncodedBatchBytes: 16_384,
				minimumFlushIntervalMilliseconds: 250,
				endpointUrl: 'agentstudio://telemetry/batch',
				scenario: 'package_apply_content_fetch_v1',
			},
			{
				flush: (batch: BridgeTelemetryBatch): boolean => {
					batches.push(batch);
					return true;
				},
			},
			(): number => nowMilliseconds,
			(callback): void => {
				idleCallbacks.push(callback);
			},
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
		]);
		expect(idleCallbacks).toHaveLength(1);
		nowMilliseconds = 1_260;
		idleCallbacks[0]?.();

		expect(batches.map((batch) => batch.samples.map((sample) => sample.name))).toEqual([
			['performance.bridge.web.code_view_item_materialize'],
			['performance.bridge.web.selected_content_painted'],
		]);
	});

	test('records only the latest selected content paint when rapid selections supersede a pending frame', () => {
		const samples: BridgeTelemetrySample[] = [];
		const frameCallbacks: FrameRequestCallback[] = [];
		const telemetryRecorder = enabledTelemetryRecorder(samples);
		let nowMilliseconds = 210;

		scheduleSelectedContentPaintedTelemetry({
			telemetryRecorder,
			traceContext: null,
			selectionDemandStartedAtMilliseconds: 100,
			materializationStartedAtMilliseconds: 180,
			materializationCompletedAtMilliseconds: 200,
			now: (): number => nowMilliseconds,
			requestAnimationFrame: (callback): number => {
				frameCallbacks.push(callback);
				return frameCallbacks.length;
			},
		});
		scheduleSelectedContentPaintedTelemetry({
			telemetryRecorder,
			traceContext: null,
			selectionDemandStartedAtMilliseconds: 140,
			materializationStartedAtMilliseconds: 205,
			materializationCompletedAtMilliseconds: 210,
			now: (): number => nowMilliseconds,
			requestAnimationFrame: (callback): number => {
				frameCallbacks.push(callback);
				return frameCallbacks.length;
			},
		});

		nowMilliseconds = 220;
		frameCallbacks[0]?.(220);
		frameCallbacks[1]?.(220);

		expect(samples).toHaveLength(1);
		expect(samples[0]).toMatchObject({
			name: 'performance.bridge.web.selected_content_painted',
			durationMilliseconds: 80,
			numericAttributes: {
				'agentstudio.bridge.selected_content.click_to_paint_ms': 80,
				'agentstudio.bridge.selected_content.frame_wait_ms': 10,
				'agentstudio.bridge.selected_content.materialize_ms': 5,
			},
		});
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

function resetSelectedContentPaintedProbe(): void {
	ensureTestWindow();
	// oxlint-disable-next-line no-underscore-dangle -- Intentional Bridge debug surface name.
	delete window.__bridgeSelectedContentPaintedProbe;
}

function readSelectedContentPaintedProbe(): BridgeSelectedContentPaintedProbe {
	ensureTestWindow();
	// oxlint-disable-next-line no-underscore-dangle -- Intentional Bridge debug surface name.
	const probe = window.__bridgeSelectedContentPaintedProbe;
	if (probe === undefined) {
		throw new Error('Expected selected content painted probe to be installed.');
	}
	return probe;
}

function ensureTestWindow(): void {
	if (typeof window === 'undefined') {
		vi.stubGlobal('window', {});
	}
}

function makeFileRendererInstance(id: string): FileRendererInstance {
	return {
		__id: id,
		onHighlightSuccess: (): void => {},
		onHighlightError: (): void => {},
	};
}

function cachedRenderFileResultFor(workerPoolManager: WorkerPoolManager): RenderFileResult {
	return {
		result: { code: [], themeStyles: '', baseThemeType: undefined },
		options: workerPoolManager.getFileRenderOptions(),
	};
}

class RecordingMetadataApplyModel {
	readonly appliedItemIds: string[] = [];
	readonly setItemsCalls: BridgeCodeViewItem[][] = [];
	readonly #itemsById = new Map<string, BridgeCodeViewItem>();

	constructor(items: readonly BridgeCodeViewItem[]) {
		for (const item of items) {
			this.#itemsById.set(item.id, item);
		}
	}

	applyItemUpdate(item: BridgeCodeViewItem): void {
		this.appliedItemIds.push(item.id);
		this.#itemsById.set(item.id, item);
	}

	getItem(itemId: string): BridgeCodeViewItem | undefined {
		return this.#itemsById.get(itemId);
	}

	setItems(items: readonly BridgeCodeViewItem[]): void {
		this.setItemsCalls.push([...items]);
		this.#itemsById.clear();
		for (const item of items) {
			this.#itemsById.set(item.id, item);
		}
	}
}

class VersionKeyedCodeViewModel {
	readonly #itemsById = new Map<string, BridgeCodeViewItem>();

	addItems(items: readonly BridgeCodeViewItem[]): void {
		for (const item of items) {
			this.#itemsById.set(item.id, item);
		}
	}

	getItem(id: string): BridgeCodeViewItem | undefined {
		return this.#itemsById.get(id);
	}

	updateItem(item: BridgeCodeViewItem): boolean {
		const previousItem = this.#itemsById.get(item.id);
		this.#itemsById.set(item.id, item);
		return previousItem !== undefined && previousItem.version !== item.version;
	}

	updateItemId(): boolean {
		return true;
	}

	scrollTo(): void {}

	setSelectedLines(): void {}
}

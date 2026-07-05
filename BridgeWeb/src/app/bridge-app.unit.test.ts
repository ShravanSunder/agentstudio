import { describe, expect, test, vi } from 'vitest';

import { createBridgeResourceExecutor } from '../core/demand/bridge-resource-executor.js';
import { createBridgeResourceDescriptorRegistry } from '../core/resources/bridge-resource-registry.js';
import type { BridgeTextResourceStreamResult } from '../core/resources/bridge-resource-stream.js';
import type { ReviewMaterializerDelta } from '../features/review/materialization/review-materializer.js';
import type { ReviewTreeRowMetadata } from '../features/review/models/review-protocol-models.js';
import {
	makeBridgeContentHandle,
	makeBridgeReviewItem,
	makeBridgeReviewPackage,
} from '../foundation/review-package/bridge-review-package-test-support.js';
import type { BridgeReviewPackage } from '../foundation/review-package/bridge-review-package.js';
import { loadReviewItemContentResourcesThroughDemandResult } from '../review-viewer/content/review-content-demand-loader.js';
import { createBridgeReviewContentRegistry } from '../review-viewer/content/review-content-registry.js';
import { makeReviewItemContentResourcesKey } from '../review-viewer/content/visible-review-content-hydration.js';
import { makeBridgeViewerBrowserFixture } from '../review-viewer/test-support/bridge-viewer-mocked-backend.js';
import { applyReviewProtocolTransportFrame } from './bridge-app-review-controller.js';
import {
	applyReviewMetadataDeltaToReviewPackage,
	bridgeReviewContentDemandByteBudget,
	contentDemandResourceUrl,
	pruneEmptyReviewTreeDirectories,
	reviewSnapshotDescriptorRefsByHandleIdForPackage,
	reviewSnapshotFrameDescriptorsMatchPackage,
	reviewTreeRowsWithMetadataDelta,
	reviewFileTargetForReviewPackagePath,
	reviewItemDemandCancellationTargetForSelectionChange,
	selectedCanvasLoadingReasonForCurrentSelection,
	selectedContentUnavailablePathForCurrentSelection,
	shouldRetrySelectedReviewContentAfterDescriptorRegistration,
	shouldStartSelectedReviewContentDemand,
	shouldPauseVisibleReviewContentHydration,
	type BridgeReviewFrameAuthority,
} from './bridge-app.js';
import {
	createDeferred,
	flushMicrotasks,
	flushMicrotasksUntil,
	makeNoopTelemetryRecorder,
	makeReviewAttachedContentDescriptor,
	makeReviewMetadataSnapshotFrame,
	makeReviewProjectionInputItem,
	makeSelectedReviewContentDemandTelemetry,
	makeTextStreamResult,
	type Deferred,
} from './bridge-app.unit.test-support.js';

type ReviewDeltaMaterializerDelta = Extract<
	ReviewMaterializerDelta,
	{ readonly kind: 'metadataDelta' }
>;

describe('BridgeApp selection demand cancellation', () => {
	test('cancels previous selected item demand without cancelling the newly selected item', () => {
		const sourceReviewPackage = makeBridgeReviewPackage();
		const previousSelectedItem = makeBridgeReviewItem({
			itemId: 'item-previous',
			path: 'Sources/App/Previous.swift',
		});
		const reviewPackage = {
			...sourceReviewPackage,
			orderedItemIds: [previousSelectedItem.itemId, ...sourceReviewPackage.orderedItemIds],
			itemsById: {
				...sourceReviewPackage.itemsById,
				[previousSelectedItem.itemId]: previousSelectedItem,
			},
		};

		const cancellationTarget = reviewItemDemandCancellationTargetForSelectionChange({
			previousSelectedItemId: previousSelectedItem.itemId,
			reviewPackage,
		});

		expect(cancellationTarget?.itemId).toBe(previousSelectedItem.itemId);
		expect(cancellationTarget?.itemId).not.toBe('item-source');
	});

	test('does not cancel descriptor demand when there is no previous selected item', () => {
		const reviewPackage = makeBridgeReviewPackage();

		const cancellationTarget = reviewItemDemandCancellationTargetForSelectionChange({
			previousSelectedItemId: null,
			reviewPackage,
		});

		expect(cancellationTarget).toBeUndefined();
	});
});

describe('BridgeApp visible review content hydration policy', () => {
	test('pauses visible warming while worker-owned selected availability is loading', () => {
		expect(
			shouldPauseVisibleReviewContentHydration({
				isActive: true,
				codeViewScrollActive: false,
				currentSelectedContentKey: 'selected-key',
				foregroundSelectedContentKey: null,
				selectedContentAvailability: { state: 'loading' },
			}),
		).toBe(true);
	});

	test('pauses visible warming immediately during foreground selection transition', () => {
		expect(
			shouldPauseVisibleReviewContentHydration({
				isActive: true,
				codeViewScrollActive: false,
				currentSelectedContentKey: 'selected-key',
				foregroundSelectedContentKey: 'selected-key',
				selectedContentAvailability: null,
			}),
		).toBe(true);
	});

	test('ignores stale foreground selection transition keys', () => {
		expect(
			shouldPauseVisibleReviewContentHydration({
				isActive: true,
				codeViewScrollActive: false,
				currentSelectedContentKey: 'selected-key',
				foregroundSelectedContentKey: 'stale-key',
				selectedContentAvailability: { state: 'ready' },
			}),
		).toBe(false);
	});

	test('pauses visible warming while initial selected content state is not yet established', () => {
		expect(
			shouldPauseVisibleReviewContentHydration({
				isActive: true,
				codeViewScrollActive: false,
				currentSelectedContentKey: 'selected-key',
				foregroundSelectedContentKey: null,
				selectedContentAvailability: null,
			}),
		).toBe(true);
	});

	test('keeps visible warming active when selected foreground content is resolved', () => {
		expect(
			shouldPauseVisibleReviewContentHydration({
				isActive: true,
				codeViewScrollActive: false,
				currentSelectedContentKey: 'selected-key',
				foregroundSelectedContentKey: null,
				selectedContentAvailability: { state: 'ready' },
			}),
		).toBe(false);
	});

	test('pauses visible warming while the Review CodeView is actively scrolling', () => {
		expect(
			shouldPauseVisibleReviewContentHydration({
				isActive: true,
				codeViewScrollActive: true,
				currentSelectedContentKey: 'selected-key',
				foregroundSelectedContentKey: null,
				selectedContentAvailability: { state: 'ready' },
			}),
		).toBe(true);
	});
});

describe('BridgeApp selected review availability display policy', () => {
	test('selected canvas content loading follows worker-owned availability', () => {
		expect(
			selectedCanvasLoadingReasonForCurrentSelection({
				selectedContentAvailability: { state: 'loading' },
				selectedContentKey: 'selected-key',
				selectedItemId: 'item-source',
				selectedMarkdownPreviewState: null,
			}),
		).toBe('content');
	});

	test('selected canvas content loading clears when worker-owned availability is ready', () => {
		expect(
			selectedCanvasLoadingReasonForCurrentSelection({
				selectedContentAvailability: { state: 'ready' },
				selectedContentKey: 'selected-key',
				selectedItemId: 'item-source',
				selectedMarkdownPreviewState: null,
			}),
		).toBeNull();
	});

	test('selected unavailable path follows worker-owned failed availability', () => {
		const reviewPackage = makeBridgeReviewPackage();

		expect(
			selectedContentUnavailablePathForCurrentSelection({
				reviewPackage,
				selectedContentAvailability: { state: 'failed' },
				selectedItemId: 'item-source',
			}),
		).toBe('Sources/App/View.swift');
	});
});

describe('BridgeApp selected review content demand policy', () => {
	test('resolves control path reveal to a file presentation target', () => {
		const reviewPackage = makeBridgeReviewPackage();

		const target = reviewFileTargetForReviewPackagePath({
			path: 'Sources/App/View.swift',
			reviewPackage,
		});

		expect(target).toEqual({
			targetKind: 'file',
			fileRef: {
				sourceId: 'repo',
				path: 'Sources/App/View.swift',
			},
			version: 'current',
			reviewItemId: 'item-source',
		});
	});

	test('resolves large fixture control path reveal to a file presentation target', () => {
		const fixture = makeBridgeViewerBrowserFixture({ fixtureClass: 'large-diffshub' });

		const target = reviewFileTargetForReviewPackagePath({
			path: 'Sources/AgentStudio/source/module-24/file-292.ts',
			reviewPackage: fixture.reviewPackage,
		});

		expect(target).toMatchObject({
			targetKind: 'file',
			fileRef: {
				path: 'Sources/AgentStudio/source/module-24/file-292.ts',
			},
			version: 'current',
			reviewItemId: 'browser-filler-large-diffshub-292',
		});
	});

	test('does not reload ready selected content when only invalidation load key changes', () => {
		const selectedContentKey = 'package-1:1:1:item-source:base-head';

		expect(
			shouldStartSelectedReviewContentDemand({
				activeSelectedContentLoadKey: null,
				currentSelectedContentResourcesState: {
					itemId: 'item-source',
					contentKey: selectedContentKey,
					status: 'ready',
					resources: {
						file: {
							handle: makeBridgeContentHandle('item-source', 'head'),
							readText: () => 'ready content',
						},
					},
				},
				selectedContentKey,
				selectedContentLoadKey: `${selectedContentKey}:invalidation:2`,
			}),
		).toBe(false);
	});

	test('retries a selected descriptor-missing failure when metadata registers descriptors', () => {
		const reviewPackage = makeBridgeReviewPackage();
		const selectedItem = reviewPackage.itemsById['item-source'];
		expect(selectedItem).toBeDefined();
		if (selectedItem === undefined) {
			return;
		}
		const selectedContentKey = makeReviewItemContentResourcesKey({
			item: selectedItem,
			reviewPackage,
		});

		expect(
			shouldRetrySelectedReviewContentAfterDescriptorRegistration({
				reviewPackage,
				selectedItemId: 'item-source',
				registeredDescriptorRefCount: 2,
				selectedContentResourcesState: {
					itemId: 'item-source',
					contentKey: selectedContentKey,
					status: 'failed',
					resources: null,
				},
				lastSelectedDemandTelemetry: makeSelectedReviewContentDemandTelemetry({
					itemId: 'item-source',
					packageId: reviewPackage.packageId,
					reviewGeneration: reviewPackage.reviewGeneration,
					revision: reviewPackage.revision,
					resultStatus: 'failed',
					resultReason: 'descriptor_missing',
				}),
			}),
		).toBe(true);
	});

	test('does not retry a selected terminal load failure when metadata registers descriptors', () => {
		const reviewPackage = makeBridgeReviewPackage();
		const selectedItem = reviewPackage.itemsById['item-source'];
		expect(selectedItem).toBeDefined();
		if (selectedItem === undefined) {
			return;
		}
		const selectedContentKey = makeReviewItemContentResourcesKey({
			item: selectedItem,
			reviewPackage,
		});

		expect(
			shouldRetrySelectedReviewContentAfterDescriptorRegistration({
				reviewPackage,
				selectedItemId: 'item-source',
				registeredDescriptorRefCount: 2,
				selectedContentResourcesState: {
					itemId: 'item-source',
					contentKey: selectedContentKey,
					status: 'failed',
					resources: null,
				},
				lastSelectedDemandTelemetry: makeSelectedReviewContentDemandTelemetry({
					itemId: 'item-source',
					packageId: reviewPackage.packageId,
					reviewGeneration: reviewPackage.reviewGeneration,
					revision: reviewPackage.revision,
					resultStatus: 'failed',
					resultReason: 'load_failed',
				}),
			}),
		).toBe(false);
	});
});

describe('BridgeApp Review content demand byte budget', () => {
	test('promotes the package-applied initial review item through foreground demand', async () => {
		const reviewPackage = makeBridgeReviewPackage();
		const reviewFrameAuthority: BridgeReviewFrameAuthority = {
			paneId: 'pane-1',
			streamId: 'review:pane-1',
		};
		const item = reviewPackage.itemsById['item-source'];
		const baseHandle = item?.contentRoles.base ?? null;
		const headHandle = item?.contentRoles.head ?? null;
		if (baseHandle === null || headHandle === null) {
			throw new Error('Expected fixture review package to include modified base/head content');
		}
		const descriptorRegistry = createBridgeResourceDescriptorRegistry({
			allowedResourceKindsByProtocol: {
				review: new Set(['content']),
			},
		});
		const frame = makeReviewMetadataSnapshotFrame({
			contentDescriptors: [
				makeReviewAttachedContentDescriptor({
					handle: baseHandle,
					reviewFrameAuthority,
					reviewPackage,
				}),
				makeReviewAttachedContentDescriptor({
					handle: headHandle,
					reviewFrameAuthority,
					reviewPackage,
				}),
			],
			reviewFrameAuthority,
			reviewPackage,
		});
		const requestedDescriptorIds: string[] = [];
		const resourceExecutor = createBridgeResourceExecutor<BridgeTextResourceStreamResult>({
			registry: descriptorRegistry,
			maxConcurrentLoads: 2,
			maxInFlightBytes: bridgeReviewContentDemandByteBudget.resourceExecutorMaxInFlightBytes,
			maxQueuedLoads: 8,
			maxQueuedBytes: bridgeReviewContentDemandByteBudget.resourceExecutorMaxQueuedBytes,
			loadResource: async ({ descriptor }) => {
				requestedDescriptorIds.push(descriptor.descriptorId);
				return {
					authoritative: true,
					content: makeTextStreamResult(`${descriptor.descriptorId} package apply text`),
					byteLength: 24,
				};
			},
		});
		const contentRegistry = createBridgeReviewContentRegistry();
		const reviewPackageRef: { current: BridgeReviewPackage | null } = { current: null };
		const currentReviewPackageRef: { current: BridgeReviewPackage | null } = { current: null };
		let currentTreeRows: readonly ReviewTreeRowMetadata[] = [];
		const selectInitialReviewItem = vi.fn<(itemId: string) => boolean>(() => true);

		await applyReviewProtocolTransportFrame({
			protocolFrame: frame,
			setReviewPackage: (update): void => {
				currentReviewPackageRef.current = update(currentReviewPackageRef.current);
			},
			setReviewTreeRows: (update): void => {
				currentTreeRows = update(currentTreeRows);
			},
			setDiffStatus: (): void => {},
			setSelectedItemId: (): void => {},
			selectInitialReviewItem,
			getSelectedItemId: (): string | null => null,
			reviewPackageRef,
			telemetryContextByPackageKey: new Map(),
			currentReviewPackageTelemetryContextRef: { current: null },
			reviewReadyStartMillisecondsByPackageKeyRef: { current: new Map() },
			descriptorRegistry,
			reviewContentDescriptorRefsByHandleIdRef: { current: new Map() },
			resourceExecutor,
			contentRegistry,
			reviewFrameAuthority,
			invalidatedFreshnessKeysRef: { current: new Set() },
			setReviewContentInvalidationVersion: (): void => {},
			onReviewContentDescriptorRefsRegistered: (): void => {},
			telemetryContext: {
				slice: 'review_metadata',
				traceContext: null,
				transport: 'intake',
			},
			telemetryRecorder: makeNoopTelemetryRecorder(),
		});
		await flushMicrotasksUntil(
			(): boolean => contentRegistry.snapshot().cachedResourceCount >= 2,
			20,
		);

		expect(selectInitialReviewItem).toHaveBeenCalledExactlyOnceWith('item-source');
		expect(requestedDescriptorIds.toSorted()).toEqual([baseHandle.handleId, headHandle.handleId]);
		const currentReviewPackage = currentReviewPackageRef.current;
		expect(currentReviewPackage?.packageId).toBe(reviewPackage.packageId);
		const appliedItem = currentReviewPackage?.itemsById['item-source'];
		const appliedBaseHandle = appliedItem?.contentRoles.base ?? null;
		const appliedHeadHandle = appliedItem?.contentRoles.head ?? null;
		if (appliedBaseHandle === null || appliedHeadHandle === null) {
			throw new Error('Expected applied package to include promoted base/head content handles');
		}
		expect(contentRegistry.peekResource(appliedBaseHandle)?.readText()).toBe(
			`${baseHandle.handleId} package apply text`,
		);
		expect(contentRegistry.peekResource(appliedHeadHandle)?.readText()).toBe(
			`${headHandle.handleId} package apply text`,
		);
		expect(currentTreeRows.length).toBeGreaterThan(0);
	});

	test('starts both selected modified native descriptors within aggregate role budget', async () => {
		const reviewPackage = makeBridgeReviewPackage();
		const reviewFrameAuthority: BridgeReviewFrameAuthority = {
			paneId: 'pane-1',
			streamId: 'review:pane-1',
		};
		const item = reviewPackage.itemsById['item-source'];
		const baseHandle = item?.contentRoles.base ?? null;
		const headHandle = item?.contentRoles.head ?? null;
		if (baseHandle === null || headHandle === null) {
			throw new Error('Expected fixture review package to include modified base/head content');
		}
		const registry = createBridgeResourceDescriptorRegistry({
			allowedResourceKindsByProtocol: {
				review: new Set(['content']),
			},
		});
		const contentByteBounds = {
			expectedBytes: undefined,
			maxBytes: bridgeReviewContentDemandByteBudget.maxContentBytesPerRole,
		};
		const frame = makeReviewMetadataSnapshotFrame({
			contentDescriptors: [
				makeReviewAttachedContentDescriptor({
					handle: baseHandle,
					reviewFrameAuthority,
					reviewPackage,
					contentByteBounds,
				}),
				makeReviewAttachedContentDescriptor({
					handle: headHandle,
					reviewFrameAuthority,
					reviewPackage,
					contentByteBounds,
				}),
			],
			reviewFrameAuthority,
			reviewPackage,
		});
		const descriptorRefsByHandleId = reviewSnapshotDescriptorRefsByHandleIdForPackage({
			descriptorRegistry: registry,
			frame,
			reviewFrameAuthority,
			reviewPackage,
		});
		if (descriptorRefsByHandleId === null) {
			throw new Error('Expected descriptor refs to register');
		}
		const requestedDescriptorIds: string[] = [];
		const deferredResultsByDescriptorId = new Map<
			string,
			Deferred<{
				readonly content: BridgeTextResourceStreamResult;
				readonly byteLength: number;
			}>
		>();
		const executor = createBridgeResourceExecutor<BridgeTextResourceStreamResult>({
			registry,
			maxConcurrentLoads: 2,
			maxInFlightBytes: bridgeReviewContentDemandByteBudget.resourceExecutorMaxInFlightBytes,
			maxQueuedLoads: 8,
			maxQueuedBytes: bridgeReviewContentDemandByteBudget.resourceExecutorMaxQueuedBytes,
			loadResource: async ({ descriptor }) => {
				requestedDescriptorIds.push(descriptor.descriptorId);
				const deferredResult = createDeferred<{
					readonly content: BridgeTextResourceStreamResult;
					readonly byteLength: number;
				}>();
				deferredResultsByDescriptorId.set(descriptor.descriptorId, deferredResult);
				return await deferredResult.promise;
			},
		});

		const resultPromise = loadReviewItemContentResourcesThroughDemandResult({
			reviewPackage,
			itemId: 'item-source',
			interest: 'selected',
			resolveDescriptorRef: (handle) => descriptorRefsByHandleId.get(handle.handleId) ?? null,
			executor,
		});
		await flushMicrotasks(4);
		const initiallyRequestedDescriptorIds = [...requestedDescriptorIds];
		for (const [descriptorId, deferredResult] of deferredResultsByDescriptorId) {
			deferredResult.resolve({
				content: makeTextStreamResult(`${descriptorId} selected text`),
				byteLength: 24,
			});
		}
		await expect(resultPromise).resolves.toMatchObject({ status: 'ready' });

		expect(initiallyRequestedDescriptorIds.toSorted()).toEqual([
			baseHandle.handleId,
			headHandle.handleId,
		]);
	});

	test('decorates native content fetch URLs with demand interest without mutating descriptor identity', () => {
		const resourceUrl =
			'agentstudio://resource/review/content/descriptor-handle?generation=1&revision=1';

		expect(contentDemandResourceUrl(resourceUrl, 'foreground')).toBe(
			'agentstudio://resource/review/content/descriptor-handle?generation=1&revision=1&interest=selected',
		);
		expect(contentDemandResourceUrl(resourceUrl, 'visible')).toBe(
			'agentstudio://resource/review/content/descriptor-handle?generation=1&revision=1&interest=visible',
		);
		expect(contentDemandResourceUrl(resourceUrl, 'idle')).toBe(
			'agentstudio://resource/review/content/descriptor-handle?generation=1&revision=1&interest=background',
		);
	});
});

describe('BridgeApp review metadata delta materialization', () => {
	test('derives complete package content descriptor coverage from partial metadata snapshots', () => {
		const reviewPackage = makeBridgeReviewPackage();
		const reviewFrameAuthority: BridgeReviewFrameAuthority = {
			paneId: 'pane-1',
			streamId: 'review:pane-1',
		};
		const item = reviewPackage.itemsById['item-source'];
		if (item?.contentRoles.base === undefined || item.contentRoles.base === null) {
			throw new Error('Expected fixture review package to include base content');
		}
		const frame = makeReviewMetadataSnapshotFrame({
			contentDescriptors: [
				makeReviewAttachedContentDescriptor({
					handle: item.contentRoles.base,
					reviewFrameAuthority,
					reviewPackage,
				}),
			],
			reviewFrameAuthority,
			reviewPackage,
		});

		expect(
			reviewSnapshotFrameDescriptorsMatchPackage({
				frame,
				reviewFrameAuthority,
				reviewPackage,
			}),
		).toBe(true);
		const descriptorRefsByHandleId = reviewSnapshotDescriptorRefsByHandleIdForPackage({
			descriptorRegistry: createBridgeResourceDescriptorRegistry({
				allowedResourceKindsByProtocol: {
					review: new Set(['content']),
				},
			}),
			frame,
			reviewFrameAuthority,
			reviewPackage,
		});

		expect(descriptorRefsByHandleId?.size).toBe(2);
		expect(descriptorRefsByHandleId?.has('handle-item-source-base')).toBe(true);
		expect(descriptorRefsByHandleId?.has('handle-item-source-head')).toBe(true);
	});

	test('preserves inexact native descriptor byte bounds for modified base content', () => {
		const reviewPackage = makeBridgeReviewPackage();
		const reviewFrameAuthority: BridgeReviewFrameAuthority = {
			paneId: 'pane-1',
			streamId: 'review:pane-1',
		};
		const item = reviewPackage.itemsById['item-source'];
		const baseHandle = item?.contentRoles.base ?? null;
		const headHandle = item?.contentRoles.head ?? null;
		if (baseHandle === null || headHandle === null) {
			throw new Error('Expected fixture review package to include modified base/head content');
		}
		const baseDescriptor = makeReviewAttachedContentDescriptor({
			handle: baseHandle,
			reviewFrameAuthority,
			reviewPackage,
			contentByteBounds: {
				expectedBytes: undefined,
				maxBytes: 50 * 1024 * 1024,
			},
		});
		const headDescriptor = makeReviewAttachedContentDescriptor({
			handle: headHandle,
			reviewFrameAuthority,
			reviewPackage,
		});
		const frame = makeReviewMetadataSnapshotFrame({
			contentDescriptors: [baseDescriptor, headDescriptor],
			reviewFrameAuthority,
			reviewPackage,
		});
		const descriptorRegistry = createBridgeResourceDescriptorRegistry({
			allowedResourceKindsByProtocol: {
				review: new Set(['content']),
			},
		});

		expect(
			reviewSnapshotFrameDescriptorsMatchPackage({
				frame,
				reviewFrameAuthority,
				reviewPackage,
			}),
		).toBe(true);
		const descriptorRefsByHandleId = reviewSnapshotDescriptorRefsByHandleIdForPackage({
			descriptorRegistry,
			frame,
			reviewFrameAuthority,
			reviewPackage,
		});
		if (descriptorRefsByHandleId === null) {
			throw new Error('Expected native descriptor refs to register');
		}
		const baseDescriptorRef = descriptorRefsByHandleId.get(baseHandle.handleId);
		const headDescriptorRef = descriptorRefsByHandleId.get(headHandle.handleId);
		if (baseDescriptorRef === undefined || headDescriptorRef === undefined) {
			throw new Error('Expected base/head descriptor refs to register');
		}
		const registeredBaseDescriptor = descriptorRegistry.lookup(baseDescriptorRef);
		const registeredHeadDescriptor = descriptorRegistry.lookup(headDescriptorRef);

		expect(registeredBaseDescriptor?.content.expectedBytes).toBeUndefined();
		expect(registeredBaseDescriptor?.content.maxBytes).toBe(50 * 1024 * 1024);
		expect(registeredHeadDescriptor?.content.expectedBytes).toBe(headHandle.sizeBytes);
		expect(registeredHeadDescriptor?.content.maxBytes).toBe(headHandle.sizeBytes);
	});

	test('preserves authoritative review summary totals while applying streamed metadata deltas', () => {
		const reviewPackage = {
			...makeBridgeReviewPackage(),
			summary: {
				filesChanged: 700,
				additions: 1234,
				deletions: 321,
				visibleFileCount: 700,
				hiddenFileCount: 17,
			},
		};
		const appendedItem = makeReviewProjectionInputItem({
			itemId: 'item-appended-summary',
			path: 'Sources/App/AppendedSummary.swift',
		});
		const deltaFrame: ReviewDeltaMaterializerDelta = {
			kind: 'metadataDelta',
			packageId: reviewPackage.packageId,
			fromRevision: reviewPackage.revision,
			toRevision: reviewPackage.revision + 1,
			operations: [{ kind: 'appendItems', items: [appendedItem] }],
			summary: reviewPackage.summary,
			registeredContentDescriptorRefs: [],
			contentDescriptors: [],
		};

		const nextReviewPackage = applyReviewMetadataDeltaToReviewPackage({
			reviewPackage,
			deltaFrame,
		});

		expect(nextReviewPackage?.summary).toEqual(reviewPackage.summary);
	});

	test('rejects metadata deltas with skipped revision gaps', () => {
		const reviewPackage = makeBridgeReviewPackage();
		const appendedItem = makeReviewProjectionInputItem({
			itemId: 'item-appended-gap',
			path: 'Sources/App/AppendedGap.swift',
		});
		const deltaFrame: ReviewDeltaMaterializerDelta = {
			kind: 'metadataDelta',
			packageId: reviewPackage.packageId,
			fromRevision: reviewPackage.revision,
			toRevision: reviewPackage.revision + 2,
			operations: [{ kind: 'appendItems', items: [appendedItem] }],
			summary: reviewPackage.summary,
			registeredContentDescriptorRefs: [],
			contentDescriptors: [],
		};

		const nextReviewPackage = applyReviewMetadataDeltaToReviewPackage({
			reviewPackage,
			deltaFrame,
		});

		expect(nextReviewPackage).toBeNull();
	});

	test('applies extent fact deltas to existing review items', () => {
		const reviewPackage = makeBridgeReviewPackage();
		const deltaFrame: ReviewDeltaMaterializerDelta = {
			kind: 'metadataDelta',
			packageId: reviewPackage.packageId,
			fromRevision: reviewPackage.revision,
			toRevision: reviewPackage.revision + 1,
			operations: [
				{
					kind: 'upsertExtentFacts',
					facts: [
						{ itemId: 'item-source', contentRole: 'base', lineCount: 17 },
						{ itemId: 'item-source', contentRole: 'head', lineCount: 23 },
					],
				},
			],
			summary: reviewPackage.summary,
			registeredContentDescriptorRefs: [],
			contentDescriptors: [],
		};

		const nextReviewPackage = applyReviewMetadataDeltaToReviewPackage({
			reviewPackage,
			deltaFrame,
		});

		expect(nextReviewPackage?.itemsById['item-source']?.contentLineCountsByRole).toEqual({
			base: 17,
			head: 23,
		});
	});

	test('preserves resolved content handles when a metadata delta omits descriptor refs', () => {
		const reviewPackage = makeBridgeReviewPackage();
		const currentItem = reviewPackage.itemsById['item-source'];
		if (currentItem === undefined) {
			throw new Error('Expected modified source item');
		}
		const resolvedBaseHandle = currentItem.contentRoles.base;
		const resolvedHeadHandle = currentItem.contentRoles.head;
		const deltaItem = makeReviewProjectionInputItem({
			itemId: currentItem.itemId,
			path: currentItem.headPath ?? 'Sources/App/Source.swift',
		});
		const deltaFrame: ReviewDeltaMaterializerDelta = {
			kind: 'metadataDelta',
			packageId: reviewPackage.packageId,
			fromRevision: reviewPackage.revision,
			toRevision: reviewPackage.revision + 1,
			operations: [{ kind: 'upsertItemMetadata', item: deltaItem }],
			summary: reviewPackage.summary,
			registeredContentDescriptorRefs: [],
			contentDescriptors: [],
		};

		const nextReviewPackage = applyReviewMetadataDeltaToReviewPackage({
			reviewPackage,
			deltaFrame,
		});

		// A metadata-only re-touch (no fresher descriptor for a role) must NOT null a resolved
		// content descriptor. The role handles + contentHash carry forward until a fresher descriptor
		// replaces them, so already-loaded content is not dropped by the content-validity gate.
		expect(nextReviewPackage?.itemsById['item-source']?.contentRoles.base).toEqual(
			resolvedBaseHandle,
		);
		expect(nextReviewPackage?.itemsById['item-source']?.contentRoles.head).toEqual(
			resolvedHeadHandle,
		);
	});

	test('applies same-batch extent facts to appended review items', () => {
		const reviewPackage = makeBridgeReviewPackage();
		const appendedItem = makeReviewProjectionInputItem({
			itemId: 'item-appended',
			path: 'Sources/App/Appended.swift',
		});
		const deltaFrame: ReviewDeltaMaterializerDelta = {
			kind: 'metadataDelta',
			packageId: reviewPackage.packageId,
			fromRevision: reviewPackage.revision,
			toRevision: reviewPackage.revision + 1,
			operations: [
				{ kind: 'appendItems', items: [appendedItem] },
				{
					kind: 'upsertExtentFacts',
					facts: [
						{ itemId: appendedItem.itemId, contentRole: 'base', lineCount: 31 },
						{ itemId: appendedItem.itemId, contentRole: 'head', lineCount: 37 },
					],
				},
			],
			summary: reviewPackage.summary,
			registeredContentDescriptorRefs: [],
			contentDescriptors: [],
		};

		const nextReviewPackage = applyReviewMetadataDeltaToReviewPackage({
			reviewPackage,
			deltaFrame,
		});

		expect(nextReviewPackage?.itemsById[appendedItem.itemId]?.contentLineCountsByRole).toEqual({
			base: 31,
			head: 37,
		});
	});

	test('prunes empty review tree directories after removing rows', () => {
		const reviewPackage = makeBridgeReviewPackage();
		const deltaFrame: ReviewDeltaMaterializerDelta = {
			kind: 'metadataDelta',
			packageId: reviewPackage.packageId,
			fromRevision: reviewPackage.revision,
			toRevision: reviewPackage.revision + 1,
			operations: [
				{
					kind: 'removeTreeRows',
					rowIds: ['row-file-a'],
				},
			],
			summary: reviewPackage.summary,
			registeredContentDescriptorRefs: [],
			contentDescriptors: [],
		};

		const rows = reviewTreeRowsWithMetadataDelta({
			current: [
				{ rowId: 'row-dir-src', path: 'src', depth: 0, isDirectory: true },
				{ rowId: 'row-dir-src-a', path: 'src/a', depth: 1, isDirectory: true },
				{
					rowId: 'row-file-a',
					itemId: 'item-a',
					path: 'src/a/File.swift',
					depth: 2,
					isDirectory: false,
				},
				{ rowId: 'row-dir-src-b', path: 'src/b', depth: 1, isDirectory: true },
				{
					rowId: 'row-file-b',
					itemId: 'item-b',
					path: 'src/b/File.swift',
					depth: 2,
					isDirectory: false,
				},
			],
			deltaFrame,
		});

		expect(rows.map((row): string => row.rowId)).toEqual([
			'row-dir-src',
			'row-dir-src-b',
			'row-file-b',
		]);
	});

	test('keeps directories with surviving file descendants', () => {
		const rows = pruneEmptyReviewTreeDirectories([
			{ rowId: 'row-dir-src', path: 'src', depth: 0, isDirectory: true },
			{ rowId: 'row-dir-src-a', path: 'src/a', depth: 1, isDirectory: true },
			{
				rowId: 'row-file-a',
				itemId: 'item-a',
				path: 'src/a/File.swift',
				depth: 2,
				isDirectory: false,
			},
		]);

		expect(rows.map((row): string => row.rowId)).toEqual([
			'row-dir-src',
			'row-dir-src-a',
			'row-file-a',
		]);
	});
});

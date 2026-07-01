import { describe, expect, test } from 'vitest';

import { createBridgeDemandScheduler } from '../core/demand/bridge-demand-scheduler.js';
import { createBridgeResourceExecutor } from '../core/demand/bridge-resource-executor.js';
import type { BridgeDemandLane } from '../core/models/bridge-demand-models.js';
import type { BridgeAttachedResourceDescriptor } from '../core/models/bridge-resource-descriptor.js';
import { createBridgeResourceDescriptorRegistry } from '../core/resources/bridge-resource-registry.js';
import type { BridgeTextResourceStreamResult } from '../core/resources/bridge-resource-stream.js';
import type { ReviewMaterializerDelta } from '../features/review/materialization/review-materializer.js';
import type { ReviewMetadataSnapshotFrame } from '../features/review/models/review-protocol-models.js';
import {
	makeBridgeContentHandle,
	makeBridgeReviewItem,
	makeBridgeReviewPackage,
} from '../foundation/review-package/bridge-review-package-test-support.js';
import type {
	BridgeContentHandle,
	BridgeReviewPackage,
} from '../foundation/review-package/bridge-review-package.js';
import {
	loadReviewItemContentResourcesThroughDemandResult,
	type ReviewContentDemandTelemetry,
} from '../review-viewer/content/review-content-demand-loader.js';
import { makeReviewItemContentResourcesKey } from '../review-viewer/content/visible-review-content-hydration.js';
import type { BridgeReviewProjectionInputItem } from '../review-viewer/models/review-projection-models.js';
import {
	applyReviewMetadataDeltaToReviewPackage,
	bridgeReviewContentDemandByteBudget,
	pruneEmptyReviewTreeDirectories,
	reviewSnapshotDescriptorRefsByHandleIdForPackage,
	reviewSnapshotFrameDescriptorsMatchPackage,
	reviewTreeRowsWithMetadataDelta,
	reviewItemDemandCancellationTargetForSelectionChange,
	shouldRetrySelectedReviewContentAfterDescriptorRegistration,
	shouldStartSelectedReviewContentDemand,
	shouldPauseVisibleReviewContentHydration,
	type BridgeReviewFrameAuthority,
} from './bridge-app.js';

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
	test('pauses visible warming while selected foreground content is loading', () => {
		expect(
			shouldPauseVisibleReviewContentHydration({
				isActive: true,
				codeViewScrollActive: false,
				currentSelectedContentKey: 'selected-key',
				foregroundSelectedContentKey: null,
				selectedContentResourcesState: {
					itemId: 'item-selected',
					contentKey: 'selected-key',
					status: 'loading',
					resources: null,
				},
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
				selectedContentResourcesState: null,
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
				selectedContentResourcesState: {
					itemId: 'item-selected',
					contentKey: 'selected-key',
					status: 'ready',
					resources: {
						file: {
							handle: makeBridgeContentHandle('item-selected', 'head'),
							readText: () => 'ready',
						},
					},
				},
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
				selectedContentResourcesState: null,
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
				selectedContentResourcesState: {
					itemId: 'item-selected',
					contentKey: 'selected-key',
					status: 'ready',
					resources: {
						file: {
							handle: makeBridgeContentHandle('item-selected', 'head'),
							readText: () => 'ready',
						},
					},
				},
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
				selectedContentResourcesState: {
					itemId: 'item-selected',
					contentKey: 'selected-key',
					status: 'ready',
					resources: {
						file: {
							handle: makeBridgeContentHandle('item-selected', 'head'),
							readText: () => 'ready',
						},
					},
				},
			}),
		).toBe(true);
	});
});

describe('BridgeApp selected review content demand policy', () => {
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
			scheduler: createBridgeDemandScheduler({
				maxQueuedIntentsPerLane: 8,
				maxQueuedEstimatedBytes: bridgeReviewContentDemandByteBudget.demandMaxQueuedEstimatedBytes,
			}),
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

	test('does not preserve stale modified content handles when metadata deltas omit descriptor refs', () => {
		const reviewPackage = makeBridgeReviewPackage();
		const currentItem = reviewPackage.itemsById['item-source'];
		if (currentItem === undefined) {
			throw new Error('Expected modified source item');
		}
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

		expect(nextReviewPackage?.itemsById['item-source']?.contentRoles.base).toBeNull();
		expect(nextReviewPackage?.itemsById['item-source']?.contentRoles.head).toBeNull();
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

function makeReviewProjectionInputItem(props: {
	readonly itemId: string;
	readonly path: string;
}): BridgeReviewProjectionInputItem {
	return {
		itemId: props.itemId,
		basePath: props.path,
		headPath: props.path,
		changeKind: 'modified',
		fileClass: 'source',
		language: 'swift',
		extension: 'swift',
		isHiddenByDefault: false,
		reviewPriority: 'normal',
		reviewState: 'unreviewed',
		contentRoles: ['base', 'head'],
		contentDescriptorIdsByRole: {},
		mimeTypes: ['text/x-swift'],
		provenance: emptyReviewProjectionItemProvenance(),
	};
}

function makeReviewMetadataSnapshotFrame(props: {
	readonly contentDescriptors: readonly BridgeAttachedResourceDescriptor[];
	readonly reviewFrameAuthority: BridgeReviewFrameAuthority;
	readonly reviewPackage: BridgeReviewPackage;
}): ReviewMetadataSnapshotFrame {
	return {
		kind: 'metadataSnapshot',
		streamId: props.reviewFrameAuthority.streamId,
		generation: props.reviewPackage.reviewGeneration,
		sequence: 0,
		frameKind: 'review.metadataSnapshot',
		comparison: {
			packageId: props.reviewPackage.packageId,
			sourceIdentity: props.reviewPackage.query.queryId,
			generation: props.reviewPackage.reviewGeneration,
			revision: props.reviewPackage.revision,
			baseEndpoint: props.reviewPackage.baseEndpoint,
			headEndpoint: props.reviewPackage.headEndpoint,
			contentDescriptors: [...props.contentDescriptors],
		},
		selectedItemId: 'item-source',
		visibleItemIds: ['item-source'],
		itemMetadata: [
			makeReviewProjectionInputItem({ itemId: 'item-source', path: 'Sources/App/View.swift' }),
		],
		treeRows: [
			{
				rowId: 'row-item-source',
				itemId: 'item-source',
				path: 'Sources/App/View.swift',
				depth: 2,
				isDirectory: false,
			},
		],
		extentFacts: [],
		summary: props.reviewPackage.summary,
	};
}

function makeReviewAttachedContentDescriptor(props: {
	readonly handle: BridgeContentHandle;
	readonly reviewFrameAuthority: BridgeReviewFrameAuthority;
	readonly reviewPackage: BridgeReviewPackage;
	readonly contentByteBounds?: {
		readonly expectedBytes?: number | undefined;
		readonly maxBytes: number;
	};
}): BridgeAttachedResourceDescriptor {
	const identity = {
		paneId: props.reviewFrameAuthority.paneId,
		protocol: 'review',
		sourceId: props.reviewPackage.query.queryId,
		packageId: props.reviewPackage.packageId,
		generation: props.handle.reviewGeneration,
		streamId: props.reviewFrameAuthority.streamId,
	} as const;
	return {
		ref: {
			descriptorId: props.handle.handleId,
			expectedProtocol: 'review',
			expectedResourceKind: 'content',
			expectedIdentity: identity,
		},
		descriptor: {
			descriptorId: props.handle.handleId,
			protocol: 'review',
			resourceKind: 'content',
			resourceUrl: props.handle.resourceUrl,
			identity,
			content: {
				mediaType: props.handle.mimeType,
				encoding: props.handle.isBinary ? 'binary' : 'utf-8',
				...(props.contentByteBounds === undefined
					? { expectedBytes: props.handle.sizeBytes }
					: props.contentByteBounds.expectedBytes === undefined
						? {}
						: { expectedBytes: props.contentByteBounds.expectedBytes }),
				maxBytes: props.contentByteBounds?.maxBytes ?? Math.max(props.handle.sizeBytes, 1),
			},
		},
	};
}

function emptyReviewProjectionItemProvenance(): BridgeReviewProjectionInputItem['provenance'] {
	return {
		agentSessionIds: [],
		promptIds: [],
		operationIds: [],
	};
}

interface Deferred<TValue> {
	readonly promise: Promise<TValue>;
	readonly resolve: (value: TValue) => void;
}

function createDeferred<TValue>(): Deferred<TValue> {
	let resolveDeferred: ((value: TValue) => void) | null = null;
	const promise = new Promise<TValue>((resolve): void => {
		resolveDeferred = resolve;
	});
	if (resolveDeferred === null) {
		throw new Error('Deferred test value did not initialize');
	}
	return {
		promise,
		resolve: resolveDeferred,
	};
}

async function flushMicrotasks(count: number): Promise<void> {
	let flushPromise = Promise.resolve();
	for (let index = 0; index < count; index += 1) {
		flushPromise = flushPromise.then((): void => {});
	}
	await flushPromise;
}

function makeTextStreamResult(text: string): BridgeTextResourceStreamResult {
	return {
		authoritative: true,
		byteLength: new TextEncoder().encode(text).byteLength,
		readText: (): string => text,
	};
}

function emptyDemandLaneByteCounts(): Record<BridgeDemandLane, number> {
	return {
		foreground: 0,
		active: 0,
		visible: 0,
		nearby: 0,
		speculative: 0,
		idle: 0,
	};
}

function makeSelectedReviewContentDemandTelemetry(
	props: Pick<
		ReviewContentDemandTelemetry,
		| 'itemId'
		| 'packageId'
		| 'reviewGeneration'
		| 'revision'
		| 'resultStatus'
		| 'resultReason'
	>,
): ReviewContentDemandTelemetry {
	return {
		...props,
		interest: 'selected',
		byteBudgetSource: 'review-content-demand',
		durationMilliseconds: 4,
		configuredExecutorMaxConcurrentLoads: 2,
		configuredExecutorMaxInFlightBytes: 10,
		configuredSchedulerMaxQueuedEstimatedBytes: 10,
		configuredSchedulerMaxQueuedIntentsPerLane: 2,
		intentCount: 0,
		foregroundIntentCount: 0,
		activeIntentCount: 0,
		visibleIntentCount: 0,
		nearbyIntentCount: 0,
		speculativeIntentCount: 0,
		idleIntentCount: 0,
		enqueueAcceptedCount: 0,
		enqueueRejectedCount: 0,
		schedulerQueuedIntentCountBefore: 0,
		schedulerQueuedIntentCountAfterEnqueue: 0,
		schedulerQueuedIntentCountAfter: 0,
		schedulerQueuedEstimatedBytesBefore: 0,
		schedulerQueuedEstimatedBytesAfterEnqueue: 0,
		schedulerQueuedEstimatedBytesAfter: 0,
		executorInFlightCountBefore: 0,
		executorInFlightCountAfterDispatch: 0,
		executorInFlightCountAfter: 0,
		executorInFlightBytesBefore: 0,
		executorInFlightBytesAfterDispatch: 0,
		executorInFlightBytesAfter: 0,
		executorQueuedLoadCountBefore: 0,
		executorQueuedLoadCountAfterDispatch: 0,
		executorQueuedLoadCountAfter: 0,
		executorQueuedBytesBefore: 0,
		executorQueuedBytesAfterDispatch: 0,
		executorQueuedBytesAfter: 0,
		laneUpgradeCount: 0,
		maxSchedulerQueuedIntentCount: 0,
		maxExecutorInFlightCount: 0,
		maxExecutorQueuedLoadCount: 0,
		admittedBytes: 0,
		admittedBytesByLane: emptyDemandLaneByteCounts(),
		deferredCount: 0,
		deferredEstimatedBytesByLane: emptyDemandLaneByteCounts(),
		droppedEstimatedBytesByLane: emptyDemandLaneByteCounts(),
		droppedIntentCount: 0,
		failedCount: props.resultStatus === 'failed' ? 1 : 0,
		loadedCount: props.resultStatus === 'ready' ? 1 : 0,
		staleDropCount: 0,
	};
}

import { describe, expect, test, vi } from 'vitest';

import { createBridgeResourceDescriptorRegistry } from '../core/resources/bridge-resource-registry.js';
import {
	applyValidatedReviewProtocolFrame,
	type ReviewMaterializerDelta,
} from '../features/review/materialization/review-materializer.js';
import type {
	ReviewInvalidationFrame,
	ReviewTreeRowMetadata,
} from '../features/review/models/review-protocol-models.js';
import {
	makeBridgeReviewItem,
	makeBridgeReviewPackage,
} from '../foundation/review-package/bridge-review-package-test-support.js';
import type { BridgeReviewPackage } from '../foundation/review-package/bridge-review-package.js';
import { makeBridgeViewerBrowserFixture } from '../review-viewer/test-support/bridge-viewer-mocked-backend.js';
import { applyReviewProtocolTransportFrame } from './bridge-app-review-controller.js';
import { bridgeReviewPackageFromMetadataSnapshot } from './bridge-app-review-metadata-package.js';
import {
	applyReviewMetadataDeltaToReviewPackage,
	contentDemandResourceUrl,
	pruneEmptyReviewTreeDirectories,
	reviewSnapshotDescriptorRefsByHandleIdForPackage,
	reviewSnapshotFrameDescriptorsMatchPackage,
	reviewTreeRowsWithMetadataDelta,
	reviewFileTargetForReviewPackagePath,
	reviewItemDemandCancellationTargetForSelectionChange,
	selectedCanvasLoadingReasonForCurrentSelection,
	selectedContentUnavailablePathForCurrentSelection,
	type BridgeReviewFrameAuthority,
} from './bridge-app.js';
import {
	makeNoopTelemetryRecorder,
	makeReviewAttachedContentDescriptor,
	makeReviewMetadataSnapshotFrame,
	makeReviewProjectionInputItem,
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

	test('selected canvas content loading follows worker-owned stale availability', () => {
		expect(
			selectedCanvasLoadingReasonForCurrentSelection({
				selectedContentAvailability: { state: 'stale' },
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
});

describe('BridgeApp Review content demand byte budget', () => {
	test('routes accepted review invalidation frames to the worker cache owner', async () => {
		const reviewPackage = makeBridgeReviewPackage();
		const reviewFrameAuthority: BridgeReviewFrameAuthority = {
			paneId: 'pane-1',
			streamId: 'review:pane-1',
		};
		const applyEvents: string[] = [];
		const currentTreeRows: readonly ReviewTreeRowMetadata[] = [
			{
				rowId: 'item-source',
				itemId: 'item-source',
				path: 'Sources/App/View.swift',
				depth: 0,
				isDirectory: false,
			},
		];
		const synchronizedReviewSources: {
			readonly reviewPackage: BridgeReviewPackage | null;
			readonly reviewTreeRows: readonly ReviewTreeRowMetadata[];
		}[] = [];
		const dispatchReviewInvalidation = vi.fn<(frame: ReviewInvalidationFrame) => void>(() => {
			applyEvents.push('invalidate');
		});
		const invalidationFrame = {
			kind: 'delta',
			frameKind: 'review.invalidate',
			streamId: reviewFrameAuthority.streamId,
			generation: reviewPackage.reviewGeneration,
			sequence: 2,
			invalidation: {
				scope: 'items',
				itemIds: ['item-source'],
				pathHints: [],
				reason: 'watchEvent',
			},
		} satisfies ReviewInvalidationFrame;

		await applyReviewProtocolTransportFrame({
			protocolFrame: invalidationFrame,
			setReviewPackage: (): void => {},
			getReviewTreeRows: (): readonly ReviewTreeRowMetadata[] => currentTreeRows,
			setReviewTreeRows: (): void => {},
			setDiffStatus: (): void => {},
			setSelectedItemId: (): void => {},
			selectInitialReviewItem: (): boolean => true,
			getSelectedItemId: (): string | null => null,
			reviewPackageRef: { current: reviewPackage },
			telemetryContextByPackageKey: new Map(),
			currentReviewPackageTelemetryContextRef: { current: null },
			reviewReadyStartMillisecondsByPackageKeyRef: { current: new Map() },
			descriptorRegistry: createBridgeResourceDescriptorRegistry({
				allowedResourceKindsByProtocol: { review: new Set(['content']) },
			}),
			dispatchReviewInvalidation,
			synchronizeReviewWorkerSource: (source): void => {
				applyEvents.push('source');
				synchronizedReviewSources.push(source);
			},
			reviewFrameAuthority,
			telemetryContext: {
				slice: 'review_metadata',
				traceContext: null,
				transport: 'intake',
			},
			telemetryRecorder: makeNoopTelemetryRecorder(),
		});

		expect(dispatchReviewInvalidation).toHaveBeenCalledExactlyOnceWith(invalidationFrame);
		expect(applyEvents).toEqual(['source', 'invalidate']);
		expect(synchronizedReviewSources).toEqual([
			{
				reviewPackage,
				reviewTreeRows: currentTreeRows,
			},
		]);
	});

	test('selects package-applied initial review item without FE foreground demand', async () => {
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
		const reviewPackageRef: { current: BridgeReviewPackage | null } = { current: null };
		const currentReviewPackageRef: { current: BridgeReviewPackage | null } = { current: null };
		let currentTreeRows: readonly ReviewTreeRowMetadata[] = [];
		const applyEvents: string[] = [];
		const synchronizedReviewSources: {
			readonly reviewPackage: BridgeReviewPackage | null;
			readonly reviewTreeRows: readonly ReviewTreeRowMetadata[];
		}[] = [];
		const selectInitialReviewItem = vi.fn<(itemId: string) => boolean>(() => {
			applyEvents.push('select');
			return true;
		});

		await applyReviewProtocolTransportFrame({
			protocolFrame: frame,
			setReviewPackage: (update): void => {
				currentReviewPackageRef.current = update(currentReviewPackageRef.current);
			},
			getReviewTreeRows: (): readonly ReviewTreeRowMetadata[] => currentTreeRows,
			setReviewTreeRows: (rows): void => {
				currentTreeRows = rows;
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
			dispatchReviewInvalidation: (): void => {},
			synchronizeReviewWorkerSource: (source): void => {
				applyEvents.push('source');
				synchronizedReviewSources.push(source);
			},
			reviewFrameAuthority,
			telemetryContext: {
				slice: 'review_metadata',
				traceContext: null,
				transport: 'intake',
			},
			telemetryRecorder: makeNoopTelemetryRecorder(),
		});

		expect(selectInitialReviewItem).toHaveBeenCalledExactlyOnceWith('item-source');
		expect(applyEvents).toEqual(['source', 'select']);
		expect(synchronizedReviewSources).toEqual([
			{
				reviewPackage: expect.objectContaining({ packageId: reviewPackage.packageId }),
				reviewTreeRows: expect.arrayContaining([
					expect.objectContaining({ itemId: 'item-source' }),
				]),
			},
		]);
		const currentReviewPackage = currentReviewPackageRef.current;
		expect(currentReviewPackage?.packageId).toBe(reviewPackage.packageId);
		const appliedItem = currentReviewPackage?.itemsById['item-source'];
		const appliedBaseHandle = appliedItem?.contentRoles.base ?? null;
		const appliedHeadHandle = appliedItem?.contentRoles.head ?? null;
		if (appliedBaseHandle === null || appliedHeadHandle === null) {
			throw new Error('Expected applied package to include base/head content handles');
		}
		expect(currentTreeRows.length).toBeGreaterThan(0);
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
				maxBytes: 4 * 1024 * 1024,
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
		).toBe(false);
		const materializeResult = applyValidatedReviewProtocolFrame({
			frame,
			paneId: reviewFrameAuthority.paneId,
			registry: descriptorRegistry,
		});
		if (!materializeResult.ok || materializeResult.delta.kind !== 'metadataSnapshot') {
			throw new Error('Expected metadata snapshot to materialize');
		}
		const materializedPackage = bridgeReviewPackageFromMetadataSnapshot(materializeResult.delta);

		expect(
			reviewSnapshotFrameDescriptorsMatchPackage({
				frame,
				reviewFrameAuthority,
				reviewPackage: materializedPackage,
			}),
		).toBe(true);
		const descriptorRefsByHandleId = reviewSnapshotDescriptorRefsByHandleIdForPackage({
			descriptorRegistry,
			frame,
			reviewFrameAuthority,
			reviewPackage: materializedPackage,
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
		expect(registeredBaseDescriptor?.content.maxBytes).toBe(4 * 1024 * 1024);
		expect(registeredHeadDescriptor?.content.expectedBytes).toBe(headHandle.sizeBytes);
		expect(registeredHeadDescriptor?.content.maxBytes).toBe(headHandle.sizeBytes);
	});

	test('materializes inexact native descriptor byte bounds into review package handles', () => {
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
		const frame = makeReviewMetadataSnapshotFrame({
			contentDescriptors: [
				makeReviewAttachedContentDescriptor({
					handle: baseHandle,
					reviewFrameAuthority,
					reviewPackage,
					contentByteBounds: {
						expectedBytes: undefined,
						maxBytes: 64,
					},
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
		const materializeResult = applyValidatedReviewProtocolFrame({
			frame,
			paneId: reviewFrameAuthority.paneId,
			registry: createBridgeResourceDescriptorRegistry({
				allowedResourceKindsByProtocol: {
					review: new Set(['content']),
				},
			}),
		});
		if (!materializeResult.ok || materializeResult.delta.kind !== 'metadataSnapshot') {
			throw new Error('Expected metadata snapshot to materialize');
		}

		const materializedPackage = bridgeReviewPackageFromMetadataSnapshot(materializeResult.delta);
		const materializedBaseHandle =
			materializedPackage.itemsById['item-source']?.contentRoles.base ?? null;

		expect(materializedBaseHandle).toMatchObject({
			handleId: baseHandle.handleId,
			sizeBytes: 0,
			sizeBytesIsExact: false,
			maxBytes: 64,
		});
	});

	test('rejects same-revision inexact descriptor reannounces with stale max bytes', () => {
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
		const frame = makeReviewMetadataSnapshotFrame({
			contentDescriptors: [
				makeReviewAttachedContentDescriptor({
					handle: baseHandle,
					reviewFrameAuthority,
					reviewPackage,
					contentByteBounds: {
						expectedBytes: undefined,
						maxBytes: 64,
					},
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
		const materializeResult = applyValidatedReviewProtocolFrame({
			frame,
			paneId: reviewFrameAuthority.paneId,
			registry: createBridgeResourceDescriptorRegistry({
				allowedResourceKindsByProtocol: {
					review: new Set(['content']),
				},
			}),
		});
		if (!materializeResult.ok || materializeResult.delta.kind !== 'metadataSnapshot') {
			throw new Error('Expected metadata snapshot to materialize');
		}
		const materializedPackage = bridgeReviewPackageFromMetadataSnapshot(materializeResult.delta);
		const staleCapFrame = makeReviewMetadataSnapshotFrame({
			contentDescriptors: [
				makeReviewAttachedContentDescriptor({
					handle: baseHandle,
					reviewFrameAuthority,
					reviewPackage,
					contentByteBounds: {
						expectedBytes: undefined,
						maxBytes: 128,
					},
				}),
				makeReviewAttachedContentDescriptor({
					handle: headHandle,
					reviewFrameAuthority,
					reviewPackage,
				}),
			],
			reviewFrameAuthority,
			reviewPackage: materializedPackage,
		});

		expect(
			reviewSnapshotFrameDescriptorsMatchPackage({
				frame: staleCapFrame,
				reviewFrameAuthority,
				reviewPackage: materializedPackage,
			}),
		).toBe(false);
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

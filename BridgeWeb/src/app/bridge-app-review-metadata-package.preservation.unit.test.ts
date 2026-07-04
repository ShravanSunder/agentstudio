import { describe, expect, test } from 'vitest';

import { createBridgeDemandScheduler } from '../core/demand/bridge-demand-scheduler.js';
import { createBridgeResourceExecutor } from '../core/demand/bridge-resource-executor.js';
import type { BridgeAttachedResourceDescriptor } from '../core/models/bridge-resource-descriptor.js';
import { createBridgeResourceDescriptorRegistry } from '../core/resources/bridge-resource-registry.js';
import type { ReviewMaterializerDelta } from '../features/review/materialization/review-materializer.js';
import type {
	ReviewMetadataDeltaFrame,
	ReviewMetadataOperation,
	ReviewProtocolFrame,
} from '../features/review/models/review-protocol-models.js';
import { makeBridgeReviewPackage } from '../foundation/review-package/bridge-review-package-test-support.js';
import type {
	BridgeContentHandle,
	BridgeContentRole,
	BridgeReviewItemDescriptor,
	BridgeReviewPackage,
} from '../foundation/review-package/bridge-review-package.js';
import { createBridgeReviewContentRegistry } from '../review-viewer/content/review-content-registry.js';
import type { BridgeReviewProjectionInputItem } from '../review-viewer/models/review-projection-models.js';
import { applyReviewProtocolTransportFrame } from './bridge-app-review-controller.js';
import type { BridgeDiffStatusState } from './bridge-app-review-controller.js';
import type { BridgeReviewFrameAuthority } from './bridge-app-review-frame-authority.js';
import {
	applyReviewMetadataDeltaToReviewPackage,
	bridgeReviewPackageFromMetadataSnapshot,
	bridgeReviewPackageWithMetadataSnapshot,
	bridgeReviewPackageWithMetadataWindow,
} from './bridge-app-review-metadata-package.js';
import {
	makeNoopTelemetryRecorder,
	makeReviewAttachedContentDescriptor,
	makeReviewProjectionInputItem,
	makeTextStreamResult,
} from './bridge-app.unit.test-support.js';

type ReviewSnapshotMaterializerDelta = Extract<
	ReviewMaterializerDelta,
	{ readonly kind: 'metadataSnapshot' }
>;
type ReviewWindowMaterializerDelta = Extract<
	ReviewMaterializerDelta,
	{ readonly kind: 'metadataWindow' }
>;
type ReviewDeltaMaterializerDelta = Extract<
	ReviewMaterializerDelta,
	{ readonly kind: 'metadataDelta' }
>;

type PreservationFramePath =
	| 'snapshot re-delivery'
	| 'metadata window'
	| 'extent-fact delta'
	| 'summary delta'
	| 'order delta'
	| 'upsertItemMetadata'
	| 'appendItems-retouch';

const preservationFramePaths = [
	'snapshot re-delivery',
	'metadata window',
	'extent-fact delta',
	'summary delta',
	'order delta',
	'upsertItemMetadata',
	'appendItems-retouch',
] as const satisfies readonly PreservationFramePath[];

const reviewFrameAuthority = {
	paneId: 'pane-1',
	streamId: 'review:pane-1',
} as const satisfies BridgeReviewFrameAuthority;
const targetItemId = 'item-source';
const targetItemPath = 'Sources/App/View.swift';

describe('Bridge review metadata package resolved-content preservation matrix', () => {
	for (const framePath of preservationFramePaths) {
		test(`${framePath}: omitting descriptor refs preserves resolved role handles and content hashes`, () => {
			const reviewPackage = makeBridgeReviewPackage();
			const currentItem = requireTargetReviewItem(reviewPackage);
			const nextReviewPackage = applyPreservationFramePath({
				framePath,
				reviewPackage,
				descriptorDelivery: { kind: 'omitted' },
			});

			const nextItem = requireTargetReviewItem(nextReviewPackage);

			expectResolvedRoleHandlesToEqualCurrent(nextItem, currentItem);
		});

		test(`${framePath}: fresher descriptor refs replace carried role handles and content hashes`, () => {
			const reviewPackage = makeBridgeReviewPackage();
			const currentItem = requireTargetReviewItem(reviewPackage);
			const freshDescriptorDelivery = makeFreshDescriptorDelivery(reviewPackage);
			const nextReviewPackage = applyPreservationFramePath({
				framePath,
				reviewPackage,
				descriptorDelivery: freshDescriptorDelivery,
			});

			const nextItem = requireTargetReviewItem(nextReviewPackage);

			expectFreshRoleHandlesToReplaceCurrent({
				currentItem,
				freshBaseHandle: freshDescriptorDelivery.baseHandle,
				freshHeadHandle: freshDescriptorDelivery.headHandle,
				nextItem,
			});
		});

		test(`${framePath}: metadata-only item stays metadata-only`, () => {
			const reviewPackage = makeMetadataOnlyReviewPackage();
			const nextReviewPackage = applyPreservationFramePath({
				framePath,
				reviewPackage,
				descriptorDelivery: { kind: 'omitted' },
			});

			const nextItem = requireTargetReviewItem(nextReviewPackage);

			expectMetadataOnlyRoleHandles(nextItem);
		});

		test(`${framePath}: generation rotation invalidates carried role handles`, async () => {
			const reviewPackage = makeBridgeReviewPackage();
			const nextReviewPackage = await applyGenerationRotatedProtocolFramePath({
				framePath,
				reviewPackage,
			});

			if (nextReviewPackage === null) {
				expect(nextReviewPackage).toBeNull();
				return;
			}
			expect(nextReviewPackage.reviewGeneration).toBe(reviewPackage.reviewGeneration + 1);
			expectMetadataOnlyRoleHandles(requireTargetReviewItem(nextReviewPackage));
		});
	}
});

interface OmittedDescriptorDelivery {
	readonly kind: 'omitted';
}

interface FreshDescriptorDelivery {
	readonly kind: 'fresh';
	readonly projectionItem: BridgeReviewProjectionInputItem;
	readonly contentDescriptors: readonly BridgeAttachedResourceDescriptor[];
	readonly baseHandle: BridgeContentHandle;
	readonly headHandle: BridgeContentHandle;
}

type DescriptorDelivery = OmittedDescriptorDelivery | FreshDescriptorDelivery;

function applyPreservationFramePath(props: {
	readonly framePath: PreservationFramePath;
	readonly reviewPackage: BridgeReviewPackage;
	readonly descriptorDelivery: DescriptorDelivery;
}): BridgeReviewPackage {
	switch (props.framePath) {
		case 'snapshot re-delivery':
			return applySnapshotRedelivery({
				reviewPackage: props.reviewPackage,
				descriptorDelivery: props.descriptorDelivery,
			});
		case 'metadata window':
			return applyMetadataWindow({
				reviewPackage: props.reviewPackage,
				descriptorDelivery: props.descriptorDelivery,
			});
		case 'extent-fact delta':
			return requireAppliedDeltaPackage({
				reviewPackage: props.reviewPackage,
				deltaFrame: makeMetadataDeltaFrame({
					reviewPackage: props.reviewPackage,
					descriptorDelivery: props.descriptorDelivery,
					operations: [
						{
							kind: 'upsertExtentFacts',
							facts: [
								{ itemId: targetItemId, contentRole: 'base', lineCount: 17 },
								{ itemId: targetItemId, contentRole: 'head', lineCount: 23 },
							],
						},
						metadataRetouchOperationForDescriptorDelivery({
							descriptorDelivery: props.descriptorDelivery,
							reviewPackage: props.reviewPackage,
						}),
					],
				}),
			});
		case 'summary delta':
			return requireAppliedDeltaPackage({
				reviewPackage: props.reviewPackage,
				deltaFrame: makeMetadataDeltaFrame({
					reviewPackage: props.reviewPackage,
					descriptorDelivery: props.descriptorDelivery,
					operations: [
						metadataRetouchOperationForDescriptorDelivery({
							descriptorDelivery: props.descriptorDelivery,
							reviewPackage: props.reviewPackage,
						}),
					],
					summary: {
						...props.reviewPackage.summary,
						filesChanged: props.reviewPackage.summary.filesChanged + 1,
					},
				}),
			});
		case 'order delta':
			return requireAppliedDeltaPackage({
				reviewPackage: props.reviewPackage,
				deltaFrame: makeMetadataDeltaFrame({
					reviewPackage: props.reviewPackage,
					descriptorDelivery: props.descriptorDelivery,
					operations: [
						{ kind: 'replaceItemOrder', itemIds: [targetItemId] },
						metadataRetouchOperationForDescriptorDelivery({
							descriptorDelivery: props.descriptorDelivery,
							reviewPackage: props.reviewPackage,
						}),
					],
				}),
			});
		case 'upsertItemMetadata':
			return requireAppliedDeltaPackage({
				reviewPackage: props.reviewPackage,
				deltaFrame: makeMetadataDeltaFrame({
					reviewPackage: props.reviewPackage,
					descriptorDelivery: props.descriptorDelivery,
					operations: [
						{
							kind: 'upsertItemMetadata',
							item: projectionItemForDescriptorDelivery({
								descriptorDelivery: props.descriptorDelivery,
								reviewPackage: props.reviewPackage,
							}),
						},
					],
				}),
			});
		case 'appendItems-retouch':
			return requireAppliedDeltaPackage({
				reviewPackage: props.reviewPackage,
				deltaFrame: makeMetadataDeltaFrame({
					reviewPackage: props.reviewPackage,
					descriptorDelivery: props.descriptorDelivery,
					operations: [
						{
							kind: 'appendItems',
							items: [
								projectionItemForDescriptorDelivery({
									descriptorDelivery: props.descriptorDelivery,
									reviewPackage: props.reviewPackage,
								}),
							],
						},
					],
				}),
			});
	}
	const exhaustiveFramePath: never = props.framePath;
	return exhaustiveFramePath;
}

function applySnapshotRedelivery(props: {
	readonly reviewPackage: BridgeReviewPackage;
	readonly descriptorDelivery: DescriptorDelivery;
}): BridgeReviewPackage {
	const snapshotFrame = makeMetadataSnapshotDelta({
		reviewPackage: props.reviewPackage,
		descriptorDelivery: props.descriptorDelivery,
		generation: props.reviewPackage.reviewGeneration,
		revision: props.reviewPackage.revision + 1,
	});
	const snapshotPackage = bridgeReviewPackageFromMetadataSnapshot(snapshotFrame);
	return bridgeReviewPackageWithMetadataSnapshot({
		reviewPackage: props.reviewPackage,
		snapshotPackage,
	});
}

function applyMetadataWindow(props: {
	readonly reviewPackage: BridgeReviewPackage;
	readonly descriptorDelivery: DescriptorDelivery;
}): BridgeReviewPackage {
	return bridgeReviewPackageWithMetadataWindow({
		reviewPackage: props.reviewPackage,
		windowFrame: {
			kind: 'metadataWindow',
			packageId: props.reviewPackage.packageId,
			generation: props.reviewPackage.reviewGeneration,
			revision: props.reviewPackage.revision,
			itemMetadata: [
				projectionItemForDescriptorDelivery({
					descriptorDelivery: props.descriptorDelivery,
					reviewPackage: props.reviewPackage,
				}),
			],
			treeRows: [targetTreeRow()],
			extentFacts: [],
			summary: props.reviewPackage.summary,
			registeredContentDescriptorRefs: [],
			contentDescriptors: contentDescriptorsForDescriptorDelivery(props.descriptorDelivery),
		},
	});
}

function requireAppliedDeltaPackage(props: {
	readonly reviewPackage: BridgeReviewPackage;
	readonly deltaFrame: ReviewDeltaMaterializerDelta;
}): BridgeReviewPackage {
	const nextReviewPackage = applyReviewMetadataDeltaToReviewPackage(props);
	if (nextReviewPackage === null) {
		throw new Error('Expected metadata delta package to apply');
	}
	return nextReviewPackage;
}

function makeMetadataSnapshotDelta(props: {
	readonly reviewPackage: BridgeReviewPackage;
	readonly descriptorDelivery: DescriptorDelivery;
	readonly generation: number;
	readonly revision: number;
}): ReviewSnapshotMaterializerDelta {
	return {
		kind: 'metadataSnapshot',
		packageId: props.reviewPackage.packageId,
		sourceIdentity: props.reviewPackage.query.queryId,
		generation: props.generation,
		revision: props.revision,
		baseEndpoint: props.reviewPackage.baseEndpoint,
		headEndpoint: props.reviewPackage.headEndpoint,
		selectedItemId: targetItemId,
		visibleItemIds: [targetItemId],
		projectionInput: {
			packageId: props.reviewPackage.packageId,
			reviewGeneration: props.generation,
			revision: props.revision,
			orderedItems: [
				projectionItemForDescriptorDelivery({
					descriptorDelivery: props.descriptorDelivery,
					reviewPackage: props.reviewPackage,
				}),
			],
		},
		treeRows: [targetTreeRow()],
		extentFacts: [],
		summary: props.reviewPackage.summary,
		registeredContentDescriptorRefs: [],
		contentDescriptors: contentDescriptorsForDescriptorDelivery(props.descriptorDelivery),
		changesetCluster: null,
	};
}

function makeMetadataDeltaFrame(props: {
	readonly reviewPackage: BridgeReviewPackage;
	readonly descriptorDelivery: DescriptorDelivery;
	readonly operations: readonly ReviewMetadataOperation[];
	readonly summary?: BridgeReviewPackage['summary'];
}): ReviewDeltaMaterializerDelta {
	return {
		kind: 'metadataDelta',
		packageId: props.reviewPackage.packageId,
		fromRevision: props.reviewPackage.revision,
		toRevision: props.reviewPackage.revision + 1,
		operations: props.operations,
		summary: props.summary ?? props.reviewPackage.summary,
		registeredContentDescriptorRefs: [],
		contentDescriptors: contentDescriptorsForDescriptorDelivery(props.descriptorDelivery),
	};
}

function metadataRetouchOperationForDescriptorDelivery(props: {
	readonly reviewPackage: BridgeReviewPackage;
	readonly descriptorDelivery: DescriptorDelivery;
}): Extract<ReviewMetadataOperation, { readonly kind: 'upsertItemMetadata' }> {
	return {
		kind: 'upsertItemMetadata',
		item: projectionItemForDescriptorDelivery(props),
	};
}

function projectionItemForDescriptorDelivery(props: {
	readonly reviewPackage: BridgeReviewPackage;
	readonly descriptorDelivery: DescriptorDelivery;
}): BridgeReviewProjectionInputItem {
	if (props.descriptorDelivery.kind === 'fresh') {
		return props.descriptorDelivery.projectionItem;
	}
	return makeProjectionInputItemWithoutDescriptorRefs(props.reviewPackage);
}

function contentDescriptorsForDescriptorDelivery(
	descriptorDelivery: DescriptorDelivery,
): readonly BridgeAttachedResourceDescriptor[] {
	return descriptorDelivery.kind === 'fresh' ? descriptorDelivery.contentDescriptors : [];
}

function makeFreshDescriptorDelivery(reviewPackage: BridgeReviewPackage): FreshDescriptorDelivery {
	const currentItem = requireTargetReviewItem(reviewPackage);
	const currentBaseHandle = requireRoleHandle({ item: currentItem, role: 'base' });
	const currentHeadHandle = requireRoleHandle({ item: currentItem, role: 'head' });
	const baseHandle = makeFreshContentHandle(currentBaseHandle);
	const headHandle = makeFreshContentHandle(currentHeadHandle);
	return {
		kind: 'fresh',
		projectionItem: makeProjectionInputItemWithDescriptorRefs({
			baseHandle,
			headHandle,
			reviewPackage,
		}),
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
		baseHandle,
		headHandle,
	};
}

function makeFreshContentHandle(handle: BridgeContentHandle): BridgeContentHandle {
	const handleId = `${handle.handleId}-fresh`;
	return {
		...handle,
		handleId,
		resourceUrl: `agentstudio://resource/review/content/${handleId}?generation=${handle.reviewGeneration}`,
		contentHash: `${handle.contentHash}:fresh`,
		cacheKey: `${handle.cacheKey}:fresh`,
	};
}

function makeProjectionInputItemWithDescriptorRefs(props: {
	readonly reviewPackage: BridgeReviewPackage;
	readonly baseHandle: BridgeContentHandle;
	readonly headHandle: BridgeContentHandle;
}): BridgeReviewProjectionInputItem {
	return {
		...makeProjectionInputItemBase(props.reviewPackage),
		contentDescriptorIdsByRole: {
			base: props.baseHandle.handleId,
			head: props.headHandle.handleId,
		},
	};
}

function makeProjectionInputItemWithoutDescriptorRefs(
	reviewPackage: BridgeReviewPackage,
): BridgeReviewProjectionInputItem {
	return makeProjectionInputItemBase(reviewPackage);
}

function makeProjectionInputItemBase(
	reviewPackage: BridgeReviewPackage,
): BridgeReviewProjectionInputItem {
	const currentItem = requireTargetReviewItem(reviewPackage);
	return {
		...makeReviewProjectionInputItem({
			itemId: currentItem.itemId,
			path: currentItem.headPath ?? currentItem.basePath ?? targetItemPath,
		}),
		contentDescriptorIdsByRole: {},
	};
}

function makeMetadataOnlyReviewPackage(): BridgeReviewPackage {
	const reviewPackage = makeBridgeReviewPackage();
	const currentItem = requireTargetReviewItem(reviewPackage);
	const metadataOnlyItem = {
		...currentItem,
		baseContentHash: null,
		headContentHash: null,
		contentRoles: { base: null, head: null, diff: null, file: null },
		cacheKey: `${currentItem.cacheKey}:metadata-only`,
	} satisfies BridgeReviewItemDescriptor;
	return {
		...reviewPackage,
		itemsById: {
			...reviewPackage.itemsById,
			[targetItemId]: metadataOnlyItem,
		},
	};
}

async function applyGenerationRotatedProtocolFramePath(props: {
	readonly framePath: PreservationFramePath;
	readonly reviewPackage: BridgeReviewPackage;
}): Promise<BridgeReviewPackage | null> {
	const harness = makeReviewProtocolFrameHarness(props.reviewPackage);
	await harness.applyFrame({
		kind: 'reset',
		streamId: reviewFrameAuthority.streamId,
		generation: props.reviewPackage.reviewGeneration + 1,
		sequence: 0,
		frameKind: 'review.reset',
		reason: 'sourceChanged',
		sourceIdentity: props.reviewPackage.query.queryId,
	});
	await harness.applyFrame(
		makeGenerationRotatedProtocolFrame({
			framePath: props.framePath,
			reviewPackage: props.reviewPackage,
		}),
	);
	return harness.currentReviewPackage();
}

function makeGenerationRotatedProtocolFrame(props: {
	readonly framePath: PreservationFramePath;
	readonly reviewPackage: BridgeReviewPackage;
}): ReviewProtocolFrame {
	const generation = props.reviewPackage.reviewGeneration + 1;
	const projectionItem = makeProjectionInputItemWithoutDescriptorRefs(props.reviewPackage);
	switch (props.framePath) {
		case 'snapshot re-delivery':
			return {
				kind: 'metadataSnapshot',
				streamId: reviewFrameAuthority.streamId,
				generation,
				sequence: 1,
				frameKind: 'review.metadataSnapshot',
				comparison: {
					packageId: props.reviewPackage.packageId,
					sourceIdentity: props.reviewPackage.query.queryId,
					generation,
					revision: props.reviewPackage.revision + 1,
					baseEndpoint: props.reviewPackage.baseEndpoint,
					headEndpoint: props.reviewPackage.headEndpoint,
				},
				selectedItemId: targetItemId,
				visibleItemIds: [targetItemId],
				itemMetadata: [projectionItem],
				treeRows: [targetTreeRow()],
				extentFacts: [],
				summary: props.reviewPackage.summary,
			};
		case 'metadata window':
			return {
				kind: 'metadataWindow',
				streamId: reviewFrameAuthority.streamId,
				generation,
				sequence: 1,
				frameKind: 'review.metadataWindow',
				packageId: props.reviewPackage.packageId,
				revision: props.reviewPackage.revision,
				itemMetadata: [projectionItem],
				treeRows: [targetTreeRow()],
				extentFacts: [],
				summary: props.reviewPackage.summary,
			};
		case 'extent-fact delta':
			return makeGenerationRotatedDeltaProtocolFrame({
				reviewPackage: props.reviewPackage,
				generation,
				operations: [
					{
						kind: 'upsertExtentFacts',
						facts: [
							{ itemId: targetItemId, contentRole: 'base', lineCount: 17 },
							{ itemId: targetItemId, contentRole: 'head', lineCount: 23 },
						],
					},
					{ kind: 'upsertItemMetadata', item: projectionItem },
				],
			});
		case 'summary delta':
			return makeGenerationRotatedDeltaProtocolFrame({
				reviewPackage: props.reviewPackage,
				generation,
				operations: [{ kind: 'upsertItemMetadata', item: projectionItem }],
			});
		case 'order delta':
			return makeGenerationRotatedDeltaProtocolFrame({
				reviewPackage: props.reviewPackage,
				generation,
				operations: [
					{ kind: 'replaceItemOrder', itemIds: [targetItemId] },
					{ kind: 'upsertItemMetadata', item: projectionItem },
				],
			});
		case 'upsertItemMetadata':
			return makeGenerationRotatedDeltaProtocolFrame({
				reviewPackage: props.reviewPackage,
				generation,
				operations: [{ kind: 'upsertItemMetadata', item: projectionItem }],
			});
		case 'appendItems-retouch':
			return makeGenerationRotatedDeltaProtocolFrame({
				reviewPackage: props.reviewPackage,
				generation,
				operations: [{ kind: 'appendItems', items: [projectionItem] }],
			});
	}
	const exhaustiveFramePath: never = props.framePath;
	return exhaustiveFramePath;
}

function makeGenerationRotatedDeltaProtocolFrame(props: {
	readonly reviewPackage: BridgeReviewPackage;
	readonly generation: number;
	readonly operations: readonly ReviewMetadataOperation[];
}): ReviewMetadataDeltaFrame {
	return {
		kind: 'metadataDelta',
		streamId: reviewFrameAuthority.streamId,
		generation: props.generation,
		sequence: 1,
		frameKind: 'review.metadataDelta',
		packageId: props.reviewPackage.packageId,
		fromRevision: props.reviewPackage.revision,
		toRevision: props.reviewPackage.revision + 1,
		operations: [...props.operations],
		summary: props.reviewPackage.summary,
	};
}

function makeReviewProtocolFrameHarness(initialReviewPackage: BridgeReviewPackage): {
	readonly applyFrame: (protocolFrame: ReviewProtocolFrame) => Promise<void>;
	readonly currentReviewPackage: () => BridgeReviewPackage | null;
} {
	const descriptorRegistry = createBridgeResourceDescriptorRegistry({
		allowedResourceKindsByProtocol: { review: new Set(['content']) },
	});
	const reviewDemandScheduler = createBridgeDemandScheduler({
		maxQueuedIntentsPerLane: 8,
		maxQueuedEstimatedBytes: 1024 * 1024,
	});
	const resourceExecutor = createBridgeResourceExecutor({
		registry: descriptorRegistry,
		maxConcurrentLoads: 2,
		maxInFlightBytes: 1024 * 1024,
		maxQueuedLoads: 8,
		maxQueuedBytes: 1024 * 1024,
		loadResource: async ({ descriptor }) => ({
			authoritative: true,
			content: makeTextStreamResult(`${descriptor.descriptorId} content`),
			byteLength: 24,
		}),
	});
	const reviewPackageRef: { current: BridgeReviewPackage | null } = {
		current: initialReviewPackage,
	};
	let currentReviewPackage: BridgeReviewPackage | null = initialReviewPackage;
	let currentTreeRows: readonly ReviewWindowMaterializerDelta['treeRows'][number][] = [];
	let diffStatus: BridgeDiffStatusState = {
		status: 'ready',
		error: null,
		epoch: initialReviewPackage.reviewGeneration,
	};
	let selectedItemId: string | null = targetItemId;
	let invalidationVersion = 0;
	return {
		applyFrame: async (protocolFrame: ReviewProtocolFrame): Promise<void> => {
			await applyReviewProtocolTransportFrame({
				protocolFrame,
				setReviewPackage: (update): void => {
					currentReviewPackage = update(currentReviewPackage);
				},
				setReviewTreeRows: (update): void => {
					currentTreeRows = update(currentTreeRows);
				},
				setDiffStatus: (update): void => {
					diffStatus = update(diffStatus);
				},
				setSelectedItemId: (itemId): void => {
					selectedItemId = itemId;
				},
				selectInitialReviewItem: (itemId): boolean => {
					selectedItemId = itemId;
					return true;
				},
				getSelectedItemId: (): string | null => selectedItemId,
				reviewPackageRef,
				telemetryContextByPackageKey: new Map(),
				currentReviewPackageTelemetryContextRef: { current: null },
				reviewReadyStartMillisecondsByPackageKeyRef: { current: new Map() },
				descriptorRegistry,
				reviewContentDescriptorRefsByHandleIdRef: { current: new Map() },
				reviewDemandScheduler,
				resourceExecutor,
				contentRegistry: createBridgeReviewContentRegistry(),
				reviewFrameAuthority,
				invalidatedFreshnessKeysRef: { current: new Set() },
				setReviewContentInvalidationVersion: (update): void => {
					invalidationVersion = typeof update === 'function' ? update(invalidationVersion) : update;
				},
				onReviewContentDescriptorRefsRegistered: (): void => {},
				telemetryContext: {
					slice: 'review_metadata',
					traceContext: null,
					transport: 'intake',
				},
				telemetryRecorder: makeNoopTelemetryRecorder(),
			});
		},
		currentReviewPackage: (): BridgeReviewPackage | null => currentReviewPackage,
	};
}

function requireTargetReviewItem(reviewPackage: BridgeReviewPackage): BridgeReviewItemDescriptor {
	const item = reviewPackage.itemsById[targetItemId];
	if (item === undefined) {
		throw new Error(`Expected review package to include ${targetItemId}`);
	}
	return item;
}

function requireRoleHandle(props: {
	readonly item: BridgeReviewItemDescriptor;
	readonly role: Extract<BridgeContentRole, 'base' | 'head'>;
}): BridgeContentHandle {
	const handle = props.item.contentRoles[props.role];
	if (handle === null || handle === undefined) {
		throw new Error(`Expected ${props.role} role to have a resolved content handle`);
	}
	return handle;
}

function expectResolvedRoleHandlesToEqualCurrent(
	nextItem: BridgeReviewItemDescriptor,
	currentItem: BridgeReviewItemDescriptor,
): void {
	for (const role of ['base', 'head'] as const) {
		const currentHandle = requireRoleHandle({ item: currentItem, role });
		const nextHandle = requireRoleHandle({ item: nextItem, role });
		expect(nextHandle).toEqual(currentHandle);
		expect(nextHandle.contentHash).toBe(currentHandle.contentHash);
	}
}

function expectFreshRoleHandlesToReplaceCurrent(props: {
	readonly currentItem: BridgeReviewItemDescriptor;
	readonly nextItem: BridgeReviewItemDescriptor;
	readonly freshBaseHandle: BridgeContentHandle;
	readonly freshHeadHandle: BridgeContentHandle;
}): void {
	expectFreshRoleHandleToReplaceCurrent({
		currentItem: props.currentItem,
		freshHandle: props.freshBaseHandle,
		nextItem: props.nextItem,
		role: 'base',
	});
	expectFreshRoleHandleToReplaceCurrent({
		currentItem: props.currentItem,
		freshHandle: props.freshHeadHandle,
		nextItem: props.nextItem,
		role: 'head',
	});
}

function expectFreshRoleHandleToReplaceCurrent(props: {
	readonly currentItem: BridgeReviewItemDescriptor;
	readonly nextItem: BridgeReviewItemDescriptor;
	readonly freshHandle: BridgeContentHandle;
	readonly role: Extract<BridgeContentRole, 'base' | 'head'>;
}): void {
	const currentHandle = requireRoleHandle({ item: props.currentItem, role: props.role });
	const nextHandle = requireRoleHandle({ item: props.nextItem, role: props.role });
	expect(nextHandle.handleId).toBe(props.freshHandle.handleId);
	expect(nextHandle.contentHash).toBe(`metadata:${props.freshHandle.handleId}`);
	expect(nextHandle.handleId).not.toBe(currentHandle.handleId);
	expect(nextHandle.contentHash).not.toBe(currentHandle.contentHash);
}

function expectMetadataOnlyRoleHandles(item: BridgeReviewItemDescriptor): void {
	expect(item.contentRoles.base).toBeNull();
	expect(item.contentRoles.head).toBeNull();
	expect(item.contentRoles.diff).toBeNull();
	expect(item.contentRoles.file).toBeNull();
}

function targetTreeRow(): ReviewWindowMaterializerDelta['treeRows'][number] {
	return {
		rowId: `review-row:${targetItemId}`,
		itemId: targetItemId,
		path: targetItemPath,
		depth: 2,
		isDirectory: false,
	};
}

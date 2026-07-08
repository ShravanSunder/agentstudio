import type { BridgeAttachedResourceDescriptor } from '../core/models/bridge-resource-descriptor.js';
import type { ReviewMaterializerDelta } from '../features/review/materialization/review-materializer.js';
import type { ReviewTreeRowMetadata } from '../features/review/models/review-protocol-models.js';
import { createBridgeReviewItemRegistry } from '../foundation/review-package/bridge-review-item-registry.js';
import type {
	BridgeContentHandle,
	BridgeContentRole,
	BridgeReviewItemDescriptor,
	BridgeReviewPackage,
} from '../foundation/review-package/bridge-review-package.js';

type ReviewSnapshotMaterializerDelta = Extract<
	ReviewMaterializerDelta,
	{ readonly kind: 'metadataSnapshot' }
>;
type ReviewDeltaMaterializerDelta = Extract<
	ReviewMaterializerDelta,
	{ readonly kind: 'metadataDelta' }
>;
type ReviewWindowMaterializerDelta = Extract<
	ReviewMaterializerDelta,
	{ readonly kind: 'metadataWindow' }
>;

export interface ReviewMetadataCarryForwardVerificationCounts {
	unverifiedKeepCount: number;
	verifiedDropCount: number;
	verifiedKeepCount: number;
}

export interface BridgeReviewSelectionInvalidationProbe {
	readonly selectItem: (itemId: string) => BridgeReviewSelectionInvalidationProbeResult;
}

export interface BridgeReviewSelectionInvalidationProbeResult {
	readonly invalidatedKeyCount: number;
	readonly packageItemCount: number;
	readonly selectedItemCount: number;
	readonly subscriberNotificationCount: number;
	readonly visibleDeltaCount: number;
}

const reviewContentRoles = [
	'base',
	'head',
	'diff',
	'file',
] as const satisfies readonly BridgeContentRole[];
type ReviewProjectionItemContentHashesByRole =
	ReviewSnapshotMaterializerDelta['projectionInput']['orderedItems'][number]['contentHashesByRole'];

export function createBridgeReviewSelectionInvalidationProbe(props: {
	readonly reviewPackage: BridgeReviewPackage;
	readonly visibleItemIds: readonly string[];
}): BridgeReviewSelectionInvalidationProbe {
	const visibleItemIds = new Set(props.visibleItemIds);
	return {
		selectItem: (itemId: string): BridgeReviewSelectionInvalidationProbeResult => {
			const invalidatedKeys = new Set<string>(visibleItemIds);
			if (itemId.length > 0) {
				invalidatedKeys.add(itemId);
			}
			return {
				invalidatedKeyCount: invalidatedKeys.size,
				packageItemCount: props.reviewPackage.orderedItemIds.length,
				selectedItemCount: itemId.length > 0 ? 1 : 0,
				subscriberNotificationCount: invalidatedKeys.size,
				visibleDeltaCount: visibleItemIds.size,
			};
		},
	};
}

export function isStaleReviewPackageReplacement(
	currentReviewPackage: BridgeReviewPackage,
	nextReviewPackage: BridgeReviewPackage,
): boolean {
	if (currentReviewPackage.packageId !== nextReviewPackage.packageId) {
		return false;
	}
	if (nextReviewPackage.reviewGeneration < currentReviewPackage.reviewGeneration) {
		return true;
	}
	return (
		nextReviewPackage.reviewGeneration === currentReviewPackage.reviewGeneration &&
		nextReviewPackage.revision <= currentReviewPackage.revision
	);
}

export function mergeReviewTreeRowsByRowId(props: {
	readonly current: readonly ReviewTreeRowMetadata[];
	readonly nextRows: readonly ReviewTreeRowMetadata[];
}): readonly ReviewTreeRowMetadata[] {
	if (props.nextRows.length === 0) {
		return props.current;
	}
	const rowsById = new Map(
		props.current.map((row): readonly [string, ReviewTreeRowMetadata] => [row.rowId, row]),
	);
	for (const row of props.nextRows) {
		rowsById.set(row.rowId, row);
	}
	return [...rowsById.values()];
}

export function reviewTreeRowsWithMetadataDelta(props: {
	readonly current: readonly ReviewTreeRowMetadata[];
	readonly deltaFrame: ReviewDeltaMaterializerDelta;
}): readonly ReviewTreeRowMetadata[] {
	let rows: readonly ReviewTreeRowMetadata[] = props.current;
	let mutableRows: ReviewTreeRowMetadata[] | null = null;
	let rowIndexesById: Map<string, number> | null = null;
	const ensureMutableRows = (): ReviewTreeRowMetadata[] => {
		if (mutableRows === null) {
			mutableRows = [...rows];
			rows = mutableRows;
			rowIndexesById = null;
		}
		return mutableRows;
	};
	const ensureRowIndexesById = (): Map<string, number> => {
		if (rowIndexesById === null) {
			rowIndexesById = new Map(
				rows.map((row, index): readonly [string, number] => [row.rowId, index]),
			);
		}
		return rowIndexesById;
	};
	for (const operation of props.deltaFrame.operations) {
		switch (operation.kind) {
			case 'appendItems':
			case 'invalidateContentDescriptors':
			case 'movePathPrefix':
			case 'removeItems':
			case 'replaceItemOrder':
			case 'selectItem':
			case 'upsertExtentFacts':
			case 'upsertItemMetadata':
				break;
			case 'upsertTreeRows': {
				if (operation.rows.length === 0) {
					break;
				}
				const nextRows = ensureMutableRows();
				const nextRowIndexesById = ensureRowIndexesById();
				for (const row of operation.rows) {
					const currentIndex = nextRowIndexesById.get(row.rowId);
					if (currentIndex === undefined) {
						nextRowIndexesById.set(row.rowId, nextRows.length);
						nextRows.push(row);
					} else {
						nextRows[currentIndex] = row;
					}
				}
				break;
			}
			case 'removeTreeRows': {
				const removedRowIds = new Set(operation.rowIds ?? []);
				const removedPaths = new Set(operation.paths ?? []);
				if (removedRowIds.size > 0 || removedPaths.size > 0) {
					rows = pruneEmptyReviewTreeDirectories(
						rows.filter(
							(row): boolean => !removedRowIds.has(row.rowId) && !removedPaths.has(row.path),
						),
					);
					mutableRows = null;
					rowIndexesById = null;
				}
				break;
			}
			case 'replaceTreeWindow':
				rows = operation.rows;
				mutableRows = null;
				rowIndexesById = null;
				break;
		}
	}
	return rows;
}

export function pruneEmptyReviewTreeDirectories(
	rows: readonly ReviewTreeRowMetadata[],
): readonly ReviewTreeRowMetadata[] {
	return rows.filter((row): boolean => {
		if (!row.isDirectory) {
			return true;
		}
		const descendantPathPrefix = `${row.path.replace(/\/+$/, '')}/`;
		return rows.some(
			(candidate): boolean =>
				!candidate.isDirectory && candidate.path.startsWith(descendantPathPrefix),
		);
	});
}

export function bridgeReviewPackageFromMetadataSnapshot(
	snapshotFrame: ReviewSnapshotMaterializerDelta,
): BridgeReviewPackage {
	const contentDescriptorsById = new Map(
		snapshotFrame.contentDescriptors.map(
			(attachedDescriptor): readonly [string, BridgeAttachedResourceDescriptor] => [
				attachedDescriptor.descriptor.descriptorId,
				attachedDescriptor,
			],
		),
	);
	const itemsById = Object.fromEntries(
		snapshotFrame.projectionInput.orderedItems.map(
			(item): readonly [string, BridgeReviewItemDescriptor] => [
				item.itemId,
				bridgeReviewItemFromMetadataProjectionItem({
					contentDescriptorsById,
					item,
					metadataFrame: snapshotFrame,
				}),
			],
		),
	);
	const reviewPackage = {
		packageId: snapshotFrame.packageId,
		schemaVersion: 1,
		reviewGeneration: snapshotFrame.generation,
		revision: snapshotFrame.revision,
		query: {
			queryId: snapshotFrame.sourceIdentity,
			queryKind: 'compare',
			repoId: snapshotFrame.baseEndpoint.repoId,
			worktreeId: snapshotFrame.headEndpoint.worktreeId,
			baseEndpointId: snapshotFrame.baseEndpoint.endpointId,
			headEndpointId: snapshotFrame.headEndpoint.endpointId,
			comparisonSemantics: 'workingTreeDelta',
			pathScope: [],
			fileTarget: null,
			viewFilter: emptyBridgeReviewViewFilter(),
			grouping: { kind: 'flat', label: null },
			provenanceFilter: emptyBridgeReviewProvenanceFilter(),
		},
		baseEndpoint: snapshotFrame.baseEndpoint,
		headEndpoint: snapshotFrame.headEndpoint,
		orderedItemIds: snapshotFrame.projectionInput.orderedItems.map((item) => item.itemId),
		itemsById,
		groups: [],
		summary: snapshotFrame.summary,
		filterState: emptyBridgeReviewViewFilter(),
		generatedAtUnixMilliseconds: 0,
	} satisfies BridgeReviewPackage;
	return reviewPackage;
}

export function bridgeReviewPackageWithMetadataWindow(props: {
	readonly reviewPackage: BridgeReviewPackage;
	readonly windowFrame: ReviewWindowMaterializerDelta;
	readonly carryForwardVerificationCounts?:
		| ReviewMetadataCarryForwardVerificationCounts
		| undefined;
}): BridgeReviewPackage {
	const contentDescriptorsById = new Map(
		props.windowFrame.contentDescriptors.map(
			(attachedDescriptor): readonly [string, BridgeAttachedResourceDescriptor] => [
				attachedDescriptor.descriptor.descriptorId,
				attachedDescriptor,
			],
		),
	);
	const windowItemsById = Object.fromEntries(
		props.windowFrame.itemMetadata.map((item): readonly [string, BridgeReviewItemDescriptor] => [
			item.itemId,
			reviewItemWithCarriedResolvedContent({
				currentItem: props.reviewPackage.itemsById[item.itemId],
				nextItem: bridgeReviewItemFromMetadataProjectionItem({
					contentDescriptorsById,
					item,
					metadataFrame: {
						...props.windowFrame,
						baseEndpoint: props.reviewPackage.baseEndpoint,
						headEndpoint: props.reviewPackage.headEndpoint,
					},
				}),
				carryForwardVerificationCounts: props.carryForwardVerificationCounts,
				nextContentHashesByRole: item.contentHashesByRole,
			}),
		]),
	);
	const orderedItemIds = [
		...props.reviewPackage.orderedItemIds,
		...props.windowFrame.itemMetadata
			.map((item) => item.itemId)
			.filter((itemId) => props.reviewPackage.itemsById[itemId] === undefined),
	];
	const reviewPackage = {
		...props.reviewPackage,
		orderedItemIds,
		itemsById: {
			...props.reviewPackage.itemsById,
			...windowItemsById,
		},
		summary: props.windowFrame.summary,
	} satisfies BridgeReviewPackage;
	return reviewPackage;
}

export function bridgeReviewPackageWithMetadataSnapshot(props: {
	readonly reviewPackage: BridgeReviewPackage;
	readonly snapshotPackage: BridgeReviewPackage;
	readonly snapshotFrame?: ReviewSnapshotMaterializerDelta;
	readonly carryForwardVerificationCounts?:
		| ReviewMetadataCarryForwardVerificationCounts
		| undefined;
}): BridgeReviewPackage {
	const contentHashesByItemId = new Map(
		props.snapshotFrame?.projectionInput.orderedItems.map(
			(item): readonly [string, ReviewProjectionItemContentHashesByRole] => [
				item.itemId,
				item.contentHashesByRole,
			],
		) ?? [],
	);
	const snapshotItemsById = Object.fromEntries(
		Object.entries(props.snapshotPackage.itemsById).map(
			([itemId, item]): readonly [string, BridgeReviewItemDescriptor] => [
				itemId,
				reviewItemWithCarriedResolvedContent({
					currentItem: props.reviewPackage.itemsById[itemId],
					nextItem: item,
					carryForwardVerificationCounts: props.carryForwardVerificationCounts,
					nextContentHashesByRole: contentHashesByItemId.get(itemId),
				}),
			],
		),
	);
	const orderedItemIds = [
		...props.reviewPackage.orderedItemIds,
		...props.snapshotPackage.orderedItemIds.filter(
			(itemId) => props.reviewPackage.itemsById[itemId] === undefined,
		),
	];
	const reviewPackage = {
		...props.reviewPackage,
		baseEndpoint: props.snapshotPackage.baseEndpoint,
		headEndpoint: props.snapshotPackage.headEndpoint,
		revision: props.snapshotPackage.revision,
		orderedItemIds,
		itemsById: {
			...props.reviewPackage.itemsById,
			...snapshotItemsById,
		},
		summary: props.snapshotPackage.summary,
	} satisfies BridgeReviewPackage;
	return reviewPackage;
}

export function applyReviewMetadataDeltaToReviewPackage(props: {
	readonly reviewPackage: BridgeReviewPackage;
	readonly deltaFrame: ReviewDeltaMaterializerDelta;
	readonly carryForwardVerificationCounts?:
		| ReviewMetadataCarryForwardVerificationCounts
		| undefined;
}): BridgeReviewPackage | null {
	if (
		props.reviewPackage.packageId !== props.deltaFrame.packageId ||
		props.reviewPackage.revision !== props.deltaFrame.fromRevision ||
		props.deltaFrame.toRevision !== props.deltaFrame.fromRevision + 1
	) {
		return null;
	}
	const contentDescriptorsById = new Map(
		props.deltaFrame.contentDescriptors.map(
			(attachedDescriptor): readonly [string, BridgeAttachedResourceDescriptor] => [
				attachedDescriptor.descriptor.descriptorId,
				attachedDescriptor,
			],
		),
	);
	const itemsById: Record<string, BridgeReviewItemDescriptor> = {
		...props.reviewPackage.itemsById,
	};
	let orderedItemIds = [...props.reviewPackage.orderedItemIds];
	let orderedItemIdSet = new Set(orderedItemIds);
	let didChange = false;
	const extentFacts = extentFactsFromMetadataDelta(props.deltaFrame);
	const appendOrderedItemIdIfMissing = (itemId: string): void => {
		if (orderedItemIdSet.has(itemId)) {
			return;
		}
		orderedItemIdSet.add(itemId);
		orderedItemIds.push(itemId);
	};
	for (const operation of props.deltaFrame.operations) {
		switch (operation.kind) {
			case 'upsertItemMetadata': {
				const currentItem = itemsById[operation.item.itemId];
				const nextItem = bridgeReviewItemFromMetadataProjectionItem({
					contentDescriptorsById,
					item: operation.item,
					metadataFrame: {
						baseEndpoint: props.reviewPackage.baseEndpoint,
						extentFacts,
						generation: props.reviewPackage.reviewGeneration,
						headEndpoint: props.reviewPackage.headEndpoint,
						revision: props.deltaFrame.toRevision,
					},
				});
				itemsById[operation.item.itemId] = reviewItemWithCarriedResolvedContent({
					currentItem,
					nextItem,
					carryForwardVerificationCounts: props.carryForwardVerificationCounts,
					nextContentHashesByRole: operation.item.contentHashesByRole,
				});
				appendOrderedItemIdIfMissing(operation.item.itemId);
				didChange = true;
				break;
			}
			case 'appendItems': {
				for (const item of operation.items) {
					const currentItem = itemsById[item.itemId];
					const nextItem = bridgeReviewItemFromMetadataProjectionItem({
						contentDescriptorsById,
						item,
						metadataFrame: {
							baseEndpoint: props.reviewPackage.baseEndpoint,
							extentFacts,
							generation: props.reviewPackage.reviewGeneration,
							headEndpoint: props.reviewPackage.headEndpoint,
							revision: props.deltaFrame.toRevision,
						},
					});
					itemsById[item.itemId] = reviewItemWithCarriedResolvedContent({
						currentItem,
						nextItem,
						carryForwardVerificationCounts: props.carryForwardVerificationCounts,
						nextContentHashesByRole: item.contentHashesByRole,
					});
					appendOrderedItemIdIfMissing(item.itemId);
				}
				didChange = operation.items.length > 0 || didChange;
				break;
			}
			case 'removeItems': {
				const removedItemIds = new Set(operation.itemIds);
				if (removedItemIds.size === 0) {
					break;
				}
				for (const itemId of removedItemIds) {
					delete itemsById[itemId];
					orderedItemIdSet.delete(itemId);
				}
				orderedItemIds = orderedItemIds.filter((itemId) => !removedItemIds.has(itemId));
				didChange = true;
				break;
			}
			case 'replaceItemOrder': {
				const seenItemIds = new Set<string>();
				orderedItemIds = [
					...operation.itemIds.filter((itemId) => {
						if (!(itemId in itemsById) || seenItemIds.has(itemId)) {
							return false;
						}
						seenItemIds.add(itemId);
						return true;
					}),
					...orderedItemIds.filter((itemId) => !seenItemIds.has(itemId)),
				];
				orderedItemIdSet = new Set(orderedItemIds);
				didChange = true;
				break;
			}
			case 'movePathPrefix': {
				applyMovedPathPrefixToReviewItemsById({
					affectedItemIds: operation.affectedItemIds,
					fromPath: operation.fromPath,
					itemsById,
					revision: props.deltaFrame.toRevision,
					toPath: operation.toPath,
				});
				didChange = operation.affectedItemIds.length > 0 || didChange;
				break;
			}
			case 'upsertTreeRows':
			case 'removeTreeRows':
			case 'replaceTreeWindow':
			case 'selectItem':
			case 'invalidateContentDescriptors':
				break;
			case 'upsertExtentFacts': {
				for (const fact of operation.facts) {
					const currentItem = itemsById[fact.itemId];
					if (currentItem === undefined) {
						continue;
					}
					itemsById[fact.itemId] = reviewItemWithExtentFacts({
						extentFacts,
						item: currentItem,
						revision: props.deltaFrame.toRevision,
					});
				}
				didChange = operation.facts.length > 0 || didChange;
				break;
			}
		}
	}
	if (!didChange && props.deltaFrame.toRevision === props.reviewPackage.revision) {
		return null;
	}
	const reviewPackage = {
		...props.reviewPackage,
		revision: props.deltaFrame.toRevision,
		orderedItemIds,
		itemsById,
		summary: props.deltaFrame.summary,
	} satisfies BridgeReviewPackage;
	return reviewPackage;
}

function extentFactsFromMetadataDelta(
	deltaFrame: ReviewDeltaMaterializerDelta,
): ReviewSnapshotMaterializerDelta['extentFacts'] {
	const facts: ReviewSnapshotMaterializerDelta['extentFacts'][number][] = [];
	for (const operation of deltaFrame.operations) {
		if (operation.kind === 'upsertExtentFacts') {
			facts.push(...operation.facts);
		}
	}
	return facts;
}

function reviewItemWithCarriedResolvedContent(props: {
	readonly currentItem: BridgeReviewItemDescriptor | undefined;
	readonly nextItem: BridgeReviewItemDescriptor;
	readonly nextContentHashesByRole?: ReviewProjectionItemContentHashesByRole | undefined;
	readonly carryForwardVerificationCounts?:
		| ReviewMetadataCarryForwardVerificationCounts
		| undefined;
}): BridgeReviewItemDescriptor {
	const current = props.currentItem;
	if (current === undefined) {
		return props.nextItem;
	}
	const contentRoles = contentRolesWithCarriedResolvedHandles({
		currentContentRoles: current.contentRoles,
		nextContentHashesByRole: props.nextContentHashesByRole,
		nextContentRoles: props.nextItem.contentRoles,
		carryForwardVerificationCounts: props.carryForwardVerificationCounts,
	});
	const shouldCarryLineCounts =
		props.nextItem.contentLineCountsByRole === undefined &&
		current.contentLineCountsByRole !== undefined;
	if (contentRoles === props.nextItem.contentRoles && !shouldCarryLineCounts) {
		return props.nextItem;
	}
	return {
		...props.nextItem,
		...(shouldCarryLineCounts ? { contentLineCountsByRole: current.contentLineCountsByRole } : {}),
		contentRoles,
	};
}

// A metadata-only re-touch (a delta/window/snapshot frame that re-delivers an item WITHOUT a fresher
// content descriptor for a role) must NOT null a resolved content handle. Carry the current handle
// forward per role until a fresher descriptor replaces it. Otherwise the item loses its contentHash
// and the content-addressed content-validity gate drops already-loaded content (stuck-on-placeholder).
function contentRolesWithCarriedResolvedHandles(props: {
	readonly currentContentRoles: BridgeReviewItemDescriptor['contentRoles'];
	readonly nextContentHashesByRole?: ReviewProjectionItemContentHashesByRole | undefined;
	readonly nextContentRoles: BridgeReviewItemDescriptor['contentRoles'];
	readonly carryForwardVerificationCounts?:
		| ReviewMetadataCarryForwardVerificationCounts
		| undefined;
}): BridgeReviewItemDescriptor['contentRoles'] {
	const next = props.nextContentRoles;
	const current = props.currentContentRoles;
	const carried = Object.fromEntries(
		reviewContentRoles.map(
			(role): readonly [BridgeContentRole, BridgeContentHandle | null | undefined] => {
				const nextHandle = next[role];
				if (nextHandle !== null && nextHandle !== undefined) {
					return [role, nextHandle];
				}
				return [
					role,
					verifiedCarriedContentHandle({
						contentHash: props.nextContentHashesByRole?.[role],
						currentHandle: current[role],
						verificationCounts: props.carryForwardVerificationCounts,
					}),
				];
			},
		),
	) as BridgeReviewItemDescriptor['contentRoles'];
	if (
		carried.base === next.base &&
		carried.head === next.head &&
		carried.diff === next.diff &&
		carried.file === next.file
	) {
		return next;
	}
	return carried;
}

function verifiedCarriedContentHandle(props: {
	readonly contentHash: string | null | undefined;
	readonly currentHandle: BridgeContentHandle | null | undefined;
	readonly verificationCounts: ReviewMetadataCarryForwardVerificationCounts | undefined;
}): BridgeContentHandle | null | undefined {
	if (props.currentHandle === null || props.currentHandle === undefined) {
		return props.currentHandle;
	}
	if (props.contentHash === null || props.contentHash === undefined) {
		if (props.verificationCounts !== undefined) {
			props.verificationCounts.unverifiedKeepCount += 1;
		}
		return props.currentHandle;
	}
	if (props.contentHash === props.currentHandle.contentHash) {
		if (props.verificationCounts !== undefined) {
			props.verificationCounts.verifiedKeepCount += 1;
		}
		return props.currentHandle;
	}
	if (props.verificationCounts !== undefined) {
		props.verificationCounts.verifiedDropCount += 1;
	}
	return null;
}

function reviewItemWithExtentFacts(props: {
	readonly extentFacts: ReviewSnapshotMaterializerDelta['extentFacts'];
	readonly item: BridgeReviewItemDescriptor;
	readonly revision: number;
}): BridgeReviewItemDescriptor {
	const contentLineCountsByRole = contentLineCountsByRoleFromExtentFacts({
		extentFacts: props.extentFacts,
		itemId: props.item.itemId,
	});
	if (contentLineCountsByRole === undefined) {
		return props.item;
	}
	return {
		...props.item,
		contentLineCountsByRole,
		cacheKey: `${props.item.cacheKey}:metadata-delta:${props.revision}:extents`,
	};
}

function applyMovedPathPrefixToReviewItemsById(props: {
	readonly affectedItemIds: readonly string[];
	readonly fromPath: string;
	readonly itemsById: Record<string, BridgeReviewItemDescriptor>;
	readonly revision: number;
	readonly toPath: string;
}): void {
	for (const itemId of props.affectedItemIds) {
		const item = props.itemsById[itemId];
		if (item === undefined) {
			continue;
		}
		props.itemsById[itemId] = {
			...item,
			basePath: pathWithMovedPrefix({
				fromPath: props.fromPath,
				path: item.basePath,
				toPath: props.toPath,
			}),
			headPath: pathWithMovedPrefix({
				fromPath: props.fromPath,
				path: item.headPath,
				toPath: props.toPath,
			}),
			cacheKey: `${item.cacheKey}:metadata-delta:${props.revision}`,
		};
	}
}

function pathWithMovedPrefix(props: {
	readonly fromPath: string;
	readonly path: string | null | undefined;
	readonly toPath: string;
}): string | null {
	if (props.path === null || props.path === undefined) {
		return null;
	}
	if (props.path === props.fromPath) {
		return props.toPath;
	}
	const prefix = `${props.fromPath}/`;
	return props.path.startsWith(prefix)
		? `${props.toPath}/${props.path.slice(prefix.length)}`
		: props.path;
}

function bridgeReviewItemFromMetadataProjectionItem(props: {
	readonly contentDescriptorsById: ReadonlyMap<string, BridgeAttachedResourceDescriptor>;
	readonly item: ReviewSnapshotMaterializerDelta['projectionInput']['orderedItems'][number];
	readonly metadataFrame: Pick<
		ReviewSnapshotMaterializerDelta,
		'baseEndpoint' | 'generation' | 'headEndpoint' | 'revision' | 'extentFacts'
	>;
}): BridgeReviewItemDescriptor {
	const contentLineCountsByRole = contentLineCountsByRoleFromExtentFacts({
		extentFacts: props.metadataFrame.extentFacts,
		itemId: props.item.itemId,
	});
	return {
		itemId: props.item.itemId,
		itemKind:
			props.item.contentRoles.includes('diff') || props.item.contentRoles.includes('base')
				? 'diff'
				: 'file',
		itemVersion: 1,
		basePath: props.item.basePath,
		headPath: props.item.headPath,
		changeKind: props.item.changeKind,
		fileClass: props.item.fileClass,
		language: props.item.language,
		extension: props.item.extension,
		sizeBytes: 0,
		baseContentHash: null,
		headContentHash: null,
		contentHashAlgorithm: 'metadata-stream',
		additions: 0,
		deletions: 0,
		isHiddenByDefault: props.item.isHiddenByDefault,
		hiddenReason: null,
		reviewPriority: props.item.reviewPriority,
		contentRoles: {
			base: metadataContentHandleForRole({ ...props, role: 'base' }),
			head: metadataContentHandleForRole({ ...props, role: 'head' }),
			diff: metadataContentHandleForRole({ ...props, role: 'diff' }),
			file: metadataContentHandleForRole({ ...props, role: 'file' }),
		},
		contentLineCountsByRole,
		cacheKey: `metadata:${props.item.itemId}:${props.metadataFrame.revision}`,
		provenance: {
			paneIds: [],
			agentSessionIds: [...props.item.provenance.agentSessionIds],
			promptIds: [...props.item.provenance.promptIds],
			operationIds: [...props.item.provenance.operationIds],
			sourceKinds: [],
		},
		annotationSummary: { threadCount: 0, unresolvedThreadCount: 0, commentCount: 0 },
		reviewState: props.item.reviewState,
		collapsed: false,
	};
}

function contentLineCountsByRoleFromExtentFacts(props: {
	readonly extentFacts: ReviewSnapshotMaterializerDelta['extentFacts'];
	readonly itemId: string;
}): BridgeReviewItemDescriptor['contentLineCountsByRole'] {
	const lineCountsByRole: NonNullable<BridgeReviewItemDescriptor['contentLineCountsByRole']> = {};
	for (const fact of props.extentFacts) {
		if (fact.itemId !== props.itemId) {
			continue;
		}
		lineCountsByRole[fact.contentRole] = fact.lineCount;
	}
	return Object.keys(lineCountsByRole).length === 0 ? undefined : lineCountsByRole;
}

function metadataContentHandleForRole(props: {
	readonly contentDescriptorsById: ReadonlyMap<string, BridgeAttachedResourceDescriptor>;
	readonly item: ReviewSnapshotMaterializerDelta['projectionInput']['orderedItems'][number];
	readonly metadataFrame: Pick<
		ReviewSnapshotMaterializerDelta,
		'baseEndpoint' | 'generation' | 'headEndpoint' | 'revision'
	>;
	readonly role: BridgeContentRole;
}): BridgeContentHandle | null {
	const descriptorId = props.item.contentDescriptorIdsByRole?.[props.role] ?? null;
	const attachedDescriptor =
		descriptorId === null ? null : (props.contentDescriptorsById.get(descriptorId) ?? null);
	if (attachedDescriptor === null) {
		return null;
	}
	const descriptor = attachedDescriptor.descriptor;
	const expectedBytes = descriptor.content.expectedBytes;
	const integrity = descriptor.content.integrity;
	const contentHash =
		integrity?.kind === 'wholeHash'
			? `${integrity.algorithm}:${integrity.value}`
			: `metadata:${descriptor.descriptorId}`;
	return {
		handleId: descriptor.descriptorId,
		itemId: props.item.itemId,
		role: props.role,
		endpointId:
			props.role === 'base'
				? props.metadataFrame.baseEndpoint.endpointId
				: props.metadataFrame.headEndpoint.endpointId,
		reviewGeneration: descriptor.identity.generation ?? props.metadataFrame.generation,
		resourceUrl: descriptor.resourceUrl,
		contentHash,
		contentHashAlgorithm: integrity?.kind === 'wholeHash' ? integrity.algorithm : 'metadata-stream',
		cacheKey: `metadata:${props.item.itemId}:${props.role}:${props.metadataFrame.revision}`,
		mimeType: descriptor.content.mediaType,
		language: props.item.language,
		sizeBytes: expectedBytes ?? 0,
		sizeBytesIsExact: expectedBytes !== undefined,
		maxBytes: descriptor.content.maxBytes,
		isBinary: descriptor.content.encoding === 'binary',
	};
}

function emptyBridgeReviewViewFilter(): BridgeReviewPackage['filterState'] {
	return {
		includedPathGlobs: [],
		excludedPathGlobs: [],
		includedFileClasses: [],
		excludedFileClasses: [],
		includedExtensions: [],
		excludedExtensions: [],
		changeKinds: [],
		reviewStates: [],
		showHiddenFiles: false,
		showBinaryFiles: false,
		showLargeFiles: false,
	};
}

function emptyBridgeReviewProvenanceFilter(): BridgeReviewPackage['query']['provenanceFilter'] {
	return {
		paneIds: [],
		agentSessionIds: [],
		promptIds: [],
		operationIds: [],
		createdAfterUnixMilliseconds: null,
		createdBeforeUnixMilliseconds: null,
		sourceKinds: [],
	};
}

export function firstVisibleItemId(reviewPackage: BridgeReviewPackage): string | null {
	const registry = createBridgeReviewItemRegistry({ reviewPackage, selectedItemId: null });
	return registry.visibleItems[0]?.itemId ?? null;
}

export function uniqueReviewVisibleItemIds(itemIds: readonly string[]): readonly string[] {
	const uniqueItemIds: string[] = [];
	const seenItemIds = new Set<string>();
	for (const itemId of itemIds) {
		if (seenItemIds.has(itemId)) {
			continue;
		}
		seenItemIds.add(itemId);
		uniqueItemIds.push(itemId);
	}
	return uniqueItemIds;
}

import type { CodeViewDiffItem, CodeViewFileItem } from '@pierre/diffs';
import { z } from 'zod';

import { bridgeContentDemandExecutionPolicy } from '../../core/demand/bridge-content-demand-policy.js';
import type {
	BridgeContentHandle,
	BridgeContentRole,
	BridgeReviewItemDescriptor,
	BridgeReviewPackage,
} from '../../foundation/review-package/bridge-review-package.js';
import type { BridgeReviewProjectionResult } from '../models/review-projection-models.js';
import { bridgeContentRoleSchema } from '../models/review-projection-models.js';
import { bridgePierreContentDescriptorCacheKey } from '../workers/pierre/bridge-pierre-worker-content-descriptor.js';
import {
	createBridgeCodeViewPlaceholderDiffFiles,
	createBridgeCodeViewPlaceholderFileDiff,
	createBridgeCodeViewPlaceholderFileContents,
} from './bridge-code-view-placeholder-content.js';

export const bridgeCodeViewContentStateSchema = z.enum([
	'placeholder',
	'loading',
	'hydrated',
	'windowed',
]);

const fullCodeViewMaterializationLineBudget = 20_000;
export const selectedBridgeCodeViewContentWindowLineCount =
	bridgeContentDemandExecutionPolicy.selectedApplyInitialWindowLineCount;
const codeViewContentWindowLineCount = selectedBridgeCodeViewContentWindowLineCount;

export const bridgeCodeViewItemMetadataSchema = z.object({
	itemId: z.string().min(1),
	displayPath: z.string().min(1),
	contentState: bridgeCodeViewContentStateSchema,
	contentRoles: z.array(bridgeContentRoleSchema).readonly(),
	cacheKey: z.string().min(1),
	lineCount: z.number().int().nonnegative().nullable(),
});

export type BridgeCodeViewItemMetadata = z.infer<typeof bridgeCodeViewItemMetadataSchema>;

export type BridgeCodeViewFileItem = CodeViewFileItem & {
	readonly bridgeMetadata: BridgeCodeViewItemMetadata;
};

export type BridgeCodeViewDiffItem = CodeViewDiffItem & {
	readonly bridgeMetadata: BridgeCodeViewItemMetadata;
};

export type BridgeCodeViewItem = BridgeCodeViewFileItem | BridgeCodeViewDiffItem;

export interface BridgeCodeViewContentRoleFacts {
	readonly byteLength?: number;
	readonly cacheKey: string;
	readonly contentHash: string;
	readonly contentHashAlgorithm: string;
	readonly sizeBytes: number;
}

export interface BridgeCodeViewContentFacts {
	readonly base?: BridgeCodeViewContentRoleFacts;
	readonly head?: BridgeCodeViewContentRoleFacts;
	readonly diff?: BridgeCodeViewContentRoleFacts;
	readonly file?: BridgeCodeViewContentRoleFacts;
}

export function bridgeCodeViewContentRoleFactsForHandle(props: {
	readonly byteLength?: number | undefined;
	readonly handle: BridgeContentHandle;
}): BridgeCodeViewContentRoleFacts {
	return {
		...(props.byteLength === undefined ? {} : { byteLength: props.byteLength }),
		cacheKey: props.handle.cacheKey,
		contentHash: props.handle.contentHash,
		contentHashAlgorithm: props.handle.contentHashAlgorithm,
		sizeBytes: props.handle.sizeBytes,
	};
}

export type BridgeCodeViewFilePresentationVersion = 'base' | 'current' | 'head';

export type BridgeCodeViewItemPresentation =
	| {
			readonly kind: 'file';
			readonly version: BridgeCodeViewFilePresentationVersion;
	  }
	| { readonly kind: 'diff' };

export interface CreateBridgeCodeViewInitialItemsProps {
	readonly itemPresentationsByItemId?: ReadonlyMap<string, BridgeCodeViewItemPresentation>;
	readonly reviewPackage: BridgeReviewPackage;
	readonly projection: BridgeReviewProjectionResult;
	readonly seedItemIds?: readonly string[];
}

export interface BridgeCodeViewMaterializationCacheKeysForItemProps {
	readonly contentWindowLineLimit?: number | undefined;
	readonly item: BridgeReviewItemDescriptor;
	readonly presentation?: BridgeCodeViewItemPresentation | null;
	readonly resources: BridgeCodeViewContentFacts;
}

export function createBridgeCodeViewInitialItems(
	props: CreateBridgeCodeViewInitialItemsProps,
): readonly BridgeCodeViewItem[] {
	const items: BridgeCodeViewItem[] = [];
	const seedItemIds = props.seedItemIds;

	if (seedItemIds !== undefined) {
		const projectionRankByItemId = props.projection.orderedItemRankByItemId;
		const seededIds: string[] = [];
		const seenItemIds = new Set<string>();
		for (const itemId of seedItemIds) {
			if (seenItemIds.has(itemId)) {
				continue;
			}
			seenItemIds.add(itemId);
			if (
				projectionRankByItemId === undefined
					? !Object.hasOwn(props.projection.primaryDisplayPathByItemId, itemId)
					: projectionRankByItemId[itemId] === undefined
			) {
				continue;
			}
			seededIds.push(itemId);
		}
		const orderedSeedIds =
			projectionRankByItemId === undefined
				? seededIds
				: seededIds.toSorted(
						(first, second): number =>
							(projectionRankByItemId[first] ?? Number.MAX_SAFE_INTEGER) -
							(projectionRankByItemId[second] ?? Number.MAX_SAFE_INTEGER),
					);
		for (const itemId of orderedSeedIds) {
			const item = props.reviewPackage.itemsById[itemId];
			if (item === undefined) {
				continue;
			}
			items.push(
				createPlaceholderItem({
					item,
					presentation: props.itemPresentationsByItemId?.get(item.itemId) ?? null,
				}),
			);
		}
		return items;
	}

	for (const itemId of props.projection.orderedItemIds) {
		const item = props.reviewPackage.itemsById[itemId];
		if (item === undefined) {
			continue;
		}
		items.push(
			createPlaceholderItem({
				item,
				presentation: props.itemPresentationsByItemId?.get(item.itemId) ?? null,
			}),
		);
	}

	return items;
}

export function bridgeCodeViewMaterializationCacheKeysForItem(
	props: BridgeCodeViewMaterializationCacheKeysForItemProps,
): readonly string[] {
	const { item, resources } = props;
	const contentWindow = codeViewContentWindowForLineLimit(props.contentWindowLineLimit);
	const oneSidedDiffResources = oneSidedDiffResourcesForItem({ item, resources });
	if (props.presentation?.kind === 'file' && oneSidedDiffResources === null) {
		const preferredResource = resourceForFilePresentation({
			resources,
			version: props.presentation.version,
		});
		return preferredResource === null
			? []
			: [
					bridgeCodeViewContentResourceMaterializationCacheKey({
						contentWindow: codeViewContentWindowForResource({
							contentWindow,
							item,
							resource: preferredResource,
						}),
						resource: preferredResource,
					}),
				];
	}

	if (oneSidedDiffResources !== null) {
		return [
			bridgeCodeViewDiffMaterializationCacheKey({
				...oneSidedDiffResources,
				contentWindow,
				item,
			}),
		];
	}

	if (
		shouldUseDiffPlaceholder(item) &&
		(resources.base !== undefined || resources.head !== undefined)
	) {
		return [
			bridgeCodeViewDiffMaterializationCacheKey({
				base: resources.base ?? null,
				contentWindow,
				head: resources.head ?? null,
				item,
			}),
		];
	}

	const preferredResource =
		resources.head ?? resources.file ?? resources.diff ?? resources.base ?? null;
	return preferredResource === null
		? []
		: [
				bridgeCodeViewContentResourceMaterializationCacheKey({
					contentWindow: codeViewContentWindowForResource({
						contentWindow,
						item,
						resource: preferredResource,
					}),
					resource: preferredResource,
				}),
			];
}

export function selectedBridgeCodeViewContentWindowLineLimitForItem(props: {
	readonly item: BridgeReviewItemDescriptor;
	readonly resources: BridgeCodeViewContentFacts;
}): number | undefined {
	if (
		maxKnownContentLineCount(props.item) > selectedBridgeCodeViewContentWindowLineCount ||
		maxKnownContentByteCount(props.resources) > 1_000_000
	) {
		return selectedBridgeCodeViewContentWindowLineCount;
	}
	return undefined;
}

export function materializeBridgeCodeViewLoadingItem(
	item: BridgeReviewItemDescriptor,
	presentation: BridgeCodeViewItemPresentation | null = null,
): BridgeCodeViewItem {
	const placeholderItem = createPlaceholderItem({ item, presentation });
	return {
		...placeholderItem,
		bridgeMetadata: {
			...placeholderItem.bridgeMetadata,
			contentState: 'loading',
		},
	};
}

function createPlaceholderItem(props: {
	readonly item: BridgeReviewItemDescriptor;
	readonly presentation: BridgeCodeViewItemPresentation | null;
}): BridgeCodeViewItem {
	if (props.presentation?.kind === 'file' && !itemIsOneSidedChange(props.item)) {
		return createPlaceholderFileItem({
			item: props.item,
			placeholderVersion: props.presentation.version,
			contentState: 'placeholder',
		});
	}
	if (shouldUseDiffPlaceholder(props.item)) {
		return createPlaceholderDiffItem({
			item: props.item,
		});
	}
	return createPlaceholderFileItem({
		item: props.item,
		placeholderVersion: 'current',
		contentState: 'placeholder',
	});
}

function itemIsOneSidedChange(item: BridgeReviewItemDescriptor): boolean {
	return item.changeKind === 'added' || item.changeKind === 'deleted';
}

function shouldUseDiffPlaceholder(item: BridgeReviewItemDescriptor): boolean {
	// Added/deleted files render as one-sided diffs (all-addition green rows / all-deletion red
	// rows), so their placeholder and loading records must be Pierre `diff` records too — even when
	// the metadata pipeline classifies a pure added/deleted file as `itemKind: 'file'`. Matching the
	// one-sided hydration path here keeps a single Pierre `type` across the item's whole lifecycle.
	if (itemIsOneSidedChange(item)) {
		return true;
	}
	return item.itemKind === 'diff';
}

function createPlaceholderDiffItem(props: {
	readonly item: BridgeReviewItemDescriptor;
}): BridgeCodeViewDiffItem {
	const placeholderFiles = createBridgeCodeViewPlaceholderDiffFiles({
		item: props.item,
		basePath: props.item.basePath ?? displayPathForItem(props.item),
		headPath: props.item.headPath ?? displayPathForItem(props.item),
	});
	const fileDiff = createBridgeCodeViewPlaceholderFileDiff(placeholderFiles);
	return {
		id: props.item.itemId,
		type: 'diff',
		fileDiff,
		version: codeViewRenderVersion({
			contentState: 'placeholder',
			itemVersion: props.item.itemVersion,
		}),
		bridgeMetadata: createMetadata({
			item: props.item,
			contentState: 'placeholder',
			contentRoles: [],
			cacheKey: `${props.item.cacheKey}:placeholder:${placeholderFiles.lineCount}`,
			lineCountOverride: placeholderFiles.lineCount,
		}),
	};
}

interface CreatePlaceholderFileItemProps {
	readonly item: BridgeReviewItemDescriptor;
	readonly placeholderVersion?: BridgeCodeViewFilePresentationVersion;
	readonly contentState: Extract<BridgeCodeViewItemMetadata['contentState'], 'placeholder'>;
}

function createPlaceholderFileItem(props: CreatePlaceholderFileItemProps): BridgeCodeViewFileItem {
	const placeholderFile = createBridgeCodeViewPlaceholderFileContents({
		item: props.item,
		path: displayPathForItem(props.item),
		version: props.placeholderVersion ?? 'current',
	});
	return {
		id: props.item.itemId,
		type: 'file',
		file: placeholderFile.file,
		version: codeViewRenderVersion({
			contentState: props.contentState,
			itemVersion: 0,
		}),
		bridgeMetadata: createMetadata({
			item: props.item,
			contentState: props.contentState,
			contentRoles: [],
			cacheKey: placeholderFile.file.cacheKey ?? props.item.cacheKey,
			lineCountOverride: placeholderFile.lineCount,
		}),
	};
}

interface BridgeCodeViewDiffMaterializationCacheKeyProps {
	readonly contentWindow?: CodeViewContentWindow | undefined;
	readonly item: BridgeReviewItemDescriptor;
	readonly base: BridgeCodeViewContentRoleFacts | null;
	readonly head: BridgeCodeViewContentRoleFacts | null;
}

function bridgeCodeViewDiffMaterializationCacheKey(
	props: BridgeCodeViewDiffMaterializationCacheKeyProps,
): string {
	const contentWindow = codeViewContentWindowForDiffItem(props);
	const baseCacheKey = bridgeCodeViewFileContentCacheKey({
		contentState: 'placeholder',
		contentWindow,
		item: props.item,
		resource: props.base,
	});
	const headCacheKey = bridgeCodeViewFileContentCacheKey({
		contentState: 'placeholder',
		contentWindow,
		item: props.item,
		resource: props.head,
	});
	const cacheKey = `${baseCacheKey}|${headCacheKey}`;
	return contentWindow.truncated ? `${cacheKey}:window:${contentWindow.maxLines}` : cacheKey;
}

function bridgeCodeViewFileContentCacheKey(props: {
	readonly contentState?: BridgeCodeViewItemMetadata['contentState'];
	readonly contentWindow: CodeViewContentWindow;
	readonly item: BridgeReviewItemDescriptor;
	readonly resource: BridgeCodeViewContentRoleFacts | null;
}): string {
	if (props.resource === null) {
		return `${props.item.cacheKey}:${props.contentState ?? 'placeholder'}`;
	}
	return bridgeCodeViewContentResourceMaterializationCacheKey({
		contentWindow: props.contentWindow,
		resource: props.resource,
	});
}

function resourceForFilePresentation(props: {
	readonly resources: BridgeCodeViewContentFacts;
	readonly version: BridgeCodeViewFilePresentationVersion;
}): BridgeCodeViewContentRoleFacts | null {
	switch (props.version) {
		case 'base':
			return props.resources.base ?? null;
		case 'head':
			return props.resources.head ?? props.resources.file ?? null;
		case 'current':
			return props.resources.head ?? props.resources.file ?? props.resources.base ?? null;
	}
	const exhaustiveVersion: never = props.version;
	void exhaustiveVersion;
	throw new Error('Unhandled Bridge CodeView file presentation version');
}

function codeViewRenderVersion(props: {
	readonly contentState: BridgeCodeViewItemMetadata['contentState'];
	readonly itemVersion: number;
}): number {
	const baseVersion = props.itemVersion * 3;
	switch (props.contentState) {
		case 'hydrated':
		case 'windowed':
			return baseVersion + 2;
		case 'loading':
			return baseVersion + 1;
		case 'placeholder':
			return baseVersion;
	}
	const exhaustiveContentState: never = props.contentState;
	void exhaustiveContentState;
	throw new Error('Unhandled Bridge CodeView content state');
}

function oneSidedDiffResourcesForItem(props: {
	readonly item: BridgeReviewItemDescriptor;
	readonly resources: BridgeCodeViewContentFacts;
}): Pick<BridgeCodeViewDiffMaterializationCacheKeyProps, 'base' | 'head'> | null {
	switch (props.item.changeKind) {
		case 'added': {
			const head = props.resources.head ?? props.resources.file ?? null;
			return head === null ? null : { base: null, head };
		}
		case 'deleted': {
			const base = props.resources.base ?? props.resources.diff ?? null;
			return base === null ? null : { base, head: null };
		}
		case 'modified':
		case 'renamed':
		case 'copied':
			return null;
	}
	const exhaustiveChangeKind: never = props.item.changeKind;
	void exhaustiveChangeKind;
	throw new Error('Unhandled Bridge review file change kind');
}

function bridgeCodeViewContentResourceMaterializationCacheKey(props: {
	readonly contentWindow: Pick<CodeViewContentWindow, 'maxLines' | 'truncated'>;
	readonly resource: BridgeCodeViewContentRoleFacts;
}): string {
	const cacheKey = bridgePierreContentDescriptorCacheKey({
		contentHash: props.resource.contentHash,
		contentHashAlgorithm: props.resource.contentHashAlgorithm,
	});
	return props.contentWindow.truncated
		? `${cacheKey}:window:${props.contentWindow.maxLines}`
		: cacheKey;
}

interface CodeViewContentWindow {
	readonly maxLines: number;
	readonly truncated: boolean;
}

function fullCodeViewContentWindow(): CodeViewContentWindow {
	return {
		maxLines: Number.POSITIVE_INFINITY,
		truncated: false,
	};
}

function codeViewContentWindowForDiffItem(
	props: BridgeCodeViewDiffMaterializationCacheKeyProps,
): CodeViewContentWindow {
	if (props.contentWindow !== undefined) {
		return props.contentWindow;
	}
	return shouldUseBoundedCodeViewWindow({
		item: props.item,
		resources: [props.base, props.head],
	})
		? {
				maxLines: codeViewContentWindowLineCount,
				truncated: true,
			}
		: fullCodeViewContentWindow();
}

function codeViewContentWindowForResource(props: {
	readonly contentWindow?: CodeViewContentWindow | undefined;
	readonly item: BridgeReviewItemDescriptor;
	readonly resource: BridgeCodeViewContentRoleFacts | null;
}): CodeViewContentWindow {
	if (props.contentWindow !== undefined) {
		return props.contentWindow;
	}
	return shouldUseBoundedCodeViewWindow({
		item: props.item,
		resources: [props.resource],
	})
		? {
				maxLines: codeViewContentWindowLineCount,
				truncated: true,
			}
		: fullCodeViewContentWindow();
}

function codeViewContentWindowForLineLimit(
	contentWindowLineLimit: number | undefined,
): CodeViewContentWindow | undefined {
	if (contentWindowLineLimit === undefined) {
		return undefined;
	}
	return {
		maxLines: Math.max(1, Math.floor(contentWindowLineLimit)),
		truncated: true,
	};
}

function shouldUseBoundedCodeViewWindow(props: {
	readonly item: BridgeReviewItemDescriptor;
	readonly resources: readonly (BridgeCodeViewContentRoleFacts | null)[];
}): boolean {
	const itemLineCount = props.item.additions + props.item.deletions;
	if (itemLineCount > fullCodeViewMaterializationLineBudget) {
		return true;
	}
	return props.resources.some(
		(resource): boolean => resource !== null && resource.sizeBytes > 1_000_000,
	);
}

function maxKnownContentLineCount(item: BridgeReviewItemDescriptor): number {
	const lineCountsByRole = item.contentLineCountsByRole;
	if (lineCountsByRole === undefined) {
		return item.additions + item.deletions;
	}
	return Math.max(0, ...Object.values(lineCountsByRole).map((lineCount): number => lineCount ?? 0));
}

function maxKnownContentByteCount(resources: BridgeCodeViewContentFacts): number {
	return Math.max(
		0,
		...Object.values(resources).map((resource): number => {
			if (resource === undefined) {
				return 0;
			}
			return resource.byteLength ?? resource.sizeBytes;
		}),
	);
}

interface CreateMetadataProps {
	readonly item: BridgeReviewItemDescriptor;
	readonly contentState: BridgeCodeViewItemMetadata['contentState'];
	readonly contentRoles: readonly BridgeContentRole[];
	readonly lineCountOverride?: number | null;
	readonly cacheKey: string;
}

function createMetadata(props: CreateMetadataProps): BridgeCodeViewItemMetadata {
	return {
		itemId: props.item.itemId,
		displayPath: displayPathForItem(props.item),
		contentState: props.contentState,
		contentRoles: props.contentRoles,
		cacheKey: props.cacheKey,
		lineCount:
			props.lineCountOverride !== undefined
				? props.lineCountOverride
				: lineCountForContentRoles({
						contentRoles: props.contentRoles,
						item: props.item,
					}),
	};
}

function lineCountForContentRoles(props: {
	readonly contentRoles: readonly BridgeContentRole[];
	readonly item: BridgeReviewItemDescriptor;
}): number | null {
	const lineCountsByRole = props.item.contentLineCountsByRole;
	let totalLineCount = 0;
	let matchedRoleCount = 0;
	for (const role of props.contentRoles) {
		const lineCount =
			lineCountsByRole?.[role] ?? oneSidedDiffContentRoleLineCount(props.item, role);
		if (lineCount === null || lineCount === undefined) {
			continue;
		}
		totalLineCount += lineCount;
		matchedRoleCount += 1;
	}
	return matchedRoleCount === 0 ? null : totalLineCount;
}

function oneSidedDiffContentRoleLineCount(
	item: BridgeReviewItemDescriptor,
	role: BridgeContentRole,
): number | null {
	if (item.changeKind === 'added' && (role === 'head' || role === 'file')) {
		return item.additions;
	}
	if (item.changeKind === 'deleted' && (role === 'base' || role === 'diff')) {
		return item.deletions;
	}
	return null;
}

function displayPathForItem(item: BridgeReviewItemDescriptor): string {
	return item.headPath ?? item.basePath ?? item.itemId;
}

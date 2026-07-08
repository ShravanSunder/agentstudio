import type { CodeViewDiffItem, CodeViewFileItem } from '@pierre/diffs';
import { parseDiffFromFile, type FileContents } from '@pierre/diffs';
import { z } from 'zod';

import {
	bridgeContentDemandExecutionPolicy,
	demandRankForContentRole,
} from '../../core/demand/bridge-content-demand-policy.js';
import type { BridgeContentDemandRole } from '../../core/models/bridge-demand-models.js';
import type { BridgeContentResource } from '../../foundation/content/content-resource-loader.js';
import type {
	BridgeContentHandle,
	BridgeContentRole,
	BridgeReviewItemDescriptor,
	BridgeReviewPackage,
} from '../../foundation/review-package/bridge-review-package.js';
import type { BridgeReviewProjectionResult } from '../models/review-projection-models.js';
import { bridgeContentRoleSchema } from '../models/review-projection-models.js';
import { bridgePierreOptionalHighlightLanguage } from '../workers/pierre/bridge-pierre-language-normalization.js';
import {
	bridgePierreContentDescriptorCacheKey,
	createBridgePierreContentDescriptorFile,
} from '../workers/pierre/bridge-pierre-worker-content-descriptor.js';
import {
	createBridgeCodeViewPlaceholderDiffFiles,
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
type BridgeDemandRankedFileContents = FileContents & { readonly bridgeDemandRank?: number };

export interface BridgeCodeViewContentResources {
	readonly base?: BridgeContentResource;
	readonly head?: BridgeContentResource;
	readonly diff?: BridgeContentResource;
	readonly file?: BridgeContentResource;
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

export interface MaterializeBridgeCodeViewItemProps {
	readonly contentDemandRole?: BridgeContentDemandRole | undefined;
	readonly contentWindowLineLimit?: number | undefined;
	readonly item: BridgeReviewItemDescriptor;
	readonly presentation?: BridgeCodeViewItemPresentation | null;
	readonly resources: BridgeCodeViewContentResources;
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

export function materializeBridgeCodeViewItem(
	props: MaterializeBridgeCodeViewItemProps,
): BridgeCodeViewItem | null {
	const { item, resources } = props;
	// A one-sided change (added/deleted) always renders as a diff (all-addition / all-deletion
	// rows), even under an explicit file navigation target — there is no meaningful whole-file
	// "version" to show for it. Resolving the one-sided resources before honoring a file
	// presentation keeps placeholder/loading/hydrated on the same Pierre `type` for these items,
	// which CodeView.syncItemRecord requires (it throws on any file<->diff type change for an id).
	const oneSidedDiffResources = oneSidedDiffResourcesForItem({ item, resources });
	if (props.presentation?.kind === 'file' && oneSidedDiffResources === null) {
		const preferredResource = resourceForFilePresentation({
			resources,
			version: props.presentation.version,
		});
		return preferredResource === null
			? null
			: createFileItem({
					contentDemandRole: props.contentDemandRole,
					contentWindow: codeViewContentWindowForLineLimit(props.contentWindowLineLimit),
					item,
					resource: preferredResource,
					version: item.itemVersion,
					contentState: 'hydrated',
				});
	}

	if (oneSidedDiffResources !== null) {
		return createDiffItem({
			...oneSidedDiffResources,
			contentDemandRole: props.contentDemandRole,
			contentWindow: codeViewContentWindowForLineLimit(props.contentWindowLineLimit),
			item,
		});
	}

	if (
		shouldUseDiffPlaceholder(item) &&
		(resources.base !== undefined || resources.head !== undefined)
	) {
		return createDiffItem({
			contentDemandRole: props.contentDemandRole,
			contentWindow: codeViewContentWindowForLineLimit(props.contentWindowLineLimit),
			item,
			base: resources.base ?? null,
			head: resources.head ?? null,
		});
	}

	const preferredResource =
		resources.head ?? resources.file ?? resources.diff ?? resources.base ?? null;
	if (preferredResource === null) {
		return null;
	}

	return createFileItem({
		contentDemandRole: props.contentDemandRole,
		contentWindow: codeViewContentWindowForLineLimit(props.contentWindowLineLimit),
		item,
		resource: preferredResource,
		version: item.itemVersion,
		contentState: 'hydrated',
	});
}

export function bridgeCodeViewMaterializationCacheKeysForItem(
	props: MaterializeBridgeCodeViewItemProps,
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
	readonly resources: BridgeCodeViewContentResources;
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
		return createFileItem({
			item: props.item,
			placeholderVersion: props.presentation.version,
			resource: null,
			version: 0,
			contentState: 'placeholder',
		});
	}
	if (shouldUseDiffPlaceholder(props.item)) {
		return createPlaceholderDiffItem({
			item: props.item,
		});
	}
	return createFileItem({
		item: props.item,
		placeholderVersion: 'current',
		resource: null,
		version: 0,
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
	return (
		item.itemKind === 'diff' &&
		(hasContentHandle(item.contentRoles.base) ||
			hasContentHandle(item.contentRoles.head) ||
			hasContentHandle(item.contentRoles.diff))
	);
}

function hasContentHandle(
	handle: BridgeContentHandle | null | undefined,
): handle is BridgeContentHandle {
	return handle !== null && handle !== undefined;
}

function createPlaceholderDiffItem(props: {
	readonly item: BridgeReviewItemDescriptor;
}): BridgeCodeViewDiffItem {
	const placeholderFiles = createBridgeCodeViewPlaceholderDiffFiles({
		item: props.item,
		basePath: props.item.basePath ?? displayPathForItem(props.item),
		headPath: props.item.headPath ?? displayPathForItem(props.item),
	});
	const fileDiff = parseDiffFromFile(placeholderFiles.base, placeholderFiles.head);
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

interface CreateFileItemProps {
	readonly contentDemandRole?: BridgeContentDemandRole | undefined;
	readonly contentWindow?: CodeViewContentWindow | undefined;
	readonly item: BridgeReviewItemDescriptor;
	readonly placeholderVersion?: BridgeCodeViewFilePresentationVersion;
	readonly resource: BridgeContentResource | null;
	readonly version: number;
	readonly contentState: BridgeCodeViewItemMetadata['contentState'];
}

function createFileItem(props: CreateFileItemProps): BridgeCodeViewFileItem {
	const contentWindow = codeViewContentWindowForResource({
		contentWindow: props.contentWindow,
		item: props.item,
		resource: props.resource,
	});
	const placeholderFile =
		props.contentState === 'placeholder' && props.resource === null
			? createBridgeCodeViewPlaceholderFileContents({
					item: props.item,
					path: displayPathForItem(props.item),
					version: props.placeholderVersion ?? 'current',
				})
			: null;
	const file =
		placeholderFile?.file ??
		createFileContents({
			item: props.item,
			resource: props.resource,
			path: displayPathForItem(props.item),
			contentState: props.contentState,
			contentWindow,
			contentDemandRole: props.contentDemandRole,
		});
	const contentState =
		props.contentState === 'hydrated' && contentWindow.truncated ? 'windowed' : props.contentState;
	return {
		id: props.item.itemId,
		type: 'file',
		file,
		version: codeViewRenderVersion({
			contentState,
			itemVersion: props.version,
		}),
		bridgeMetadata: createMetadata({
			item: props.item,
			contentState,
			contentRoles: props.resource === null ? [] : [props.resource.handle.role],
			cacheKey: file.cacheKey ?? props.item.cacheKey,
			...(placeholderFile === null ? {} : { lineCountOverride: placeholderFile.lineCount }),
		}),
	};
}

interface CreateDiffItemProps {
	readonly contentDemandRole?: BridgeContentDemandRole | undefined;
	readonly contentWindow?: CodeViewContentWindow | undefined;
	readonly item: BridgeReviewItemDescriptor;
	readonly base: BridgeContentResource | null;
	readonly head: BridgeContentResource | null;
}

function createDiffItem(props: CreateDiffItemProps): BridgeCodeViewDiffItem {
	const contentWindow = codeViewContentWindowForDiffItem(props);
	const oldFile = createFileContents({
		item: props.item,
		resource: props.base,
		path: props.item.basePath ?? displayPathForItem(props.item),
		contentState: 'placeholder',
		contentWindow,
		contentDemandRole: props.contentDemandRole,
	});
	const newFile = createFileContents({
		item: props.item,
		resource: props.head,
		path: props.item.headPath ?? displayPathForItem(props.item),
		contentState: 'placeholder',
		contentWindow,
		contentDemandRole: props.contentDemandRole,
	});
	const fileDiff = parseDiffFromFile(oldFile, newFile);
	const fallbackLanguage = bridgePierreOptionalHighlightLanguage(
		newFile.lang ?? oldFile.lang ?? props.item.language,
	);
	if (fileDiff.lang === undefined && fallbackLanguage !== undefined) {
		fileDiff.lang = fallbackLanguage;
	}
	const contentState = contentWindow.truncated ? 'windowed' : 'hydrated';
	const cacheKey = bridgeCodeViewDiffMaterializationCacheKey({ ...props, contentWindow });
	return {
		id: props.item.itemId,
		type: 'diff',
		fileDiff,
		version: codeViewRenderVersion({
			contentState,
			itemVersion: props.item.itemVersion,
		}),
		bridgeMetadata: createMetadata({
			item: props.item,
			contentState,
			contentRoles: loadedDiffContentRoles(props),
			cacheKey,
		}),
	};
}

function bridgeCodeViewDiffMaterializationCacheKey(props: CreateDiffItemProps): string {
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
	readonly resource: BridgeContentResource | null;
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
	readonly resources: BridgeCodeViewContentResources;
	readonly version: BridgeCodeViewFilePresentationVersion;
}): BridgeContentResource | null {
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

function loadedDiffContentRoles(props: CreateDiffItemProps): readonly BridgeContentRole[] {
	const roles: BridgeContentRole[] = [];
	if (props.base !== null) {
		roles.push('base');
	}
	if (props.head !== null) {
		roles.push('head');
	}
	return roles;
}

function oneSidedDiffResourcesForItem(props: {
	readonly item: BridgeReviewItemDescriptor;
	readonly resources: BridgeCodeViewContentResources;
}): Omit<CreateDiffItemProps, 'item'> | null {
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

interface CreateFileContentsProps {
	readonly contentDemandRole?: BridgeContentDemandRole | undefined;
	readonly item: BridgeReviewItemDescriptor;
	readonly missingResourceText?: string;
	readonly resource: BridgeContentResource | null;
	readonly path: string;
	readonly contentState?: BridgeCodeViewItemMetadata['contentState'];
	readonly contentWindow?: CodeViewContentWindow;
}

function createFileContents(props: CreateFileContentsProps): FileContents {
	if (props.resource !== null) {
		const text = props.resource.readText();
		return createFileContentsForResource({
			contentWindow: props.contentWindow ?? fullCodeViewContentWindow(),
			item: props.item,
			path: props.path,
			resource: props.resource,
			text,
			contentDemandRole: props.contentDemandRole,
		});
	}

	const windowedText = windowTextForCodeView({
		contentWindow: props.contentWindow ?? fullCodeViewContentWindow(),
		text:
			props.missingResourceText ??
			(props.contentState === 'loading' ? loadingMissingResourceText : ''),
	});
	return fileContentsWithDemandRank({
		contentDemandRole: props.contentDemandRole,
		file: {
			name: props.path,
			contents: windowedText.text,
			cacheKey: `${props.item.cacheKey}:${props.contentState ?? 'placeholder'}`,
		},
	});
}

function createFileContentsForResource(props: {
	readonly contentDemandRole?: BridgeContentDemandRole | undefined;
	readonly contentWindow: CodeViewContentWindow;
	readonly item: BridgeReviewItemDescriptor;
	readonly path: string;
	readonly resource: BridgeContentResource;
	readonly text: string;
}): FileContents {
	const windowedText = windowTextForCodeView({
		contentWindow: props.contentWindow,
		text: props.text,
	});
	const cacheKey = bridgeCodeViewContentResourceMaterializationCacheKey({
		contentWindow: windowedText,
		resource: props.resource,
	});
	const normalizedLanguage = bridgePierreOptionalHighlightLanguage(
		props.resource.handle.language ?? props.item.language,
	);
	if (windowedText.truncated) {
		return fileContentsWithDemandRank({
			contentDemandRole: props.contentDemandRole,
			file: {
				name: props.path,
				contents: windowedText.text,
				cacheKey,
				...(normalizedLanguage === undefined ? {} : { lang: normalizedLanguage }),
			},
		});
	}
	const lineCount = props.item.contentLineCountsByRole?.[props.resource.handle.role] ?? null;
	return fileContentsWithDemandRank({
		contentDemandRole: props.contentDemandRole,
		file: createBridgePierreContentDescriptorFile({
			cacheKey,
			contentHash: props.resource.handle.contentHash,
			contentHashAlgorithm: props.resource.handle.contentHashAlgorithm,
			generation: props.resource.handle.reviewGeneration,
			lang: normalizedLanguage,
			lineCount,
			maxBytes: Math.max(1, props.resource.handle.sizeBytes),
			name: props.path,
			resourceUrl: props.resource.handle.resourceUrl,
			text: windowedText.text,
		}),
	});
}

function bridgeCodeViewContentResourceMaterializationCacheKey(props: {
	readonly contentWindow: Pick<CodeViewContentWindow, 'maxLines' | 'truncated'>;
	readonly resource: BridgeContentResource;
}): string {
	const cacheKey = bridgePierreContentDescriptorCacheKey({
		contentHash: props.resource.handle.contentHash,
		contentHashAlgorithm: props.resource.handle.contentHashAlgorithm,
	});
	return props.contentWindow.truncated
		? `${cacheKey}:window:${props.contentWindow.maxLines}`
		: cacheKey;
}

function fileContentsWithDemandRank(props: {
	readonly contentDemandRole?: BridgeContentDemandRole | undefined;
	readonly file: FileContents;
}): BridgeDemandRankedFileContents {
	if (props.contentDemandRole === undefined) {
		return props.file;
	}
	return {
		...props.file,
		bridgeDemandRank: demandRankForContentRole(props.contentDemandRole),
	};
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

function codeViewContentWindowForDiffItem(props: CreateDiffItemProps): CodeViewContentWindow {
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
	readonly resource: BridgeContentResource | null;
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
	readonly resources: readonly (BridgeContentResource | null)[];
}): boolean {
	const itemLineCount = props.item.additions + props.item.deletions;
	if (itemLineCount > fullCodeViewMaterializationLineBudget) {
		return true;
	}
	return props.resources.some(
		(resource): boolean => resource !== null && (resource.handle.sizeBytes ?? 0) > 1_000_000,
	);
}

function maxKnownContentLineCount(item: BridgeReviewItemDescriptor): number {
	const lineCountsByRole = item.contentLineCountsByRole;
	if (lineCountsByRole === undefined) {
		return item.additions + item.deletions;
	}
	return Math.max(0, ...Object.values(lineCountsByRole).map((lineCount): number => lineCount ?? 0));
}

function maxKnownContentByteCount(resources: BridgeCodeViewContentResources): number {
	return Math.max(
		0,
		...Object.values(resources).map((resource): number => {
			if (resource === undefined) {
				return 0;
			}
			return resource.byteLength ?? resource.handle.sizeBytes ?? 0;
		}),
	);
}

function windowTextForCodeView(props: {
	readonly contentWindow: CodeViewContentWindow;
	readonly text: string;
}): {
	readonly maxLines: number;
	readonly text: string;
	readonly truncated: boolean;
} {
	if (!Number.isFinite(props.contentWindow.maxLines)) {
		return {
			maxLines: props.contentWindow.maxLines,
			text: props.text,
			truncated: false,
		};
	}
	const maxLines = Math.max(1, Math.floor(props.contentWindow.maxLines));
	let currentIndex = 0;
	for (let lineIndex = 0; lineIndex < maxLines; lineIndex += 1) {
		const newlineIndex = props.text.indexOf('\n', currentIndex);
		if (newlineIndex === -1) {
			return {
				maxLines,
				text: props.text,
				truncated: false,
			};
		}
		currentIndex = newlineIndex + 1;
	}
	return {
		maxLines,
		text: props.text.slice(0, currentIndex),
		truncated: true,
	};
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

const loadingMissingResourceText = 'Loading content...\nLoading syntax view...\n';

function displayPathForItem(item: BridgeReviewItemDescriptor): string {
	return item.headPath ?? item.basePath ?? item.itemId;
}

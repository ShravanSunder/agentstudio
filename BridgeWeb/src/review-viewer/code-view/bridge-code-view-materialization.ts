import type { CodeViewDiffItem, CodeViewFileItem } from '@pierre/diffs';
import { parseDiffFromFile, type FileContents } from '@pierre/diffs';
import { z } from 'zod';

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
	bridgePierreWorkerContentDescriptorFetchIsEnabled,
	createBridgePierreContentDescriptorFile,
} from '../workers/pierre/bridge-pierre-worker-content-descriptor.js';

export const bridgeCodeViewContentStateSchema = z.enum([
	'placeholder',
	'loading',
	'hydrated',
	'windowed',
]);

const fullCodeViewMaterializationLineBudget = 20_000;
const codeViewContentWindowLineCount = 1_500;

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
	readonly item: BridgeReviewItemDescriptor;
	readonly presentation?: BridgeCodeViewItemPresentation | null;
	readonly resources: BridgeCodeViewContentResources;
}

interface BridgeCodeViewLineCountEstimates {
	readonly lineCountByRole: Readonly<Partial<Record<BridgeContentRole, number>>>;
}

export function createBridgeCodeViewInitialItems(
	props: CreateBridgeCodeViewInitialItemsProps,
): readonly BridgeCodeViewItem[] {
	const items: BridgeCodeViewItem[] = [];
	const seedItemIds = props.seedItemIds === undefined ? null : new Set<string>(props.seedItemIds);
	const lineCountEstimates = bridgeCodeViewLineCountEstimatesForPackage(props.reviewPackage);

	for (const itemId of props.projection.orderedItemIds) {
		if (seedItemIds !== null && !seedItemIds.has(itemId)) {
			continue;
		}
		const item = props.reviewPackage.itemsById[itemId];
		if (item === undefined) {
			continue;
		}
		items.push(
			createPlaceholderItem({
				item,
				lineCountEstimates,
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
					item,
					resource: preferredResource,
					version: item.itemVersion,
					contentState: 'hydrated',
				});
	}

	if (oneSidedDiffResources !== null) {
		return createDiffItem({
			...oneSidedDiffResources,
			item,
		});
	}

	if (
		shouldUseDiffPlaceholder(item) &&
		(resources.base !== undefined || resources.head !== undefined)
	) {
		return createDiffItem({
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
		item,
		resource: preferredResource,
		version: item.itemVersion,
		contentState: 'hydrated',
	});
}

export function materializeBridgeCodeViewLoadingItem(
	item: BridgeReviewItemDescriptor,
	presentation: BridgeCodeViewItemPresentation | null = null,
): BridgeCodeViewItem {
	if (presentation?.kind === 'file' && !itemIsOneSidedChange(item)) {
		return createFileItem({
			item,
			placeholderContentRoles: contentRolesForFilePresentation({
				item,
				version: presentation.version,
			}),
			resource: null,
			version: item.itemVersion,
			contentState: 'loading',
		});
	}
	if (shouldUseDiffPlaceholder(item)) {
		return createLoadingDiffItem(item);
	}
	const file: FileContents = {
		name: displayPathForItem(item),
		contents: 'Loading content...\nLoading syntax view...\n',
		cacheKey: `${item.cacheKey}:loading`,
		lang: 'text',
	};
	return {
		id: item.itemId,
		type: 'file',
		file,
		version: codeViewRenderVersion({
			contentState: 'loading',
			itemVersion: item.itemVersion,
		}),
		bridgeMetadata: createMetadata({
			item,
			contentState: 'loading',
			contentRoles: [],
			cacheKey: file.cacheKey ?? `${item.cacheKey}:loading`,
		}),
	};
}

function createLoadingDiffItem(item: BridgeReviewItemDescriptor): BridgeCodeViewDiffItem {
	const placeholderContentRoles = placeholderContentRolesForDiffItem({
		item,
		lineCountEstimates: emptyBridgeCodeViewLineCountEstimates,
	});
	const oldFile: FileContents = {
		...createFileContents({
			item,
			placeholderLineCount: loadingPlaceholderLineCountForContentRoles({
				contentRoles: ['base', 'diff'],
				fallbackLineCount: null,
				item,
			}),
			resource: null,
			path: item.basePath ?? displayPathForItem(item),
			contentState: 'loading',
		}),
		lang: 'text',
	};
	const newFile: FileContents = {
		...createFileContents({
			item,
			placeholderLineCount: loadingPlaceholderLineCountForContentRoles({
				contentRoles: ['head', 'file', 'diff'],
				fallbackLineCount: 2,
				item,
			}),
			resource: null,
			path: item.headPath ?? displayPathForItem(item),
			contentState: 'loading',
		}),
		lang: 'text',
	};
	const fileDiff = parseDiffFromFile(oldFile, newFile);
	return {
		id: item.itemId,
		type: 'diff',
		fileDiff,
		version: codeViewRenderVersion({
			contentState: 'loading',
			itemVersion: item.itemVersion,
		}),
		bridgeMetadata: createMetadata({
			item,
			contentState: 'loading',
			contentRoles: placeholderContentRoles,
			cacheKey: `${item.cacheKey}:loading`,
		}),
	};
}

function createPlaceholderItem(props: {
	readonly item: BridgeReviewItemDescriptor;
	readonly lineCountEstimates: BridgeCodeViewLineCountEstimates;
	readonly presentation: BridgeCodeViewItemPresentation | null;
}): BridgeCodeViewItem {
	if (props.presentation?.kind === 'file' && !itemIsOneSidedChange(props.item)) {
		return createFileItem({
			item: props.item,
			lineCountEstimates: props.lineCountEstimates,
			placeholderContentRoles: contentRolesForFilePresentation({
				item: props.item,
				version: props.presentation.version,
			}),
			resource: null,
			version: 0,
			contentState: 'placeholder',
		});
	}
	if (shouldUseDiffPlaceholder(props.item)) {
		return createPlaceholderDiffItem({
			item: props.item,
			lineCountEstimates: props.lineCountEstimates,
		});
	}
	return createFileItem({
		item: props.item,
		lineCountEstimates: props.lineCountEstimates,
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
	readonly lineCountEstimates: BridgeCodeViewLineCountEstimates;
}): BridgeCodeViewDiffItem {
	const placeholderContentRoles = placeholderContentRolesForDiffItem({
		item: props.item,
		lineCountEstimates: props.lineCountEstimates,
	});
	// One-sided changes must reserve ZERO lines on the absent side, matching
	// oneSidedDiffResourcesForItem's hydrated path. Otherwise the absent side borrows a
	// package-wide cross-item line estimate (e.g. a modified sibling's base average) and
	// parseDiffFromFile matches the two skeletons' shared placeholder lines as phantom
	// "unmodified" context, then renders the rest as textless addition rows.
	const emptyBase = createFileContents({
		item: props.item,
		placeholderLineCount:
			props.item.changeKind === 'added'
				? 0
				: lineCountForFirstAvailableContentRole({
						contentRoles: ['base', 'diff'],
						item: props.item,
						lineCountEstimates: props.lineCountEstimates,
					}),
		resource: null,
		path: props.item.basePath ?? displayPathForItem(props.item),
	});
	const emptyHead = createFileContents({
		item: props.item,
		placeholderLineCount:
			props.item.changeKind === 'deleted'
				? 0
				: lineCountForFirstAvailableContentRole({
						contentRoles: ['head', 'file', 'diff'],
						item: props.item,
						lineCountEstimates: props.lineCountEstimates,
					}),
		resource: null,
		path: props.item.headPath ?? displayPathForItem(props.item),
	});
	const fileDiff = parseDiffFromFile(emptyBase, emptyHead);
	const hasPlaceholderExtents = placeholderContentRoles.length > 0;
	return {
		id: props.item.itemId,
		type: 'diff',
		fileDiff,
		...(hasPlaceholderExtents ? {} : { collapsed: true }),
		version: codeViewRenderVersion({
			contentState: 'placeholder',
			itemVersion: props.item.itemVersion,
		}),
		bridgeMetadata: createMetadata({
			item: props.item,
			contentState: 'placeholder',
			contentRoles: placeholderContentRoles,
			lineCountEstimates: props.lineCountEstimates,
			cacheKey: `${props.item.cacheKey}:placeholder`,
		}),
	};
}

interface CreateFileItemProps {
	readonly item: BridgeReviewItemDescriptor;
	readonly lineCountEstimates?: BridgeCodeViewLineCountEstimates;
	readonly placeholderContentRoles?: readonly BridgeContentRole[];
	readonly resource: BridgeContentResource | null;
	readonly version: number;
	readonly contentState: BridgeCodeViewItemMetadata['contentState'];
}

function createFileItem(props: CreateFileItemProps): BridgeCodeViewFileItem {
	const contentWindow = codeViewContentWindowForResource({
		item: props.item,
		resource: props.resource,
	});
	const placeholderLineCount =
		props.resource === null && props.placeholderContentRoles !== undefined
			? lineCountForFirstAvailableContentRole({
					contentRoles: props.placeholderContentRoles,
					item: props.item,
					lineCountEstimates: props.lineCountEstimates ?? emptyBridgeCodeViewLineCountEstimates,
				})
			: null;
	const file = createFileContents({
		item: props.item,
		placeholderLineCount,
		resource: props.resource,
		path: displayPathForItem(props.item),
		contentState: props.contentState,
		contentWindow,
	});
	const contentState =
		props.contentState === 'hydrated' && contentWindow.truncated ? 'windowed' : props.contentState;
	return {
		id: props.item.itemId,
		type: 'file',
		file,
		...(contentState === 'placeholder' ? { collapsed: true } : {}),
		version: codeViewRenderVersion({
			contentState,
			itemVersion: props.version,
		}),
		bridgeMetadata: createMetadata({
			item: props.item,
			contentState,
			contentRoles: props.resource === null ? [] : [props.resource.handle.role],
			...(props.resource === null && props.placeholderContentRoles !== undefined
				? { lineCountOverride: placeholderLineCount }
				: {}),
			lineCountEstimates: props.lineCountEstimates ?? emptyBridgeCodeViewLineCountEstimates,
			cacheKey: file.cacheKey ?? props.item.cacheKey,
		}),
	};
}

interface CreateDiffItemProps {
	readonly item: BridgeReviewItemDescriptor;
	readonly base: BridgeContentResource | null;
	readonly basePlaceholderLineCount?: number | null;
	readonly head: BridgeContentResource | null;
	readonly headPlaceholderLineCount?: number | null;
}

function createDiffItem(props: CreateDiffItemProps): BridgeCodeViewDiffItem {
	const contentWindow = codeViewContentWindowForDiffItem(props);
	const oldFile = createFileContents({
		item: props.item,
		placeholderLineCount:
			props.base === null
				? (props.basePlaceholderLineCount ??
					lineCountForFirstAvailableContentRole({
						contentRoles: ['base', 'diff'],
						item: props.item,
					}))
				: null,
		resource: props.base,
		path: props.item.basePath ?? displayPathForItem(props.item),
		contentState: 'placeholder',
		contentWindow,
	});
	const newFile = createFileContents({
		item: props.item,
		placeholderLineCount:
			props.head === null
				? (props.headPlaceholderLineCount ??
					lineCountForFirstAvailableContentRole({
						contentRoles: ['head', 'file', 'diff'],
						item: props.item,
					}))
				: null,
		resource: props.head,
		path: props.item.headPath ?? displayPathForItem(props.item),
		contentState: 'placeholder',
		contentWindow,
	});
	const fileDiff = parseDiffFromFile(oldFile, newFile);
	const fallbackLanguage = bridgePierreOptionalHighlightLanguage(
		newFile.lang ?? oldFile.lang ?? props.item.language,
	);
	if (fileDiff.lang === undefined && fallbackLanguage !== undefined) {
		fileDiff.lang = fallbackLanguage;
	}
	const contentState = contentWindow.truncated ? 'windowed' : 'hydrated';
	const cacheKey = `${oldFile.cacheKey ?? props.base?.handle.cacheKey ?? 'placeholder'}|${
		newFile.cacheKey ?? props.head?.handle.cacheKey ?? 'placeholder'
	}`;
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
			cacheKey: contentWindow.truncated ? `${cacheKey}:window:${contentWindow.maxLines}` : cacheKey,
		}),
	};
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

function contentRolesForFilePresentation(props: {
	readonly item: BridgeReviewItemDescriptor;
	readonly version: BridgeCodeViewFilePresentationVersion;
}): readonly BridgeContentRole[] {
	switch (props.version) {
		case 'base':
			return ['base'];
		case 'head':
			return ['head', 'file'];
		case 'current':
			return ['head', 'file', 'base'];
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
			return head === null ? null : { base: null, basePlaceholderLineCount: 0, head };
		}
		case 'deleted': {
			const base = props.resources.base ?? props.resources.diff ?? null;
			return base === null ? null : { base, head: null, headPlaceholderLineCount: 0 };
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

function placeholderContentRolesForDiffItem(props: {
	readonly item: BridgeReviewItemDescriptor;
	readonly lineCountEstimates?: BridgeCodeViewLineCountEstimates;
}): readonly BridgeContentRole[] {
	// Skip the absent side's roles for one-sided changes so a cross-item estimate can't
	// manufacture a placeholder extent for a side that has no content.
	const emptySideRoles = emptyDiffSideRolesForItem(props.item);
	const roles: BridgeContentRole[] = [];
	for (const role of [
		'base',
		'head',
		'file',
		'diff',
	] as const satisfies readonly BridgeContentRole[]) {
		if (emptySideRoles.has(role)) {
			continue;
		}
		const lineCount =
			props.item.contentLineCountsByRole?.[role] ?? props.lineCountEstimates?.lineCountByRole[role];
		if (lineCount !== null && lineCount !== undefined) {
			roles.push(role);
		}
	}
	return roles;
}

function emptyDiffSideRolesForItem(
	item: BridgeReviewItemDescriptor,
): ReadonlySet<BridgeContentRole> {
	if (item.changeKind === 'added') {
		return new Set<BridgeContentRole>(['base', 'diff']);
	}
	if (item.changeKind === 'deleted') {
		return new Set<BridgeContentRole>(['head', 'file']);
	}
	return new Set<BridgeContentRole>();
}

function loadingPlaceholderLineCountForContentRoles(props: {
	readonly contentRoles: readonly BridgeContentRole[];
	readonly fallbackLineCount: number | null;
	readonly item: BridgeReviewItemDescriptor;
}): number | null {
	return (
		lineCountForFirstAvailableContentRole({
			contentRoles: props.contentRoles,
			item: props.item,
		}) ?? props.fallbackLineCount
	);
}

interface CreateFileContentsProps {
	readonly item: BridgeReviewItemDescriptor;
	readonly placeholderLineCount?: number | null;
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
		});
	}

	const windowedText = windowTextForCodeView({
		contentWindow: props.contentWindow ?? fullCodeViewContentWindow(),
		text: placeholderTextForLineCount({
			contentState: props.contentState ?? 'placeholder',
			lineCount: props.placeholderLineCount ?? null,
			maxPlaceholderLineCount: placeholderLineCountBudgetForItem(props.item),
		}),
	});
	return {
		name: props.path,
		contents: windowedText.text,
		cacheKey: `${props.item.cacheKey}:${props.contentState ?? 'placeholder'}${
			props.placeholderLineCount === null || props.placeholderLineCount === undefined
				? ''
				: `:extent:${props.placeholderLineCount}`
		}`,
	};
}

function createFileContentsForResource(props: {
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
	const cacheKey = windowedText.truncated
		? `${props.resource.handle.cacheKey}:window:${windowedText.maxLines}`
		: props.resource.handle.cacheKey;
	const normalizedLanguage = bridgePierreOptionalHighlightLanguage(
		props.resource.handle.language ?? props.item.language,
	);
	if (windowedText.truncated) {
		return {
			name: props.path,
			contents: windowedText.text,
			cacheKey,
			...(normalizedLanguage === undefined ? {} : { lang: normalizedLanguage }),
		};
	}
	const lineCount = props.item.contentLineCountsByRole?.[props.resource.handle.role] ?? null;
	if (bridgePierreWorkerContentDescriptorFetchIsEnabled()) {
		return createBridgePierreContentDescriptorFile({
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
		});
	}
	return createBridgePierreContentDescriptorFile({
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
	});
}

export function placeholderLineCountBudgetForItem(item: BridgeReviewItemDescriptor): number {
	// F2 placeholder/hydrated cap parity: reserve the placeholder with the same line budget
	// the hydrated content will use. Items that hydrate to a bounded window keep the window
	// cap; everything else reserves up to the full materialization budget so the item does
	// not grow (or shrink) on hydrate.
	return shouldUseBoundedCodeViewWindow({ item, resources: [null] })
		? codeViewContentWindowLineCount
		: fullCodeViewMaterializationLineBudget;
}

function placeholderTextForLineCount(props: {
	readonly contentState: BridgeCodeViewItemMetadata['contentState'];
	readonly lineCount: number | null;
	readonly maxPlaceholderLineCount: number;
}): string {
	if (props.lineCount === null || props.lineCount <= 0) {
		return '';
	}
	const boundedLineCount = Math.min(props.lineCount, props.maxPlaceholderLineCount);
	const statusLines =
		props.contentState === 'loading'
			? ['Loading content...', 'Loading syntax view...']
			: ['Loading content...'];
	return (
		Array.from({ length: boundedLineCount }, (_, index): string => statusLines[index] ?? '').join(
			'\n',
		) + '\n'
	);
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
	readonly item: BridgeReviewItemDescriptor;
	readonly resource: BridgeContentResource | null;
}): CodeViewContentWindow {
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
	readonly lineCountEstimates?: BridgeCodeViewLineCountEstimates;
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
						lineCountEstimates: props.lineCountEstimates ?? emptyBridgeCodeViewLineCountEstimates,
					}),
	};
}

function lineCountForFirstAvailableContentRole(props: {
	readonly contentRoles: readonly BridgeContentRole[];
	readonly item: BridgeReviewItemDescriptor;
	readonly lineCountEstimates?: BridgeCodeViewLineCountEstimates;
}): number | null {
	const lineCountsByRole = props.item.contentLineCountsByRole;
	for (const role of props.contentRoles) {
		const lineCount = lineCountsByRole?.[role] ?? props.lineCountEstimates?.lineCountByRole[role];
		if (lineCount !== null && lineCount !== undefined) {
			return lineCount;
		}
	}
	return null;
}

function lineCountForContentRoles(props: {
	readonly contentRoles: readonly BridgeContentRole[];
	readonly item: BridgeReviewItemDescriptor;
	readonly lineCountEstimates?: BridgeCodeViewLineCountEstimates;
}): number | null {
	const lineCountsByRole = props.item.contentLineCountsByRole;
	let totalLineCount = 0;
	let matchedRoleCount = 0;
	for (const role of props.contentRoles) {
		const lineCount = lineCountsByRole?.[role] ?? props.lineCountEstimates?.lineCountByRole[role];
		if (lineCount === null || lineCount === undefined) {
			continue;
		}
		totalLineCount += lineCount;
		matchedRoleCount += 1;
	}
	return matchedRoleCount === 0 ? null : totalLineCount;
}

const emptyBridgeCodeViewLineCountEstimates: BridgeCodeViewLineCountEstimates = {
	lineCountByRole: {},
};

function bridgeCodeViewLineCountEstimatesForPackage(
	reviewPackage: BridgeReviewPackage,
): BridgeCodeViewLineCountEstimates {
	const totalsByRole: Partial<Record<BridgeContentRole, number>> = {};
	const countsByRole: Partial<Record<BridgeContentRole, number>> = {};
	for (const itemId of reviewPackage.orderedItemIds) {
		const lineCountsByRole = reviewPackage.itemsById[itemId]?.contentLineCountsByRole;
		if (lineCountsByRole === undefined) {
			continue;
		}
		for (const role of [
			'base',
			'head',
			'diff',
			'file',
		] as const satisfies readonly BridgeContentRole[]) {
			const lineCount = lineCountsByRole[role];
			if (lineCount === null || lineCount === undefined || lineCount <= 0) {
				continue;
			}
			totalsByRole[role] = (totalsByRole[role] ?? 0) + lineCount;
			countsByRole[role] = (countsByRole[role] ?? 0) + 1;
		}
	}
	const lineCountByRole: Partial<Record<BridgeContentRole, number>> = {};
	for (const role of [
		'base',
		'head',
		'diff',
		'file',
	] as const satisfies readonly BridgeContentRole[]) {
		const count = countsByRole[role] ?? 0;
		if (count <= 0) {
			continue;
		}
		lineCountByRole[role] = Math.max(1, Math.round((totalsByRole[role] ?? 0) / count));
	}
	return { lineCountByRole };
}

function displayPathForItem(item: BridgeReviewItemDescriptor): string {
	return item.headPath ?? item.basePath ?? item.itemId;
}

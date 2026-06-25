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

export const bridgeCodeViewContentStateSchema = z.enum(['placeholder', 'loading', 'hydrated']);

export const bridgeCodeViewItemMetadataSchema = z.object({
	itemId: z.string().min(1),
	displayPath: z.string().min(1),
	contentState: bridgeCodeViewContentStateSchema,
	contentRoles: z.array(bridgeContentRoleSchema).readonly(),
	cacheKey: z.string().min(1),
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
}

export interface MaterializeBridgeCodeViewItemProps {
	readonly item: BridgeReviewItemDescriptor;
	readonly presentation?: BridgeCodeViewItemPresentation | null;
	readonly resources: BridgeCodeViewContentResources;
}

export function createBridgeCodeViewInitialItems(
	props: CreateBridgeCodeViewInitialItemsProps,
): readonly BridgeCodeViewItem[] {
	const items: BridgeCodeViewItem[] = [];

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
	if (props.presentation?.kind === 'file') {
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
): BridgeCodeViewItem {
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
	const oldFile: FileContents = {
		name: item.basePath ?? displayPathForItem(item),
		contents: '',
		cacheKey: `${item.cacheKey}:loading:base`,
		lang: 'text',
	};
	const newFile: FileContents = {
		name: item.headPath ?? displayPathForItem(item),
		contents: 'Loading content...\nLoading syntax view...\n',
		cacheKey: `${item.cacheKey}:loading:head`,
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
			contentRoles: [],
			cacheKey: `${item.cacheKey}:loading`,
		}),
	};
}

function createPlaceholderItem(props: {
	readonly item: BridgeReviewItemDescriptor;
	readonly presentation: BridgeCodeViewItemPresentation | null;
}): BridgeCodeViewItem {
	if (props.presentation?.kind === 'file') {
		return createFileItem({
			item: props.item,
			resource: null,
			version: 0,
			contentState: 'placeholder',
		});
	}
	if (shouldUseDiffPlaceholder(props.item)) {
		return createPlaceholderDiffItem(props.item);
	}
	return createFileItem({
		item: props.item,
		resource: null,
		version: 0,
		contentState: 'placeholder',
	});
}

function shouldUseDiffPlaceholder(item: BridgeReviewItemDescriptor): boolean {
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

function createPlaceholderDiffItem(item: BridgeReviewItemDescriptor): BridgeCodeViewDiffItem {
	const emptyBase = createFileContents({
		item,
		resource: null,
		path: item.basePath ?? displayPathForItem(item),
	});
	const emptyHead = createFileContents({
		item,
		resource: null,
		path: item.headPath ?? displayPathForItem(item),
	});
	const fileDiff = parseDiffFromFile(emptyBase, emptyHead);
	return {
		id: item.itemId,
		type: 'diff',
		fileDiff,
		collapsed: true,
		version: codeViewRenderVersion({
			contentState: 'placeholder',
			itemVersion: item.itemVersion,
		}),
		bridgeMetadata: createMetadata({
			item,
			contentState: 'placeholder',
			contentRoles: [],
			cacheKey: `${item.cacheKey}:placeholder`,
		}),
	};
}

interface CreateFileItemProps {
	readonly item: BridgeReviewItemDescriptor;
	readonly resource: BridgeContentResource | null;
	readonly version: number;
	readonly contentState: BridgeCodeViewItemMetadata['contentState'];
}

function createFileItem(props: CreateFileItemProps): BridgeCodeViewFileItem {
	const file = createFileContents({
		item: props.item,
		resource: props.resource,
		path: displayPathForItem(props.item),
	});
	return {
		id: props.item.itemId,
		type: 'file',
		file,
		...(props.contentState === 'placeholder' ? { collapsed: true } : {}),
		version: codeViewRenderVersion({
			contentState: props.contentState,
			itemVersion: props.version,
		}),
		bridgeMetadata: createMetadata({
			item: props.item,
			contentState: props.contentState,
			contentRoles: props.resource === null ? [] : [props.resource.handle.role],
			cacheKey: file.cacheKey ?? props.item.cacheKey,
		}),
	};
}

interface CreateDiffItemProps {
	readonly item: BridgeReviewItemDescriptor;
	readonly base: BridgeContentResource | null;
	readonly head: BridgeContentResource | null;
}

function createDiffItem(props: CreateDiffItemProps): BridgeCodeViewDiffItem {
	const oldFile = createFileContents({
		item: props.item,
		resource: props.base,
		path: props.item.basePath ?? displayPathForItem(props.item),
	});
	const newFile = createFileContents({
		item: props.item,
		resource: props.head,
		path: props.item.headPath ?? displayPathForItem(props.item),
	});
	const fileDiff = parseDiffFromFile(oldFile, newFile);
	return {
		id: props.item.itemId,
		type: 'diff',
		fileDiff,
		version: codeViewRenderVersion({
			contentState: 'hydrated',
			itemVersion: props.item.itemVersion,
		}),
		bridgeMetadata: createMetadata({
			item: props.item,
			contentState: 'hydrated',
			contentRoles: loadedDiffContentRoles(props),
			cacheKey: `${props.base?.handle.cacheKey ?? 'placeholder'}|${props.head?.handle.cacheKey ?? 'placeholder'}`,
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

function codeViewRenderVersion(props: {
	readonly contentState: BridgeCodeViewItemMetadata['contentState'];
	readonly itemVersion: number;
}): number {
	const baseVersion = props.itemVersion * 3;
	switch (props.contentState) {
		case 'hydrated':
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

interface CreateFileContentsProps {
	readonly item: BridgeReviewItemDescriptor;
	readonly resource: BridgeContentResource | null;
	readonly path: string;
}

function createFileContents(props: CreateFileContentsProps): FileContents {
	return {
		name: props.path,
		contents: props.resource?.text ?? '',
		cacheKey:
			props.resource === null
				? `${props.item.cacheKey}:placeholder`
				: props.resource.handle.cacheKey,
	};
}

interface CreateMetadataProps {
	readonly item: BridgeReviewItemDescriptor;
	readonly contentState: BridgeCodeViewItemMetadata['contentState'];
	readonly contentRoles: readonly BridgeContentRole[];
	readonly cacheKey: string;
}

function createMetadata(props: CreateMetadataProps): BridgeCodeViewItemMetadata {
	return {
		itemId: props.item.itemId,
		displayPath: displayPathForItem(props.item),
		contentState: props.contentState,
		contentRoles: props.contentRoles,
		cacheKey: props.cacheKey,
	};
}

function displayPathForItem(item: BridgeReviewItemDescriptor): string {
	return item.headPath ?? item.basePath ?? item.itemId;
}

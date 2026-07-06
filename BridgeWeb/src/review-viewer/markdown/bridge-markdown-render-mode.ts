import { z } from 'zod';

import { parseBridgeContentResourceUrl } from '../../bridge/bridge-resource-url.js';
import type { BridgeMainCodeViewItem } from '../../core/comm-worker/bridge-main-render-snapshot-store.js';
import type { BridgeContentResource } from '../../foundation/content/content-resource-loader.js';
import type {
	BridgeContentHandle,
	BridgeContentRole,
	BridgeReviewItemDescriptor,
	BridgeReviewPackage,
} from '../../foundation/review-package/bridge-review-package.js';
import type { BridgeCodeViewContentResources } from '../code-view/bridge-code-view-materialization.js';
import { bridgeContentRoleSchema } from '../models/review-projection-models.js';
import { bridgePierreContentDescriptorCacheKey } from '../workers/pierre/bridge-pierre-worker-content-descriptor.js';

export const bridgeMarkdownPreviewMaxBytes = 512 * 1024;

export const bridgeMarkdownPreviewFallbackReasonSchema = z.enum([
	'noSelectedItem',
	'missingSelectedItem',
	'contentPending',
	'contentUnavailable',
	'twoSidedDiff',
	'diffPatchResource',
	'invalidResourceUrl',
	'binaryContent',
	'largeContent',
	'notMarkdown',
]);

export const bridgeMarkdownPreviewSourceSchema = z.object({
	itemId: z.string().min(1),
	itemVersion: z.number().int().nonnegative(),
	role: bridgeContentRoleSchema,
	sourcePath: z.string().min(1),
	contentCacheKey: z.string().min(1),
	contentHash: z.string().min(1),
	markdownText: z.string(),
});

export const bridgeMarkdownPreviewDecisionSchema = z.discriminatedUnion('kind', [
	z.object({
		kind: z.literal('preview'),
		source: bridgeMarkdownPreviewSourceSchema,
	}),
	z.object({
		kind: z.literal('codeView'),
		reason: bridgeMarkdownPreviewFallbackReasonSchema,
	}),
]);

export type BridgeMarkdownPreviewFallbackReason = z.infer<
	typeof bridgeMarkdownPreviewFallbackReasonSchema
>;

export type BridgeMarkdownPreviewSource = z.infer<typeof bridgeMarkdownPreviewSourceSchema>;

export type BridgeMarkdownPreviewDecision = z.infer<typeof bridgeMarkdownPreviewDecisionSchema>;

export interface ResolveBridgeMarkdownPreviewDecisionProps {
	readonly reviewPackage: BridgeReviewPackage;
	readonly selectedItemId: string | null;
	readonly resources: BridgeCodeViewContentResources | null;
	readonly maxBytes?: number;
}

export interface ResolveBridgeMarkdownPreviewDecisionFromCodeViewItemProps {
	readonly reviewPackage: BridgeReviewPackage;
	readonly selectedCodeViewItem: BridgeMainCodeViewItem | null;
	readonly selectedItemId: string | null;
	readonly maxBytes?: number;
}

export function resolveBridgeMarkdownPreviewDecision(
	props: ResolveBridgeMarkdownPreviewDecisionProps,
): BridgeMarkdownPreviewDecision {
	if (props.selectedItemId === null) {
		return { kind: 'codeView', reason: 'noSelectedItem' };
	}

	const item = props.reviewPackage.itemsById[props.selectedItemId];
	if (item === undefined) {
		return { kind: 'codeView', reason: 'missingSelectedItem' };
	}

	if (props.resources === null) {
		return { kind: 'codeView', reason: 'contentPending' };
	}

	if (props.resources.diff !== undefined) {
		return { kind: 'codeView', reason: 'diffPatchResource' };
	}

	const selectedResource = preferredMarkdownPreviewResource(props.resources);
	if (selectedResource === null) {
		return { kind: 'codeView', reason: 'contentUnavailable' };
	}

	const parsedResourceUrl = parseBridgeContentResourceUrl(selectedResource.handle.resourceUrl);
	if (
		parsedResourceUrl === null ||
		parsedResourceUrl.handleId !== selectedResource.handle.handleId ||
		parsedResourceUrl.generation !== props.reviewPackage.reviewGeneration
	) {
		return { kind: 'codeView', reason: 'invalidResourceUrl' };
	}

	if (selectedResource.handle.isBinary) {
		return { kind: 'codeView', reason: 'binaryContent' };
	}

	const maxBytes = props.maxBytes ?? bridgeMarkdownPreviewMaxBytes;
	const selectedResourceText = selectedResource.readText();
	const contentBytes = new TextEncoder().encode(selectedResourceText).byteLength;
	if (selectedResource.handle.sizeBytes > maxBytes || contentBytes > maxBytes) {
		return { kind: 'codeView', reason: 'largeContent' };
	}

	if (!isMarkdownReviewItem(item, selectedResource)) {
		return { kind: 'codeView', reason: 'notMarkdown' };
	}

	return {
		kind: 'preview',
		source: {
			itemId: item.itemId,
			itemVersion: item.itemVersion,
			role: selectedResource.handle.role,
			sourcePath: displayPathForMarkdownResource(item, selectedResource),
			contentCacheKey: selectedResource.handle.cacheKey,
			contentHash: selectedResource.handle.contentHash,
			markdownText: selectedResourceText,
		},
	};
}

export function resolveBridgeMarkdownPreviewDecisionFromCodeViewItem(
	props: ResolveBridgeMarkdownPreviewDecisionFromCodeViewItemProps,
): BridgeMarkdownPreviewDecision {
	if (props.selectedItemId === null) {
		return { kind: 'codeView', reason: 'noSelectedItem' };
	}

	const item = props.reviewPackage.itemsById[props.selectedItemId];
	if (item === undefined) {
		return { kind: 'codeView', reason: 'missingSelectedItem' };
	}

	if (
		props.selectedCodeViewItem === null ||
		props.selectedCodeViewItem.bridgeMetadata.itemId !== props.selectedItemId
	) {
		return { kind: 'codeView', reason: 'contentPending' };
	}

	if (props.selectedCodeViewItem.bridgeMetadata.contentState === 'windowed') {
		return { kind: 'codeView', reason: 'largeContent' };
	}

	if (!codeViewItemCacheMatchesCurrentPackage(item, props.selectedCodeViewItem)) {
		return { kind: 'codeView', reason: 'contentPending' };
	}

	const previewSource = markdownPreviewSourceFromCodeViewItem({
		codeViewItem: props.selectedCodeViewItem,
		item,
	});
	if (previewSource === null) {
		return { kind: 'codeView', reason: 'contentUnavailable' };
	}

	const maxBytes = props.maxBytes ?? bridgeMarkdownPreviewMaxBytes;
	const contentBytes = new TextEncoder().encode(previewSource.markdownText).byteLength;
	if (contentBytes > maxBytes) {
		return { kind: 'codeView', reason: 'largeContent' };
	}

	if (
		!isMarkdownReviewCodeViewItem({
			item,
			language: previewSource.language,
			sourcePath: previewSource.sourcePath,
		})
	) {
		return { kind: 'codeView', reason: 'notMarkdown' };
	}
	const previewHandle = currentContentHandleForRole(item, previewSource.role);
	if (previewHandle === null) {
		return { kind: 'codeView', reason: 'contentUnavailable' };
	}

	return {
		kind: 'preview',
		source: {
			itemId: item.itemId,
			itemVersion: item.itemVersion,
			role: previewSource.role,
			sourcePath: previewSource.sourcePath,
			contentCacheKey: previewHandle.cacheKey,
			contentHash: previewHandle.contentHash,
			markdownText: previewSource.markdownText,
		},
	};
}

function preferredMarkdownPreviewResource(
	resources: BridgeCodeViewContentResources,
): BridgeContentResource | null {
	return resources.file ?? resources.head ?? resources.base ?? null;
}

function isMarkdownReviewItem(
	item: BridgeReviewItemDescriptor,
	resource: BridgeContentResource,
): boolean {
	const extension = normalizedExtension(
		item.extension ?? extensionForPath(displayPathForMarkdownItem(item)),
	);
	if (extension === 'md' || extension === 'mdx') {
		return true;
	}
	if (item.language === 'markdown' || resource.handle.language === 'markdown') {
		return true;
	}
	if (
		resource.handle.mimeType === 'text/markdown' ||
		resource.handle.mimeType === 'text/x-markdown'
	) {
		return true;
	}
	return item.fileClass === 'docs' && isPlanOrDocsMarkdownPath(displayPathForMarkdownItem(item));
}

interface MarkdownPreviewCodeViewSource {
	readonly language: string | undefined;
	readonly markdownText: string;
	readonly role: BridgeContentRole;
	readonly sourcePath: string;
}

function markdownPreviewSourceFromCodeViewItem(props: {
	readonly codeViewItem: BridgeMainCodeViewItem;
	readonly item: BridgeReviewItemDescriptor;
}): MarkdownPreviewCodeViewSource | null {
	if (props.codeViewItem.type === 'file') {
		const role = props.codeViewItem.bridgeMetadata.contentRoles[0];
		if (role === undefined) {
			return null;
		}
		return {
			language: props.codeViewItem.file.lang,
			markdownText: props.codeViewItem.file.contents,
			role,
			sourcePath: displayPathForMarkdownCodeViewRole(props.item, role),
		};
	}

	if (
		props.codeViewItem.bridgeMetadata.contentRoles.includes('head') &&
		props.codeViewItem.fileDiff.additionLines.length > 0
	) {
		return {
			language: props.codeViewItem.fileDiff.lang,
			markdownText: props.codeViewItem.fileDiff.additionLines.join('\n'),
			role: 'head',
			sourcePath: displayPathForMarkdownRole(props.item, 'head'),
		};
	}

	if (
		props.codeViewItem.bridgeMetadata.contentRoles.includes('base') &&
		props.codeViewItem.fileDiff.deletionLines.length > 0
	) {
		return {
			language: props.codeViewItem.fileDiff.lang,
			markdownText: props.codeViewItem.fileDiff.deletionLines.join('\n'),
			role: 'base',
			sourcePath: displayPathForMarkdownRole(props.item, 'base'),
		};
	}

	return null;
}

function codeViewItemCacheMatchesCurrentPackage(
	item: BridgeReviewItemDescriptor,
	codeViewItem: BridgeMainCodeViewItem,
): boolean {
	if (codeViewItem.type === 'file') {
		const role = codeViewItem.bridgeMetadata.contentRoles[0];
		if (role === undefined) {
			return false;
		}
		const expectedCacheKey = contentCacheKeyForCurrentRole(item, role);
		return expectedCacheKey !== null && codeViewItem.bridgeMetadata.cacheKey === expectedCacheKey;
	}

	const roles = codeViewItem.bridgeMetadata.contentRoles;
	const hasBase = roles.includes('base');
	const hasHead = roles.includes('head');
	if (!hasBase && !hasHead) {
		return false;
	}
	const baseCacheKey = hasBase
		? contentCacheKeyForCurrentRole(item, 'base')
		: pierreEmptyContentCacheKey;
	const headCacheKey = hasHead
		? contentCacheKeyForCurrentRole(item, 'head')
		: pierreEmptyContentCacheKey;
	if (baseCacheKey === null || headCacheKey === null) {
		return false;
	}
	return codeViewItem.bridgeMetadata.cacheKey === `${baseCacheKey}|${headCacheKey}`;
}

const pierreEmptyContentCacheKey = 'pierre-content:empty';

function contentCacheKeyForCurrentRole(
	item: BridgeReviewItemDescriptor,
	role: BridgeContentRole,
): string | null {
	const handle = currentContentHandleForRole(item, role);
	return handle === null
		? null
		: bridgePierreContentDescriptorCacheKey({
				contentHash: handle.contentHash,
				contentHashAlgorithm: handle.contentHashAlgorithm,
			});
}

function currentContentHandleForRole(
	item: BridgeReviewItemDescriptor,
	role: BridgeContentRole,
): BridgeContentHandle | null {
	const directHandle = item.contentRoles[role];
	if (directHandle !== null && directHandle !== undefined) {
		return directHandle;
	}
	return (
		Object.values(item.contentRoles).find(
			(handle): handle is BridgeContentHandle =>
				handle !== null && handle !== undefined && handle.role === role,
		) ?? null
	);
}

function isMarkdownReviewCodeViewItem(props: {
	readonly item: BridgeReviewItemDescriptor;
	readonly language: string | undefined;
	readonly sourcePath: string;
}): boolean {
	const extension = normalizedExtension(props.item.extension ?? extensionForPath(props.sourcePath));
	if (extension === 'md' || extension === 'mdx') {
		return true;
	}
	const language = props.language?.toLowerCase() ?? '';
	if (props.item.language === 'markdown' || language === 'markdown') {
		return true;
	}
	return props.item.fileClass === 'docs' && isPlanOrDocsMarkdownPath(props.sourcePath);
}

function displayPathForMarkdownItem(item: BridgeReviewItemDescriptor): string {
	return item.headPath ?? item.basePath ?? item.itemId;
}

function displayPathForMarkdownResource(
	item: BridgeReviewItemDescriptor,
	resource: BridgeContentResource,
): string {
	if (resource.handle.role === 'base') {
		return item.basePath ?? item.headPath ?? item.itemId;
	}
	return item.headPath ?? item.basePath ?? item.itemId;
}

function displayPathForMarkdownRole(
	item: BridgeReviewItemDescriptor,
	role: Extract<BridgeContentRole, 'base' | 'head'>,
): string {
	if (role === 'base') {
		return item.basePath ?? item.headPath ?? item.itemId;
	}
	return item.headPath ?? item.basePath ?? item.itemId;
}

function displayPathForMarkdownCodeViewRole(
	item: BridgeReviewItemDescriptor,
	role: BridgeContentRole,
): string {
	if (role === 'base' || role === 'head') {
		return displayPathForMarkdownRole(item, role);
	}
	return displayPathForMarkdownItem(item);
}

function normalizedExtension(extension: string | null): string {
	return extension === null ? '' : extension.replace(/^\./, '').toLowerCase();
}

function extensionForPath(path: string): string | null {
	const lastPathComponent = path.split('/').at(-1) ?? '';
	const dotIndex = lastPathComponent.lastIndexOf('.');
	if (dotIndex < 0 || dotIndex === lastPathComponent.length - 1) {
		return null;
	}
	return lastPathComponent.slice(dotIndex + 1);
}

function isPlanOrDocsMarkdownPath(path: string): boolean {
	const normalizedPath = path.toLowerCase();
	return (
		normalizedPath.endsWith('.md') &&
		(normalizedPath.startsWith('docs/') ||
			normalizedPath.startsWith('readme') ||
			normalizedPath.includes('/docs/'))
	);
}

export function roleForMarkdownPreviewSource(
	source: BridgeMarkdownPreviewSource,
): BridgeContentRole {
	return source.role;
}

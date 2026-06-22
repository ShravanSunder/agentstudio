import { z } from 'zod';

import { parseBridgeContentResourceUrl } from '../../bridge/bridge-resource-url.js';
import type { BridgeContentResource } from '../../foundation/content/content-resource-loader.js';
import type {
	BridgeContentRole,
	BridgeReviewItemDescriptor,
	BridgeReviewPackage,
} from '../../foundation/review-package/bridge-review-package.js';
import type { BridgeCodeViewContentResources } from '../code-view/bridge-code-view-materialization.js';
import { bridgeContentRoleSchema } from '../models/review-projection-models.js';

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
	const contentBytes = new TextEncoder().encode(selectedResource.text).byteLength;
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
			markdownText: selectedResource.text,
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

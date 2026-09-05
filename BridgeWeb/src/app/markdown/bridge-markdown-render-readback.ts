import type {
	BridgeMainRenderedItemReadback,
	BridgeMainRenderPublicationItem,
	BridgeMainRenderReadback,
} from '../../core/comm-worker/bridge-main-render-fulfillment-coordinator.js';
import type {
	BridgeMarkdownPresentationState,
	BridgeMarkdownRenderIntent,
} from './use-bridge-markdown-presentation.js';
import { markdownRenderIdentitiesMatch } from './worker/bridge-markdown-render-worker-rpc.js';

export interface BridgeMarkdownRenderBinding {
	readonly isActive: boolean;
	readonly intent: BridgeMarkdownRenderIntent;
	readonly presentation: BridgeMarkdownPresentationState;
	readonly selectedItem: BridgeMainRenderPublicationItem;
}

export interface BridgeMarkdownRenderedArticle extends HTMLElement {
	readonly dataset: DOMStringMap & {
		readonly bridgeMarkdownContentCacheKey?: string;
		readonly bridgeMarkdownContentHash?: string;
		readonly bridgeMarkdownFileId?: string;
		readonly bridgeMarkdownFileVersion?: string;
		readonly bridgeMarkdownRequestId?: string;
		readonly bridgeMarkdownSourceGeneration?: string;
		readonly bridgeMarkdownSourceId?: string;
		readonly bridgeMarkdownSourcePath?: string;
	};
}

export function createBridgeMarkdownRenderReadback(props: {
	readonly expectedBinding: BridgeMarkdownRenderBinding;
	readonly readArticle: () => BridgeMarkdownRenderedArticle | null;
	readonly readBinding: () => BridgeMarkdownRenderBinding | null;
}): BridgeMainRenderReadback {
	return {
		readCurrentItem: (): BridgeMainRenderPublicationItem | undefined =>
			readValidBridgeMarkdownRender(props)?.binding.selectedItem,
		readRenderedItem: (): BridgeMainRenderedItemReadback | null => {
			const validRender = readValidBridgeMarkdownRender(props);
			if (validRender === null) return null;
			return {
				element: validRender.article,
				item: validRender.binding.selectedItem,
				readableContentMatchesItem: true,
			};
		},
	};
}

function readValidBridgeMarkdownRender(props: {
	readonly expectedBinding: BridgeMarkdownRenderBinding;
	readonly readArticle: () => BridgeMarkdownRenderedArticle | null;
	readonly readBinding: () => BridgeMarkdownRenderBinding | null;
}): {
	readonly article: BridgeMarkdownRenderedArticle;
	readonly binding: BridgeMarkdownRenderBinding;
} | null {
	const binding = readValidBridgeMarkdownBinding(props);
	if (binding === null) return null;
	const article = props.readArticle();
	return article !== null &&
		article.isConnected &&
		bridgeMarkdownArticleMatchesBinding(article, binding)
		? { article, binding }
		: null;
}

function readValidBridgeMarkdownBinding(props: {
	readonly expectedBinding: BridgeMarkdownRenderBinding;
	readonly readBinding: () => BridgeMarkdownRenderBinding | null;
}): BridgeMarkdownRenderBinding | null {
	const binding = props.readBinding();
	if (binding === null) return null;
	const presentation = binding.presentation;
	const expectedPresentation = props.expectedBinding.presentation;
	if (!binding.isActive || presentation.status !== 'ready') return null;
	if (
		expectedPresentation.status !== 'ready' ||
		binding.selectedItem !== props.expectedBinding.selectedItem ||
		!markdownRenderIdentitiesMatch(presentation.identity, expectedPresentation.identity)
	) {
		return null;
	}
	if (
		presentation.sourcePath !== binding.intent.sourcePath ||
		!markdownRenderIdentitiesMatch(presentation.identity, presentation.renderResult) ||
		!bridgeMarkdownIdentityMatchesIntent(presentation.identity, binding.intent) ||
		!bridgeMarkdownItemMatchesIntent(binding.selectedItem, binding.intent)
	) {
		return null;
	}
	return binding;
}

function bridgeMarkdownIdentityMatchesIntent(
	identity: Extract<BridgeMarkdownPresentationState, { readonly status: 'ready' }>['identity'],
	intent: BridgeMarkdownRenderIntent,
): boolean {
	const sourceIdentity = identity.sourceIdentity;
	const expectedSourceIdentity = intent.sourceIdentity;
	return (
		identity.contentCacheKey === intent.contentCacheKey &&
		identity.contentHash === intent.contentHash &&
		sourceIdentity.surface === expectedSourceIdentity.surface &&
		sourceIdentity.sourceId === expectedSourceIdentity.sourceId &&
		sourceIdentity.sourceGeneration === expectedSourceIdentity.sourceGeneration &&
		sourceIdentity.fileId === expectedSourceIdentity.fileId &&
		sourceIdentity.fileVersion === expectedSourceIdentity.fileVersion
	);
}

function bridgeMarkdownItemMatchesIntent(
	item: BridgeMainRenderPublicationItem,
	intent: BridgeMarkdownRenderIntent,
): boolean {
	return (
		item.type === 'file' &&
		item.bridgeMetadata.itemId === intent.sourceIdentity.fileId &&
		(item.version ?? 0) === intent.sourceIdentity.fileVersion &&
		item.bridgeMetadata.cacheKey === intent.contentCacheKey &&
		item.file.cacheKey === intent.contentCacheKey &&
		item.bridgeMetadata.displayPath === intent.sourcePath &&
		item.file.name === intent.sourcePath &&
		item.file.contents === intent.markdownText
	);
}

function bridgeMarkdownArticleMatchesBinding(
	article: BridgeMarkdownRenderedArticle,
	binding: BridgeMarkdownRenderBinding,
): boolean {
	const identity = requireReadyPresentation(binding.presentation).identity;
	return (
		article.dataset.bridgeMarkdownRequestId === identity.requestId &&
		article.dataset.bridgeMarkdownContentCacheKey === identity.contentCacheKey &&
		article.dataset.bridgeMarkdownContentHash === identity.contentHash &&
		article.dataset.bridgeMarkdownSourcePath === binding.intent.sourcePath &&
		article.dataset.bridgeMarkdownSourceId === identity.sourceIdentity.sourceId &&
		article.dataset.bridgeMarkdownSourceGeneration ===
			identity.sourceIdentity.sourceGeneration.toString() &&
		article.dataset.bridgeMarkdownFileId === identity.sourceIdentity.fileId &&
		article.dataset.bridgeMarkdownFileVersion === identity.sourceIdentity.fileVersion.toString()
	);
}

function requireReadyPresentation(
	presentation: BridgeMarkdownPresentationState,
): Extract<BridgeMarkdownPresentationState, { readonly status: 'ready' }> {
	if (presentation.status !== 'ready') {
		throw new Error('Expected a ready Markdown presentation after binding validation.');
	}
	return presentation;
}

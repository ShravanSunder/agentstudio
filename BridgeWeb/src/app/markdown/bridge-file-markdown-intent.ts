import type { BridgeFileViewerSelectedCodeViewItem } from '../../file-viewer/bridge-file-viewer-code-view-items.js';
import type { BridgeFileViewerDisplaySource } from '../../file-viewer/bridge-file-viewer-display-model.js';
import type { BridgeMarkdownRenderIntent } from './use-bridge-markdown-presentation.js';

export const bridgeMarkdownRenderMaxBytes = 512 * 1024;

export type BridgeFileMarkdownDecision =
	| { readonly kind: 'pierre' }
	| { readonly kind: 'loading' }
	| { readonly kind: 'render'; readonly intent: BridgeMarkdownRenderIntent };

export function resolveBridgeFileMarkdownIntent(props: {
	readonly displaySource: BridgeFileViewerDisplaySource | null;
	readonly openFileStatus: 'idle' | 'failed' | 'loading' | 'ready' | 'stale' | 'unavailable';
	readonly selectedCodeViewItem: BridgeFileViewerSelectedCodeViewItem | null;
	readonly selectedPath: string | null;
	readonly maxBytes?: number;
}): BridgeFileMarkdownDecision {
	if (
		props.selectedPath === null ||
		!selectedFileIsMarkdown({
			selectedCodeViewItem: props.selectedCodeViewItem,
			selectedPath: props.selectedPath,
		})
	) {
		return { kind: 'pierre' };
	}
	if (
		props.openFileStatus === 'loading' ||
		(props.openFileStatus === 'ready' && props.selectedCodeViewItem === null)
	) {
		return { kind: 'loading' };
	}
	if (
		props.openFileStatus !== 'ready' ||
		props.selectedCodeViewItem === null ||
		props.selectedCodeViewItem.bridgeMetadata.contentState !== 'hydrated' ||
		props.displaySource === null
	) {
		return { kind: 'pierre' };
	}
	const markdownText = props.selectedCodeViewItem.file.contents;
	if (
		new TextEncoder().encode(markdownText).byteLength >
		(props.maxBytes ?? bridgeMarkdownRenderMaxBytes)
	) {
		return { kind: 'pierre' };
	}
	const contentCacheKey = props.selectedCodeViewItem.bridgeMetadata.cacheKey;
	return {
		kind: 'render',
		intent: {
			sourceIdentity: {
				surface: 'file',
				sourceId: props.displaySource.sourceId,
				sourceGeneration: props.displaySource.generation,
				fileId: props.selectedCodeViewItem.bridgeMetadata.itemId,
				fileVersion: props.selectedCodeViewItem.version ?? 0,
			},
			sourcePath: props.selectedPath,
			contentCacheKey,
			contentHash: contentCacheKey,
			markdownText,
		},
	};
}

export function isMarkdownPath(path: string): boolean {
	return /\.md$/iu.test(path);
}

function selectedFileIsMarkdown(props: {
	readonly selectedCodeViewItem: BridgeFileViewerSelectedCodeViewItem | null;
	readonly selectedPath: string;
}): boolean {
	return (
		isMarkdownPath(props.selectedPath) ||
		props.selectedCodeViewItem?.file.lang?.trim().toLowerCase() === 'markdown'
	);
}

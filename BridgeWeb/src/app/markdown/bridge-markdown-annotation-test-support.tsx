import type { ReactElement } from 'react';

import type { BridgeFileViewerSelectedCodeViewItem } from '../../file-viewer/bridge-file-viewer-code-view-items.js';
import { BridgeMarkdownCanvas } from './bridge-markdown-canvas.js';
import type { BridgeMarkdownRenderIntent } from './use-bridge-markdown-presentation.js';
import { buildBridgeMarkdownRenderWorkerSuccessResponse } from './worker/bridge-markdown-render-worker-renderer.js';

export function fileItem(contents: string, version = 1): BridgeFileViewerSelectedCodeViewItem {
	const cacheKey = `plan:${version}`;
	return {
		id: 'file:plan',
		type: 'file',
		version,
		file: { name: 'plan.md', lang: 'markdown', cacheKey, contents },
		bridgeMetadata: {
			cacheKey,
			contentRoles: ['file'],
			contentState: 'hydrated',
			displayPath: 'plan.md',
			itemId: 'plan',
			lineCount: contents.split('\n').length,
			sourceDescriptorId: `plan-descriptor-${version}`,
		},
	};
}

export function fileIntent(item: BridgeFileViewerSelectedCodeViewItem): BridgeMarkdownRenderIntent {
	return {
		sourceIdentity: {
			surface: 'file',
			sourceId: 'worktree',
			sourceGeneration: 1,
			fileId: 'plan',
			fileVersion: item.version ?? 0,
		},
		contentCacheKey: item.bridgeMetadata.cacheKey,
		contentHash: item.bridgeMetadata.cacheKey,
		sourcePath: 'plan.md',
		markdownText: item.file.contents,
	};
}

export async function markdownCanvas(contents: string, version = 1): Promise<ReactElement> {
	const item = fileItem(contents, version);
	const intent = fileIntent(item);
	const response = await buildBridgeMarkdownRenderWorkerSuccessResponse({
		request: {
			...intent,
			schemaVersion: 1,
			method: 'markdown.render',
			requestId: `markdown-${version}`,
		},
	});
	return (
		<BridgeMarkdownCanvas
			isActive
			annotationSource={{ item }}
			retry={(): void => {}}
			presentationState={{
				status: 'ready',
				refresh: { kind: 'current' },
				identity: response,
				renderResult: response,
				sourcePath: 'plan.md',
			}}
			renderFulfillment={{
				intent,
				selectedItem: item,
				coordinator: { observePostRender: (): void => {}, reconcilePublication: (): void => {} },
			}}
		/>
	);
}

import {
	createBridgeMermaidRenderer,
	type BridgeMermaidRenderer,
} from './bridge-mermaid-renderer.js';
import type { BridgeMarkdownRenderWorkerClient } from './worker/bridge-markdown-render-worker-client.js';
import { createBridgeMarkdownRenderWebWorkerClient } from './worker/bridge-markdown-render-worker-transport.js';

export interface BridgeMarkdownRenderRuntime {
	readonly workerClient: BridgeMarkdownRenderWorkerClient | null;
	readonly mermaidRenderer: BridgeMermaidRenderer;
	readonly dispose: () => void;
}

export function createBridgeMarkdownRenderRuntime(): BridgeMarkdownRenderRuntime {
	const workerClient = createBridgeMarkdownRenderWebWorkerClient();
	return {
		workerClient,
		mermaidRenderer: createBridgeMermaidRenderer(),
		dispose: (): void => workerClient?.dispose(),
	};
}

export function createBridgeMarkdownRenderRuntimeWithClient(
	workerClient: BridgeMarkdownRenderWorkerClient | null,
): BridgeMarkdownRenderRuntime {
	return {
		workerClient,
		mermaidRenderer: createBridgeMermaidRenderer(),
		dispose: (): void => workerClient?.dispose(),
	};
}

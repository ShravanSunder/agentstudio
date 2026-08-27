import { existsSync, readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

import { describe, expect, test } from 'vitest';

describe('BridgeApp source structure', () => {
	test('routes active viewer mode updates through the comm worker instead of page-owned RPC', () => {
		const source = readSource('bridge-app.tsx');

		expect(source).not.toContain('createBridgeRPCClient');
		expect(source).not.toContain('sendCommandAndWait');
		expect(source).not.toContain("method: 'bridge.activeViewerMode.update'");
		expect(source).toContain('encodeBridgeWorkerActiveViewerModeUpdateCommand');
	});

	test('keeps packaged File product ownership out of the page and native intake backend', () => {
		const appSource = [
			readSource('bridge-app.tsx'),
			readSource('bridge-app-bootstrap.tsx'),
			readSource('bridge-app-file-viewer-mode.tsx'),
			readSource('bridge-app-protocol-router.tsx'),
		].join('\n');

		expect(sourceExists('bridge-app-native-worktree-file.ts')).toBe(false);
		expect(appSource).not.toContain('createBridgeAppNativeWorktreeFileBackend');
		expect(appSource).not.toContain('worktreeFileSurfaceTransport');
		expect(appSource).not.toContain("method: 'worktreeFileSurface.openSourceStream'");
		expect(appSource).not.toContain("method: 'worktreeFileSurface.requestFileDescriptor'");
		expect(appSource).not.toContain("fetch('agentstudio://rpc/");
	});

	test('discovers File authority and metadata through the worker-owned typed product transport', () => {
		const source = readSource('../core/comm-worker/bridge-comm-worker-product-controller.ts');

		expect(source).toContain("this.#productTransport.call('file.source.current', {})");
		expect(source).toContain(
			'this.#productTransport.subscribe(bridgeProductFileMetadataApplicationProtocol, options)',
		);
		expect(source).not.toContain("this.#productTransport.subscribe('file.metadata', options)");
	});

	test('keeps application metadata schemas and transforms behind registered protocols', () => {
		const sessionContracts = readSource('../core/comm-worker/bridge-product-session-contracts.ts');
		const subscriptionState = readSource(
			'../core/comm-worker/bridge-product-subscription-state.ts',
		);
		const accounting = readSource('../core/comm-worker/bridge-product-subscription-accounting.ts');
		const preflight = readSource(
			'../core/comm-worker/bridge-product-subscription-interest-preflight.ts',
		);
		const codec = readSource(
			'../core/comm-worker/bridge-product-subscription-interest-state-codec.ts',
		);

		expect(sessionContracts).not.toContain(
			'bridgeProductSubscriptionDataFrameSchema = z.discriminatedUnion',
		);
		expect(sessionContracts).not.toContain('bridgeProductSubscriptionOpenSchema');
		expect(sessionContracts).not.toContain('bridgeProductSubscriptionInterestDeltaSchema');
		expect(subscriptionState).not.toContain("case 'file.metadata'");
		expect(subscriptionState).not.toContain("case 'review.metadata'");
		expect(accounting).not.toContain('switch (delta.subscriptionKind)');
		expect(preflight).not.toContain("state.subscriptionKind === 'file.metadata'");
		expect(codec).not.toContain('bridgeProductSubscriptionKindTag');
	});

	test('mounts one pane runtime and compile-deletes the legacy page-owned dispatcher', () => {
		const source = readSource('bridge-app.tsx');

		expect(source).toContain("from '../core/comm-worker/bridge-pane-runtime.js'");
		expect(source).toContain('createBridgePaneRuntime(');
		expect(source).not.toContain('createBridgePaneRuntimeProtocolDispatcher');
		expect(source).not.toContain('createBridgeReviewRuntimeProtocolDispatcher');
		expect(source).not.toContain('getBridgePaneCommWorkerSession');
		expect(source).not.toContain('disposeBridgePaneCommWorkerSession');
	});

	test('keeps session-only pane bootstrap free of legacy Review payload carriers', () => {
		const source = readSource('../core/comm-worker/bridge-pane-runtime.ts');

		expect(source).not.toContain('bridgeCommWorkerBootstrapRequestSchema');
		expect(source).not.toContain('contentItems: []');
		expect(source).not.toContain('contentRequestDescriptors: []');
		expect(source).not.toContain('renderSemantics: []');
		expect(source).not.toContain('rows: []');
	});

	test('keeps annotation thread expansion inline under Pierre ownership', () => {
		const reviewModeSource = readSource('bridge-app-review-viewer-mode.tsx');
		const filePanelSource = readSource('../file-viewer/bridge-file-viewer-code-panel.tsx');
		const compactThreadSource = readSource(
			'../worktree-annotations/worktree-annotation-compact-thread.tsx',
		);
		const surfaceProviderSource = readSource(
			'../worktree-annotations/worktree-annotation-surface-provider.tsx',
		);
		const annotationHookSource = readSource(
			'../review-viewer/code-view/use-bridge-code-view-worktree-annotations.tsx',
		);
		const codeViewPanelSource = readSource('../review-viewer/code-view/bridge-code-view-panel.tsx');
		const codeViewFrameSource = readSource(
			'../review-viewer/code-view/bridge-code-view-panel-frame.tsx',
		);

		expect(reviewModeSource).not.toContain('WorktreeAnnotationThreadOverlayHost');
		expect(filePanelSource).not.toContain('WorktreeAnnotationThreadOverlayHost');
		expect(compactThreadSource).toContain('interaction.expandThread');
		expect(compactThreadSource).toContain('<WorktreeAnnotationNewMessageComposer');
		expect(compactThreadSource).not.toContain('<Popover');
		expect(compactThreadSource).not.toContain('<ScrollArea');
		expect(surfaceProviderSource).not.toContain('WorktreeAnnotationThreadOverlayHost');
		expect(annotationHookSource).not.toContain('WorktreeAnnotationThreadOverlayHost');
		expect(annotationHookSource).not.toContain('readonly overlay: ReactNode');
		expect(codeViewPanelSource).not.toContain('annotationOverlay=');
		expect(codeViewFrameSource).not.toContain('annotationOverlay');
	});
});

function readSource(relativePath: string): string {
	return readFileSync(fileURLToPath(new URL(relativePath, import.meta.url)), 'utf8');
}

function sourceExists(relativePath: string): boolean {
	return existsSync(fileURLToPath(new URL(relativePath, import.meta.url)));
}

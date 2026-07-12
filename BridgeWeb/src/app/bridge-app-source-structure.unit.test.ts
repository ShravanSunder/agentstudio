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
		expect(source).toContain("this.#productTransport.subscribe('file.metadata', options)");
	});
});

function readSource(relativePath: string): string {
	return readFileSync(fileURLToPath(new URL(relativePath, import.meta.url)), 'utf8');
}

function sourceExists(relativePath: string): boolean {
	return existsSync(fileURLToPath(new URL(relativePath, import.meta.url)));
}

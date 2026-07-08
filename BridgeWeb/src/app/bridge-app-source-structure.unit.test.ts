import { readFileSync } from 'node:fs';
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

	test('routes Worktree/File intake-ready through the comm worker instead of page-owned RPC', () => {
		const source = readSource('bridge-app-native-worktree-file.ts');

		expect(source).not.toContain('sendNativeBridgeIntakeReadyCommand');
		expect(source).not.toContain('method: bridgeIntakeReadyMethod');
		expect(source).not.toContain("protocolId: 'worktree-file'");
		expect(source).toContain('sendWorktreeFileIntakeReady');
	});

	test('routes Worktree/File open and descriptor requests through worker senders', () => {
		const source = readSource('bridge-app-native-worktree-file.ts');

		expect(source).not.toContain('fetchRPC');
		expect(source).not.toContain('rpcEndpointUrl');
		expect(source).not.toContain("method: 'worktreeFileSurface.openSourceStream'");
		expect(source).not.toContain("method: 'worktreeFileSurface.requestFileDescriptor'");
		expect(source).toContain('worktreeFileWorkerRpcTransport.sendOpenSourceStream');
		expect(source).toContain('worktreeFileWorkerRpcTransport.sendRequestDescriptor');
	});
});

function readSource(relativePath: string): string {
	return readFileSync(fileURLToPath(new URL(relativePath, import.meta.url)), 'utf8');
}

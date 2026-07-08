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
});

function readSource(relativePath: string): string {
	return readFileSync(fileURLToPath(new URL(relativePath, import.meta.url)), 'utf8');
}

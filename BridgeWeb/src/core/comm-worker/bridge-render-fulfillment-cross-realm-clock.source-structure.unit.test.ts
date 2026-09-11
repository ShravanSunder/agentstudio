import { readFileSync } from 'node:fs';

import { describe, expect, test } from 'vitest';

describe('Bridge render fulfillment cross-realm clock wiring', () => {
	test('uses the normalized absolute clock for every production receipt lease boundary', () => {
		// Arrange
		const coordinatorSource = readSource('./bridge-main-render-fulfillment-coordinator.ts');
		const registrySource = readSource('./bridge-worker-render-fulfillment-registry.ts');
		const runtimeProtocolSource = readSource('./bridge-comm-worker-runtime-protocol.ts');
		const storeSource = readSource('./bridge-comm-worker-store.ts');

		// Act / Assert
		expect(coordinatorSource).toContain(
			'props.nowMilliseconds ?? readBridgeCommWorkerAbsoluteNowMilliseconds',
		);
		expect(registrySource).toContain('props.now ?? readBridgeCommWorkerAbsoluteNowMilliseconds');
		expect(runtimeProtocolSource).toContain(
			'props.now ?? readBridgeCommWorkerAbsoluteNowMilliseconds',
		);
		expect(storeSource).toContain('...(props.now === undefined ? {} : { now: props.now })');
		expect(storeSource).not.toContain('now,\n\t\t\treceiptLeaseDurationMilliseconds');
	});
});

function readSource(relativePath: string): string {
	return readFileSync(new URL(relativePath, import.meta.url), 'utf8');
}

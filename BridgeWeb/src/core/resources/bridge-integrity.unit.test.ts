import { describe, expect, test } from 'vitest';

import { verifyBridgeResourceIntegrity } from './bridge-integrity.js';

describe('bridge resource integrity', () => {
	test('accepts whole-body resources whose bytes match the issued sha256 integrity', async () => {
		const data = new TextEncoder().encode('hello bridge');

		await expect(
			verifyBridgeResourceIntegrity({
				data,
				integrity: {
					algorithm: 'sha256',
					value: 'sha256:af967f619c7e16dae9cce287b0ac3e399b29721ee73c37536df35dfbaf5fd0cd',
				},
			}),
		).resolves.toEqual({ ok: true });
	});

	test('rejects tampered whole-body resources when integrity is issued', async () => {
		const data = new TextEncoder().encode('tampered bridge');

		await expect(
			verifyBridgeResourceIntegrity({
				data,
				integrity: {
					algorithm: 'sha256',
					value: 'sha256:3173778af72bee80065ddb3dc0fa2319fcaca233bdfd4591d1b3a4ca5115d5a9',
				},
			}),
		).resolves.toEqual({
			ok: false,
			reason: 'integrity_mismatch',
			actual: 'sha256:9d36310871ac939092426ea5d0484ff8a9fd98c00aa4a2a970b23c9c76eaf880',
		});
	});
});

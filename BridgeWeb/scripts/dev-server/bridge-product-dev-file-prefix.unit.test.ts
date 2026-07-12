import { Buffer } from 'node:buffer';
import { createHash } from 'node:crypto';

import { describe, expect, test } from 'vitest';

import { deriveBridgeProductDevFilePrefix } from './bridge-product-dev-file-prefix.js';

describe('Bridge product dev File prefix', () => {
	test('bounds content by lines without fabricating a partial line', () => {
		const sourceBytes = Buffer.from('a\nb\ntail', 'utf8');
		const prefix = deriveBridgeProductDevFilePrefix(sourceBytes, {
			maximumBytes: 64,
			maximumLines: 2,
		});

		expect(new TextDecoder().decode(prefix.bytes)).toBe('a\nb\n');
		expect(prefix).toMatchObject({
			didReachEnd: false,
			endsMidLine: false,
			endsWithNewline: true,
			isBinary: false,
			isValidUTF8: true,
			payloadLineCount: 2,
			truncationKind: 'lineLimit',
		});
		expect(prefix.sha256).toBe(sha256Hex(prefix.bytes));
	});

	test('backs up from a UTF-8 scalar split by the byte ceiling', () => {
		const sourceBytes = Buffer.from('a'.repeat(6) + '€b', 'utf8');
		const prefix = deriveBridgeProductDevFilePrefix(sourceBytes, {
			maximumBytes: 8,
			maximumLines: 10,
		});

		expect(new TextDecoder().decode(prefix.bytes)).toBe('a'.repeat(6));
		expect(prefix).toMatchObject({
			didReachEnd: false,
			endsMidLine: true,
			isValidUTF8: true,
			payloadLineCount: 1,
			truncationKind: 'byteLimit',
		});
	});

	test('classifies NUL and invalid UTF-8 without admitting content bytes', () => {
		const binary = deriveBridgeProductDevFilePrefix(Uint8Array.from([97, 0, 98]), {
			maximumBytes: 64,
			maximumLines: 10,
		});
		const invalid = deriveBridgeProductDevFilePrefix(Uint8Array.from([0xe0, 0x80, 0x61]), {
			maximumBytes: 64,
			maximumLines: 10,
		});

		expect(binary.isBinary).toBe(true);
		expect(invalid.isValidUTF8).toBe(false);
	});
});

function sha256Hex(bytes: Uint8Array): string {
	return createHash('sha256').update(bytes).digest('hex');
}

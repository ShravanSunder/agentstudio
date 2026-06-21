import { describe, expect, test } from 'vitest';

import {
	decodeBridgeWorktreeContentHandle,
	parseBridgeWorktreeContentRequest,
} from '../vite.config.js';

describe('BridgeWeb Vite worktree content route helpers', () => {
	test('rejects malformed percent-encoded content handles', () => {
		expect(decodeBridgeWorktreeContentHandle('/%E0%A4%A')).toBeNull();
	});

	test('rejects path-like content handles', () => {
		expect(decodeBridgeWorktreeContentHandle('/handle%2Fsecret')).toBeNull();
	});

	test('rejects missing content generation and revision query params', () => {
		const parsed = parseBridgeWorktreeContentRequest({
			contentUrl: new URL('/handle?generation=1', 'http://127.0.0.1'),
			handleId: 'handle',
		});

		expect(parsed).toBeNull();
	});

	test('rejects non-integer content generation and revision query params', () => {
		const parsed = parseBridgeWorktreeContentRequest({
			contentUrl: new URL('/handle?generation=1.5&revision=-1', 'http://127.0.0.1'),
			handleId: 'handle',
		});

		expect(parsed).toBeNull();
	});

	test('rejects duplicate content generation and revision query params', () => {
		const parsed = parseBridgeWorktreeContentRequest({
			contentUrl: new URL('/handle?generation=7&generation=8&revision=3', 'http://127.0.0.1'),
			handleId: 'handle',
		});

		expect(parsed).toBeNull();
	});

	test('rejects unexpected content resource query params', () => {
		const parsed = parseBridgeWorktreeContentRequest({
			contentUrl: new URL('/handle?generation=7&revision=3&path=secret', 'http://127.0.0.1'),
			handleId: 'handle',
		});

		expect(parsed).toBeNull();
	});

	test('parses valid content resource identity query params', () => {
		const parsed = parseBridgeWorktreeContentRequest({
			contentUrl: new URL('/handle?generation=7&revision=3', 'http://127.0.0.1'),
			handleId: 'handle',
		});

		expect(parsed).toEqual({
			handleId: 'handle',
			reviewGeneration: 7,
			revision: 3,
		});
	});
});

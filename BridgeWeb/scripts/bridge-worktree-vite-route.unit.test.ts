import { describe, expect, test } from 'vitest';

import {
	decodeBridgeWorktreeContentHandle,
	parseBridgeWorktreeFileContentRequest,
} from '../vite.config.js';

describe('BridgeWeb Vite worktree content route helpers', () => {
	test('rejects malformed percent-encoded content handles', () => {
		expect(decodeBridgeWorktreeContentHandle('/%E0%A4%A')).toBeNull();
	});

	test('rejects path-like content handles', () => {
		expect(decodeBridgeWorktreeContentHandle('/handle%2Fsecret')).toBeNull();
	});

	test('rejects missing content generation and cursor query params', () => {
		const parsed = parseBridgeWorktreeFileContentRequest({
			contentUrl: new URL('/descriptor?generation=1', 'http://127.0.0.1'),
			descriptorId: 'descriptor',
		});

		expect(parsed).toBeNull();
	});

	test('rejects non-integer content generation query params', () => {
		const parsed = parseBridgeWorktreeFileContentRequest({
			contentUrl: new URL('/descriptor?generation=1.5&cursor=cursor-1', 'http://127.0.0.1'),
			descriptorId: 'descriptor',
		});

		expect(parsed).toBeNull();
	});

	test('rejects duplicate content generation and cursor query params', () => {
		const parsed = parseBridgeWorktreeFileContentRequest({
			contentUrl: new URL(
				'/descriptor?generation=7&generation=8&cursor=cursor-1',
				'http://127.0.0.1',
			),
			descriptorId: 'descriptor',
		});

		expect(parsed).toBeNull();
	});

	test('rejects unexpected content resource query params', () => {
		const parsed = parseBridgeWorktreeFileContentRequest({
			contentUrl: new URL(
				'/descriptor?generation=7&cursor=cursor-1&path=secret',
				'http://127.0.0.1',
			),
			descriptorId: 'descriptor',
		});

		expect(parsed).toBeNull();
	});

	test('allows worktree scenario routing context on content resource requests', () => {
		const parsed = parseBridgeWorktreeFileContentRequest({
			contentUrl: new URL(
				'/descriptor?scenario=current-worktree&generation=7&cursor=cursor-1',
				'http://127.0.0.1',
			),
			descriptorId: 'descriptor',
		});

		expect(parsed).toEqual({
			descriptorId: 'descriptor',
			sourceCursor: 'cursor-1',
			subscriptionGeneration: 7,
		});
	});

	test('parses valid content resource identity query params', () => {
		const parsed = parseBridgeWorktreeFileContentRequest({
			contentUrl: new URL('/descriptor?generation=7&cursor=cursor-1', 'http://127.0.0.1'),
			descriptorId: 'descriptor',
		});

		expect(parsed).toEqual({
			descriptorId: 'descriptor',
			sourceCursor: 'cursor-1',
			subscriptionGeneration: 7,
		});
	});
});

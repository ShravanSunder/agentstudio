import { describe, expect, test } from 'vitest';

import {
	bridgeWorktreeDevProviderConfigCacheKey,
	decodeBridgeWorktreeContentHandle,
	parseBridgeWorktreeFileDescriptorRequest,
	parseBridgeWorktreeFileContentRequest,
} from '../vite.config.js';

describe('BridgeWeb Vite worktree content route helpers', () => {
	test('keys provider config caching by stable dev route context, not content identity', () => {
		const env = { BRIDGE_WEB_DEV_SCENARIO: undefined };

		expect(
			bridgeWorktreeDevProviderConfigCacheKey({
				env,
				requestUrl:
					'/__bridge-worktree/file-content/a?scenario=current-worktree&generation=1&cursor=cursor-1',
			}),
		).toBe(
			bridgeWorktreeDevProviderConfigCacheKey({
				env,
				requestUrl:
					'/__bridge-worktree/file-content/b?scenario=current-worktree&generation=2&cursor=cursor-2',
			}),
		);
		expect(
			bridgeWorktreeDevProviderConfigCacheKey({
				env,
				requestUrl:
					'/__bridge-worktree/file-content/a?scenario=current-worktree&generation=1&cursor=cursor-1',
			}),
		).not.toBe(
			bridgeWorktreeDevProviderConfigCacheKey({
				env,
				requestUrl: '/__bridge-worktree/file-content/a?scenario=other&generation=1&cursor=cursor-1',
			}),
		);
	});

	test('does not cache non-loopback absolute provider config requests', () => {
		expect(
			bridgeWorktreeDevProviderConfigCacheKey({
				env: {},
				requestUrl:
					'https://example.test/__bridge-worktree/file-content/a?scenario=current-worktree',
			}),
		).toBeNull();
	});

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

	test('parses valid descriptor demand identity query params', () => {
		const parsed = parseBridgeWorktreeFileDescriptorRequest({
			requestUrl:
				'/__bridge-worktree/file-descriptor?path=src%2Fapp.ts&generation=7&cursor=cursor-1',
		});

		expect(parsed).toEqual({
			path: 'src/app.ts',
			sourceCursor: 'cursor-1',
			subscriptionGeneration: 7,
		});
	});

	test('rejects descriptor demand requests without path, generation, or cursor', () => {
		expect(
			parseBridgeWorktreeFileDescriptorRequest({
				requestUrl: '/__bridge-worktree/file-descriptor?path=src%2Fapp.ts&generation=7',
			}),
		).toBeNull();
		expect(
			parseBridgeWorktreeFileDescriptorRequest({
				requestUrl: '/__bridge-worktree/file-descriptor?path=src%2Fapp.ts&cursor=cursor-1',
			}),
		).toBeNull();
		expect(
			parseBridgeWorktreeFileDescriptorRequest({
				requestUrl: '/__bridge-worktree/file-descriptor?generation=7&cursor=cursor-1',
			}),
		).toBeNull();
	});

	test('rejects duplicate or unexpected descriptor demand query params', () => {
		expect(
			parseBridgeWorktreeFileDescriptorRequest({
				requestUrl:
					'/__bridge-worktree/file-descriptor?path=src%2Fapp.ts&path=src%2Fother.ts&generation=7&cursor=cursor-1',
			}),
		).toBeNull();
		expect(
			parseBridgeWorktreeFileDescriptorRequest({
				requestUrl:
					'/__bridge-worktree/file-descriptor?path=src%2Fapp.ts&generation=7&cursor=cursor-1&descriptor=raw',
			}),
		).toBeNull();
	});
});

import { describe, expect, test } from 'vitest';

import {
	bridgeWorktreeDevFileContentRouteMatchesHandle,
	bridgeWorktreeDevFileContentRouteUsesOrigin,
	parseBridgeWorktreeDevReloadIntegerList,
	parseBridgeWorktreeDevReloadIntegerToken,
} from './bridge-worktree-dev-reload-diagnostics.js';

describe('bridge worktree dev reload diagnostics', () => {
	test('parses strict nonnegative integer lists', () => {
		expect(parseBridgeWorktreeDevReloadIntegerList({ label: 'sequences', text: '' })).toEqual([]);
		expect(parseBridgeWorktreeDevReloadIntegerList({ label: 'sequences', text: '1,2,3' })).toEqual([
			1, 2, 3,
		]);
	});

	test('rejects malformed integer tokens and comma lists', () => {
		for (const text of ['2x', '1e3', '2 ', '2,,3', '2,', ',2']) {
			expect(() => parseBridgeWorktreeDevReloadIntegerList({ label: 'sequences', text })).toThrow(
				/strict nonnegative integer/u,
			);
		}
		expect(() => parseBridgeWorktreeDevReloadIntegerToken({ label: 'count', token: '-1' })).toThrow(
			/strict nonnegative integer/u,
		);
	});

	test('matches file-content route URLs only on the expected dev-server origin', () => {
		const expectedOrigin = 'http://127.0.0.1:5173';
		const expectedUrl =
			'http://127.0.0.1:5173/__bridge-worktree/file-content/dev-file-1?scenario=current-worktree';

		expect(
			bridgeWorktreeDevFileContentRouteUsesOrigin({
				expectedOrigin,
				url: expectedUrl,
			}),
		).toBe(true);
		expect(
			bridgeWorktreeDevFileContentRouteMatchesHandle({
				expectedContentHandle: 'dev-file-1',
				expectedOrigin,
				url: expectedUrl,
			}),
		).toBe(true);
		expect(
			bridgeWorktreeDevFileContentRouteUsesOrigin({
				expectedOrigin,
				url: 'http://localhost:5173/__bridge-worktree/file-content/dev-file-1',
			}),
		).toBe(false);
		expect(
			bridgeWorktreeDevFileContentRouteMatchesHandle({
				expectedContentHandle: 'dev-file-1',
				expectedOrigin,
				url: 'http://evil.invalid/__bridge-worktree/file-content/dev-file-1',
			}),
		).toBe(false);
		expect(
			bridgeWorktreeDevFileContentRouteUsesOrigin({
				expectedOrigin,
				url: 'not a url',
			}),
		).toBe(false);
	});
});

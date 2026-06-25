import { describe, expect, test } from 'vitest';

import {
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
});

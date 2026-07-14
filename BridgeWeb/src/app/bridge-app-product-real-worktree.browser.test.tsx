import { describe, test } from 'vitest';

import { expectBridgeProductSourceCellCorrelation } from './bridge-app-product-source-cell.browser-test-support.js';

describe('Bridge product real-worktree source cell', () => {
	test('correlates selected File and Review live-git bytes through descriptor, request, readable DOM, and painted disposition', async () => {
		await expectBridgeProductSourceCellCorrelation({
			expectedOracleKind: 'gitObjectDatabase',
			expectedProjectName: 'VB-real-worktree',
			expectedSourceKind: 'liveGitWorktree',
		});
	});
});

import { describe, expect, test } from 'vitest';

import {
	bridgeFileViewerHasActiveCommentDraft,
	shouldAutoRefreshStaleOpenFile,
} from './bridge-file-viewer-stale-refresh-policy.js';

describe('file viewer stale refresh policy', () => {
	test('auto-refreshes silently when no comment draft is active', () => {
		expect(shouldAutoRefreshStaleOpenFile({ hasActiveCommentDraft: false })).toBe(true);
	});

	test('keeps the refresh prompt when a comment draft could be lost', () => {
		expect(shouldAutoRefreshStaleOpenFile({ hasActiveCommentDraft: true })).toBe(false);
	});

	test('comments are not integrated yet, so no surface reports a draft', () => {
		expect(bridgeFileViewerHasActiveCommentDraft).toBe(false);
	});
});

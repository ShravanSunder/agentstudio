import { describe, expect, test } from 'vitest';

import {
	bridgeFileViewerHasActiveCommentDraft,
	shouldSuppressStaleOpenFileNotice,
} from './bridge-file-viewer-stale-refresh-policy.js';

describe('file viewer stale refresh policy', () => {
	test('suppresses the stale prompt when no comment draft is active', () => {
		expect(shouldSuppressStaleOpenFileNotice({ hasActiveCommentDraft: false })).toBe(true);
	});

	test('keeps the refresh prompt when a comment draft could be lost', () => {
		expect(shouldSuppressStaleOpenFileNotice({ hasActiveCommentDraft: true })).toBe(false);
	});

	test('comments are not integrated yet, so no surface reports a draft', () => {
		expect(bridgeFileViewerHasActiveCommentDraft).toBe(false);
	});
});

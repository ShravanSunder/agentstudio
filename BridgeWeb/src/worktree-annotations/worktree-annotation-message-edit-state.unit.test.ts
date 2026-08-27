import { describe, expect, test } from 'vitest';

import { worktreeAnnotationMessageHasUnsavedChanges } from './worktree-annotation-message-edit-state.js';

describe('worktree annotation message edit state', () => {
	test('enables Save only while the current body differs from the saved body', () => {
		expect(worktreeAnnotationMessageHasUnsavedChanges('Saved body.', 'Saved body.')).toBe(false);
		expect(worktreeAnnotationMessageHasUnsavedChanges('Changed body.', 'Saved body.')).toBe(true);
		expect(worktreeAnnotationMessageHasUnsavedChanges('Saved body.', 'Saved body.')).toBe(false);
	});

	test('treats a never-saved non-empty draft as saveable', () => {
		expect(worktreeAnnotationMessageHasUnsavedChanges('', null)).toBe(false);
		expect(worktreeAnnotationMessageHasUnsavedChanges('Draft body.', null)).toBe(true);
	});
});

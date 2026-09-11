import { describe, expect, test } from 'vitest';

import {
	matchesWorktreeAnnotationActionShortcut,
	worktreeAnnotationActionSpec,
} from './worktree-annotation-action-spec.js';

describe('worktree annotation action specs', () => {
	test('keeps canonical display copy and shortcut hints in one descriptor', () => {
		expect(worktreeAnnotationActionSpec('replyToThread')).toMatchObject({
			accessibleName: 'Reply to annotation thread',
			shortcutKeycap: 'R',
			tooltip: 'Reply to annotation thread (R)',
		});
		expect(worktreeAnnotationActionSpec('editAnnotation')).toMatchObject({
			accessibleName: 'Edit annotation',
			shortcutKeycap: '⌃E',
			tooltip: 'Edit annotation (⌃E)',
		});
		expect(worktreeAnnotationActionSpec('saveAnnotation').tooltip).toBe('Save annotation (⌘↵)');
		expect(worktreeAnnotationActionSpec('expandThread', 3).accessibleName).toBe(
			'Expand 3 annotations',
		);
	});

	test.each([
		{ actionId: 'replyToThread' as const, ctrlKey: false, key: 'r' },
		{ actionId: 'replyToThread' as const, ctrlKey: true, key: 'r' },
		{ actionId: 'editAnnotation' as const, ctrlKey: true, key: 'e' },
	])('matches the accepted shortcut for $actionId', ({ actionId, ctrlKey, key }) => {
		expect(
			matchesWorktreeAnnotationActionShortcut(
				{ altKey: false, ctrlKey, key, metaKey: false, shiftKey: false },
				actionId,
			),
		).toBe(true);
	});

	test('does not bind plain E to annotation Edit', () => {
		expect(
			matchesWorktreeAnnotationActionShortcut(
				{ altKey: false, ctrlKey: false, key: 'e', metaKey: false, shiftKey: false },
				'editAnnotation',
			),
		).toBe(false);
	});

	test('does not steal modified system shortcuts', () => {
		expect(
			matchesWorktreeAnnotationActionShortcut(
				{ altKey: false, ctrlKey: false, key: 'r', metaKey: true, shiftKey: false },
				'replyToThread',
			),
		).toBe(false);
		expect(
			matchesWorktreeAnnotationActionShortcut(
				{ altKey: true, ctrlKey: false, key: 'e', metaKey: false, shiftKey: false },
				'editAnnotation',
			),
		).toBe(false);
	});
});

import { describe, expect, test } from 'vitest';

import {
	clearWorktreeAnnotationOutputSelection,
	createWorktreeAnnotationOutputSelection,
	selectAllEligibleWorktreeAnnotationOutput,
	selectedWorktreeAnnotationMessageIds,
	toggleWorktreeAnnotationOutputMessage,
	worktreeAnnotationOutputWireSelection,
} from './worktree-annotation-output-selection.js';

describe('worktree annotation output selection', () => {
	test('starts as an empty explicit selection and toggles individual messages explicitly', () => {
		const emptySelection = createWorktreeAnnotationOutputSelection();
		const selected = toggleWorktreeAnnotationOutputMessage(emptySelection, 'message-1', true);

		expect(emptySelection).toEqual({ kind: 'explicit', messageIds: new Set() });
		expect(selectedWorktreeAnnotationMessageIds(selected, ['message-1', 'message-2'])).toEqual([
			'message-1',
		]);
		expect(worktreeAnnotationOutputWireSelection(selected)).toEqual({
			kind: 'explicit',
			messageIds: ['message-1'],
		});
	});

	test('select all uses allEligible and tracks later deselections as exclusions', () => {
		const selectedAll = selectAllEligibleWorktreeAnnotationOutput();
		const excluded = toggleWorktreeAnnotationOutputMessage(selectedAll, 'message-2', false);

		expect(selectedWorktreeAnnotationMessageIds(excluded, ['message-1', 'message-2'])).toEqual([
			'message-1',
		]);
		expect(worktreeAnnotationOutputWireSelection(excluded)).toEqual({
			excludedMessageIds: ['message-2'],
			kind: 'allEligible',
		});
		expect(clearWorktreeAnnotationOutputSelection()).toEqual({
			kind: 'explicit',
			messageIds: new Set(),
		});
	});

	test('select all represents more than 64 eligible messages without enumerating them on the wire', () => {
		const eligibleMessageIds = Array.from(
			{ length: 65 },
			(_unused, index): string => `message-${index + 1}`,
		);
		const selectedAll = selectAllEligibleWorktreeAnnotationOutput();

		expect(selectedWorktreeAnnotationMessageIds(selectedAll, eligibleMessageIds)).toHaveLength(65);
		expect(worktreeAnnotationOutputWireSelection(selectedAll)).toEqual({
			excludedMessageIds: [],
			kind: 'allEligible',
		});
	});
});

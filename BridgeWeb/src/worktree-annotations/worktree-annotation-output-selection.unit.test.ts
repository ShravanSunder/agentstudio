import { describe, expect, test } from 'vitest';

import { bridgeProductWorktreeAnnotationOperationSchema } from '../core/comm-worker/bridge-product-call-contracts.js';
import {
	clearWorktreeAnnotationOutputSelection,
	createWorktreeAnnotationOutputSelection,
	selectAllEligibleWorktreeAnnotationOutput,
	selectedWorktreeAnnotationMessageIds,
	toggleWorktreeAnnotationOutputMessage,
	worktreeAnnotationOutputTransferOperations,
} from './worktree-annotation-output-selection.js';

describe('worktree annotation output selection', () => {
	test('chunks the middle 65 of 130 eligible messages into one total explicit transfer', () => {
		const eligibleMessageIds = Array.from(
			{ length: 130 },
			(_value, index): string => `00000000-0000-7000-8000-${String(index + 1).padStart(12, '0')}`,
		);
		const middleSixtyFive = eligibleMessageIds.slice(32, 97);

		const operations = worktreeAnnotationOutputTransferOperations({
			outputKind: 'clipboardMarkdown',
			selection: { kind: 'explicit', messageIds: new Set(middleSixtyFive) },
			sessionId: '00000000-0000-7000-8000-000000000001',
			transferId: 'transfer-middle-65',
		});

		expect(operations.map((operation) => operation.kind)).toEqual([
			'output.selection.begin',
			'output.selection.chunk',
			'output.selection.chunk',
			'output.selection.commit',
		]);
		expect(
			operations.every(
				(operation) => bridgeProductWorktreeAnnotationOperationSchema.safeParse(operation).success,
			),
		).toBe(true);
		expect(operations[1]).toMatchObject({ messageIds: middleSixtyFive.slice(0, 64), ordinal: 0 });
		expect(operations[2]).toMatchObject({ messageIds: middleSixtyFive.slice(64), ordinal: 1 });
	});
	test('starts as an empty explicit selection and toggles individual messages explicitly', () => {
		const emptySelection = createWorktreeAnnotationOutputSelection();
		const selected = toggleWorktreeAnnotationOutputMessage(emptySelection, 'message-1', true);

		expect(emptySelection).toEqual({ kind: 'explicit', messageIds: new Set() });
		expect(selectedWorktreeAnnotationMessageIds(selected, ['message-1', 'message-2'])).toEqual([
			'message-1',
		]);
	});

	test('select all uses allEligible and tracks later deselections as exclusions', () => {
		const selectedAll = selectAllEligibleWorktreeAnnotationOutput();
		const excluded = toggleWorktreeAnnotationOutputMessage(selectedAll, 'message-2', false);

		expect(selectedWorktreeAnnotationMessageIds(excluded, ['message-1', 'message-2'])).toEqual([
			'message-1',
		]);
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
		expect(
			worktreeAnnotationOutputTransferOperations({
				outputKind: 'jsonFile',
				selection: selectedAll,
				sessionId: '00000000-0000-7000-8000-000000000001',
				transferId: 'transfer-all',
			}).map((operation) => operation.kind),
		).toEqual(['output.selection.begin', 'output.selection.commit']);
	});
});

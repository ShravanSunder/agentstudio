import { describe, expect, test } from 'vitest';

import {
	createBridgeViewerSearchState,
	transitionBridgeViewerSearchState,
	type BridgeViewerSearchAction,
	type BridgeViewerSearchState,
} from './bridge-viewer-search-state.js';

describe('Bridge viewer Search state', () => {
	test('opens without changing the current criteria', () => {
		const closedState = acceptedState(createBridgeViewerSearchState(), {
			type: 'change_query',
			query: 'Sources',
		});
		const transition = transitionBridgeViewerSearchState(
			{ ...closedState, isOpen: false },
			{ type: 'open' },
		);

		expect(transition.rejectionReason).toBeNull();
		expect(transition.state).toEqual({ ...closedState, isOpen: true });
	});

	test('ordinary close clears entered and accepted queries and error while preserving mode', () => {
		const regexState = acceptedState(createBridgeViewerSearchState(), {
			type: 'change_mode',
			mode: 'regex',
		});
		const invalidState = acceptedState(regexState, {
			type: 'change_query',
			query: '[',
		});
		const transition = transitionBridgeViewerSearchState(invalidState, { type: 'close' });

		expect(transition).toEqual({
			state: {
				isOpen: false,
				enteredCriteria: { query: '', mode: 'regex' },
				acceptedCriteria: { query: '', mode: 'regex' },
				error: null,
			},
			rejectionReason: null,
		});
	});

	test('reset closes and clears Search and restores text mode', () => {
		const regexState = acceptedState(createBridgeViewerSearchState(), {
			type: 'change_mode',
			mode: 'regex',
		});
		const populatedState = acceptedState(regexState, {
			type: 'change_query',
			query: '\\.swift$',
		});

		expect(transitionBridgeViewerSearchState(populatedState, { type: 'reset' })).toEqual({
			state: createBridgeViewerSearchState(),
			rejectionReason: null,
		});
	});

	test('admits 4,096 UTF-16 code units and atomically rejects 4,097', () => {
		const admittedQuery = 'a'.repeat(4_096);
		const admittedTransition = transitionBridgeViewerSearchState(createBridgeViewerSearchState(), {
			type: 'change_query',
			query: admittedQuery,
		});
		const rejectedTransition = transitionBridgeViewerSearchState(admittedTransition.state, {
			type: 'change_query',
			query: `${admittedQuery}b`,
		});

		expect(admittedTransition.rejectionReason).toBeNull();
		expect(admittedTransition.state.enteredCriteria.query).toBe(admittedQuery);
		expect(admittedTransition.state.acceptedCriteria.query).toBe(admittedQuery);
		expect(rejectedTransition.state).toBe(admittedTransition.state);
		expect(rejectedTransition.state).toEqual(admittedTransition.state);
		expect(rejectedTransition.rejectionReason).toBe('search_query_too_long');
	});

	test('oversized input preserves an existing invalid-regex validation state', () => {
		const regexState = acceptedState(createBridgeViewerSearchState(), {
			type: 'change_mode',
			mode: 'regex',
		});
		const invalidState = acceptedState(regexState, {
			type: 'change_query',
			query: '[',
		});
		const rejectedTransition = transitionBridgeViewerSearchState(invalidState, {
			type: 'change_query',
			query: 'a'.repeat(4_097),
		});

		expect(rejectedTransition.state).toBe(invalidState);
		expect(rejectedTransition.state).toEqual({
			...invalidState,
			error: 'invalid_regex',
		});
		expect(rejectedTransition.rejectionReason).toBe('search_query_too_long');
	});

	test('counts non-BMP characters as two UTF-16 code units', () => {
		const admittedQuery = '🧭'.repeat(2_048);
		const admittedTransition = transitionBridgeViewerSearchState(createBridgeViewerSearchState(), {
			type: 'change_query',
			query: admittedQuery,
		});
		const rejectedTransition = transitionBridgeViewerSearchState(admittedTransition.state, {
			type: 'change_query',
			query: `${admittedQuery}a`,
		});

		expect(admittedTransition.state.acceptedCriteria.query).toBe(admittedQuery);
		expect(rejectedTransition.state).toBe(admittedTransition.state);
		expect(rejectedTransition.rejectionReason).toBe('search_query_too_long');
	});

	test('invalid regex updates entered criteria but preserves the last accepted criteria', () => {
		const textState = acceptedState(createBridgeViewerSearchState(), {
			type: 'change_query',
			query: 'Sources',
		});
		const regexState = acceptedState(textState, { type: 'change_mode', mode: 'regex' });
		const transition = transitionBridgeViewerSearchState(regexState, {
			type: 'change_query',
			query: '[',
		});

		expect(transition.rejectionReason).toBeNull();
		expect(transition.state.enteredCriteria).toEqual({ query: '[', mode: 'regex' });
		expect(transition.state.acceptedCriteria).toEqual({ query: 'Sources', mode: 'regex' });
		expect(transition.state.error).toBe('invalid_regex');
	});

	test('valid input after an invalid regex becomes the accepted criteria', () => {
		const regexState = acceptedState(createBridgeViewerSearchState(), {
			type: 'change_mode',
			mode: 'regex',
		});
		const invalidState = acceptedState(regexState, { type: 'change_query', query: '[' });
		const transition = transitionBridgeViewerSearchState(invalidState, {
			type: 'change_query',
			query: '\\.swift$',
		});

		expect(transition.rejectionReason).toBeNull();
		expect(transition.state.enteredCriteria).toEqual({ query: '\\.swift$', mode: 'regex' });
		expect(transition.state.acceptedCriteria).toEqual({ query: '\\.swift$', mode: 'regex' });
		expect(transition.state.error).toBeNull();
	});

	test('switching an invalid regex to text recovers and accepts the entered query', () => {
		const regexState = acceptedState(createBridgeViewerSearchState(), {
			type: 'change_mode',
			mode: 'regex',
		});
		const invalidState = acceptedState(regexState, { type: 'change_query', query: '[' });
		const transition = transitionBridgeViewerSearchState(invalidState, {
			type: 'change_mode',
			mode: 'text',
		});

		expect(transition.rejectionReason).toBeNull();
		expect(transition.state.enteredCriteria).toEqual({ query: '[', mode: 'text' });
		expect(transition.state.acceptedCriteria).toEqual({ query: '[', mode: 'text' });
		expect(transition.state.error).toBeNull();
	});

	test('admits a complete semantic Search candidate in one transition', () => {
		const transition = transitionBridgeViewerSearchState(createBridgeViewerSearchState(), {
			type: 'apply_semantic_criteria',
			criteria: { query: '^Sources/.+\\.swift$', mode: 'regex' },
		});

		expect(transition).toEqual({
			state: {
				isOpen: true,
				enteredCriteria: { query: '^Sources/.+\\.swift$', mode: 'regex' },
				acceptedCriteria: { query: '^Sources/.+\\.swift$', mode: 'regex' },
				error: null,
			},
			rejectionReason: null,
		});
	});

	test('rejects a complete oversized semantic Search candidate without opening', () => {
		const initialState = createBridgeViewerSearchState();
		const transition = transitionBridgeViewerSearchState(initialState, {
			type: 'apply_semantic_criteria',
			criteria: { query: 'x'.repeat(4_097), mode: 'regex' },
		});

		expect(transition.state).toBe(initialState);
		expect(transition.rejectionReason).toBe('search_query_too_long');
	});

	test('Clear with text stays open and clears criteria', () => {
		const openState = acceptedState(createBridgeViewerSearchState(), { type: 'open' });
		const populatedState = acceptedState(openState, {
			type: 'change_query',
			query: 'Sources',
		});

		expect(transitionBridgeViewerSearchState(populatedState, { type: 'clear_or_close' })).toEqual({
			state: {
				isOpen: true,
				enteredCriteria: { query: '', mode: 'text' },
				acceptedCriteria: { query: '', mode: 'text' },
				error: null,
			},
			rejectionReason: null,
		});
	});

	test('Clear with an empty entered query closes Search', () => {
		const openState = acceptedState(createBridgeViewerSearchState(), { type: 'open' });

		expect(transitionBridgeViewerSearchState(openState, { type: 'clear_or_close' })).toEqual({
			state: createBridgeViewerSearchState(),
			rejectionReason: null,
		});
	});
});

function acceptedState(
	state: BridgeViewerSearchState,
	action: BridgeViewerSearchAction,
): BridgeViewerSearchState {
	const transition = transitionBridgeViewerSearchState(state, action);
	expect(transition.rejectionReason).toBeNull();
	return transition.state;
}

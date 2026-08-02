import {
	bridgeFileTreeSearchTextMaximumLength,
	compileBridgeFileTreeSearchPattern,
	type BridgeFileTreeSearchMode,
} from '../core/models/bridge-file-tree-search.js';

export type BridgeViewerSearchError = 'invalid_regex';

export type BridgeViewerSearchRejectionReason = 'search_query_too_long';

export interface BridgeViewerSearchCriteria {
	readonly query: string;
	readonly mode: BridgeFileTreeSearchMode;
}

export interface BridgeViewerSearchState {
	readonly isOpen: boolean;
	readonly enteredCriteria: BridgeViewerSearchCriteria;
	readonly acceptedCriteria: BridgeViewerSearchCriteria;
	readonly error: BridgeViewerSearchError | null;
}

export type BridgeViewerSearchAction =
	| { readonly type: 'open' }
	| { readonly type: 'close' }
	| { readonly type: 'reset' }
	| { readonly type: 'clear_or_close' }
	| { readonly type: 'change_query'; readonly query: string }
	| { readonly type: 'change_mode'; readonly mode: BridgeFileTreeSearchMode }
	| { readonly type: 'apply_semantic_criteria'; readonly criteria: BridgeViewerSearchCriteria };

export interface BridgeViewerSearchTransition {
	readonly state: BridgeViewerSearchState;
	readonly rejectionReason: BridgeViewerSearchRejectionReason | null;
}

export function createBridgeViewerSearchState(): BridgeViewerSearchState {
	const emptyCriteria = createSearchCriteria('', 'text');
	return {
		isOpen: false,
		enteredCriteria: emptyCriteria,
		acceptedCriteria: emptyCriteria,
		error: null,
	};
}

export function transitionBridgeViewerSearchState(
	state: BridgeViewerSearchState,
	action: BridgeViewerSearchAction,
): BridgeViewerSearchTransition {
	switch (action.type) {
		case 'open':
			return acceptedTransition({ ...state, isOpen: true });
		case 'close':
			return acceptedTransition(closeSearch(state.enteredCriteria.mode));
		case 'reset':
			return acceptedTransition(createBridgeViewerSearchState());
		case 'clear_or_close':
			return acceptedTransition(
				state.enteredCriteria.query.length === 0
					? closeSearch(state.enteredCriteria.mode)
					: clearSearch(state.enteredCriteria.mode),
			);
		case 'change_query':
			return admitSearchCriteria(state, {
				query: action.query,
				mode: state.enteredCriteria.mode,
			});
		case 'change_mode':
			return admitSearchCriteria(state, {
				query: state.enteredCriteria.query,
				mode: action.mode,
			});
		case 'apply_semantic_criteria': {
			const transition = admitSearchCriteria(state, action.criteria);
			return transition.rejectionReason === null
				? acceptedTransition({ ...transition.state, isOpen: true })
				: transition;
		}
	}
	return assertNeverBridgeViewerSearchAction(action);
}

function admitSearchCriteria(
	state: BridgeViewerSearchState,
	enteredCriteria: BridgeViewerSearchCriteria,
): BridgeViewerSearchTransition {
	if (enteredCriteria.query.length > bridgeFileTreeSearchTextMaximumLength) {
		return { state, rejectionReason: 'search_query_too_long' };
	}

	const compilation = compileBridgeFileTreeSearchPattern({
		searchMode: enteredCriteria.mode,
		searchText: enteredCriteria.query,
	});
	if (compilation.searchError !== null) {
		return acceptedTransition({
			...state,
			enteredCriteria,
			error: 'invalid_regex',
		});
	}

	return acceptedTransition({
		...state,
		enteredCriteria,
		acceptedCriteria: enteredCriteria,
		error: null,
	});
}

function acceptedTransition(state: BridgeViewerSearchState): BridgeViewerSearchTransition {
	return { state, rejectionReason: null };
}

function clearSearch(mode: BridgeFileTreeSearchMode): BridgeViewerSearchState {
	const emptyCriteria = createSearchCriteria('', mode);
	return {
		isOpen: true,
		enteredCriteria: emptyCriteria,
		acceptedCriteria: emptyCriteria,
		error: null,
	};
}

function closeSearch(mode: BridgeFileTreeSearchMode): BridgeViewerSearchState {
	return { ...clearSearch(mode), isOpen: false };
}

function createSearchCriteria(
	query: string,
	mode: BridgeFileTreeSearchMode,
): BridgeViewerSearchCriteria {
	return { query, mode };
}

function assertNeverBridgeViewerSearchAction(_action: never): never {
	throw new Error('Unexpected Bridge viewer Search action');
}

export type BridgeFileTreeSearchMode = 'regex' | 'text';

export const bridgeFileTreeSearchTextMaximumLength = 4_096;

export interface BridgeFileTreeSearchPatternCompilation {
	readonly pattern: RegExp | null;
	readonly searchError: string | null;
}

export function compileBridgeFileTreeSearchPattern(props: {
	readonly searchMode: BridgeFileTreeSearchMode;
	readonly searchText: string;
}): BridgeFileTreeSearchPatternCompilation {
	const searchText = props.searchText.trim();
	if (searchText.length === 0) return { pattern: null, searchError: null };
	try {
		return {
			pattern: new RegExp(
				props.searchMode === 'text' ? escapeRegularExpression(searchText) : searchText,
				'iu',
			),
			searchError: null,
		};
	} catch {
		return {
			pattern: null,
			searchError: 'Invalid regex',
		};
	}
}

function escapeRegularExpression(value: string): string {
	return value.replace(/[.*+?^${}()|[\]\\]/gu, '\\$&');
}

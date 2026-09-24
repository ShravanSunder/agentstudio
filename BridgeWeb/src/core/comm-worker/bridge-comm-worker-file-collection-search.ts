import {
	compileBridgeFileTreeSearchPattern,
	type BridgeFileTreeSearchMode,
} from '../models/bridge-file-tree-search.js';
import type { BridgeProductFileMemberGroup } from './bridge-product-file-member-group-contracts.js';

/** The row fields a collection search reads. */
export interface BridgeFileCollectionSearchRow {
	readonly documentLocation: string | null;
	readonly fileId: string | null;
	readonly isDirectory: boolean;
	readonly path: string;
	readonly projectionIndex: number;
}

/** Which part of the receiving collection a search covers. */
export type BridgeFileCollectionSearchScope =
	| { readonly kind: 'all' }
	| { readonly kind: 'member'; readonly worktreeId: string }
	| { readonly kind: 'openedDocuments' };

export interface BridgeFileCollectionSearchCriteria {
	readonly limit: number;
	readonly scope: BridgeFileCollectionSearchScope;
	readonly searchMode: BridgeFileTreeSearchMode;
	readonly searchText: string;
}

export interface BridgeFileCollectionSearchMatch {
	readonly displayPath: string;
	/** Set for an individually opened document outside every member. */
	readonly documentLocation: string | null;
	readonly fileId: string;
	/** The member whose tree lists the file; null for an opened document. */
	readonly memberWorktreeId: string | null;
}

export type BridgeFileCollectionSearchResult =
	| {
			readonly kind: 'matches';
			readonly matches: readonly BridgeFileCollectionSearchMatch[];
			readonly totalMatchCount: number;
			readonly truncated: boolean;
	  }
	| { readonly kind: 'invalidPattern'; readonly searchError: string };

/**
 * Search the receiving collection's listed files with the tree search's own
 * matcher: a row matches on its collection path or, for an opened document,
 * on its real location. Directories never match. Results keep collection
 * order, one per listed file, and name the member or opened document each
 * belongs to. This reads the rows only; it never changes the viewer's query.
 */
export function searchBridgeFileCollection(props: {
	readonly criteria: BridgeFileCollectionSearchCriteria;
	readonly memberGroups: readonly BridgeProductFileMemberGroup[];
	readonly rows: Iterable<BridgeFileCollectionSearchRow>;
}): BridgeFileCollectionSearchResult {
	const compilation = compileBridgeFileTreeSearchPattern({
		searchMode: props.criteria.searchMode,
		searchText: props.criteria.searchText,
	});
	if (compilation.searchError !== null) {
		return { kind: 'invalidPattern', searchError: compilation.searchError };
	}
	const pattern = compilation.pattern;
	const matches: BridgeFileCollectionSearchMatch[] = [];
	for (const row of [...props.rows].toSorted(
		(left, right) => left.projectionIndex - right.projectionIndex,
	)) {
		if (row.isDirectory || row.fileId === null) continue;
		const memberWorktreeId =
			row.documentLocation === null ? memberWorktreeIdForPath(props.memberGroups, row.path) : null;
		if (!rowIsInScope(props.criteria.scope, row, memberWorktreeId)) continue;
		if (pattern !== null && !rowMatches(row, pattern)) continue;
		matches.push({
			displayPath: row.path,
			documentLocation: row.documentLocation,
			fileId: row.fileId,
			memberWorktreeId,
		});
	}
	return {
		kind: 'matches',
		matches: matches.slice(0, props.criteria.limit),
		totalMatchCount: matches.length,
		truncated: matches.length > props.criteria.limit,
	};
}

function rowMatches(row: BridgeFileCollectionSearchRow, pattern: RegExp): boolean {
	if (pattern.test(row.path)) return true;
	return row.documentLocation !== null && pattern.test(row.documentLocation);
}

function rowIsInScope(
	scope: BridgeFileCollectionSearchScope,
	row: BridgeFileCollectionSearchRow,
	memberWorktreeId: string | null,
): boolean {
	if (scope.kind === 'all') return true;
	if (scope.kind === 'openedDocuments') return row.documentLocation !== null;
	return (
		memberWorktreeId !== null && memberWorktreeId.toLowerCase() === scope.worktreeId.toLowerCase()
	);
}

/** The member whose group directory lists `path`; nested members own their own files. */
function memberWorktreeIdForPath(
	memberGroups: readonly BridgeProductFileMemberGroup[],
	path: string,
): string | null {
	for (const group of memberGroups) {
		if (!path.startsWith(`${group.groupPath}/`)) continue;
		const relativePath = path.slice(group.groupPath.length + 1);
		const isNested = group.nestedMemberRelativeRoots.some(
			(root) => relativePath === root || relativePath.startsWith(`${root}/`),
		);
		return isNested ? null : group.worktreeId;
	}
	return null;
}

import { describe, expect, test } from 'vitest';

import {
	searchBridgeFileCollection,
	type BridgeFileCollectionSearchCriteria,
	type BridgeFileCollectionSearchRow,
} from './bridge-comm-worker-file-collection-search.js';
import type { BridgeProductFileMemberGroup } from './bridge-product-file-member-group-contracts.js';

const frontendWorktreeId = '0198f3a2-0000-7000-8000-00000000000a';
const backendWorktreeId = '0198f3a2-0000-7000-8000-00000000000b';

const memberGroups: readonly BridgeProductFileMemberGroup[] = [
	{
		groupPath: 'app',
		identityPrefix: 'm0000000000aa.',
		nestedMemberRelativeRoots: [],
		worktreeId: frontendWorktreeId,
	},
	{
		groupPath: 'app (2)',
		identityPrefix: 'm0000000000bb.',
		nestedMemberRelativeRoots: [],
		worktreeId: backendWorktreeId,
	},
];

let projectionIndex = 0;
function row(
	path: string,
	props: Partial<BridgeFileCollectionSearchRow> = {},
): BridgeFileCollectionSearchRow {
	projectionIndex += 1;
	return {
		documentLocation: null,
		fileId: `file-${path}`,
		isDirectory: false,
		path,
		projectionIndex,
		...props,
	};
}

const rows: readonly BridgeFileCollectionSearchRow[] = [
	row('app', { fileId: null, isDirectory: true }),
	row('app/src/index.ts'),
	row('app/src/plan.md'),
	row('app (2)/src/index.ts'),
	row('Open Files/plan.md', { documentLocation: '/Users/me/notes/plan.md' }),
];

function criteria(
	overrides: Partial<BridgeFileCollectionSearchCriteria> = {},
): BridgeFileCollectionSearchCriteria {
	return { limit: 50, scope: { kind: 'all' }, searchMode: 'text', searchText: '', ...overrides };
}

describe('searchBridgeFileCollection', () => {
	test('searches every member and opened document, naming what each match belongs to', () => {
		// Act
		const result = searchBridgeFileCollection({
			criteria: criteria({ searchText: 'plan' }),
			memberGroups,
			rows,
		});

		// Assert
		expect(result).toEqual({
			kind: 'matches',
			matches: [
				{
					displayPath: 'app/src/plan.md',
					documentLocation: null,
					fileId: 'file-app/src/plan.md',
					memberWorktreeId: frontendWorktreeId,
				},
				{
					displayPath: 'Open Files/plan.md',
					documentLocation: '/Users/me/notes/plan.md',
					fileId: 'file-Open Files/plan.md',
					memberWorktreeId: null,
				},
			],
			totalMatchCount: 2,
			truncated: false,
		});
	});

	test('keeps equal relative paths of two members distinct', () => {
		// Act
		const result = searchBridgeFileCollection({
			criteria: criteria({ searchText: 'src/index.ts' }),
			memberGroups,
			rows,
		});

		// Assert
		expect(
			result.kind === 'matches' ? result.matches.map((match) => match.memberWorktreeId) : [],
		).toEqual([frontendWorktreeId, backendWorktreeId]);
	});

	test('an opened document matches on its real location', () => {
		// Act
		const result = searchBridgeFileCollection({
			criteria: criteria({ searchText: 'notes/' }),
			memberGroups,
			rows,
		});

		// Assert
		expect(
			result.kind === 'matches' ? result.matches.map((match) => match.displayPath) : [],
		).toEqual(['Open Files/plan.md']);
	});

	test('narrows to one member or to opened documents without redefining membership', () => {
		// Act
		const member = searchBridgeFileCollection({
			criteria: criteria({
				scope: { kind: 'member', worktreeId: backendWorktreeId.toUpperCase() },
			}),
			memberGroups,
			rows,
		});
		const opened = searchBridgeFileCollection({
			criteria: criteria({ scope: { kind: 'openedDocuments' } }),
			memberGroups,
			rows,
		});

		// Assert
		expect(
			member.kind === 'matches' ? member.matches.map((match) => match.displayPath) : [],
		).toEqual(['app (2)/src/index.ts']);
		expect(
			opened.kind === 'matches' ? opened.matches.map((match) => match.displayPath) : [],
		).toEqual(['Open Files/plan.md']);
	});

	test('reports the total and truncation beyond the limit, in collection order', () => {
		// Act
		const result = searchBridgeFileCollection({
			criteria: criteria({ limit: 2, searchText: '' }),
			memberGroups,
			rows,
		});

		// Assert
		expect(result).toMatchObject({ kind: 'matches', totalMatchCount: 4, truncated: true });
		expect(
			result.kind === 'matches' ? result.matches.map((match) => match.displayPath) : [],
		).toEqual(['app/src/index.ts', 'app/src/plan.md']);
	});

	test('an invalid regex is reported, not treated as no matches', () => {
		// Act
		const result = searchBridgeFileCollection({
			criteria: criteria({ searchMode: 'regex', searchText: '(' }),
			memberGroups,
			rows,
		});

		// Assert
		expect(result).toEqual({ kind: 'invalidPattern', searchError: 'Invalid regex' });
	});
});

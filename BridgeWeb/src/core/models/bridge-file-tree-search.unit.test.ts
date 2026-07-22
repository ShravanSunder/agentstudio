import { describe, expect, test } from 'vitest';

import { compileBridgeFileTreeSearchPattern } from './bridge-file-tree-search.js';

describe('Bridge file tree search', () => {
	test('compiles trimmed case-insensitive Unicode text and regex patterns', () => {
		const text = compileBridgeFileTreeSearchPattern({
			searchMode: 'text',
			searchText: '  CAFÉ.  ',
		});
		const regex = compileBridgeFileTreeSearchPattern({
			searchMode: 'regex',
			searchText: ' \\.md$ ',
		});

		expect(text).toMatchObject({ searchError: null });
		expect(text.pattern?.test('docs/café.md')).toBe(true);
		expect(text.pattern?.test('docs/cafés.md')).toBe(false);
		expect(regex).toMatchObject({ searchError: null });
		expect(regex.pattern?.test('README.MD')).toBe(true);
	});

	test('returns stable empty and invalid-regex result shapes', () => {
		expect(compileBridgeFileTreeSearchPattern({ searchMode: 'text', searchText: '   ' })).toEqual({
			pattern: null,
			searchError: null,
		});

		const invalid = compileBridgeFileTreeSearchPattern({ searchMode: 'regex', searchText: '[' });
		expect(invalid.pattern).toBeNull();
		expect(invalid.searchError).toContain('regular expression');
	});
});

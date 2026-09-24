import { describe, expect, test } from 'vitest';

import type {
	BridgeProductFileMemberGroup,
	BridgeProductFileOpenedDocumentEntry,
} from '../core/comm-worker/bridge-product-file-member-group-contracts.js';
import {
	fileCollectionDescriptorIdentity,
	fileCollectionDisplayPath,
	fileCollectionOpenedDocumentSourceLocation,
} from './bridge-file-collection-display-path.js';

const frontendWorktreeId = '0198f3a2-0000-7000-8000-00000000000a';
const backendWorktreeId = '0198f3a2-0000-7000-8000-00000000000b';
const nestedWorktreeId = '0198f3a2-0000-7000-8000-00000000000c';

const memberGroups: readonly BridgeProductFileMemberGroup[] = [
	{
		groupPath: 'app',
		identityPrefix: 'm0000000000aa.',
		nestedMemberRelativeRoots: ['vendor/lib'],
		worktreeId: frontendWorktreeId,
	},
	{
		groupPath: 'app (2)',
		identityPrefix: 'm0000000000bb.',
		nestedMemberRelativeRoots: [],
		worktreeId: backendWorktreeId,
	},
	{
		groupPath: 'lib',
		identityPrefix: 'm0000000000cc.',
		nestedMemberRelativeRoots: [],
		worktreeId: nestedWorktreeId,
	},
];

describe('fileCollectionDisplayPath', () => {
	test('maps equal relative paths in two members to each member own display key', () => {
		// Act
		const frontendPath = fileCollectionDisplayPath(
			memberGroups,
			frontendWorktreeId,
			'src/index.ts',
		);
		const backendPath = fileCollectionDisplayPath(memberGroups, backendWorktreeId, 'src/index.ts');

		// Assert
		expect(frontendPath).toBe('app/src/index.ts');
		expect(backendPath).toBe('app (2)/src/index.ts');
	});

	test('matches a Review worktree id spelled in upper case', () => {
		expect(
			fileCollectionDisplayPath(memberGroups, backendWorktreeId.toUpperCase(), 'README.md'),
		).toBe('app (2)/README.md');
	});

	test('does not list a path owned by a deeper nested member under the outer member', () => {
		expect(
			fileCollectionDisplayPath(memberGroups, frontendWorktreeId, 'vendor/lib/a.ts'),
		).toBeNull();
		expect(fileCollectionDisplayPath(memberGroups, frontendWorktreeId, 'vendor/lib')).toBeNull();
		expect(fileCollectionDisplayPath(memberGroups, frontendWorktreeId, 'vendor/library.ts')).toBe(
			'app/vendor/library.ts',
		);
		expect(fileCollectionDisplayPath(memberGroups, nestedWorktreeId, 'a.ts')).toBe('lib/a.ts');
	});

	test('is unavailable before the first member-groups event instead of guessing a flat path', () => {
		// Arrange — the display slice is empty until the collection names its members.
		const noMemberGroupsYet: readonly BridgeProductFileMemberGroup[] = [];

		// Act
		const displayPath = fileCollectionDisplayPath(
			noMemberGroupsYet,
			frontendWorktreeId,
			'src/index.ts',
		);

		// Assert
		expect(displayPath).toBeNull();
	});

	test('returns null for a worktree outside the collection or an empty path', () => {
		expect(
			fileCollectionDisplayPath(memberGroups, '0198f3a2-0000-7000-8000-0000000000ff', 'a.ts'),
		).toBeNull();
		expect(fileCollectionDisplayPath(memberGroups, frontendWorktreeId, '')).toBeNull();
	});
});

describe('fileCollectionDescriptorIdentity', () => {
	test('maps a member-scoped descriptor identity to each member own collection identity', () => {
		// Act
		const frontendIdentity = fileCollectionDescriptorIdentity(
			memberGroups,
			frontendWorktreeId,
			'file-content-0123',
		);
		const backendIdentity = fileCollectionDescriptorIdentity(
			memberGroups,
			backendWorktreeId.toUpperCase(),
			'file-content-0123',
		);

		// Assert
		expect(frontendIdentity).toBe('m0000000000aa.file-content-0123');
		expect(backendIdentity).toBe('m0000000000bb.file-content-0123');
	});

	test('is unavailable before the first member-groups event or when the prefix overflows', () => {
		expect(
			fileCollectionDescriptorIdentity([], frontendWorktreeId, 'file-content-0123'),
		).toBeNull();
		expect(
			fileCollectionDescriptorIdentity(memberGroups, frontendWorktreeId, 'x'.repeat(120)),
		).toBeNull();
	});
});

describe('fileCollectionOpenedDocumentSourceLocation', () => {
	const openedDocuments: readonly BridgeProductFileOpenedDocumentEntry[] = [
		{
			displayPath: 'Open Files/notes.md',
			documentLocation: '/Users/dev/notes.md',
			identityPrefix: 'lnotes.',
		},
	];

	test('maps a matching document location to its opened-document display path and prefixed identity', () => {
		// Act
		const located = fileCollectionOpenedDocumentSourceLocation(
			openedDocuments,
			'/Users/dev/notes.md',
			{
				path: 'notes.md',
				sourceIdentity: 'descriptor-notes',
			},
		);

		// Assert
		expect(located).toEqual({
			path: 'Open Files/notes.md',
			sourceIdentity: 'lnotes.descriptor-notes',
		});
	});

	test('returns null when Files does not currently open that document location', () => {
		expect(
			fileCollectionOpenedDocumentSourceLocation(openedDocuments, '/Users/dev/closed.md', {
				path: 'closed.md',
				sourceIdentity: 'descriptor-closed',
			}),
		).toBeNull();
	});
});

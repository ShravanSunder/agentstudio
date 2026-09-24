import { describe, expect, test } from 'vitest';

import type {
	BridgeProductFileMemberGroup,
	BridgeProductFileOpenedDocumentEntry,
} from '../core/comm-worker/bridge-product-file-member-group-contracts.js';
import type { BridgeProductWorktreeAnnotationSubject } from '../core/comm-worker/bridge-product-worktree-annotation-contracts.js';
import {
	fileCollectionOpenedDocumentSourceLocation,
	fileCollectionSourceLocation,
} from '../file-viewer/bridge-file-collection-display-path.js';
import {
	emptyWorktreeAnnotationProjectionSnapshot,
	type WorktreeAnnotationCommandConfirmedThreadProjection,
	type WorktreeAnnotationProjectionSnapshot,
	type WorktreeAnnotationThreadProjection,
} from './worktree-annotation-surface-client.js';
import {
	presentWorktreeAnnotationThreadSources,
	type WorktreeAnnotationThreadSourcePresenter,
} from './worktree-annotation-thread-source-presentation.js';

const frontendWorktreeId = '0198f3a2-0000-7000-8000-00000000000a';
const backendWorktreeId = '0198f3a2-0000-7000-8000-00000000000b';

const frontendSubject: BridgeProductWorktreeAnnotationSubject = {
	kind: 'git',
	worktreeId: frontendWorktreeId,
};
const backendSubject: BridgeProductWorktreeAnnotationSubject = {
	kind: 'git',
	worktreeId: backendWorktreeId,
};

const memberGroups: readonly BridgeProductFileMemberGroup[] = [
	{
		groupPath: 'frontend',
		identityPrefix: 'mfrontend.',
		nestedMemberRelativeRoots: ['vendor'],
		worktreeId: frontendWorktreeId,
	},
	{
		groupPath: 'backend',
		identityPrefix: 'mbackend.',
		nestedMemberRelativeRoots: [],
		worktreeId: backendWorktreeId,
	},
];

const openedDocuments: readonly BridgeProductFileOpenedDocumentEntry[] = [
	{
		displayPath: 'Open Files/notes.md',
		documentLocation: '/Users/dev/notes.md',
		identityPrefix: 'lnotes.',
	},
];

const presentFilesSource = fileCollectionSourcePresenter(memberGroups, openedDocuments);

describe('presentWorktreeAnnotationThreadSources', () => {
	test('lists each thread under its own projection member when two members share a relative path', () => {
		// Arrange
		const frontendProjection = snapshot([serverThread('src/index.ts', 1, frontendSubject)]);
		const backendProjection = snapshot([serverThread('src/index.ts', 1, backendSubject)]);

		// Act
		const frontend = presentWorktreeAnnotationThreadSources(frontendProjection, presentFilesSource);
		const backend = presentWorktreeAnnotationThreadSources(backendProjection, presentFilesSource);

		// Assert
		expect(frontend.threads.map((thread) => thread.context.path)).toEqual([
			'frontend/src/index.ts',
		]);
		expect(backend.threads.map((thread) => thread.context.path)).toEqual(['backend/src/index.ts']);
		expect(frontend.threads[0]?.context.sourceIdentity).toBe('mfrontend.descriptor-1');
		expect(backend.threads[0]?.context.sourceIdentity).toBe('mbackend.descriptor-1');
		expect(backend.threads[0]?.context.startLine).toBe(1);
	});

	test('lists git threads from two different members in one snapshot under their own member groups', () => {
		// Arrange — the multi-member fix: one snapshot carries threads owned by two distinct members.
		const projection = snapshot([
			serverThread('src/index.ts', 1, frontendSubject, '00000000-0000-7000-8000-000000000101'),
			serverThread('src/index.ts', 2, backendSubject, '00000000-0000-7000-8000-000000000102'),
		]);

		// Act
		const presented = presentWorktreeAnnotationThreadSources(projection, presentFilesSource);

		// Assert
		expect(presented.threads.map((thread) => thread.context.path)).toEqual([
			'frontend/src/index.ts',
			'backend/src/index.ts',
		]);
		expect(presented.threads.map((thread) => thread.context.sourceIdentity)).toEqual([
			'mfrontend.descriptor-1',
			'mbackend.descriptor-1',
		]);
	});

	test('maps a just-saved command-confirmed thread before the projection arrives', () => {
		// Arrange
		const projection: WorktreeAnnotationProjectionSnapshot = {
			...snapshot([]),
			commandConfirmedThreads: [commandConfirmedThread('README.md', backendSubject)],
		};

		// Act
		const presented = presentWorktreeAnnotationThreadSources(projection, presentFilesSource);

		// Assert
		expect(
			presented.commandConfirmedThreads.map((thread) => [
				thread.context.path,
				thread.context.sourceIdentity,
			]),
		).toEqual([['backend/README.md', 'mbackend.descriptor-1']]);
	});

	test('withholds every thread before the first member-groups event', () => {
		// Arrange
		const presentWithoutGroups = fileCollectionSourcePresenter([], []);
		const projection: WorktreeAnnotationProjectionSnapshot = {
			...snapshot([serverThread('src/index.ts', 1, backendSubject)]),
			commandConfirmedThreads: [commandConfirmedThread('README.md', backendSubject)],
		};

		// Act
		const presented = presentWorktreeAnnotationThreadSources(projection, presentWithoutGroups);

		// Assert
		expect(presented.threads).toEqual([]);
		expect(presented.commandConfirmedThreads).toEqual([]);
	});

	test('withholds a git thread Files does not list instead of keeping its worktree-relative path', () => {
		// Arrange — `vendor` belongs to a deeper member, so the outer member cannot claim it.
		const nestedProjection = snapshot([serverThread('vendor/lib.ts', 2, frontendSubject)]);

		// Act
		const nested = presentWorktreeAnnotationThreadSources(nestedProjection, presentFilesSource);

		// Assert
		expect(nested.threads).toEqual([]);
	});

	test('presents a localFile thread under its opened-document entry displayPath with the prefixed identity', () => {
		// Arrange
		const localSubject: BridgeProductWorktreeAnnotationSubject = {
			documentLocation: '/Users/dev/notes.md',
			kind: 'localFile',
		};
		const projection = snapshot([
			serverThreadWithSubject({
				endLine: 1,
				path: 'notes.md',
				sourceIdentity: 'descriptor-notes',
				startLine: 1,
				subject: localSubject,
				threadId: '00000000-0000-7000-8000-000000000301',
			}),
		]);

		// Act
		const presented = presentWorktreeAnnotationThreadSources(projection, presentFilesSource);

		// Assert
		expect(presented.threads[0]?.context.path).toBe('Open Files/notes.md');
		expect(presented.threads[0]?.context.sourceIdentity).toBe('lnotes.descriptor-notes');
	});

	test('withholds a localFile thread whose document Files no longer has open', () => {
		// Arrange — `closed.md` was never named in `openedDocuments`.
		const localSubject: BridgeProductWorktreeAnnotationSubject = {
			documentLocation: '/Users/dev/closed.md',
			kind: 'localFile',
		};
		const projection = snapshot([
			serverThreadWithSubject({
				endLine: 1,
				path: 'closed.md',
				sourceIdentity: 'descriptor-closed',
				startLine: 1,
				subject: localSubject,
				threadId: '00000000-0000-7000-8000-000000000302',
			}),
		]);

		// Act
		const presented = presentWorktreeAnnotationThreadSources(projection, presentFilesSource);

		// Assert
		expect(presented.threads).toEqual([]);
	});
});

function fileCollectionSourcePresenter(
	groups: readonly BridgeProductFileMemberGroup[],
	documents: readonly BridgeProductFileOpenedDocumentEntry[],
): WorktreeAnnotationThreadSourcePresenter {
	return (subject, storedSource) =>
		subject.kind === 'git'
			? fileCollectionSourceLocation(groups, subject.worktreeId, storedSource)
			: fileCollectionOpenedDocumentSourceLocation(
					documents,
					subject.documentLocation,
					storedSource,
				);
}

function snapshot(
	threads: readonly WorktreeAnnotationThreadProjection[],
): WorktreeAnnotationProjectionSnapshot {
	return { ...emptyWorktreeAnnotationProjectionSnapshot, threads };
}

function serverThread(
	path: string,
	line: number,
	subject: BridgeProductWorktreeAnnotationSubject,
	threadId = `00000000-0000-7000-8000-00000000010${line}`,
): WorktreeAnnotationThreadProjection {
	return serverThreadWithSubject({
		endLine: line,
		path,
		sourceIdentity: 'descriptor-1',
		startLine: line,
		subject,
		threadId,
	});
}

function serverThreadWithSubject(props: {
	readonly endLine: number;
	readonly path: string;
	readonly sourceIdentity: string;
	readonly startLine: number;
	readonly subject: BridgeProductWorktreeAnnotationSubject;
	readonly threadId: string;
}): WorktreeAnnotationThreadProjection {
	return {
		context: {
			diffSide: null,
			endLine: props.endLine,
			path: props.path,
			placement: 'exact',
			resolution: 'open',
			scope: 'located',
			sourceIdentity: props.sourceIdentity,
			sourceRole: 'file',
			startLine: props.startLine,
			subject: props.subject,
			threadId: props.threadId,
		},
		messages: [],
	};
}

function commandConfirmedThread(
	path: string,
	subject: BridgeProductWorktreeAnnotationSubject,
): WorktreeAnnotationCommandConfirmedThreadProjection {
	return {
		context: {
			diffSide: null,
			endLine: 1,
			path,
			placement: 'command_confirmed',
			resolution: 'open',
			scope: 'located',
			sourceIdentity: 'descriptor-1',
			sourceRole: 'file',
			startLine: 1,
			subject,
			threadId: '00000000-0000-7000-8000-000000000201',
		},
		messages: [],
	};
}

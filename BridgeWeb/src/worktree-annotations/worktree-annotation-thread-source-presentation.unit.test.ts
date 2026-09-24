import { describe, expect, test } from 'vitest';

import type { BridgeProductFileMemberGroup } from '../core/comm-worker/bridge-product-file-member-group-contracts.js';
import { fileCollectionSourceLocation } from '../file-viewer/bridge-file-collection-display-path.js';
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

const presentFilesSource = fileCollectionSourcePresenter(memberGroups);

describe('presentWorktreeAnnotationThreadSources', () => {
	test('lists each thread under its own projection member when two members share a relative path', () => {
		// Arrange
		const frontendProjection = snapshot(frontendWorktreeId, [serverThread('src/index.ts', 1)]);
		const backendProjection = snapshot(backendWorktreeId, [serverThread('src/index.ts', 1)]);

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

	test('maps a just-saved command-confirmed thread before the projection arrives', () => {
		// Arrange
		const projection: WorktreeAnnotationProjectionSnapshot = {
			...snapshot(backendWorktreeId, []),
			commandConfirmedThreads: [commandConfirmedThread('README.md')],
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
		const presentWithoutGroups = fileCollectionSourcePresenter([]);
		const projection: WorktreeAnnotationProjectionSnapshot = {
			...snapshot(backendWorktreeId, [serverThread('src/index.ts', 1)]),
			commandConfirmedThreads: [commandConfirmedThread('README.md')],
		};

		// Act
		const presented = presentWorktreeAnnotationThreadSources(projection, presentWithoutGroups);

		// Assert
		expect(presented.threads).toEqual([]);
		expect(presented.commandConfirmedThreads).toEqual([]);
	});

	test('withholds a thread Files does not list instead of keeping its worktree-relative path', () => {
		// Arrange — `vendor` belongs to a deeper member, and no catalog names a worktree yet.
		const nestedProjection = snapshot(frontendWorktreeId, [serverThread('vendor/lib.ts', 2)]);
		const unboundProjection = { ...snapshot(null, [serverThread('src/index.ts', 3)]) };

		// Act
		const nested = presentWorktreeAnnotationThreadSources(nestedProjection, presentFilesSource);
		const unbound = presentWorktreeAnnotationThreadSources(unboundProjection, presentFilesSource);

		// Assert
		expect(nested.threads).toEqual([]);
		expect(unbound.threads).toEqual([]);
	});
});

function fileCollectionSourcePresenter(
	groups: readonly BridgeProductFileMemberGroup[],
): WorktreeAnnotationThreadSourcePresenter {
	return (worktreeId, storedSource) =>
		fileCollectionSourceLocation(groups, worktreeId, storedSource);
}

function snapshot(
	worktreeId: string | null,
	threads: readonly WorktreeAnnotationThreadProjection[],
): WorktreeAnnotationProjectionSnapshot {
	return { ...emptyWorktreeAnnotationProjectionSnapshot, threads, worktreeId };
}

function serverThread(path: string, line: number): WorktreeAnnotationThreadProjection {
	return {
		context: {
			diffSide: null,
			endLine: line,
			path,
			placement: 'exact',
			resolution: 'open',
			scope: 'located',
			sourceIdentity: 'descriptor-1',
			sourceRole: 'file',
			startLine: line,
			threadId: `00000000-0000-7000-8000-00000000010${line}`,
		},
		messages: [],
	};
}

function commandConfirmedThread(path: string): WorktreeAnnotationCommandConfirmedThreadProjection {
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
			threadId: '00000000-0000-7000-8000-000000000201',
		},
		messages: [],
	};
}

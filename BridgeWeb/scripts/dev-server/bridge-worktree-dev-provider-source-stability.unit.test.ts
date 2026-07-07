import { execFile } from 'node:child_process';
import { mkdir, mkdtemp, rm, unlink, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { promisify } from 'node:util';

import { describe, expect, test } from 'vitest';

import type { WorktreeFileDescriptor } from '../../src/features/worktree-file/models/worktree-file-protocol-models.js';
import { reconcileOpenFileStateWithFrames } from '../../src/file-viewer/bridge-file-viewer-state.js';
import {
	createBridgeWorktreeDevProvider,
	type BridgeWorktreeDevProvider,
} from './bridge-worktree-dev-provider.js';

const execFileAsync = promisify(execFile);

async function runGit(root: string, ...args: readonly string[]): Promise<void> {
	await execFileAsync('git', [...args], { cwd: root });
}

async function makeSourceStabilityFixture(): Promise<string> {
	const repoRoot = await mkdtemp(join(tmpdir(), 'bridge-worktree-source-stability-'));
	await runGit(repoRoot, 'init');
	await runGit(repoRoot, 'config', 'user.name', 'Bridge Test');
	await runGit(repoRoot, 'config', 'user.email', 'bridge@example.test');
	await runGit(repoRoot, 'config', 'commit.gpgsign', 'false');
	await mkdir(join(repoRoot, 'src'), { recursive: true });
	await writeFile(join(repoRoot, 'README.md'), '# Open target\n\nstable body\n');
	await writeFile(join(repoRoot, 'src/other.ts'), 'export const value = 1;\n');
	await runGit(repoRoot, 'add', '.');
	await runGit(repoRoot, 'commit', '-m', 'base');
	return repoRoot;
}

async function loadOpenDescriptor(props: {
	readonly path: string;
	readonly provider: BridgeWorktreeDevProvider;
	readonly source: {
		readonly sourceCursor: string;
		readonly subscriptionGeneration: number;
	};
}): Promise<WorktreeFileDescriptor> {
	const frame = await props.provider.loadWorktreeFileDescriptor({
		path: props.path,
		sourceCursor: props.source.sourceCursor,
		subscriptionGeneration: props.source.subscriptionGeneration,
	});
	return frame.descriptor;
}

describe('Bridge worktree dev provider source-identity stability', () => {
	test('keeps source cursor and descriptor identity stable across two materializations of unchanged content', async () => {
		const repoRoot = await makeSourceStabilityFixture();
		try {
			const provider = await createBridgeWorktreeDevProvider({
				baseRef: 'HEAD',
				scenarioName: 'current-worktree',
				worktreeRoot: repoRoot,
			});

			const firstSurface = await provider.loadWorktreeFileSurface();
			const firstReadme = await loadOpenDescriptor({
				path: 'README.md',
				provider,
				source: firstSurface.source,
			});
			const secondSurface = await provider.loadWorktreeFileSurface();
			const secondReadme = await loadOpenDescriptor({
				path: 'README.md',
				provider,
				source: secondSurface.source,
			});

			expect(secondSurface.source.sourceCursor).toBe(firstSurface.source.sourceCursor);
			expect(secondReadme.contentHash).toBe(firstReadme.contentHash);
			expect(secondReadme.contentHandle).toBe(firstReadme.contentHandle);
			expect(secondReadme.fileId).toBe(firstReadme.fileId);
		} finally {
			await rm(repoRoot, { force: true, recursive: true });
		}
	});

	test('does not stale an unchanged open file when an unrelated file changes', async () => {
		const repoRoot = await makeSourceStabilityFixture();
		try {
			const provider = await createBridgeWorktreeDevProvider({
				baseRef: 'HEAD',
				scenarioName: 'current-worktree',
				worktreeRoot: repoRoot,
			});

			const firstSurface = await provider.loadWorktreeFileSurface();
			const openReadme = await loadOpenDescriptor({
				path: 'README.md',
				provider,
				source: firstSurface.source,
			});
			await writeFile(join(repoRoot, 'src/other.ts'), 'export const value = 999;\n');
			const secondSurface = await provider.loadWorktreeFileSurface();
			const reopenedReadme = await loadOpenDescriptor({
				path: 'README.md',
				provider,
				source: secondSurface.source,
			});

			expect(reopenedReadme.contentHash).toBe(openReadme.contentHash);
			expect(reopenedReadme.contentHandle).toBe(openReadme.contentHandle);
			expect(secondSurface.source.sourceCursor).toBe(firstSurface.source.sourceCursor);

			const reconciled = reconcileOpenFileStateWithFrames({
				currentOpenFileState: { status: 'ready', path: 'README.md', descriptor: openReadme },
				frames: secondSurface.frames,
				openFileRequestIdRef: { current: 0 },
			});
			expect(reconciled.status).toBe('ready');
		} finally {
			await rm(repoRoot, { force: true, recursive: true });
		}
	});

	test('stales a genuinely-changed open file via a fileInvalidated frame', async () => {
		const repoRoot = await makeSourceStabilityFixture();
		try {
			const provider = await createBridgeWorktreeDevProvider({
				baseRef: 'HEAD',
				scenarioName: 'current-worktree',
				worktreeRoot: repoRoot,
			});

			const firstSurface = await provider.loadWorktreeFileSurface();
			const openReadme = await loadOpenDescriptor({
				path: 'README.md',
				provider,
				source: firstSurface.source,
			});
			await writeFile(join(repoRoot, 'README.md'), '# Open target\n\nCHANGED body\n');
			const secondSurface = await provider.loadWorktreeFileSurface();

			const invalidation = secondSurface.frames.find(
				(frame) =>
					frame.frameKind === 'worktree.fileInvalidated' && frame.invalidation.path === 'README.md',
			);
			expect(invalidation).toBeDefined();

			const reconciled = reconcileOpenFileStateWithFrames({
				currentOpenFileState: { status: 'ready', path: 'README.md', descriptor: openReadme },
				frames: secondSurface.frames,
				openFileRequestIdRef: { current: 0 },
			});
			expect(reconciled.status).toBe('stale');
		} finally {
			await rm(repoRoot, { force: true, recursive: true });
		}
	});

	test('stales a removed open file via a fileInvalidated frame without a latest descriptor', async () => {
		const repoRoot = await makeSourceStabilityFixture();
		try {
			const provider = await createBridgeWorktreeDevProvider({
				baseRef: 'HEAD',
				scenarioName: 'current-worktree',
				worktreeRoot: repoRoot,
			});

			const firstSurface = await provider.loadWorktreeFileSurface();
			const openReadme = await loadOpenDescriptor({
				path: 'README.md',
				provider,
				source: firstSurface.source,
			});
			await unlink(join(repoRoot, 'README.md'));
			const secondSurface = await provider.loadWorktreeFileSurface();

			const invalidation = secondSurface.frames.find(
				(frame) =>
					frame.frameKind === 'worktree.fileInvalidated' && frame.invalidation.path === 'README.md',
			);
			expect(invalidation).toBeDefined();
			expect(invalidation?.frameKind === 'worktree.fileInvalidated').toBe(true);
			if (invalidation?.frameKind !== 'worktree.fileInvalidated') {
				return;
			}
			expect(invalidation.invalidation.latestDescriptor).toBeUndefined();
			expect(invalidation.invalidation.contentHandleIds).toContain(openReadme.contentHandle);

			const reconciled = reconcileOpenFileStateWithFrames({
				currentOpenFileState: { status: 'ready', path: 'README.md', descriptor: openReadme },
				frames: secondSurface.frames,
				openFileRequestIdRef: { current: 0 },
			});
			expect(reconciled.status).toBe('stale');
		} finally {
			await rm(repoRoot, { force: true, recursive: true });
		}
	});
});

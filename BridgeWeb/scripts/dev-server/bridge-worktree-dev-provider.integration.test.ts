import { execFile } from 'node:child_process';
import { mkdtemp, mkdir, realpath, rm, symlink, unlink, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { promisify } from 'node:util';

import { describe, expect, test } from 'vitest';

import type { WorktreeFileDescriptor } from '../../src/features/worktree-file/models/worktree-file-protocol-models.js';
import { countFlattenedWorktreeFileTreeRows } from '../../src/features/worktree-file/models/worktree-file-tree-size.js';
import {
	createBridgeWorktreeDevProvider,
	loadBridgeWorktreeDevSnapshot,
	resolveBridgeWorktreeDevProviderConfig,
	type BridgeWorktreeDevProviderWorktreeFileContentRequest,
	type BridgeWorktreeDevProviderWorktreeFileSurface,
} from './bridge-worktree-dev-provider.js';

const execFileAsync = promisify(execFile);

describe('Bridge worktree dev provider', () => {
	test('projects an allowlisted git worktree into Worktree/File frames and descriptor-backed content', async () => {
		const repoRoot = await makeGitFixtureWorktree();
		try {
			const provider = await createBridgeWorktreeDevProvider({
				baseRef: 'HEAD',
				scenarioName: 'current-worktree',
				worktreeRoot: repoRoot,
			});

			const surface = await provider.loadWorktreeFileSurface();
			const frameKinds = surface.frames.map((frame) => frame.frameKind);
			const surfaceJson = JSON.stringify(surface);
			const sourceDescriptor = findWorktreeFileDescriptor(surface, 'src/app.ts');
			const docsDescriptor = findWorktreeFileDescriptor(surface, 'docs/bridge-plan.md');
			const deletedDescriptor = findWorktreeFileDescriptor(surface, 'docs/deleted-plan.md');

			expect(frameKinds[0]).toBe('worktree.snapshot');
			expect(frameKinds).toContain('worktree.fileDescriptor');
			expect(surface.provenance).toEqual({
				baseRef: 'HEAD',
				scenarioName: 'current-worktree',
				worktreeRootToken: expect.stringMatching(/^root-[a-f0-9]{32}$/u),
			});
			expect(surface.source.sourceId).toBe('dev-worktree-source');
			expect(surface.treeSizeFacts.pathCount).toBeGreaterThanOrEqual(2);
			const expectedFlattenedRowCount = countFlattenedWorktreeFileTreeRows([
				'src/app.ts',
				'docs/bridge-plan.md',
				'docs/deleted-plan.md',
			]);
			expect(surface.treeSizeFacts.estimatedTotalHeightPixels).toBe(
				expectedFlattenedRowCount * surface.treeSizeFacts.rowHeightPixels,
			);
			expect(surface.treeSizeFacts.pathCount).toBeDefined();
			expect(surface.treeSizeFacts.estimatedTotalHeightPixels).not.toBe(
				Number(surface.treeSizeFacts.pathCount) * surface.treeSizeFacts.rowHeightPixels,
			);
			expect(sourceDescriptor.virtualizedExtentKind).toBe('exactLineCount');
			expect(sourceDescriptor.lineCount).toBeGreaterThan(0);
			expect(deletedDescriptor.virtualizedExtentKind).toBe('unavailable');
			expect(deletedDescriptor.isBinary).toBe(false);
			expect(sourceDescriptor.contentDescriptor.descriptor.resourceUrl).toContain(
				'agentstudio://resource/worktree-file/worktree.fileContent/',
			);
			expect(surfaceJson).not.toContain('new docs body');
			expect(surfaceJson).not.toContain('export const value = 2');

			const docsContent = await provider.loadWorktreeFileContent(
				worktreeFileContentRequestForDescriptor(docsDescriptor),
			);
			const sourceContent = await provider.loadWorktreeFileContent(
				worktreeFileContentRequestForDescriptor(sourceDescriptor),
			);
			expect(renderLineCount('')).toBe(0);
			expect(renderLineCount('\n')).toBe(1);
			expect(renderLineCount('line 1\nline 2\n')).toBe(2);
			expect(renderLineCount('line 1\n\nline 3\n')).toBe(3);
			expect(docsDescriptor.lineCount).toBe(3);
			expect(sourceDescriptor.lineCount).toBe(1);
			expect(docsDescriptor.lineCount).toBe(renderLineCount(docsContent));
			expect(sourceDescriptor.lineCount).toBe(renderLineCount(sourceContent));
			expect(docsContent).toContain('new docs body');
			expect(sourceContent).toContain('export const value = 2');
			await expect(
				provider.loadWorktreeFileContent(
					worktreeFileContentRequestForDescriptor(deletedDescriptor),
				),
			).rejects.toThrow(/Unknown Bridge worktree file content descriptor/);
		} finally {
			await rm(repoRoot, { force: true, recursive: true });
		}
	});

	test('resolves the package-local default worktree and compares against the main merge base', async () => {
		const repoRoot = await makeGitFixtureWorktree();
		try {
			await git(repoRoot, 'branch', '-M', 'main');
			await git(repoRoot, 'checkout', '-b', 'feature/review');
			await writeFile(join(repoRoot, 'src/feature.ts'), 'export const feature = true;\n');
			await git(repoRoot, 'add', '.');
			await git(repoRoot, 'commit', '-m', 'feature change');
			await writeFile(join(repoRoot, 'src/app.ts'), 'export const value = 3;\n');

			const config = await resolveBridgeWorktreeDevProviderConfig({
				env: {},
				packageRoot: join(repoRoot, 'BridgeWeb'),
				requestUrl: null,
			});
			const provider = await createBridgeWorktreeDevProvider(config);
			const surface = await provider.loadWorktreeFileSurface();
			const featureDescriptor = findWorktreeFileDescriptor(surface, 'src/feature.ts');
			const appDescriptor = findWorktreeFileDescriptor(surface, 'src/app.ts');

			expect(config.worktreeRoot).toBe(await realpath(repoRoot));
			expect(config.baseRef).not.toBe('HEAD');
			expect(featureDescriptor.language).toBe('typescript');
			expect(appDescriptor.language).toBe('typescript');
		} finally {
			await rm(repoRoot, { force: true, recursive: true });
		}
	});

	test('preserves real git rename and copy paths in the changed-file snapshot', async () => {
		const repoRoot = await makeGitRenameCopyFixtureWorktree();
		try {
			await git(repoRoot, 'mv', 'src/source.ts', 'src/renamed.ts');
			await writeFile(join(repoRoot, 'src/copied.ts'), sourceFixtureContent());
			await git(repoRoot, 'add', 'src/copied.ts', 'src/renamed.ts');

			const snapshot = await loadBridgeWorktreeDevSnapshot({
				baseRef: 'HEAD',
				worktreeRoot: repoRoot,
			});
			const renamedFile = findChangedFile(snapshot.changedFiles, 'src/renamed.ts');
			const copiedFile = findChangedFile(snapshot.changedFiles, 'src/copied.ts');

			expect(renamedFile).toMatchObject({
				baseContent: sourceFixtureContent(),
				basePath: 'src/source.ts',
				changeKind: 'renamed',
				headContent: sourceFixtureContent(),
				headPath: 'src/renamed.ts',
				path: 'src/renamed.ts',
			});
			expect(copiedFile).toMatchObject({
				baseContent: sourceFixtureContent(),
				basePath: 'src/source.ts',
				changeKind: 'copied',
				headContent: sourceFixtureContent(),
				headPath: 'src/copied.ts',
				path: 'src/copied.ts',
			});
		} finally {
			await rm(repoRoot, { force: true, recursive: true });
		}
	});

	test('accepts request query overrides for dev-only worktree surface routes', async () => {
		const repoRoot = await makeGitFixtureWorktree();
		try {
			const config = await resolveBridgeWorktreeDevProviderConfig({
				env: { BRIDGE_WEB_DEV_BASE: 'HEAD', BRIDGE_WEB_DEV_WORKTREE: repoRoot },
				packageRoot: join(repoRoot, 'BridgeWeb'),
				requestUrl: '/__bridge-worktree/surface?scenario=current-worktree',
			});

			expect(config).toEqual({
				baseRef: 'HEAD',
				scenarioName: 'current-worktree',
				worktreeRoot: await realpath(repoRoot),
			});
		} finally {
			await rm(repoRoot, { force: true, recursive: true });
		}
	});

	test('rejects unknown worktree dev scenarios instead of resolving arbitrary sources', async () => {
		const repoRoot = await makeGitFixtureWorktree();
		try {
			await expect(
				resolveBridgeWorktreeDevProviderConfig({
					env: { BRIDGE_WEB_DEV_BASE: 'HEAD', BRIDGE_WEB_DEV_WORKTREE: repoRoot },
					packageRoot: join(repoRoot, 'BridgeWeb'),
					requestUrl: '/__bridge-worktree/surface?scenario=/tmp/raw-path',
				}),
			).rejects.toThrow(/Invalid Bridge worktree dev provider config/);
		} finally {
			await rm(repoRoot, { force: true, recursive: true });
		}
	});

	test('rejects non-loopback absolute request URLs before reading scenario input', async () => {
		const repoRoot = await makeGitFixtureWorktree();
		try {
			await expect(
				resolveBridgeWorktreeDevProviderConfig({
					env: { BRIDGE_WEB_DEV_BASE: 'HEAD', BRIDGE_WEB_DEV_WORKTREE: repoRoot },
					packageRoot: join(repoRoot, 'BridgeWeb'),
					requestUrl: 'https://example.test/__bridge-worktree/surface?scenario=current-worktree',
				}),
			).rejects.toThrow(/loopback/);
		} finally {
			await rm(repoRoot, { force: true, recursive: true });
		}
	});

	test('rejects raw worktree repo and base query usage on shareable routes', async () => {
		const repoRoot = await makeGitFixtureWorktree();
		try {
			const rawQueryAssertions = [
				`worktree=${encodeURIComponent(repoRoot)}`,
				`repo=${encodeURIComponent(repoRoot)}`,
				'base=HEAD',
			].map(async (query: string): Promise<void> => {
				await expect(
					resolveBridgeWorktreeDevProviderConfig({
						env: { BRIDGE_WEB_DEV_BASE: 'HEAD', BRIDGE_WEB_DEV_WORKTREE: repoRoot },
						packageRoot: join(repoRoot, 'BridgeWeb'),
						requestUrl: `/__bridge-worktree/surface?scenario=current-worktree&${query}`,
					}),
				).rejects.toThrow(/raw worktree, repo, or base query parameters/);
			});
			await Promise.all(rawQueryAssertions);
		} finally {
			await rm(repoRoot, { force: true, recursive: true });
		}
	});

	test('rejects non-git-root worktree roots supplied through local diagnostics', async () => {
		const repoRoot = await makeGitFixtureWorktree();
		try {
			await expect(
				resolveBridgeWorktreeDevProviderConfig({
					env: { BRIDGE_WEB_DEV_BASE: 'HEAD', BRIDGE_WEB_DEV_WORKTREE: join(repoRoot, 'src') },
					packageRoot: join(repoRoot, 'BridgeWeb'),
					requestUrl: '/__bridge-worktree/surface?scenario=current-worktree',
				}),
			).rejects.toThrow(/must be the git root/);
		} finally {
			await rm(repoRoot, { force: true, recursive: true });
		}
	});

	test('rejects stale generation and cursor content resource requests', async () => {
		const repoRoot = await makeGitFixtureWorktree();
		try {
			const provider = await createBridgeWorktreeDevProvider({
				baseRef: 'HEAD',
				scenarioName: 'current-worktree',
				worktreeRoot: repoRoot,
			});
			const surface = await provider.loadWorktreeFileSurface();
			const docsDescriptor = findWorktreeFileDescriptor(surface, 'docs/bridge-plan.md');
			const validContentRequest = worktreeFileContentRequestForDescriptor(docsDescriptor);

			await expect(provider.loadWorktreeFileContent(validContentRequest)).resolves.toContain(
				'new docs body',
			);
			await expect(
				provider.loadWorktreeFileContent({ ...validContentRequest, subscriptionGeneration: 0 }),
			).rejects.toThrow(/stale Bridge worktree file content generation/);
			await expect(
				provider.loadWorktreeFileContent({ ...validContentRequest, sourceCursor: 'old-cursor' }),
			).rejects.toThrow(/stale Bridge worktree file content cursor/);
			await expect(
				provider.loadWorktreeFileContent({
					...validContentRequest,
					descriptorId: 'missing-descriptor',
				}),
			).rejects.toThrow(/Unknown Bridge worktree file content descriptor: missing-descriptor/);
		} finally {
			await rm(repoRoot, { force: true, recursive: true });
		}
	});

	test('rejects changed-file symlinks that resolve outside the worktree root', async () => {
		const repoRoot = await makeGitFixtureWorktree();
		const externalRoot = await mkdtemp(join(tmpdir(), 'bridge-worktree-provider-secret-'));
		try {
			await writeFile(join(externalRoot, 'secret.txt'), 'external secret must not load\n');
			await symlink(join(externalRoot, 'secret.txt'), join(repoRoot, 'linked-secret.txt'));
			const provider = await createBridgeWorktreeDevProvider({
				baseRef: 'HEAD',
				scenarioName: 'current-worktree',
				worktreeRoot: repoRoot,
			});

			await expect(provider.loadWorktreeFileSurface()).rejects.toThrow(/escapes root/);
		} finally {
			await rm(repoRoot, { force: true, recursive: true });
			await rm(externalRoot, { force: true, recursive: true });
		}
	});

	test('changes source cursor when the worktree snapshot changes and rejects old content URLs', async () => {
		const repoRoot = await makeGitFixtureWorktree();
		try {
			const provider = await createBridgeWorktreeDevProvider({
				baseRef: 'HEAD',
				scenarioName: 'current-worktree',
				worktreeRoot: repoRoot,
			});
			const firstSurface = await provider.loadWorktreeFileSurface();
			const firstDocsDescriptor = findWorktreeFileDescriptor(firstSurface, 'docs/bridge-plan.md');
			const firstRequest = worktreeFileContentRequestForDescriptor(firstDocsDescriptor);

			await writeFile(join(repoRoot, 'docs/bridge-plan.md'), '# Plan\n\nupdated docs body\n');

			const secondSurface = await provider.loadWorktreeFileSurface();
			const secondDocsDescriptor = findWorktreeFileDescriptor(secondSurface, 'docs/bridge-plan.md');
			const secondRequest = worktreeFileContentRequestForDescriptor(secondDocsDescriptor);

			expect(secondSurface.source.sourceCursor).not.toBe(firstSurface.source.sourceCursor);
			expect(secondRequest.sourceCursor).toBe(secondSurface.source.sourceCursor);
			await expect(provider.loadWorktreeFileContent(firstRequest)).rejects.toThrow(
				/stale Bridge worktree file content cursor/,
			);
			await expect(provider.loadWorktreeFileContent(secondRequest)).resolves.toContain(
				'updated docs body',
			);
		} finally {
			await rm(repoRoot, { force: true, recursive: true });
		}
	});

	test('serves descriptor-cursor content from the accepted surface until another surface refresh', async () => {
		const repoRoot = await makeGitFixtureWorktree();
		try {
			const provider = await createBridgeWorktreeDevProvider({
				baseRef: 'HEAD',
				scenarioName: 'current-worktree',
				worktreeRoot: repoRoot,
			});
			const firstSurface = await provider.loadWorktreeFileSurface();
			const firstDocsDescriptor = findWorktreeFileDescriptor(firstSurface, 'docs/bridge-plan.md');
			const firstRequest = worktreeFileContentRequestForDescriptor(firstDocsDescriptor);

			await writeFile(join(repoRoot, 'docs/bridge-plan.md'), '# Plan\n\nupdated docs body\n');

			const contentBeforeRefresh = await provider.loadWorktreeFileContent(firstRequest);
			expect(contentBeforeRefresh).toContain('new docs body');
			expect(contentBeforeRefresh).not.toContain('updated docs body');
		} finally {
			await rm(repoRoot, { force: true, recursive: true });
		}
	});
});

async function makeGitFixtureWorktree(): Promise<string> {
	const repoRoot = await mkdtemp(join(tmpdir(), 'bridge-worktree-provider-'));
	await git(repoRoot, 'init');
	await git(repoRoot, 'config', 'user.name', 'Bridge Test');
	await git(repoRoot, 'config', 'user.email', 'bridge@example.test');
	await git(repoRoot, 'config', 'commit.gpgsign', 'false');
	await mkdir(join(repoRoot, 'src'), { recursive: true });
	await mkdir(join(repoRoot, 'docs'), { recursive: true });
	await writeFile(join(repoRoot, 'src/app.ts'), 'export const value = 1;\n');
	await writeFile(join(repoRoot, 'docs/deleted-plan.md'), '# Deleted\n\nold docs body\n');
	await git(repoRoot, 'add', '.');
	await git(repoRoot, 'commit', '-m', 'base');
	await writeFile(join(repoRoot, 'src/app.ts'), 'export const value = 2;\n');
	await writeFile(join(repoRoot, 'docs/bridge-plan.md'), '# Plan\n\nnew docs body\n');
	await unlink(join(repoRoot, 'docs/deleted-plan.md'));
	return repoRoot;
}

async function makeGitRenameCopyFixtureWorktree(): Promise<string> {
	const repoRoot = await mkdtemp(join(tmpdir(), 'bridge-worktree-provider-rename-copy-'));
	await git(repoRoot, 'init');
	await git(repoRoot, 'config', 'user.name', 'Bridge Test');
	await git(repoRoot, 'config', 'user.email', 'bridge@example.test');
	await git(repoRoot, 'config', 'commit.gpgsign', 'false');
	await mkdir(join(repoRoot, 'src'), { recursive: true });
	await writeFile(join(repoRoot, 'src/source.ts'), sourceFixtureContent());
	await git(repoRoot, 'add', '.');
	await git(repoRoot, 'commit', '-m', 'base');
	return repoRoot;
}

function sourceFixtureContent(): string {
	return [
		'export function sourceFixture(): string {',
		"  const name = 'bridge';",
		"  const mode = 'review';",
		'  return `${name}:${mode}`;',
		'}',
		'',
	].join('\n');
}

async function git(cwd: string, ...args: readonly string[]): Promise<void> {
	await execFileAsync('git', args, { cwd });
}

function findWorktreeFileDescriptor(
	surface: BridgeWorktreeDevProviderWorktreeFileSurface,
	path: string,
): WorktreeFileDescriptor {
	const descriptor = surface.frames
		.filter((frame) => frame.frameKind === 'worktree.fileDescriptor')
		.map((frame) => frame.descriptor)
		.find((candidate) => candidate.path === path);
	if (descriptor === undefined) {
		throw new Error(`Expected Worktree/File descriptor for ${path}`);
	}
	return descriptor;
}

function findChangedFile(
	changedFiles: Awaited<ReturnType<typeof loadBridgeWorktreeDevSnapshot>>['changedFiles'],
	path: string,
): Awaited<ReturnType<typeof loadBridgeWorktreeDevSnapshot>>['changedFiles'][number] {
	const changedFile = changedFiles.find((candidate) => candidate.path === path);
	if (changedFile === undefined) {
		throw new Error(`Expected changed file for ${path}`);
	}
	return changedFile;
}

function renderLineCount(content: string): number {
	if (content.length === 0) {
		return 0;
	}
	const renderedContent = content.endsWith('\n') ? content.slice(0, -1) : content;
	return renderedContent.split('\n').length;
}

function worktreeFileContentRequestForDescriptor(
	descriptor: WorktreeFileDescriptor,
): BridgeWorktreeDevProviderWorktreeFileContentRequest {
	const identity = descriptor.contentDescriptor.ref.expectedIdentity;
	if (identity.generation === undefined || identity.cursor === undefined) {
		throw new Error('Expected Worktree/File descriptor identity generation and cursor');
	}
	return {
		descriptorId: descriptor.contentDescriptor.ref.descriptorId,
		sourceCursor: identity.cursor,
		subscriptionGeneration: identity.generation,
	};
}

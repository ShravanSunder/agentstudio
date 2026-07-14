import { execFile } from 'node:child_process';
import { mkdtemp, mkdir, realpath, rm, symlink, unlink, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { promisify } from 'node:util';

import { describe, expect, test } from 'vitest';

import { countFlattenedWorktreeFileTreeRows } from '../../src/features/worktree-file/models/worktree-file-tree-size.js';
import type { WorktreeFileDescriptor } from './bridge-worktree-dev-file-fixture-contracts.js';
import { worktreeFileProtocolFrameSchema } from './bridge-worktree-dev-file-fixture-contracts.js';
import {
	createBridgeWorktreeDevProvider,
	loadBridgeWorktreeDevSnapshot,
	resolveBridgeWorktreeDevProviderConfig,
	type BridgeWorktreeDevProvider,
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
			const sourceDescriptor = await loadWorktreeFileDescriptor(provider, surface, 'src/app.ts');
			const unchangedDescriptor = await loadWorktreeFileDescriptor(provider, surface, 'README.md');
			const docsDescriptor = await loadWorktreeFileDescriptor(
				provider,
				surface,
				'docs/bridge-plan.md',
			);
			const deletedDescriptor = await loadWorktreeFileDescriptor(
				provider,
				surface,
				'docs/deleted-plan.md',
			);

			expect(frameKinds[0]).toBe('worktree.snapshot');
			expect(frameKinds).not.toContain('worktree.fileDescriptor');
			expect(surface.provenance).toEqual({
				baseRef: 'HEAD',
				scenarioName: 'current-worktree',
				worktreeRootToken: expect.stringMatching(/^root-[a-f0-9]{32}$/u),
			});
			expect(surface.source.sourceId).toBe('dev-worktree-source');
			expect(surface.treeSizeFacts.pathCount).toBeGreaterThanOrEqual(2);
			const expectedFlattenedRowCount = countFlattenedWorktreeFileTreeRows([
				'README.md',
				'src/app.ts',
				'docs/bridge-plan.md',
			]);
			expect(surface.treeSizeFacts.estimatedTotalHeightPixels).toBe(
				expectedFlattenedRowCount * surface.treeSizeFacts.rowHeightPixels,
			);
			expect(surface.treeSizeFacts.pathCount).toBe(expectedFlattenedRowCount);
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
			const unchangedContent = await provider.loadWorktreeFileContent(
				worktreeFileContentRequestForDescriptor(unchangedDescriptor),
			);
			expect(renderLineCount('')).toBe(0);
			expect(renderLineCount('\n')).toBe(1);
			expect(renderLineCount('line 1\nline 2\n')).toBe(2);
			expect(renderLineCount('line 1\n\nline 3\n')).toBe(3);
			expect(docsDescriptor.lineCount).toBe(3);
			expect(sourceDescriptor.lineCount).toBe(1);
			expect(unchangedDescriptor.lineCount).toBe(3);
			expect(docsDescriptor.lineCount).toBe(renderLineCount(docsContent));
			expect(sourceDescriptor.lineCount).toBe(renderLineCount(sourceContent));
			expect(unchangedDescriptor.lineCount).toBe(renderLineCount(unchangedContent));
			expect(docsContent).toContain('new docs body');
			expect(sourceContent).toContain('export const value = 2');
			expect(unchangedContent).toContain('Unchanged fixture');
			await expect(
				provider.loadWorktreeFileContent(
					worktreeFileContentRequestForDescriptor(deletedDescriptor),
				),
			).rejects.toThrow(/Unknown Bridge worktree file content descriptor/);
		} finally {
			await rm(repoRoot, { force: true, recursive: true });
		}
	});

	test('streams initial tree metadata and mints file descriptors on demand', async () => {
		const repoRoot = await makeGitFixtureWorktree();
		try {
			const provider = await createBridgeWorktreeDevProvider({
				baseRef: 'HEAD',
				scenarioName: 'current-worktree',
				worktreeRoot: repoRoot,
			});

			const surface = await provider.loadWorktreeFileSurface();
			const snapshot = surface.frames[0];
			const descriptorFrame = await provider.loadWorktreeFileDescriptor({
				path: 'src/app.ts',
				sourceCursor: surface.source.sourceCursor,
				subscriptionGeneration: surface.source.subscriptionGeneration,
			});

			expect(snapshot?.frameKind).toBe('worktree.snapshot');
			expect(surface.frames.some((frame) => frame.frameKind === 'worktree.fileDescriptor')).toBe(
				false,
			);
			expect(snapshot?.frameKind === 'worktree.snapshot' ? snapshot.treeRows : []).toEqual(
				expect.arrayContaining([
					expect.objectContaining({ isDirectory: false, path: 'README.md' }),
					expect.objectContaining({ isDirectory: true, path: 'src' }),
					expect.objectContaining({
						fileId: expect.stringMatching(/^dev-file-id-/u),
						isDirectory: false,
						path: 'src/app.ts',
					}),
				]),
			);
			expect(
				snapshot?.frameKind === 'worktree.snapshot'
					? snapshot.treeRows.find((row) => row.path === 'src/app.ts')?.lineCount
					: null,
			).toBeUndefined();
			expect(descriptorFrame.frameKind).toBe('worktree.fileDescriptor');
			expect(descriptorFrame.descriptor.path).toBe('src/app.ts');
			expect(descriptorFrame.descriptor.contentDescriptor.descriptor.resourceKind).toBe(
				'worktree.fileContent',
			);
			await expect(
				provider.loadWorktreeFileContent(
					worktreeFileContentRequestForDescriptor(descriptorFrame.descriptor),
				),
			).resolves.toContain('export const value = 2');
		} finally {
			await rm(repoRoot, { force: true, recursive: true });
		}
	});

	test('classifies invalid UTF-8 files as unsupported encoding without rejecting demand', async () => {
		const repoRoot = await makeGitFixtureWorktree();
		try {
			await mkdir(join(repoRoot, 'assets'), { recursive: true });
			await writeFile(
				join(repoRoot, 'assets', 'invalid-utf8.png'),
				Uint8Array.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0xff]),
			);
			const provider = await createBridgeWorktreeDevProvider({
				baseRef: 'HEAD',
				scenarioName: 'current-worktree',
				worktreeRoot: repoRoot,
			});

			const surface = await provider.loadWorktreeFileSurface();
			const descriptor = await loadWorktreeFileDescriptor(
				provider,
				surface,
				'assets/invalid-utf8.png',
			);

			expect(descriptor).toMatchObject({
				isBinary: false,
				unavailableReason: 'unsupported_encoding',
				virtualizedExtentKind: 'unavailable',
			});
		} finally {
			await rm(repoRoot, { force: true, recursive: true });
		}
	});

	test('bounds initial tree metadata and streams ordered tree-window continuations', async () => {
		const repoRoot = await makeLargeGitFixtureWorktree();
		try {
			const provider = await createBridgeWorktreeDevProvider({
				baseRef: 'HEAD',
				scenarioName: 'current-worktree',
				worktreeRoot: repoRoot,
			});

			const surface = await provider.loadWorktreeFileSurface();
			const parsedFrames = surface.frames.map((frame) =>
				worktreeFileProtocolFrameSchema.parse(frame),
			);
			const snapshot = parsedFrames[0];
			const treeWindowFrames = parsedFrames.filter(
				(frame) => frame.frameKind === 'worktree.treeWindow',
			);

			expect(snapshot?.frameKind).toBe('worktree.snapshot');
			expect(snapshot?.frameKind === 'worktree.snapshot' ? snapshot.treeRows : []).toHaveLength(
				200,
			);
			expect(snapshot?.frameKind === 'worktree.snapshot' ? snapshot.treeSizeFacts : null).toEqual(
				expect.objectContaining({
					extentKind: 'exactPathCount',
					pathCount: 261,
					windowRowCount: 200,
					windowStartIndex: 0,
				}),
			);
			expect(treeWindowFrames).toHaveLength(1);
			expect(treeWindowFrames[0]).toEqual(
				expect.objectContaining({
					frameKind: 'worktree.treeWindow',
					generation: surface.source.subscriptionGeneration,
					kind: 'delta',
					sequence: 1,
				}),
			);
			expect(treeWindowFrames[0]?.treeSizeFacts).toEqual(
				expect.objectContaining({
					extentKind: 'exactPathCount',
					pathCount: 261,
					windowRowCount: 61,
					windowStartIndex: 200,
				}),
			);
			expect(treeWindowFrames[0]?.rows).toHaveLength(61);
			expect(treeWindowFrames[0]?.rows[0]?.path).toBe('Sources/Visible199.swift');
			expect(treeWindowFrames[0]?.rows.at(-1)?.path).toBe('Sources/Visible259.swift');
		} finally {
			await rm(repoRoot, { force: true, recursive: true });
		}
	});

	test('resolves the package-local default worktree and compares against the main merge base', async () => {
		const repoRoot = await makeGitFixtureWorktree();
		try {
			await runGitTestFixtureCommand(repoRoot, 'branch', '-M', 'main');
			await runGitTestFixtureCommand(repoRoot, 'checkout', '-b', 'feature/review');
			await writeFile(join(repoRoot, 'src/feature.ts'), 'export const feature = true;\n');
			await runGitTestFixtureCommand(repoRoot, 'add', '.');
			await runGitTestFixtureCommand(repoRoot, 'commit', '-m', 'feature change');
			await writeFile(join(repoRoot, 'src/app.ts'), 'export const value = 3;\n');

			const config = await resolveBridgeWorktreeDevProviderConfig({
				env: {},
				packageRoot: join(repoRoot, 'BridgeWeb'),
				requestUrl: null,
			});
			const provider = await createBridgeWorktreeDevProvider(config);
			const surface = await provider.loadWorktreeFileSurface();
			const featureDescriptor = await loadWorktreeFileDescriptor(
				provider,
				surface,
				'src/feature.ts',
			);
			const appDescriptor = await loadWorktreeFileDescriptor(provider, surface, 'src/app.ts');

			expect(config.worktreeRoot).toBe(await realpath(repoRoot));
			expect(config.baseRef).not.toBe('HEAD');
			expect(featureDescriptor.language).toBe('typescript');
			expect(appDescriptor.language).toBe('typescript');
		} finally {
			await rm(repoRoot, { force: true, recursive: true });
		}
	});

	test('resolves the package-local default worktree against origin HEAD before main fallbacks', async () => {
		const repoRoot = await makeGitFixtureWorktree();
		try {
			await runGitTestFixtureCommand(repoRoot, 'branch', '-M', 'trunk');
			const trunkBaseRef = await runGitTestFixtureStdout(repoRoot, 'rev-parse', 'HEAD');
			await runGitTestFixtureCommand(
				repoRoot,
				'symbolic-ref',
				'refs/remotes/origin/HEAD',
				'refs/remotes/origin/trunk',
			);
			await runGitTestFixtureCommand(repoRoot, 'update-ref', 'refs/remotes/origin/trunk', 'HEAD');
			await runGitTestFixtureCommand(repoRoot, 'checkout', '-b', 'feature/review');
			await writeFile(
				join(repoRoot, 'src/trunk-feature.ts'),
				'export const trunkFeature = true;\n',
			);
			await runGitTestFixtureCommand(repoRoot, 'add', '.');
			await runGitTestFixtureCommand(repoRoot, 'commit', '-m', 'feature change');

			const config = await resolveBridgeWorktreeDevProviderConfig({
				env: {},
				packageRoot: join(repoRoot, 'BridgeWeb'),
				requestUrl: null,
			});
			const provider = await createBridgeWorktreeDevProvider(config);
			const surface = await provider.loadWorktreeFileSurface();
			const featureDescriptor = await loadWorktreeFileDescriptor(
				provider,
				surface,
				'src/trunk-feature.ts',
			);

			expect(config.baseRef).toBe(trunkBaseRef.trim());
			expect(config.baseRef).not.toBe('HEAD');
			expect(featureDescriptor.path).toBe('src/trunk-feature.ts');
		} finally {
			await rm(repoRoot, { force: true, recursive: true });
		}
	});

	test('excludes gitignored untracked files before publishing worktree candidates', async () => {
		const repoRoot = await makeGitIgnoreFixtureWorktree();
		try {
			const snapshot = await loadBridgeWorktreeDevSnapshot({
				baseRef: 'HEAD',
				worktreeRoot: repoRoot,
			});
			const changedPaths = snapshot.changedFiles.map((changedFile) => changedFile.path);

			expect(changedPaths).toContain('src/app.ts');
			expect(changedPaths).toContain('docs/visible.md');
			expect(changedPaths).not.toContain('ignored-output/log.txt');
			expect(changedPaths).not.toContain('src/generated.generated.ts');

			const provider = await createBridgeWorktreeDevProvider({
				baseRef: 'HEAD',
				scenarioName: 'current-worktree',
				worktreeRoot: repoRoot,
			});
			const surface = await provider.loadWorktreeFileSurface();
			const treeRowPaths = worktreeTreeRowPaths(surface);

			expect(treeRowPaths).toContain('src/app.ts');
			expect(treeRowPaths).toContain('docs/visible.md');
			expect(treeRowPaths).not.toContain('ignored-output/log.txt');
			expect(treeRowPaths).not.toContain('src/generated.generated.ts');
		} finally {
			await rm(repoRoot, { force: true, recursive: true });
		}
	});

	test('loads untracked worktree files whose paths require git quote escaping', async () => {
		const repoRoot = await makeGitFixtureWorktree();
		try {
			const oddPath = 'docs/"quoted\nfile.md';
			await writeFile(join(repoRoot, oddPath), '# Odd path\n');

			const snapshot = await loadBridgeWorktreeDevSnapshot({
				baseRef: 'HEAD',
				worktreeRoot: repoRoot,
			});
			const changedPaths = snapshot.changedFiles.map((changedFile) => changedFile.path);
			const currentPaths = snapshot.currentFilePaths;

			expect(changedPaths).toContain(oddPath);
			expect(currentPaths).toContain(oddPath);
		} finally {
			await rm(repoRoot, { force: true, recursive: true });
		}
	});

	test('preserves real git rename and copy paths in the changed-file snapshot', async () => {
		const repoRoot = await makeGitRenameCopyFixtureWorktree();
		try {
			await runGitTestFixtureCommand(repoRoot, 'mv', 'src/source.ts', 'src/renamed.ts');
			await writeFile(join(repoRoot, 'src/copied.ts'), sourceFixtureContent());
			await runGitTestFixtureCommand(repoRoot, 'add', 'src/copied.ts', 'src/renamed.ts');

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
			const docsDescriptor = await loadWorktreeFileDescriptor(
				provider,
				surface,
				'docs/bridge-plan.md',
			);
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

	test('retains accepted descriptor content after a newer worktree surface refreshes', async () => {
		const repoRoot = await makeGitFixtureWorktree();
		try {
			const provider = await createBridgeWorktreeDevProvider({
				baseRef: 'HEAD',
				scenarioName: 'current-worktree',
				worktreeRoot: repoRoot,
			});
			const firstSurface = await provider.loadWorktreeFileSurface();
			const firstDocsDescriptor = await loadWorktreeFileDescriptor(
				provider,
				firstSurface,
				'docs/bridge-plan.md',
			);
			const firstRequest = worktreeFileContentRequestForDescriptor(firstDocsDescriptor);

			await writeFile(join(repoRoot, 'docs/bridge-plan.md'), '# Plan\n\nupdated docs body\n');

			const secondSurface = await provider.loadWorktreeFileSurface();
			const secondDocsDescriptor = await loadWorktreeFileDescriptor(
				provider,
				secondSurface,
				'docs/bridge-plan.md',
			);
			const secondRequest = worktreeFileContentRequestForDescriptor(secondDocsDescriptor);

			expect(secondSurface.source.sourceCursor).toBe(firstSurface.source.sourceCursor);
			expect(secondRequest.sourceCursor).toBe(secondSurface.source.sourceCursor);
			await expect(provider.loadWorktreeFileContent(firstRequest)).resolves.toContain(
				'new docs body',
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
			const firstDocsDescriptor = await loadWorktreeFileDescriptor(
				provider,
				firstSurface,
				'docs/bridge-plan.md',
			);
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
	await runGitTestFixtureCommand(repoRoot, 'init');
	await runGitTestFixtureCommand(repoRoot, 'config', 'user.name', 'Bridge Test');
	await runGitTestFixtureCommand(repoRoot, 'config', 'user.email', 'bridge@example.test');
	await runGitTestFixtureCommand(repoRoot, 'config', 'commit.gpgsign', 'false');
	await mkdir(join(repoRoot, 'src'), { recursive: true });
	await mkdir(join(repoRoot, 'docs'), { recursive: true });
	await writeFile(join(repoRoot, 'README.md'), '# Unchanged fixture\n\nstable body\n');
	await writeFile(join(repoRoot, 'src/app.ts'), 'export const value = 1;\n');
	await writeFile(join(repoRoot, 'docs/deleted-plan.md'), '# Deleted\n\nold docs body\n');
	await runGitTestFixtureCommand(repoRoot, 'add', '.');
	await runGitTestFixtureCommand(repoRoot, 'commit', '-m', 'base');
	await writeFile(join(repoRoot, 'src/app.ts'), 'export const value = 2;\n');
	await writeFile(join(repoRoot, 'docs/bridge-plan.md'), '# Plan\n\nnew docs body\n');
	await unlink(join(repoRoot, 'docs/deleted-plan.md'));
	return repoRoot;
}

async function makeGitIgnoreFixtureWorktree(): Promise<string> {
	const repoRoot = await mkdtemp(join(tmpdir(), 'bridge-worktree-provider-ignore-'));
	await runGitTestFixtureCommand(repoRoot, 'init');
	await runGitTestFixtureCommand(repoRoot, 'config', 'user.name', 'Bridge Test');
	await runGitTestFixtureCommand(repoRoot, 'config', 'user.email', 'bridge@example.test');
	await runGitTestFixtureCommand(repoRoot, 'config', 'commit.gpgsign', 'false');
	await mkdir(join(repoRoot, 'src'), { recursive: true });
	await mkdir(join(repoRoot, 'docs'), { recursive: true });
	await mkdir(join(repoRoot, 'ignored-output'), { recursive: true });
	await writeFile(join(repoRoot, '.gitignore'), 'ignored-output/\n*.generated.ts\n');
	await writeFile(join(repoRoot, 'src/app.ts'), 'export const value = 1;\n');
	await runGitTestFixtureCommand(repoRoot, 'add', '.');
	await runGitTestFixtureCommand(repoRoot, 'commit', '-m', 'base');
	await writeFile(join(repoRoot, 'src/app.ts'), 'export const value = 2;\n');
	await writeFile(join(repoRoot, 'docs/visible.md'), '# Visible\n');
	await writeFile(join(repoRoot, 'ignored-output/log.txt'), 'ignored log\n');
	await writeFile(join(repoRoot, 'src/generated.generated.ts'), 'export const generated = true;\n');
	return repoRoot;
}

async function makeLargeGitFixtureWorktree(): Promise<string> {
	const repoRoot = await mkdtemp(join(tmpdir(), 'bridge-worktree-provider-large-'));
	await runGitTestFixtureCommand(repoRoot, 'init');
	await runGitTestFixtureCommand(repoRoot, 'config', 'user.name', 'Bridge Test');
	await runGitTestFixtureCommand(repoRoot, 'config', 'user.email', 'bridge@example.test');
	await runGitTestFixtureCommand(repoRoot, 'config', 'commit.gpgsign', 'false');
	await mkdir(join(repoRoot, 'Sources'), { recursive: true });
	for (let fileIndex = 0; fileIndex < 260; fileIndex += 1) {
		const fileName = `Visible${fileIndex.toString().padStart(3, '0')}.swift`;
		// oxlint-disable-next-line no-await-in-loop -- Deterministic fixture creation is intentionally ordered.
		await writeFile(join(repoRoot, 'Sources', fileName), `struct Visible${fileIndex} {}\n`);
	}
	await runGitTestFixtureCommand(repoRoot, 'add', '.');
	await runGitTestFixtureCommand(repoRoot, 'commit', '-m', 'base');
	return repoRoot;
}

async function makeGitRenameCopyFixtureWorktree(): Promise<string> {
	const repoRoot = await mkdtemp(join(tmpdir(), 'bridge-worktree-provider-rename-copy-'));
	await runGitTestFixtureCommand(repoRoot, 'init');
	await runGitTestFixtureCommand(repoRoot, 'config', 'user.name', 'Bridge Test');
	await runGitTestFixtureCommand(repoRoot, 'config', 'user.email', 'bridge@example.test');
	await runGitTestFixtureCommand(repoRoot, 'config', 'commit.gpgsign', 'false');
	await mkdir(join(repoRoot, 'src'), { recursive: true });
	await writeFile(join(repoRoot, 'src/source.ts'), sourceFixtureContent());
	await runGitTestFixtureCommand(repoRoot, 'add', '.');
	await runGitTestFixtureCommand(repoRoot, 'commit', '-m', 'base');
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

async function runGitTestFixtureCommand(cwd: string, ...args: readonly string[]): Promise<void> {
	// Test-fixture only: product Swift-side Bridge git data prep must use agentstudio-git.
	await execFileAsync('git', args, { cwd });
}

async function runGitTestFixtureStdout(cwd: string, ...args: readonly string[]): Promise<string> {
	// Test-fixture only: product Swift-side Bridge git data prep must use agentstudio-git.
	const result = await execFileAsync('git', args, { cwd });
	return result.stdout;
}

async function loadWorktreeFileDescriptor(
	provider: BridgeWorktreeDevProvider,
	surface: BridgeWorktreeDevProviderWorktreeFileSurface,
	path: string,
): Promise<WorktreeFileDescriptor> {
	const descriptorFrame = await provider.loadWorktreeFileDescriptor({
		path,
		sourceCursor: surface.source.sourceCursor,
		subscriptionGeneration: surface.source.subscriptionGeneration,
	});
	if (descriptorFrame.descriptor.path !== path) {
		throw new Error(`Expected Worktree/File descriptor for ${path}`);
	}
	return descriptorFrame.descriptor;
}

function worktreeTreeRowPaths(
	surface: BridgeWorktreeDevProviderWorktreeFileSurface,
): readonly string[] {
	const snapshotFrame = surface.frames.find((frame) => frame.frameKind === 'worktree.snapshot');
	return snapshotFrame?.frameKind === 'worktree.snapshot'
		? (snapshotFrame.treeRows ?? []).map((row) => row.path)
		: [];
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

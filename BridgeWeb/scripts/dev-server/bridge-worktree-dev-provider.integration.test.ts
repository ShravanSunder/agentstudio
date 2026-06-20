import { execFile } from 'node:child_process';
import { mkdtemp, mkdir, realpath, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { promisify } from 'node:util';

import { describe, expect, test } from 'vitest';

import type { BridgeReviewItemDescriptor } from '../../src/foundation/review-package/bridge-review-package.js';
import {
	createBridgeWorktreeDevProvider,
	resolveBridgeWorktreeDevProviderConfig,
	type BridgeWorktreeDevProvider,
	type BridgeWorktreeDevProviderContentRequest,
} from './bridge-worktree-dev-provider.js';

const execFileAsync = promisify(execFile);

describe('Bridge worktree dev provider', () => {
	test('projects an allowlisted git worktree into Bridge metadata and lazy content handles', async () => {
		const repoRoot = await makeGitFixtureWorktree();
		try {
			const provider = await createBridgeWorktreeDevProvider({
				baseRef: 'HEAD',
				scenarioName: 'current-worktree',
				worktreeRoot: repoRoot,
			});

			const reviewPackage = await provider.loadReviewPackage();
			const items = Object.values(reviewPackage.itemsById);
			const packageJson = JSON.stringify(reviewPackage);
			const addedDocsItem = findItemByPath(provider, reviewPackage, 'docs/bridge-plan.md');
			const modifiedSourceItem = findItemByPath(provider, reviewPackage, 'src/app.ts');
			const docsHeadHandle = addedDocsItem.contentRoles.head;
			const sourceHeadHandle = modifiedSourceItem.contentRoles.head;

			expect(reviewPackage.packageId).toBe('dev-worktree');
			expect(reviewPackage.summary.filesChanged).toBe(2);
			expect(items.map((item) => item.changeKind).toSorted()).toEqual(['added', 'modified']);
			expect(addedDocsItem.fileClass).toBe('docs');
			expect(addedDocsItem.language).toBe('markdown');
			expect(modifiedSourceItem.fileClass).toBe('source');
			expect(modifiedSourceItem.language).toBe('typescript');
			expect(packageJson).not.toContain('new docs body');
			expect(packageJson).not.toContain('export const value = 2');
			expect(docsHeadHandle?.resourceUrl).toContain('agentstudio://resource/content/');
			expect(sourceHeadHandle?.resourceUrl).toContain('agentstudio://resource/content/');
			expect(docsHeadHandle?.sizeBytes).toBeGreaterThan(0);

			const docsContent = await provider.loadContent(contentRequestForHandle(docsHeadHandle));
			const sourceContent = await provider.loadContent(contentRequestForHandle(sourceHeadHandle));
			expect(docsContent).toContain('new docs body');
			expect(sourceContent).toContain('export const value = 2');
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
			const reviewPackage = await provider.loadReviewPackage();

			expect(config.worktreeRoot).toBe(await realpath(repoRoot));
			expect(config.baseRef).not.toBe('HEAD');
			expect(findItemByPath(provider, reviewPackage, 'src/feature.ts').changeKind).toBe('added');
			expect(findItemByPath(provider, reviewPackage, 'src/app.ts').changeKind).toBe('modified');
		} finally {
			await rm(repoRoot, { force: true, recursive: true });
		}
	});

	test('accepts request query overrides for dev-only worktree package routes', async () => {
		const repoRoot = await makeGitFixtureWorktree();
		try {
			const config = await resolveBridgeWorktreeDevProviderConfig({
				env: { BRIDGE_WEB_DEV_BASE: 'HEAD', BRIDGE_WEB_DEV_WORKTREE: repoRoot },
				packageRoot: join(repoRoot, 'BridgeWeb'),
				requestUrl: '/__bridge-worktree/package?scenario=current-worktree',
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
					requestUrl: '/__bridge-worktree/package?scenario=/tmp/raw-path',
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
					requestUrl: 'https://example.test/__bridge-worktree/package?scenario=current-worktree',
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
						requestUrl: `/__bridge-worktree/package?scenario=current-worktree&${query}`,
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
					requestUrl: '/__bridge-worktree/package?scenario=current-worktree',
				}),
			).rejects.toThrow(/must be the git root/);
		} finally {
			await rm(repoRoot, { force: true, recursive: true });
		}
	});

	test('rejects stale generation and revision content resource requests', async () => {
		const repoRoot = await makeGitFixtureWorktree();
		try {
			const provider = await createBridgeWorktreeDevProvider({
				baseRef: 'HEAD',
				scenarioName: 'current-worktree',
				worktreeRoot: repoRoot,
			});
			const reviewPackage = await provider.loadReviewPackage();
			const addedDocsItem = findItemByPath(provider, reviewPackage, 'docs/bridge-plan.md');
			const docsHeadHandle = addedDocsItem.contentRoles.head;
			const validContentRequest: BridgeWorktreeDevProviderContentRequest = {
				handleId: requiredHandleId(docsHeadHandle),
				reviewGeneration: reviewPackage.reviewGeneration,
				revision: reviewPackage.revision,
			};

			await expect(provider.loadContent(validContentRequest)).resolves.toContain('new docs body');
			await expect(
				provider.loadContent({ ...validContentRequest, reviewGeneration: 0 }),
			).rejects.toThrow(/stale Bridge worktree content generation/);
			await expect(provider.loadContent({ ...validContentRequest, revision: 0 })).rejects.toThrow(
				/stale Bridge worktree content revision/,
			);
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
	await writeFile(join(repoRoot, 'src/app.ts'), 'export const value = 1;\n');
	await git(repoRoot, 'add', '.');
	await git(repoRoot, 'commit', '-m', 'base');
	await mkdir(join(repoRoot, 'docs'), { recursive: true });
	await writeFile(join(repoRoot, 'src/app.ts'), 'export const value = 2;\n');
	await writeFile(join(repoRoot, 'docs/bridge-plan.md'), '# Plan\n\nnew docs body\n');
	return repoRoot;
}

async function git(cwd: string, ...args: readonly string[]): Promise<void> {
	await execFileAsync('git', args, { cwd });
}

function findItemByPath(
	_provider: BridgeWorktreeDevProvider,
	reviewPackage: Awaited<ReturnType<BridgeWorktreeDevProvider['loadReviewPackage']>>,
	path: string,
): BridgeReviewItemDescriptor {
	const item = Object.values(reviewPackage.itemsById).find(
		(candidate) => candidate.headPath === path || candidate.basePath === path,
	);
	if (item === undefined) {
		throw new Error(`Expected Bridge review item for ${path}`);
	}
	return item;
}

function contentRequestForHandle(
	handle:
		| {
				readonly handleId: string;
				readonly reviewGeneration?: number;
				readonly resourceUrl?: string;
		  }
		| null
		| undefined,
): BridgeWorktreeDevProviderContentRequest {
	const handleId = requiredHandleId(handle);
	const parsedUrl = new URL(requiredResourceUrl(handle));
	return {
		handleId,
		reviewGeneration: Number(parsedUrl.searchParams.get('generation')),
		revision: Number(parsedUrl.searchParams.get('revision')),
	};
}

function requiredHandleId(handle: { readonly handleId: string } | null | undefined): string {
	if (handle === null || handle === undefined) {
		throw new Error('Expected Bridge content handle');
	}
	return handle.handleId;
}

function requiredResourceUrl(handle: { readonly resourceUrl?: string } | null | undefined): string {
	if (handle === null || handle === undefined || handle.resourceUrl === undefined) {
		throw new Error('Expected Bridge content resource URL');
	}
	return handle.resourceUrl;
}

import { mkdtemp, mkdir, realpath, rm, symlink, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

import { afterEach, describe, expect, test } from 'vitest';

import { resolveBridgeWorktreeVerifierWritePath } from './verify-bridge-viewer-worktree-dev-server-paths.js';

describe('resolveBridgeWorktreeVerifierWritePath', () => {
	let tempRootPath: string | null = null;

	afterEach(async () => {
		if (tempRootPath !== null) {
			await rm(tempRootPath, { force: true, recursive: true });
			tempRootPath = null;
		}
	});

	test('resolves an existing descriptor path inside the worktree root', async () => {
		const { repoRootPath } = await makeVerifierPathFixture();
		const filePath = join(repoRootPath, 'src', 'app.ts');
		await mkdir(join(repoRootPath, 'src'));
		await writeFile(filePath, 'export const value = 1;\n');

		await expect(
			resolveBridgeWorktreeVerifierWritePath({
				descriptorPath: 'src/app.ts',
				rootPath: repoRootPath,
			}),
		).resolves.toBe(await realpath(filePath));
	});

	test('rejects parent-directory descriptor paths before verifier writes', async () => {
		const { parentPath, repoRootPath } = await makeVerifierPathFixture();
		await writeFile(join(parentPath, 'escape.txt'), 'outside\n');

		await expect(
			resolveBridgeWorktreeVerifierWritePath({
				descriptorPath: '../escape.txt',
				rootPath: repoRootPath,
			}),
		).rejects.toThrow(/escapes root/u);
	});

	test('rejects absolute descriptor paths before verifier writes', async () => {
		const { parentPath, repoRootPath } = await makeVerifierPathFixture();
		const outsidePath = join(parentPath, 'absolute-escape.txt');
		await writeFile(outsidePath, 'outside\n');

		await expect(
			resolveBridgeWorktreeVerifierWritePath({
				descriptorPath: outsidePath,
				rootPath: repoRootPath,
			}),
		).rejects.toThrow(/must be relative/u);
	});

	test('rejects descriptor paths that resolve through symlinks outside the root', async () => {
		const { parentPath, repoRootPath } = await makeVerifierPathFixture();
		const outsidePath = join(parentPath, 'symlink-target.txt');
		await writeFile(outsidePath, 'outside\n');
		await symlink(outsidePath, join(repoRootPath, 'linked-file.ts'));

		await expect(
			resolveBridgeWorktreeVerifierWritePath({
				descriptorPath: 'linked-file.ts',
				rootPath: repoRootPath,
			}),
		).rejects.toThrow(/escapes root/u);
	});

	async function makeVerifierPathFixture(): Promise<{
		readonly parentPath: string;
		readonly repoRootPath: string;
	}> {
		tempRootPath = await mkdtemp(join(tmpdir(), 'bridge-verifier-paths-'));
		const repoRootPath = join(tempRootPath, 'repo');
		await mkdir(repoRootPath);
		return {
			parentPath: tempRootPath,
			repoRootPath,
		};
	}
});

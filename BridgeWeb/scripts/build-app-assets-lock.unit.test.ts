import { mkdir, rmdir, unlink, utimes, writeFile } from 'node:fs/promises';
import { join } from 'node:path';

import { afterEach, beforeEach, describe, expect, test } from 'vitest';

import { withBridgeWebAppBuildLock } from './build-app-assets-lock.ts';

const buildLockParentDirectoryPath = new URL('../../tmp/bridge-web-assets/', import.meta.url);
const buildLockDirectoryPath = join(buildLockParentDirectoryPath.pathname, 'build-app-assets.lock');
const buildLockOwnerFilePath = join(buildLockDirectoryPath, 'owner.json');
const staleLockTimestamp = new Date(Date.now() - 121_000);

describe('BridgeWeb app asset build lock', () => {
	beforeEach(async () => {
		await removeTestLockDirectory();
	});

	afterEach(async () => {
		await removeTestLockDirectory();
	});

	test('recovers a lock left behind by a dead owner process', async () => {
		await mkdir(buildLockDirectoryPath, { recursive: true });
		await writeFile(
			buildLockOwnerFilePath,
			JSON.stringify({
				pid: 2_147_483_647,
				acquiredAtMilliseconds: Date.now() - 10_000,
				token: 'abandoned-test-owner',
			}),
		);

		await expectBuildLockRecovery();
	});

	test('recovers a stale ownerless lock directory', async () => {
		await mkdir(buildLockDirectoryPath, { recursive: true });
		await utimes(buildLockDirectoryPath, staleLockTimestamp, staleLockTimestamp);

		await expectBuildLockRecovery();
	});
});

async function expectBuildLockRecovery(): Promise<void> {
	let didEnterCriticalSection = false;
	const buildLockPromise = withBridgeWebAppBuildLock(async (): Promise<void> => {
		didEnterCriticalSection = true;
	});
	const recoveryResultPromise = Promise.race([
		buildLockPromise.then((): boolean => true),
		new Promise<boolean>((resolve): void => {
			setTimeout((): void => {
				resolve(false);
			}, 1_000);
		}),
	]);

	await expect(recoveryResultPromise).resolves.toBe(true);
	expect(didEnterCriticalSection).toBe(true);
}

async function removeTestLockDirectory(): Promise<void> {
	await unlink(buildLockOwnerFilePath).catch(ignoreMissingPath);
	await rmdir(buildLockDirectoryPath).catch(ignoreMissingPath);
}

function ignoreMissingPath(error: unknown): void {
	if (!isNodeErrorWithCode(error, 'ENOENT')) {
		throw error;
	}
}

function isNodeErrorWithCode(error: unknown, code: string): boolean {
	return (
		typeof error === 'object' &&
		error !== null &&
		'code' in error &&
		(error as { readonly code?: unknown }).code === code
	);
}

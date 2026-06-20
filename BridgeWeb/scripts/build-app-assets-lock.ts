import { mkdir, rmdir } from 'node:fs/promises';
import { join } from 'node:path';
import { setTimeout as sleep } from 'node:timers/promises';
import { fileURLToPath } from 'node:url';

const buildLockParentDirectoryPath = fileURLToPath(
	new URL('../../tmp/bridge-web-assets/', import.meta.url),
);
const buildLockDirectoryPath = join(buildLockParentDirectoryPath, 'build-app-assets.lock');
const buildLockPollMilliseconds = 250;
const buildLockTimeoutMilliseconds = 120_000;

export async function withBridgeWebAppBuildLock(run: () => Promise<void>): Promise<void> {
	const releaseLock = await acquireBridgeWebAppBuildLock();
	try {
		await run();
	} finally {
		await releaseLock();
	}
}

async function acquireBridgeWebAppBuildLock(): Promise<() => Promise<void>> {
	await mkdir(buildLockParentDirectoryPath, { recursive: true });
	return acquireBridgeWebAppBuildLockAttempt(Date.now());
}

async function acquireBridgeWebAppBuildLockAttempt(
	startedAtMilliseconds: number,
): Promise<() => Promise<void>> {
	try {
		await mkdir(buildLockDirectoryPath);
		return async (): Promise<void> => {
			await rmdir(buildLockDirectoryPath);
		};
	} catch (error) {
		if (!isNodeErrorWithCode(error, 'EEXIST')) {
			throw error;
		}
		if (Date.now() - startedAtMilliseconds > buildLockTimeoutMilliseconds) {
			throw new Error(
				`Timed out waiting for BridgeWeb app asset build lock: ${buildLockDirectoryPath}`,
				{ cause: error },
			);
		}
		await sleep(buildLockPollMilliseconds);
		return acquireBridgeWebAppBuildLockAttempt(startedAtMilliseconds);
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

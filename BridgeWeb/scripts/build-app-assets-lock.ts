import { randomUUID } from 'node:crypto';
import { mkdir, readFile, rmdir, stat, unlink, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { setTimeout as sleep } from 'node:timers/promises';
import { fileURLToPath } from 'node:url';

const buildLockParentDirectoryPath = fileURLToPath(
	new URL('../../tmp/bridge-web-assets/', import.meta.url),
);
const buildLockDirectoryPath = join(buildLockParentDirectoryPath, 'build-app-assets.lock');
const buildLockOwnerFilePath = join(buildLockDirectoryPath, 'owner.json');
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
		const owner = createBuildLockOwner();
		await writeBuildLockOwner(owner);
		return async (): Promise<void> => {
			await releaseBridgeWebAppBuildLock(owner);
		};
	} catch (error) {
		if (!isNodeErrorWithCode(error, 'EEXIST')) {
			throw error;
		}
		if (await reapRecoverableBridgeWebAppBuildLock()) {
			return acquireBridgeWebAppBuildLockAttempt(startedAtMilliseconds);
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

interface BuildLockOwner {
	readonly pid: number;
	readonly acquiredAtMilliseconds: number;
	readonly token: string;
}

function createBuildLockOwner(): BuildLockOwner {
	return {
		pid: process.pid,
		acquiredAtMilliseconds: Date.now(),
		token: randomUUID(),
	};
}

async function writeBuildLockOwner(owner: BuildLockOwner): Promise<void> {
	try {
		await writeFile(buildLockOwnerFilePath, `${JSON.stringify(owner)}\n`, { flag: 'wx' });
	} catch (error) {
		await rmdir(buildLockDirectoryPath).catch(ignoreMissingPath);
		throw error;
	}
}

async function releaseBridgeWebAppBuildLock(owner: BuildLockOwner): Promise<void> {
	const currentOwner = await readBuildLockOwner();
	if (currentOwner !== null && currentOwner.token !== owner.token) {
		return;
	}

	await unlink(buildLockOwnerFilePath).catch(ignoreMissingPath);
	await rmdir(buildLockDirectoryPath).catch(ignoreMissingPath);
}

async function reapRecoverableBridgeWebAppBuildLock(): Promise<boolean> {
	const currentOwner = await readBuildLockOwner();
	if (currentOwner !== null) {
		if (!isProcessRunning(currentOwner.pid)) {
			await removeBridgeWebAppBuildLock();
			return true;
		}
		return false;
	}

	const lockDirectoryStat = await stat(buildLockDirectoryPath).catch((error: unknown): null => {
		if (isNodeErrorWithCode(error, 'ENOENT')) {
			return null;
		}
		throw error;
	});
	if (lockDirectoryStat === null) {
		return true;
	}

	if (Date.now() - lockDirectoryStat.mtimeMs <= buildLockTimeoutMilliseconds) {
		return false;
	}

	await removeBridgeWebAppBuildLock();
	return true;
}

async function readBuildLockOwner(): Promise<BuildLockOwner | null> {
	const ownerJson = await readFile(buildLockOwnerFilePath, 'utf8').catch((error: unknown): null => {
		if (isNodeErrorWithCode(error, 'ENOENT')) {
			return null;
		}
		throw error;
	});
	if (ownerJson === null) {
		return null;
	}

	const owner: unknown = parseJson(ownerJson);
	if (!isBuildLockOwner(owner)) {
		return null;
	}
	return owner;
}

function parseJson(json: string): unknown {
	try {
		return JSON.parse(json);
	} catch (error) {
		if (error instanceof SyntaxError) {
			return null;
		}
		throw error;
	}
}

function isBuildLockOwner(owner: unknown): owner is BuildLockOwner {
	return (
		typeof owner === 'object' &&
		owner !== null &&
		'pid' in owner &&
		typeof owner.pid === 'number' &&
		Number.isSafeInteger(owner.pid) &&
		owner.pid > 0 &&
		'acquiredAtMilliseconds' in owner &&
		typeof owner.acquiredAtMilliseconds === 'number' &&
		Number.isFinite(owner.acquiredAtMilliseconds) &&
		'token' in owner &&
		typeof owner.token === 'string' &&
		owner.token.length > 0
	);
}

function isProcessRunning(pid: number): boolean {
	try {
		process.kill(pid, 0);
		return true;
	} catch (error) {
		if (isNodeErrorWithCode(error, 'ESRCH') || isNodeErrorWithCode(error, 'EINVAL')) {
			return false;
		}
		if (isNodeErrorWithCode(error, 'EPERM')) {
			return true;
		}
		throw error;
	}
}

async function removeBridgeWebAppBuildLock(): Promise<void> {
	await unlink(buildLockOwnerFilePath).catch(ignoreMissingPath);
	await rmdir(buildLockDirectoryPath).catch((error: unknown): void => {
		if (!isNodeErrorWithCode(error, 'ENOENT') && !isNodeErrorWithCode(error, 'ENOTEMPTY')) {
			throw error;
		}
	});
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

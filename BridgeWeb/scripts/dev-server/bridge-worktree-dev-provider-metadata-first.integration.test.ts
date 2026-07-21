import { execFile } from 'node:child_process';
import { createHash } from 'node:crypto';
import { mkdir, mkdtemp, readFile, realpath, rm, stat, utimes, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, relative, resolve, sep } from 'node:path';
import { promisify } from 'node:util';

import { afterEach, describe, expect, test } from 'vitest';

import { BridgeProductDevReviewAdapter } from './bridge-product-dev-review-adapter.ts';
import {
	BRIDGE_WORKTREE_DEV_MAXIMUM_FILESYSTEM_CONCURRENCY,
	BRIDGE_WORKTREE_DEV_MAXIMUM_GIT_CONCURRENCY,
	BRIDGE_WORKTREE_DEV_RETAINED_CONTENT_BODY_LIMIT,
	BRIDGE_WORKTREE_DEV_RETAINED_CONTENT_BYTE_LIMIT,
	BRIDGE_WORKTREE_DEV_RETAINED_PROVIDER_STATE_LIMIT,
	createBridgeWorktreeDevPorts,
	createBridgeWorktreeDevProvider,
	hydrateBridgeWorktreeDevContentWindow,
	loadBridgeWorktreeDevMetadataSnapshot,
	type BridgeWorktreeDevProviderWorktreeFileSurface,
	type BridgeWorktreeDevPortObserver,
} from './bridge-worktree-dev-provider.ts';
import { resolveDefaultBaseRef } from './bridge-worktree-dev-provider/files.ts';

const execFileAsync = promisify(execFile);
const fixtureRoots: string[] = [];
const validStartupFixtureSha256 =
	'10331eb3c39f7ff25da92c8cdae394446bc7b11fb7b3be25d7bbf94260862173';

interface CountedPortMetrics {
	activeFilesystemOperationCount: number;
	activeGitChildCount: number;
	contentBodyByteCount: number;
	contentBodyReadCount: number;
	contentGitShowCount: number;
	filesystemMetadataOperationCount: number;
	gitChildCount: number;
	maximumFilesystemConcurrency: number;
	maximumGitConcurrency: number;
}

class CountedPortObserver implements BridgeWorktreeDevPortObserver {
	readonly metrics: CountedPortMetrics = {
		activeFilesystemOperationCount: 0,
		activeGitChildCount: 0,
		contentBodyByteCount: 0,
		contentBodyReadCount: 0,
		contentGitShowCount: 0,
		filesystemMetadataOperationCount: 0,
		gitChildCount: 0,
		maximumFilesystemConcurrency: 0,
		maximumGitConcurrency: 0,
	};
	abortControllerOnNextGitStart: AbortController | null = null;

	readonly fileMetadataFinished = (): void => {
		this.metrics.activeFilesystemOperationCount -= 1;
	};

	readonly fileMetadataStarted = (): void => {
		this.metrics.filesystemMetadataOperationCount += 1;
		this.#filesystemOperationStarted();
	};

	readonly fileWindowFinished = (byteCount: number): void => {
		this.metrics.contentBodyByteCount += byteCount;
		this.metrics.activeFilesystemOperationCount -= 1;
	};

	readonly fileWindowStarted = (): void => {
		this.metrics.contentBodyReadCount += 1;
		this.#filesystemOperationStarted();
	};

	readonly gitFinished = (): void => {
		this.metrics.activeGitChildCount -= 1;
	};

	readonly gitStarted = (args: readonly string[]): void => {
		this.metrics.gitChildCount += 1;
		this.metrics.activeGitChildCount += 1;
		this.metrics.maximumGitConcurrency = Math.max(
			this.metrics.maximumGitConcurrency,
			this.metrics.activeGitChildCount,
		);
		if (args[0] === 'show') this.metrics.contentGitShowCount += 1;
		const abortController = this.abortControllerOnNextGitStart;
		this.abortControllerOnNextGitStart = null;
		abortController?.abort();
	};

	readonly realpathFinished = (): void => {
		this.metrics.activeFilesystemOperationCount -= 1;
	};

	readonly realpathStarted = (): void => {
		this.metrics.filesystemMetadataOperationCount += 1;
		this.#filesystemOperationStarted();
	};

	#filesystemOperationStarted(): void {
		this.metrics.activeFilesystemOperationCount += 1;
		this.metrics.maximumFilesystemConcurrency = Math.max(
			this.metrics.maximumFilesystemConcurrency,
			this.metrics.activeFilesystemOperationCount,
		);
	}
}

afterEach(async () => {
	await Promise.all(
		fixtureRoots.splice(0).map(async (root) => await rm(root, { force: true, recursive: true })),
	);
});

describe('Bridge worktree dev provider metadata-first source', () => {
	test('publishes synthetic large-repo metadata without bodies and hydrates only selected head/base windows', async () => {
		const repoRoot = await makeSyntheticLargeRepo();
		const observer = new CountedPortObserver();
		const ports = createBridgeWorktreeDevPorts(observer);
		const provider = await createBridgeWorktreeDevProvider(
			{ baseRef: 'HEAD', scenarioName: 'current-worktree', worktreeRoot: repoRoot },
			{ ports },
		);

		const surface = await provider.loadWorktreeFileSurface();
		const metadataMetrics = { ...observer.metrics };
		const startupDiagnostics = provider.diagnostics?.();

		expect(metadataMetrics.gitChildCount).toBe(7);
		expect(metadataMetrics.contentGitShowCount).toBe(0);
		expect(metadataMetrics.contentBodyReadCount).toBe(0);
		expect(metadataMetrics.contentBodyByteCount).toBe(0);
		expect(metadataMetrics.maximumGitConcurrency).toBeLessThanOrEqual(
			BRIDGE_WORKTREE_DEV_MAXIMUM_GIT_CONCURRENCY,
		);
		expect(metadataMetrics.maximumFilesystemConcurrency).toBeLessThanOrEqual(
			BRIDGE_WORKTREE_DEV_MAXIMUM_FILESYSTEM_CONCURRENCY,
		);
		expect(startupDiagnostics?.retainedContentBodyCount).toBe(0);
		expect(startupDiagnostics?.retainedContentByteCount).toBe(0);
		expect(surface.frames.some((frame) => frame.frameKind === 'worktree.fileDescriptor')).toBe(
			false,
		);

		const selectedPath = 'Sources/Tracked042.swift';
		const selectedText = syntheticHeadText(42);
		const descriptorFrame = await provider.loadWorktreeFileDescriptor({
			maximumBytes: 4_096,
			path: selectedPath,
			sourceCursor: surface.source.sourceCursor,
			subscriptionGeneration: surface.source.subscriptionGeneration,
		});
		const descriptor = descriptorFrame.descriptor;
		const selectedContent = await provider.loadWorktreeFileContent({
			descriptorId: descriptor.contentHandle,
			sourceCursor: surface.source.sourceCursor,
			subscriptionGeneration: surface.source.subscriptionGeneration,
		});

		expect(selectedContent).toBe(selectedText);
		expect(descriptor.contentHash).toBe(`sha256:${sha256Text(selectedText)}`);
		expect(observer.metrics.contentBodyReadCount).toBe(1);
		expect(observer.metrics.contentBodyByteCount).toBe(Buffer.byteLength(selectedText));
		expect(observer.metrics.contentGitShowCount).toBe(0);
		expect(provider.diagnostics?.().retainedContentBodyCount).toBe(1);

		const metadataSnapshot = await loadBridgeWorktreeDevMetadataSnapshot({
			baseRef: 'HEAD',
			ports,
			worktreeRoot: repoRoot,
		});
		const selectedChange = metadataSnapshot.changedFiles.find(
			(changedFile) => changedFile.path === selectedPath,
		);
		expect(selectedChange).toBeDefined();
		if (selectedChange === undefined) return;
		const baseWindow = await hydrateBridgeWorktreeDevContentWindow({
			baseRef: 'HEAD',
			changedFile: selectedChange,
			maximumBytes: 4_096,
			ports,
			role: 'base',
			startByte: 0,
			worktreeRoot: repoRoot,
		});
		const expectedBaseText = syntheticBaseText(42);

		expect(new TextDecoder().decode(baseWindow.bytes)).toBe(expectedBaseText);
		expect(baseWindow.sha256).toBe(sha256Text(expectedBaseText));
		expect(observer.metrics.contentGitShowCount).toBe(1);
		expect(observer.metrics.contentBodyReadCount).toBe(1);
		expect(observer.metrics.maximumGitConcurrency).toBeLessThanOrEqual(
			BRIDGE_WORKTREE_DEV_MAXIMUM_GIT_CONCURRENCY,
		);
		expect(observer.metrics.maximumFilesystemConcurrency).toBeLessThanOrEqual(
			BRIDGE_WORKTREE_DEV_MAXIMUM_FILESYSTEM_CONCURRENCY,
		);
	});

	test('joins cancelled metadata work with zero active children tasks or retained bodies', async () => {
		const repoRoot = await makeSyntheticLargeRepo();
		const observer = new CountedPortObserver();
		const ports = createBridgeWorktreeDevPorts(observer);
		const abortController = new AbortController();
		const provider = await createBridgeWorktreeDevProvider(
			{ baseRef: 'HEAD', scenarioName: 'current-worktree', worktreeRoot: repoRoot },
			{ ports, signal: abortController.signal },
		);
		observer.abortControllerOnNextGitStart = abortController;

		await expect(provider.loadWorktreeFileSurface()).rejects.toMatchObject({ name: 'AbortError' });

		expect(observer.metrics.activeGitChildCount).toBe(0);
		expect(observer.metrics.activeFilesystemOperationCount).toBe(0);
		expect(observer.metrics.contentBodyReadCount).toBe(0);
		expect(provider.diagnostics?.()).toEqual({
			retainedContentBodyCount: 0,
			retainedContentByteCount: 0,
			retainedProviderStateCount: 0,
		});
	});

	test('changes Review publication identity when same-size dirty bytes change under restored mtimes', async () => {
		// Arrange
		const repoRoot = await makePublicationIdentityRepo();
		const trackedPath = join(repoRoot, 'Tracked.txt');
		const untrackedPath = join(repoRoot, 'Untracked.txt');
		const fixedTimestamp = new Date(1_700_000_000_000);
		await utimes(trackedPath, fixedTimestamp, fixedTimestamp);
		await utimes(untrackedPath, fixedTimestamp, fixedTimestamp);
		const firstTrackedMetadata = await stat(trackedPath);
		const firstUntrackedMetadata = await stat(untrackedPath);
		const firstNumstat = await gitStdout(repoRoot, ['diff', '--numstat', 'HEAD', '--']);
		const firstSnapshot = await loadBridgeWorktreeDevMetadataSnapshot({
			baseRef: 'HEAD',
			worktreeRoot: repoRoot,
		});
		const firstPublication = await new BridgeProductDevReviewAdapter({
			baseRef: 'HEAD',
			worktreeRoot: repoRoot,
		}).loadSource();
		const unchangedReplacementPublication = await new BridgeProductDevReviewAdapter({
			baseRef: 'HEAD',
			worktreeRoot: repoRoot,
		}).loadSource();

		// Act
		await writeFile(trackedPath, 'cccccc\n');
		await writeFile(untrackedPath, 'yyyyyy\n');
		await utimes(trackedPath, fixedTimestamp, fixedTimestamp);
		await utimes(untrackedPath, fixedTimestamp, fixedTimestamp);
		const secondNumstat = await gitStdout(repoRoot, ['diff', '--numstat', 'HEAD', '--']);
		const secondTrackedMetadata = await stat(trackedPath);
		const secondUntrackedMetadata = await stat(untrackedPath);
		const secondSnapshot = await loadBridgeWorktreeDevMetadataSnapshot({
			baseRef: 'HEAD',
			worktreeRoot: repoRoot,
		});
		const secondPublication = await new BridgeProductDevReviewAdapter({
			baseRef: 'HEAD',
			worktreeRoot: repoRoot,
		}).loadSource();

		// Assert
		expect(secondNumstat).toBe(firstNumstat);
		expect(secondTrackedMetadata.size).toBe(firstTrackedMetadata.size);
		expect(Math.trunc(secondTrackedMetadata.mtimeMs)).toBe(
			Math.trunc(firstTrackedMetadata.mtimeMs),
		);
		expect(secondUntrackedMetadata.size).toBe(firstUntrackedMetadata.size);
		expect(Math.trunc(secondUntrackedMetadata.mtimeMs)).toBe(
			Math.trunc(firstUntrackedMetadata.mtimeMs),
		);
		expect(unchangedReplacementPublication.events[0]?.publicationId).toBe(
			firstPublication.events[0]?.publicationId,
		);
		expect(secondSnapshot.fingerprint).not.toBe(firstSnapshot.fingerprint);
		expect(secondPublication.events[0]?.publicationId).not.toBe(
			firstPublication.events[0]?.publicationId,
		);
	});

	test('bounds post-demand content retention under the named body LRU policies', async () => {
		const repoRoot = await makeLruPressureRepo();
		const observer = new CountedPortObserver();
		const provider = await createBridgeWorktreeDevProvider(
			{ baseRef: 'HEAD', scenarioName: 'current-worktree', worktreeRoot: repoRoot },
			{ ports: createBridgeWorktreeDevPorts(observer) },
		);
		const surface = await provider.loadWorktreeFileSurface();

		// oxlint-disable no-await-in-loop -- Ordered demand is the content LRU policy input under test.
		for (let fileIndex = 0; fileIndex < 9; fileIndex += 1) {
			const descriptor =
				// oxlint-disable-next-line no-await-in-loop -- LRU admission order is the behavior under test.
				(
					await provider.loadWorktreeFileDescriptor({
						maximumBytes: lruPressureBodyByteCount,
						path: lruPressureFilePath(fileIndex),
						sourceCursor: surface.source.sourceCursor,
						subscriptionGeneration: surface.source.subscriptionGeneration,
					})
				).descriptor;
			// oxlint-disable-next-line no-await-in-loop -- Each demand must complete before the next LRU admission.
			await expect(
				provider.loadWorktreeFileContent({
					descriptorId: descriptor.contentHandle,
					sourceCursor: surface.source.sourceCursor,
					subscriptionGeneration: surface.source.subscriptionGeneration,
				}),
			).resolves.toHaveLength(lruPressureBodyByteCount);
		}

		// oxlint-enable no-await-in-loop
		const diagnostics = provider.diagnostics?.();

		expect(diagnostics?.retainedContentBodyCount).toBe(
			BRIDGE_WORKTREE_DEV_RETAINED_CONTENT_BODY_LIMIT,
		);
		expect(diagnostics?.retainedContentByteCount).toBe(
			BRIDGE_WORKTREE_DEV_RETAINED_CONTENT_BYTE_LIMIT,
		);
		expect(observer.metrics.contentBodyReadCount).toBe(9);
		expect(observer.metrics.contentBodyByteCount).toBe(9 * lruPressureBodyByteCount);
		expect(observer.metrics.maximumFilesystemConcurrency).toBeLessThanOrEqual(
			BRIDGE_WORKTREE_DEV_MAXIMUM_FILESYSTEM_CONCURRENCY,
		);
	});

	test('bounds provider-state retention under the named state LRU policy', async () => {
		const repoRoot = await makePublicationIdentityRepo();
		const provider = await createBridgeWorktreeDevProvider({
			baseRef: 'HEAD',
			scenarioName: 'current-worktree',
			worktreeRoot: repoRoot,
		});
		const initialSurface = await provider.loadWorktreeFileSurface();
		const retainedPath = 'Tracked.txt';
		const retainedDescriptor = (
			await provider.loadWorktreeFileDescriptor({
				maximumBytes: 4_096,
				path: retainedPath,
				sourceCursor: initialSurface.source.sourceCursor,
				subscriptionGeneration: initialSurface.source.subscriptionGeneration,
			})
		).descriptor;
		const retainedContent = await provider.loadWorktreeFileContent({
			descriptorId: retainedDescriptor.contentHandle,
			sourceCursor: initialSurface.source.sourceCursor,
			subscriptionGeneration: initialSurface.source.subscriptionGeneration,
		});

		for (let refreshIndex = 0; refreshIndex < 6; refreshIndex += 1) {
			// oxlint-disable-next-line no-await-in-loop -- Each distinct fingerprint must become the next retained state.
			await writeFile(
				join(repoRoot, `Refresh${refreshIndex}.txt`),
				`refresh-${refreshIndex}-${'x'.repeat(refreshIndex)}\n`,
			);
			// oxlint-disable-next-line no-await-in-loop -- Refresh state order is the retention policy input.
			await provider.loadWorktreeFileSurface();
		}

		const diagnostics = provider.diagnostics?.();
		expect(diagnostics?.retainedProviderStateCount).toBe(
			BRIDGE_WORKTREE_DEV_RETAINED_PROVIDER_STATE_LIMIT,
		);
		expect(diagnostics?.retainedContentBodyCount).toBe(1);
		expect(diagnostics?.retainedContentByteCount).toBe(Buffer.byteLength(retainedContent));
	});

	test('records a pathless current-worktree freshness and counted proof receipt', async () => {
		const worktreeRoot = await realpath(resolve(process.cwd(), '..'));
		const resolvedBaseRef = await resolveDefaultBaseRef(worktreeRoot);
		const mergeBase = (await gitStdout(worktreeRoot, ['rev-parse', resolvedBaseRef])).trim();
		const head = (await gitStdout(worktreeRoot, ['rev-parse', 'HEAD'])).trim();
		const observer = new CountedPortObserver();
		const provider = await createBridgeWorktreeDevProvider(
			{
				baseRef: mergeBase,
				scenarioName: 'current-worktree',
				worktreeRoot,
			},
			{ ports: createBridgeWorktreeDevPorts(observer) },
		);

		const surface = await provider.loadWorktreeFileSurface();
		const metadataMetrics = { ...observer.metrics };
		const changedPathCount = changedFileRowCount(surface);
		const selectedPath = firstTextSourcePath(surface);
		const descriptor = (
			await provider.loadWorktreeFileDescriptor({
				maximumBytes: 64 * 1024,
				path: selectedPath,
				sourceCursor: surface.source.sourceCursor,
				subscriptionGeneration: surface.source.subscriptionGeneration,
			})
		).descriptor;
		const selectedContent = await provider.loadWorktreeFileContent({
			descriptorId: descriptor.contentHandle,
			sourceCursor: surface.source.sourceCursor,
			subscriptionGeneration: surface.source.subscriptionGeneration,
		});
		const fingerprints = await currentWorktreeFingerprints(worktreeRoot);
		const gitVersion = (await execFileAsync('git', ['--version'])).stdout.trim();
		const receipt = {
			changedPathCount,
			contentBodyByteCount: observer.metrics.contentBodyByteCount,
			contentBodyReadCount: observer.metrics.contentBodyReadCount,
			contentGitShowCount: observer.metrics.contentGitShowCount,
			filesystemMetadataOperationCount: metadataMetrics.filesystemMetadataOperationCount,
			fullDirtyFingerprint: fingerprints.fullDirtyFingerprint,
			gitChildCountBeforeDemand: metadataMetrics.gitChildCount,
			gitVersion,
			head,
			maximumFilesystemConcurrency: observer.metrics.maximumFilesystemConcurrency,
			maximumGitConcurrency: observer.metrics.maximumGitConcurrency,
			mergeBase,
			nodeVersion: process.version,
			retainedBodyCountBeforeDemand: 0,
			retainedBodyCountAfterDemand: provider.diagnostics?.().retainedContentBodyCount ?? null,
			selectedChecksum: sha256Text(selectedContent),
			sourceFingerprint: surface.source.rootRevisionToken,
			treePathCount: surface.treeSizeFacts.pathCount,
			trackedDiffFingerprint: fingerprints.trackedDiffFingerprint,
			untrackedContentFingerprint: fingerprints.untrackedContentFingerprint,
			validStartupFixtureSha256,
		};

		expect(metadataMetrics.contentBodyReadCount).toBe(0);
		expect(metadataMetrics.contentGitShowCount).toBe(0);
		expect(metadataMetrics.gitChildCount).toBe(7);
		expect(receipt.maximumGitConcurrency).toBeLessThanOrEqual(
			BRIDGE_WORKTREE_DEV_MAXIMUM_GIT_CONCURRENCY,
		);
		expect(receipt.maximumFilesystemConcurrency).toBeLessThanOrEqual(
			BRIDGE_WORKTREE_DEV_MAXIMUM_FILESYSTEM_CONCURRENCY,
		);
		expect(descriptor.contentHash).toBe(`sha256:${receipt.selectedChecksum}`);
		expect(receipt.fullDirtyFingerprint).toMatch(/^[a-f0-9]{64}$/u);
		expect(receipt.head).toMatch(/^[a-f0-9]{40}$/u);
		expect(receipt.mergeBase).toMatch(/^[a-f0-9]{40}$/u);
		console.info(`BRIDGE_WORKTREE_N1_PROOF ${JSON.stringify(receipt)}`);
	});

	test('loads the provider entrypoint through direct Node strip-types resolution', async () => {
		await expect(
			execFileAsync(
				process.execPath,
				[
					'--experimental-strip-types',
					'--input-type=module',
					'--eval',
					"await import('./scripts/dev-server/bridge-worktree-dev-provider.ts')",
				],
				{ cwd: process.cwd() },
			),
		).resolves.toMatchObject({ stderr: '', stdout: '' });
	});
});

async function makeSyntheticLargeRepo(): Promise<string> {
	const repoRoot = await mkdtemp(join(tmpdir(), 'bridge-worktree-metadata-first-'));
	fixtureRoots.push(repoRoot);
	await runGit(repoRoot, ['init']);
	await runGit(repoRoot, ['config', 'user.name', 'Bridge Test']);
	await runGit(repoRoot, ['config', 'user.email', 'bridge@example.test']);
	await runGit(repoRoot, ['config', 'commit.gpgsign', 'false']);
	await mkdir(join(repoRoot, 'Sources'), { recursive: true });
	await Promise.all(
		Array.from({ length: 128 }, async (_, fileIndex) => {
			await writeFile(
				join(repoRoot, 'Sources', trackedFileName(fileIndex)),
				syntheticBaseText(fileIndex),
			);
		}),
	);
	await runGit(repoRoot, ['add', '.']);
	await runGit(repoRoot, ['commit', '-m', 'base']);
	await Promise.all([
		...Array.from({ length: 96 }, async (_, fileIndex) => {
			await writeFile(
				join(repoRoot, 'Sources', trackedFileName(fileIndex)),
				syntheticHeadText(fileIndex),
			);
		}),
		...Array.from({ length: 32 }, async (_, fileIndex) => {
			await writeFile(
				join(repoRoot, 'Sources', `Untracked${fileIndex.toString().padStart(3, '0')}.swift`),
				`struct Untracked${fileIndex} {}\n`,
			);
		}),
	]);
	return repoRoot;
}

async function makePublicationIdentityRepo(): Promise<string> {
	const repoRoot = await mkdtemp(join(tmpdir(), 'bridge-review-publication-identity-'));
	fixtureRoots.push(repoRoot);
	await runGit(repoRoot, ['init']);
	await runGit(repoRoot, ['config', 'user.name', 'Bridge Test']);
	await runGit(repoRoot, ['config', 'user.email', 'bridge@example.test']);
	await runGit(repoRoot, ['config', 'commit.gpgsign', 'false']);
	await writeFile(join(repoRoot, 'Tracked.txt'), 'aaaaaa\n');
	await runGit(repoRoot, ['add', '.']);
	await runGit(repoRoot, ['commit', '-m', 'base']);
	await writeFile(join(repoRoot, 'Tracked.txt'), 'bbbbbb\n');
	await writeFile(join(repoRoot, 'Untracked.txt'), 'xxxxxx\n');
	return repoRoot;
}

const lruPressureBodyByteCount = 4 * 1024 * 1024;

async function makeLruPressureRepo(): Promise<string> {
	const repoRoot = await mkdtemp(join(tmpdir(), 'bridge-worktree-lru-pressure-'));
	fixtureRoots.push(repoRoot);
	await runGit(repoRoot, ['init']);
	await runGit(repoRoot, ['config', 'user.name', 'Bridge Test']);
	await runGit(repoRoot, ['config', 'user.email', 'bridge@example.test']);
	await runGit(repoRoot, ['config', 'commit.gpgsign', 'false']);
	await writeFile(join(repoRoot, 'README.md'), 'LRU pressure fixture\n');
	await runGit(repoRoot, ['add', '.']);
	await runGit(repoRoot, ['commit', '-m', 'base']);
	await mkdir(join(repoRoot, 'Large'), { recursive: true });
	const body = 'x'.repeat(lruPressureBodyByteCount);
	await Promise.all(
		Array.from({ length: 9 }, async (_, fileIndex) => {
			await writeFile(join(repoRoot, lruPressureFilePath(fileIndex)), body);
		}),
	);
	return repoRoot;
}

function lruPressureFilePath(fileIndex: number): string {
	return `Large/Body${fileIndex.toString().padStart(2, '0')}.txt`;
}

function trackedFileName(fileIndex: number): string {
	return `Tracked${fileIndex.toString().padStart(3, '0')}.swift`;
}

function syntheticBaseText(fileIndex: number): string {
	return `struct Tracked${fileIndex} { let value = ${fileIndex} }\n`;
}

function syntheticHeadText(fileIndex: number): string {
	return `struct Tracked${fileIndex} { let value = ${fileIndex + 10_000} }\n`;
}

async function runGit(cwd: string, args: readonly string[]): Promise<void> {
	await execFileAsync('git', [...args], { cwd });
}

async function gitStdout(cwd: string, args: readonly string[]): Promise<string> {
	return (await execFileAsync('git', [...args], { cwd, maxBuffer: 64 * 1024 * 1024 })).stdout;
}

function sha256Text(text: string): string {
	return createHash('sha256').update(text).digest('hex');
}

function firstTextSourcePath(surface: BridgeWorktreeDevProviderWorktreeFileSurface): string {
	for (const frame of surface.frames) {
		const rows =
			frame.frameKind === 'worktree.snapshot'
				? frame.treeRows
				: frame.frameKind === 'worktree.treeWindow'
					? frame.rows
					: [];
		const row = rows.find(
			(candidate) =>
				!candidate.isDirectory &&
				(candidate.path.endsWith('.ts') || candidate.path.endsWith('.swift')),
		);
		if (row !== undefined) return row.path;
	}
	throw new Error('Current-worktree N1 proof requires one text source row');
}

function changedFileRowCount(surface: BridgeWorktreeDevProviderWorktreeFileSurface): number {
	let changedPathCount = 0;
	for (const frame of surface.frames) {
		const rows =
			frame.frameKind === 'worktree.snapshot'
				? frame.treeRows
				: frame.frameKind === 'worktree.treeWindow'
					? frame.rows
					: [];
		changedPathCount += rows.filter(
			(row) => !row.isDirectory && row.changeStatus !== undefined,
		).length;
	}
	return changedPathCount;
}

async function currentWorktreeFingerprints(worktreeRoot: string): Promise<{
	readonly fullDirtyFingerprint: string;
	readonly trackedDiffFingerprint: string;
	readonly untrackedContentFingerprint: string;
}> {
	const [status, trackedDiff, untrackedOutput] = await Promise.all([
		gitStdout(worktreeRoot, ['status', '--porcelain=v1', '-z', '--untracked-files=all']),
		gitStdout(worktreeRoot, ['diff', '--binary', 'HEAD', '--']),
		gitStdout(worktreeRoot, ['ls-files', '--others', '--exclude-standard', '-z']),
	]);
	const untrackedPaths = untrackedOutput
		.split('\0')
		.filter((path) => path.length > 0)
		.toSorted();
	const untrackedContentHasher = createHash('sha256');
	for (const path of untrackedPaths) {
		// Test-proof only. Raw paths and bytes are reduced to a digest and never emitted.
		untrackedContentHasher.update(createHash('sha256').update(path).digest());
		// oxlint-disable-next-line no-await-in-loop -- Sequential hashing preserves canonical path order with bounded memory.
		const candidatePath = await realpath(resolve(worktreeRoot, path));
		const relativePath = relative(worktreeRoot, candidatePath);
		if (relativePath.startsWith('..') || relativePath.split(sep).includes('..')) {
			untrackedContentHasher.update('external-symlink');
			continue;
		}
		// oxlint-disable-next-line no-await-in-loop -- Sequential hashing avoids unbounded proof-only body reads.
		const bytes = await readFile(candidatePath);
		untrackedContentHasher.update(createHash('sha256').update(bytes).digest());
	}
	const trackedDiffFingerprint = sha256Text(trackedDiff);
	const untrackedContentFingerprint = untrackedContentHasher.digest('hex');
	const statusFingerprint = sha256Text(status);
	return {
		fullDirtyFingerprint: createHash('sha256')
			.update(statusFingerprint)
			.update(trackedDiffFingerprint)
			.update(untrackedContentFingerprint)
			.digest('hex'),
		trackedDiffFingerprint,
		untrackedContentFingerprint,
	};
}

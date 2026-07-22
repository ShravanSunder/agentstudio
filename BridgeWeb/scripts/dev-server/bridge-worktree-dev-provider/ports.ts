import { spawn } from 'node:child_process';
import { createHash } from 'node:crypto';
import { open, realpath } from 'node:fs/promises';

export const BRIDGE_WORKTREE_DEV_MAXIMUM_GIT_CONCURRENCY = 4;
export const BRIDGE_WORKTREE_DEV_MAXIMUM_FILESYSTEM_CONCURRENCY = 8;
export const BRIDGE_WORKTREE_DEV_MAXIMUM_GIT_OUTPUT_BYTES = 64 * 1024 * 1024;
export const BRIDGE_WORKTREE_DEV_MAXIMUM_CONTENT_BYTES = 32 * 1024 * 1024;

export interface BridgeWorktreeDevGitRequest {
	readonly args: readonly string[];
	readonly cwd: string;
	readonly input?: Uint8Array;
	readonly maximumOutputBytes?: number;
	readonly signal?: AbortSignal | undefined;
}

export interface BridgeWorktreeDevFileMetadata {
	readonly contentSha256: string;
	readonly modifiedAtUnixMilliseconds: number;
	readonly sizeBytes: number;
}

export interface BridgeWorktreeDevFileWindowRequest {
	readonly absolutePath: string;
	readonly maximumBytes: number;
	readonly signal?: AbortSignal | undefined;
	readonly startByte: number;
}

export interface BridgeWorktreeDevFileWindow {
	readonly bytes: Uint8Array;
	readonly endOfFile: boolean;
	readonly totalByteLength: number;
}

export interface BridgeWorktreeDevPorts {
	readonly fileMetadata: (
		absolutePath: string,
		signal?: AbortSignal,
	) => Promise<BridgeWorktreeDevFileMetadata>;
	readonly readFileWindow: (
		request: BridgeWorktreeDevFileWindowRequest,
	) => Promise<BridgeWorktreeDevFileWindow>;
	readonly realpath: (path: string, signal?: AbortSignal) => Promise<string>;
	readonly runGit: (request: BridgeWorktreeDevGitRequest) => Promise<Uint8Array>;
}

export interface BridgeWorktreeDevPortObserver {
	readonly fileMetadataFinished?: (() => void) | undefined;
	readonly fileMetadataStarted?: (() => void) | undefined;
	readonly fileWindowFinished?: ((byteCount: number) => void) | undefined;
	readonly fileWindowStarted?: (() => void) | undefined;
	readonly gitFinished?: ((args: readonly string[], outputByteCount: number) => void) | undefined;
	readonly gitStarted?: ((args: readonly string[]) => void) | undefined;
	readonly realpathFinished?: (() => void) | undefined;
	readonly realpathStarted?: (() => void) | undefined;
}

interface QueuedTask {
	readonly cancel: () => void;
	readonly execute: () => Promise<void>;
	readonly signal: AbortSignal | undefined;
}

class BoundedConcurrencyLane {
	readonly #limit: number;
	readonly #queue: QueuedTask[] = [];
	#activeTaskCount = 0;

	constructor(limit: number) {
		this.#limit = limit;
	}

	run<TResult>(run: () => Promise<TResult>, signal?: AbortSignal): Promise<TResult> {
		if (signal?.aborted === true) {
			return Promise.reject(abortError());
		}
		return new Promise<TResult>((resolve, reject) => {
			this.#queue.push({
				cancel: (): void => reject(abortError()),
				execute: async (): Promise<void> => {
					try {
						resolve(await run());
					} catch (error) {
						reject(error);
					}
				},
				signal,
			});
			this.#drain();
		});
	}

	#drain(): void {
		while (this.#activeTaskCount < this.#limit) {
			const task = this.#queue.shift();
			if (task === undefined) return;
			if (task.signal?.aborted === true) {
				task.cancel();
				continue;
			}
			this.#activeTaskCount += 1;
			void task.execute().finally(() => {
				this.#activeTaskCount -= 1;
				this.#drain();
			});
		}
	}
}

export function createBridgeWorktreeDevPorts(
	observer: BridgeWorktreeDevPortObserver = {},
): BridgeWorktreeDevPorts {
	const gitLane = new BoundedConcurrencyLane(BRIDGE_WORKTREE_DEV_MAXIMUM_GIT_CONCURRENCY);
	const filesystemLane = new BoundedConcurrencyLane(
		BRIDGE_WORKTREE_DEV_MAXIMUM_FILESYSTEM_CONCURRENCY,
	);
	return {
		fileMetadata: async (
			absolutePath: string,
			signal?: AbortSignal,
		): Promise<BridgeWorktreeDevFileMetadata> =>
			await filesystemLane.run(async () => {
				observer.fileMetadataStarted?.();
				try {
					throwIfAborted(signal);
					const fileHandle = await open(absolutePath, 'r');
					try {
						const fileStats = await fileHandle.stat();
						const contentHasher = createHash('sha256');
						for await (const chunk of fileHandle.createReadStream({ autoClose: false })) {
							throwIfAborted(signal);
							contentHasher.update(chunk);
						}
						throwIfAborted(signal);
						return {
							contentSha256: contentHasher.digest('hex'),
							modifiedAtUnixMilliseconds: Math.max(0, Math.trunc(fileStats.mtimeMs)),
							sizeBytes: fileStats.size,
						};
					} finally {
						await fileHandle.close();
					}
				} finally {
					observer.fileMetadataFinished?.();
				}
			}, signal),
		readFileWindow: async (
			request: BridgeWorktreeDevFileWindowRequest,
		): Promise<BridgeWorktreeDevFileWindow> =>
			await filesystemLane.run(async () => {
				observer.fileWindowStarted?.();
				let observedByteCount = 0;
				try {
					validateFileWindowRequest(request);
					throwIfAborted(request.signal);
					const fileHandle = await open(request.absolutePath, 'r');
					try {
						const fileStats = await fileHandle.stat();
						const requestedByteCount = Math.min(
							request.maximumBytes,
							Math.max(0, fileStats.size - request.startByte),
						);
						const buffer = Buffer.allocUnsafe(requestedByteCount);
						throwIfAborted(request.signal);
						const result = await fileHandle.read(buffer, 0, requestedByteCount, request.startByte);
						observedByteCount = result.bytesRead;
						throwIfAborted(request.signal);
						return {
							bytes: buffer.subarray(0, result.bytesRead),
							endOfFile: request.startByte + result.bytesRead >= fileStats.size,
							totalByteLength: fileStats.size,
						};
					} finally {
						await fileHandle.close();
					}
				} finally {
					observer.fileWindowFinished?.(observedByteCount);
				}
			}, request.signal),
		realpath: async (path: string, signal?: AbortSignal): Promise<string> =>
			await filesystemLane.run(async () => {
				observer.realpathStarted?.();
				try {
					throwIfAborted(signal);
					const resolvedPath = await realpath(path);
					throwIfAborted(signal);
					return resolvedPath;
				} finally {
					observer.realpathFinished?.();
				}
			}, signal),
		runGit: async (request: BridgeWorktreeDevGitRequest): Promise<Uint8Array> =>
			await gitLane.run(async () => await runGitChild(request, observer), request.signal),
	};
}

export const defaultBridgeWorktreeDevPorts: BridgeWorktreeDevPorts = createBridgeWorktreeDevPorts();

async function runGitChild(
	request: BridgeWorktreeDevGitRequest,
	observer: BridgeWorktreeDevPortObserver,
): Promise<Uint8Array> {
	throwIfAborted(request.signal);
	const maximumOutputBytes =
		request.maximumOutputBytes ?? BRIDGE_WORKTREE_DEV_MAXIMUM_GIT_OUTPUT_BYTES;
	if (!Number.isSafeInteger(maximumOutputBytes) || maximumOutputBytes <= 0) {
		throw new Error('Bridge worktree git output limit must be a positive safe integer');
	}
	return await new Promise<Uint8Array>((resolve, reject) => {
		const child = spawn('git', [...request.args], {
			cwd: request.cwd,
			stdio: ['pipe', 'pipe', 'pipe'],
		});
		const stdoutChunks: Buffer[] = [];
		let stdoutByteCount = 0;
		let rejectedForLimit = false;
		const abortListener = (): void => {
			child.kill('SIGKILL');
		};
		request.signal?.addEventListener('abort', abortListener, { once: true });
		observer.gitStarted?.(request.args);
		if (request.signal?.aborted === true) abortListener();
		child.stdout.on('data', (chunk: Buffer) => {
			stdoutByteCount += chunk.byteLength;
			if (stdoutByteCount > maximumOutputBytes) {
				rejectedForLimit = true;
				child.kill('SIGKILL');
				return;
			}
			stdoutChunks.push(chunk);
		});
		// Drain stderr without retaining untrusted paths or content.
		child.stderr.resume();
		child.stdin.on('error', () => {
			// Cancellation can close stdin before a bounded request payload is written.
		});
		child.once('error', () => {
			request.signal?.removeEventListener('abort', abortListener);
			reject(new Error('Bridge worktree git command could not start'));
		});
		child.once('close', (exitCode) => {
			request.signal?.removeEventListener('abort', abortListener);
			observer.gitFinished?.(request.args, stdoutByteCount);
			if (request.signal?.aborted === true) {
				reject(abortError());
				return;
			}
			if (rejectedForLimit) {
				reject(new Error('Bridge worktree git command exceeded its bounded output limit'));
				return;
			}
			if (exitCode !== 0) {
				reject(new Error(`Bridge worktree git command failed with exit code ${exitCode ?? -1}`));
				return;
			}
			resolve(Buffer.concat(stdoutChunks));
		});
		if (request.input === undefined) {
			child.stdin.end();
		} else {
			child.stdin.end(request.input);
		}
	});
}

function validateFileWindowRequest(request: BridgeWorktreeDevFileWindowRequest): void {
	if (!Number.isSafeInteger(request.startByte) || request.startByte < 0) {
		throw new Error('Bridge worktree file window start must be a nonnegative safe integer');
	}
	if (!Number.isSafeInteger(request.maximumBytes) || request.maximumBytes <= 0) {
		throw new Error('Bridge worktree file window limit must be a positive safe integer');
	}
	if (request.maximumBytes > BRIDGE_WORKTREE_DEV_MAXIMUM_CONTENT_BYTES) {
		throw new Error('Bridge worktree file window exceeds the content policy limit');
	}
}

function throwIfAborted(signal: AbortSignal | undefined): void {
	if (signal?.aborted === true) throw abortError();
}

function abortError(): Error {
	const error = new Error('Bridge worktree dev operation was cancelled');
	error.name = 'AbortError';
	return error;
}

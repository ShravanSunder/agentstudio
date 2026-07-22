import { createHash } from 'node:crypto';
import { isAbsolute, resolve } from 'node:path';

import {
	BRIDGE_WORKTREE_DEV_MAXIMUM_BASE_REF_BYTES,
	BRIDGE_WORKTREE_DEV_MAXIMUM_PATH_BYTES,
	isPathInsideRoot,
	type BridgeWorktreeChangedFileMetadata,
} from './metadata.ts';
import {
	BRIDGE_WORKTREE_DEV_MAXIMUM_CONTENT_BYTES,
	defaultBridgeWorktreeDevPorts,
	type BridgeWorktreeDevPorts,
} from './ports.ts';

export type BridgeWorktreeDevContentRole = 'base' | 'head';

export interface BridgeWorktreeDevContentWindow {
	readonly bytes: Uint8Array;
	readonly endOfSource: boolean;
	readonly sha256: string;
	readonly startByte: number;
	readonly totalByteLength: number;
}

export async function hydrateBridgeWorktreeDevContentWindow(props: {
	readonly baseRef: string;
	readonly changedFile: BridgeWorktreeChangedFileMetadata;
	readonly maximumBytes: number;
	readonly ports?: BridgeWorktreeDevPorts;
	readonly role: BridgeWorktreeDevContentRole;
	readonly signal?: AbortSignal | undefined;
	readonly startByte: number;
	readonly worktreeRoot: string;
}): Promise<BridgeWorktreeDevContentWindow> {
	validateContentWindow(props.startByte, props.maximumBytes);
	validateContentAuthority(props.baseRef, props.changedFile);
	const ports = props.ports ?? defaultBridgeWorktreeDevPorts;
	const sourcePath =
		props.role === 'base' ? props.changedFile.basePath : props.changedFile.headPath;
	if (sourcePath === null) {
		throw new Error('Bridge worktree content role is unavailable for this change');
	}
	const content =
		props.role === 'base'
			? await readBaseContent({
					baseRef: props.baseRef,
					maximumBytes: props.maximumBytes,
					path: sourcePath,
					ports,
					signal: props.signal,
					startByte: props.startByte,
					worktreeRoot: props.worktreeRoot,
				})
			: await readHeadContent({
					maximumBytes: props.maximumBytes,
					path: sourcePath,
					ports,
					signal: props.signal,
					startByte: props.startByte,
					worktreeRoot: props.worktreeRoot,
				});
	return {
		...content,
		sha256: createHash('sha256').update(content.bytes).digest('hex'),
		startByte: props.startByte,
	};
}

function validateContentAuthority(
	baseRef: string,
	changedFile: BridgeWorktreeChangedFileMetadata,
): void {
	if (
		baseRef.length === 0 ||
		baseRef.includes('\0') ||
		Buffer.byteLength(baseRef) > BRIDGE_WORKTREE_DEV_MAXIMUM_BASE_REF_BYTES
	) {
		throw new Error('Bridge worktree content base reference violates the policy limit');
	}
	for (const path of [changedFile.path, changedFile.basePath, changedFile.headPath]) {
		if (path === null) continue;
		if (
			path.length === 0 ||
			isAbsolute(path) ||
			path.split('/').includes('..') ||
			Buffer.byteLength(path) > BRIDGE_WORKTREE_DEV_MAXIMUM_PATH_BYTES
		) {
			throw new Error('Bridge worktree content path violates the policy limit');
		}
	}
}

async function readHeadContent(props: {
	readonly maximumBytes: number;
	readonly path: string;
	readonly ports: BridgeWorktreeDevPorts;
	readonly signal?: AbortSignal | undefined;
	readonly startByte: number;
	readonly worktreeRoot: string;
}): Promise<{
	readonly bytes: Uint8Array;
	readonly endOfSource: boolean;
	readonly totalByteLength: number;
}> {
	const absolutePath = resolve(props.worktreeRoot, props.path);
	if (!isPathInsideRoot({ absolutePath, rootPath: props.worktreeRoot })) {
		throw new Error('Bridge worktree content path escapes root containment');
	}
	const realAbsolutePath = await props.ports.realpath(absolutePath, props.signal);
	if (!isPathInsideRoot({ absolutePath: realAbsolutePath, rootPath: props.worktreeRoot })) {
		throw new Error('Bridge worktree content path escapes root containment');
	}
	const window = await props.ports.readFileWindow({
		absolutePath: realAbsolutePath,
		maximumBytes: props.maximumBytes,
		signal: props.signal,
		startByte: props.startByte,
	});
	return {
		bytes: window.bytes,
		endOfSource: window.endOfFile,
		totalByteLength: window.totalByteLength,
	};
}

async function readBaseContent(props: {
	readonly baseRef: string;
	readonly maximumBytes: number;
	readonly path: string;
	readonly ports: BridgeWorktreeDevPorts;
	readonly signal?: AbortSignal | undefined;
	readonly startByte: number;
	readonly worktreeRoot: string;
}): Promise<{
	readonly bytes: Uint8Array;
	readonly endOfSource: boolean;
	readonly totalByteLength: number;
}> {
	const bytes = await props.ports.runGit({
		args: ['show', '--end-of-options', `${props.baseRef}:${props.path}`],
		cwd: props.worktreeRoot,
		maximumOutputBytes: BRIDGE_WORKTREE_DEV_MAXIMUM_CONTENT_BYTES,
		signal: props.signal,
	});
	const startByte = Math.min(props.startByte, bytes.byteLength);
	const endByte = Math.min(startByte + props.maximumBytes, bytes.byteLength);
	return {
		bytes: bytes.slice(startByte, endByte),
		endOfSource: endByte >= bytes.byteLength,
		totalByteLength: bytes.byteLength,
	};
}

function validateContentWindow(startByte: number, maximumBytes: number): void {
	if (!Number.isSafeInteger(startByte) || startByte < 0) {
		throw new Error('Bridge worktree content start must be a nonnegative safe integer');
	}
	if (!Number.isSafeInteger(maximumBytes) || maximumBytes <= 0) {
		throw new Error('Bridge worktree content limit must be a positive safe integer');
	}
	if (maximumBytes > BRIDGE_WORKTREE_DEV_MAXIMUM_CONTENT_BYTES) {
		throw new Error('Bridge worktree content demand exceeds the policy limit');
	}
}

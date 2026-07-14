import { createHash } from 'node:crypto';
import { isAbsolute, relative, resolve, sep } from 'node:path';

import {
	defaultBridgeWorktreeDevPorts,
	type BridgeWorktreeDevFileMetadata,
	type BridgeWorktreeDevPorts,
} from './ports.ts';

export type BridgeWorktreeDevChangeKind = 'added' | 'copied' | 'deleted' | 'modified' | 'renamed';

export const BRIDGE_WORKTREE_DEV_MAXIMUM_CHANGED_PATH_COUNT = 50_000;
export const BRIDGE_WORKTREE_DEV_MAXIMUM_CURRENT_PATH_COUNT = 100_000;
export const BRIDGE_WORKTREE_DEV_MAXIMUM_PATH_BYTES = 16 * 1024;
export const BRIDGE_WORKTREE_DEV_MAXIMUM_BASE_REF_BYTES = 4 * 1024;

export interface BridgeWorktreeChangedFileMetadata {
	readonly additions: number | null;
	readonly basePath: string | null;
	readonly changeKind: BridgeWorktreeDevChangeKind;
	readonly deletions: number | null;
	readonly headFileMetadata: BridgeWorktreeDevFileMetadata | null;
	readonly headPath: string | null;
	readonly path: string;
}

export interface BridgeWorktreeDevMetadataSnapshot {
	readonly changedFiles: readonly BridgeWorktreeChangedFileMetadata[];
	readonly currentFilePaths: readonly string[];
	readonly fingerprint: string;
}

interface GitNameStatusRecord {
	readonly basePath: string | null;
	readonly changeKind: BridgeWorktreeDevChangeKind;
	readonly headPath: string | null;
	readonly path: string;
}

interface GitNumstatRecord {
	readonly additions: number | null;
	readonly deletions: number | null;
	readonly path: string;
}

export async function loadBridgeWorktreeDevMetadataSnapshot(props: {
	readonly baseRef: string;
	readonly ports?: BridgeWorktreeDevPorts;
	readonly signal?: AbortSignal | undefined;
	readonly worktreeRoot: string;
}): Promise<BridgeWorktreeDevMetadataSnapshot> {
	validateBaseRef(props.baseRef);
	const ports = props.ports ?? defaultBridgeWorktreeDevPorts;
	const worktreeRoot = await ports.realpath(props.worktreeRoot, props.signal);
	const commandResults = await joinAllOrThrow([
		gitText(ports, worktreeRoot, props.signal, [
			'diff',
			'--name-status',
			'-z',
			'--find-renames',
			'--find-copies',
			'--end-of-options',
			props.baseRef,
			'--',
		]),
		gitText(ports, worktreeRoot, props.signal, [
			'diff',
			'--numstat',
			'-z',
			'--find-renames',
			'--find-copies',
			'--end-of-options',
			props.baseRef,
			'--',
		]),
		gitText(ports, worktreeRoot, props.signal, [
			'ls-files',
			'--cached',
			'--others',
			'--exclude-standard',
			'-z',
		]),
		gitText(ports, worktreeRoot, props.signal, ['ls-files', '--deleted', '-z']),
		gitText(ports, worktreeRoot, props.signal, [
			'ls-files',
			'--others',
			'--exclude-standard',
			'-z',
		]),
	]);
	const [nameStatusOutput, numstatOutput, currentFilesOutput, deletedFilesOutput, untrackedOutput] =
		commandResults;
	if (
		nameStatusOutput === undefined ||
		numstatOutput === undefined ||
		currentFilesOutput === undefined ||
		deletedFilesOutput === undefined ||
		untrackedOutput === undefined
	) {
		throw new Error('Bridge worktree metadata command set was incomplete');
	}
	const changedFileRecords = mergeChangedFileRecords({
		nameStatusOutput,
		numstatOutput,
		untrackedOutput,
	});
	if (changedFileRecords.length > BRIDGE_WORKTREE_DEV_MAXIMUM_CHANGED_PATH_COUNT) {
		throw new Error('Bridge worktree changed-path count exceeds the metadata policy limit');
	}
	for (const record of changedFileRecords) validateChangedFileRecordPaths(record);
	const changedFiles = await joinAllOrThrow(
		changedFileRecords.map(async (record): Promise<BridgeWorktreeChangedFileMetadata> => {
			const headFileMetadata =
				record.headPath === null
					? null
					: await containedHeadFileMetadata({
							path: record.headPath,
							ports,
							signal: props.signal,
							worktreeRoot,
						});
			return {
				additions: record.additions,
				basePath: record.basePath,
				changeKind: record.changeKind,
				deletions: record.deletions,
				headFileMetadata,
				headPath: record.headPath,
				path: record.path,
			};
		}),
	);
	const deletedPathFields = nulFields(deletedFilesOutput);
	const currentPathFields = nulFields(currentFilesOutput);
	if (currentPathFields.length > BRIDGE_WORKTREE_DEV_MAXIMUM_CURRENT_PATH_COUNT) {
		throw new Error('Bridge worktree current-path count exceeds the metadata policy limit');
	}
	for (const path of [...currentPathFields, ...deletedPathFields]) {
		validateRepositoryRelativePath(path);
	}
	const deletedPaths = new Set(deletedPathFields);
	const currentFilePaths = currentPathFields
		.filter((path) => !deletedPaths.has(path))
		.toSorted((left, right) => left.localeCompare(right));
	return {
		changedFiles,
		currentFilePaths,
		fingerprint: fingerprintMetadataSnapshot({ changedFiles, currentFilePaths }),
	};
}

function validateBaseRef(baseRef: string): void {
	if (
		baseRef.length === 0 ||
		baseRef.includes('\0') ||
		Buffer.byteLength(baseRef) > BRIDGE_WORKTREE_DEV_MAXIMUM_BASE_REF_BYTES
	) {
		throw new Error('Bridge worktree base reference violates the metadata policy');
	}
}

function validateChangedFileRecordPaths(
	record: Omit<BridgeWorktreeChangedFileMetadata, 'headFileMetadata'>,
): void {
	validateRepositoryRelativePath(record.path);
	if (record.basePath !== null) validateRepositoryRelativePath(record.basePath);
	if (record.headPath !== null) validateRepositoryRelativePath(record.headPath);
}

function validateRepositoryRelativePath(path: string): void {
	if (
		path.length === 0 ||
		isAbsolute(path) ||
		path.split('/').includes('..') ||
		Buffer.byteLength(path) > BRIDGE_WORKTREE_DEV_MAXIMUM_PATH_BYTES
	) {
		throw new Error('Bridge worktree git output contains an invalid repository-relative path');
	}
}

function mergeChangedFileRecords(props: {
	readonly nameStatusOutput: string;
	readonly numstatOutput: string;
	readonly untrackedOutput: string;
}): readonly Omit<BridgeWorktreeChangedFileMetadata, 'headFileMetadata'>[] {
	const numstatByPath = new Map(
		parseNumstatRecords(props.numstatOutput).map((record) => [record.path, record]),
	);
	const recordsByPath = new Map<
		string,
		Omit<BridgeWorktreeChangedFileMetadata, 'headFileMetadata'>
	>();
	for (const record of parseNameStatusRecords(props.nameStatusOutput)) {
		const numstat = numstatByPath.get(record.path);
		recordsByPath.set(record.path, {
			...record,
			additions: numstat?.additions ?? null,
			deletions: numstat?.deletions ?? null,
		});
	}
	for (const path of nulFields(props.untrackedOutput)) {
		recordsByPath.set(path, {
			additions: null,
			basePath: null,
			changeKind: 'added',
			deletions: 0,
			headPath: path,
			path,
		});
	}
	return [...recordsByPath.values()].toSorted((left, right) => left.path.localeCompare(right.path));
}

function parseNameStatusRecords(output: string): readonly GitNameStatusRecord[] {
	const records: GitNameStatusRecord[] = [];
	const fields = output.split('\0');
	let fieldIndex = 0;
	while (fieldIndex < fields.length) {
		const status = fields[fieldIndex];
		if (status === undefined || status.length === 0) {
			fieldIndex += 1;
			continue;
		}
		const hasSourcePath = status.startsWith('R') || status.startsWith('C');
		const oldPath = hasSourcePath ? fields[fieldIndex + 1] : null;
		const path = hasSourcePath ? fields[fieldIndex + 2] : fields[fieldIndex + 1];
		fieldIndex += hasSourcePath ? 3 : 2;
		if (path === undefined || path.length === 0 || oldPath === undefined) {
			throw new Error('Bridge worktree git name-status output was invalid');
		}
		const changeKind = changeKindForGitStatus(status);
		records.push({
			basePath: changeKind === 'added' ? null : (oldPath ?? path),
			changeKind,
			headPath: changeKind === 'deleted' ? null : path,
			path,
		});
	}
	return records;
}

function parseNumstatRecords(output: string): readonly GitNumstatRecord[] {
	const records: GitNumstatRecord[] = [];
	const fields = output.split('\0');
	let fieldIndex = 0;
	while (fieldIndex < fields.length) {
		const field = fields[fieldIndex];
		fieldIndex += 1;
		if (field === undefined || field.length === 0) continue;
		const [rawAdditions, rawDeletions, embeddedPath] = field.split('\t');
		if (rawAdditions === undefined || rawDeletions === undefined || embeddedPath === undefined) {
			throw new Error('Bridge worktree git numstat output was invalid');
		}
		let path = embeddedPath;
		if (path.length === 0) {
			const oldPath = fields[fieldIndex];
			const newPath = fields[fieldIndex + 1];
			fieldIndex += 2;
			if (oldPath === undefined || newPath === undefined || newPath.length === 0) {
				throw new Error('Bridge worktree git rename numstat output was invalid');
			}
			path = newPath;
		}
		records.push({
			additions: parseNumstatCount(rawAdditions),
			deletions: parseNumstatCount(rawDeletions),
			path,
		});
	}
	return records;
}

function parseNumstatCount(rawCount: string): number | null {
	if (rawCount === '-') return null;
	const count = Number.parseInt(rawCount, 10);
	if (!Number.isSafeInteger(count) || count < 0) {
		throw new Error('Bridge worktree git numstat count was invalid');
	}
	return count;
}

function changeKindForGitStatus(status: string): BridgeWorktreeDevChangeKind {
	switch (status[0] ?? '') {
		case 'A':
			return 'added';
		case 'C':
			return 'copied';
		case 'D':
			return 'deleted';
		case 'R':
			return 'renamed';
		default:
			return 'modified';
	}
}

async function containedHeadFileMetadata(props: {
	readonly path: string;
	readonly ports: BridgeWorktreeDevPorts;
	readonly signal?: AbortSignal | undefined;
	readonly worktreeRoot: string;
}): Promise<BridgeWorktreeDevFileMetadata> {
	const absolutePath = resolve(props.worktreeRoot, props.path);
	if (!isPathInsideRoot({ absolutePath, rootPath: props.worktreeRoot })) {
		throw new Error('Bridge worktree metadata path escapes root containment');
	}
	const realAbsolutePath = await props.ports.realpath(absolutePath, props.signal);
	if (!isPathInsideRoot({ absolutePath: realAbsolutePath, rootPath: props.worktreeRoot })) {
		throw new Error('Bridge worktree metadata path escapes root containment');
	}
	return await props.ports.fileMetadata(realAbsolutePath, props.signal);
}

export function isPathInsideRoot(props: {
	readonly absolutePath: string;
	readonly rootPath: string;
}): boolean {
	const relativePath = relative(props.rootPath, props.absolutePath);
	return (
		relativePath !== '' && !relativePath.startsWith('..') && !relativePath.split(sep).includes('..')
	);
}

function fingerprintMetadataSnapshot(props: {
	readonly changedFiles: readonly BridgeWorktreeChangedFileMetadata[];
	readonly currentFilePaths: readonly string[];
}): string {
	return createHash('sha256').update(JSON.stringify(props)).digest('hex');
}

function nulFields(output: string): string[] {
	return output.split('\0').filter((field) => field.length > 0);
}

async function gitText(
	ports: BridgeWorktreeDevPorts,
	cwd: string,
	signal: AbortSignal | undefined,
	args: readonly string[],
): Promise<string> {
	const bytes = await ports.runGit({ args, cwd, signal });
	return new TextDecoder('utf-8', { fatal: true }).decode(bytes);
}

async function joinAllOrThrow<TResult>(tasks: readonly Promise<TResult>[]): Promise<TResult[]> {
	const results = await Promise.allSettled(tasks);
	const values: TResult[] = [];
	for (const result of results) {
		if (result.status === 'rejected') throw result.reason;
		values.push(result.value);
	}
	return values;
}

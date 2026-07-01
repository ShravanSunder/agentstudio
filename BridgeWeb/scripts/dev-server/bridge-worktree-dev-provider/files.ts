import { execFile } from 'node:child_process';
import { createHash } from 'node:crypto';
import { readFile, realpath } from 'node:fs/promises';
import { extname, relative, resolve, sep } from 'node:path';
import { promisify } from 'node:util';

const execFileAsync = promisify(execFile);

type WorktreeFileChangeKind = 'added' | 'copied' | 'deleted' | 'modified' | 'renamed';

export interface BridgeWorktreeChangedFile {
	readonly additions: number;
	readonly baseContent: string | null;
	readonly basePath: string | null;
	readonly changeKind: WorktreeFileChangeKind;
	readonly deletions: number;
	readonly headContent: string | null;
	readonly headPath: string | null;
	readonly path: string;
}

export interface BridgeWorktreeDevSnapshot {
	readonly changedFiles: readonly BridgeWorktreeChangedFile[];
	readonly currentFilePaths: readonly string[];
	readonly fingerprint: string;
}

interface GitNameStatusRecord {
	readonly basePath: string | null;
	readonly changeKind: WorktreeFileChangeKind;
	readonly headPath: string | null;
	readonly path: string;
}

export async function loadBridgeWorktreeDevSnapshot(props: {
	readonly baseRef: string;
	readonly worktreeRoot: string;
}): Promise<BridgeWorktreeDevSnapshot> {
	const worktreeRoot = await realpath(props.worktreeRoot);
	const [changedFiles, currentFilePaths] = await Promise.all([
		readChangedFiles({
			baseRef: props.baseRef,
			worktreeRoot,
		}),
		readCurrentWorktreeFilePaths(worktreeRoot),
	]);
	return {
		changedFiles,
		currentFilePaths,
		fingerprint: fingerprintWorktreeSnapshot({ changedFiles, currentFilePaths }),
	};
}

export async function bridgeWorktreeDevRootTokenForPath(path: string): Promise<string> {
	return `root-${hashText(await realpath(path)).slice(0, 32)}`;
}

async function readChangedFiles(props: {
	readonly baseRef: string;
	readonly worktreeRoot: string;
}): Promise<readonly BridgeWorktreeChangedFile[]> {
	const records = await gitNameStatusRecords(props);
	const changedFiles = await Promise.all(
		records.map(async (record): Promise<BridgeWorktreeChangedFile> => {
			const [baseContent, headContent] = await Promise.all([
				record.changeKind === 'added'
					? Promise.resolve(null)
					: gitShowOrNull(props.worktreeRoot, props.baseRef, record.basePath ?? record.path),
				record.changeKind === 'deleted'
					? Promise.resolve(null)
					: readWorktreeFileText({ path: record.path, worktreeRoot: props.worktreeRoot }),
			]);
			const lineDelta = countLineDelta(baseContent, headContent);
			return {
				additions: lineDelta.additions,
				baseContent,
				basePath: record.basePath,
				changeKind: record.changeKind,
				deletions: lineDelta.deletions,
				headContent,
				headPath: record.headPath,
				path: record.path,
			};
		}),
	);
	return changedFiles;
}

function fingerprintWorktreeSnapshot(props: {
	readonly changedFiles: readonly BridgeWorktreeChangedFile[];
	readonly currentFilePaths: readonly string[];
}): string {
	return hashText(
		JSON.stringify({
			changedFiles: props.changedFiles.map((changedFile) => ({
				additions: changedFile.additions,
				baseContentHash:
					changedFile.baseContent === null ? null : hashText(changedFile.baseContent),
				changeKind: changedFile.changeKind,
				deletions: changedFile.deletions,
				basePath: changedFile.basePath,
				headContentHash:
					changedFile.headContent === null ? null : hashText(changedFile.headContent),
				headPath: changedFile.headPath,
				path: changedFile.path,
			})),
			currentFilePaths: props.currentFilePaths,
		}),
	);
}

async function gitNameStatusRecords(props: {
	readonly baseRef: string;
	readonly worktreeRoot: string;
}): Promise<readonly GitNameStatusRecord[]> {
	const diffOutput = await gitStdout(props.worktreeRoot, [
		'diff',
		'--name-status',
		'--find-renames',
		'--find-copies',
		props.baseRef,
		'--',
	]);
	const untrackedOutput = await gitStdout(props.worktreeRoot, [
		'ls-files',
		'--others',
		'--exclude-standard',
	]);
	const diffRecords = diffOutput
		.split('\n')
		.map((line) => line.trim())
		.filter((line) => line.length > 0)
		.map(parseNameStatusLine);
	const untrackedRecords = untrackedOutput
		.split('\n')
		.map((line) => line.trim())
		.filter((path) => path.length > 0)
		.map(
			(path): GitNameStatusRecord => ({
				basePath: null,
				changeKind: 'added',
				headPath: path,
				path,
			}),
		);
	const recordByPath = new Map<string, GitNameStatusRecord>();
	for (const record of [...diffRecords, ...untrackedRecords]) {
		recordByPath.set(record.path, record);
	}
	return [...recordByPath.values()].toSorted((left, right) => left.path.localeCompare(right.path));
}

async function readCurrentWorktreeFilePaths(worktreeRoot: string): Promise<readonly string[]> {
	const currentFilesOutput = await gitStdout(worktreeRoot, [
		'ls-files',
		'--cached',
		'--others',
		'--exclude-standard',
		'-z',
	]);
	const candidatePaths = currentFilesOutput
		.split('\0')
		.map((path) => path.trim())
		.filter((path) => path.length > 0);
	const pathEntries = await Promise.all(
		candidatePaths.map(async (path): Promise<string | null> => {
			const absolutePath = resolve(worktreeRoot, path);
			try {
				const realAbsolutePath = await realpath(absolutePath);
				return isPathInsideRoot({ absolutePath: realAbsolutePath, rootPath: worktreeRoot })
					? path
					: null;
			} catch {
				return null;
			}
		}),
	);
	return pathEntries
		.filter((path): path is string => path !== null)
		.toSorted((left, right) => left.localeCompare(right));
}

function parseNameStatusLine(line: string): GitNameStatusRecord {
	const columns = line.split('\t');
	const status = columns[0] ?? '';
	const oldPath = status.startsWith('R') || status.startsWith('C') ? columns[1] : null;
	const path = status.startsWith('R') || status.startsWith('C') ? columns[2] : columns[1];
	if (path === undefined || path.length === 0 || oldPath === undefined) {
		throw new Error(`Invalid git name-status line: ${line}`);
	}
	const changeKind = changeKindForGitStatus(status);
	return {
		basePath: changeKind === 'added' ? null : (oldPath ?? path),
		changeKind,
		headPath: changeKind === 'deleted' ? null : path,
		path,
	};
}

function changeKindForGitStatus(status: string): WorktreeFileChangeKind {
	const statusKind = status[0] ?? '';
	switch (statusKind) {
		case 'A':
			return 'added';
		case 'C':
			return 'copied';
		case 'D':
			return 'deleted';
		case 'M':
			return 'modified';
		case 'R':
			return 'renamed';
		default:
			return 'modified';
	}
}

export async function resolveAllowedWorktreeRoot(rawWorktreeRoot: string): Promise<string> {
	const worktreeRoot = await realpath(resolve(rawWorktreeRoot));
	const gitRoot = (await gitStdout(worktreeRoot, ['rev-parse', '--show-toplevel'])).trim();
	const realGitRoot = await realpath(gitRoot);
	if (worktreeRoot !== realGitRoot) {
		throw new Error(`Bridge worktree dev provider root must be the git root: ${realGitRoot}`);
	}
	return worktreeRoot;
}

export async function resolveDefaultBaseRef(worktreeRoot: string): Promise<string> {
	const remoteDefaultBranchMergeBase = await gitRemoteDefaultBranchMergeBaseOrNull(worktreeRoot);
	if (remoteDefaultBranchMergeBase !== null) {
		return remoteDefaultBranchMergeBase;
	}
	const mergeBaseCandidates = await Promise.all(
		['origin/main', 'main', 'origin/master', 'master'].map(
			async (candidateRef): Promise<string | null> =>
				await gitMergeBaseOrNull(worktreeRoot, candidateRef),
		),
	);
	return mergeBaseCandidates.find((mergeBase): mergeBase is string => mergeBase !== null) ?? 'HEAD';
}

async function gitRemoteDefaultBranchMergeBaseOrNull(worktreeRoot: string): Promise<string | null> {
	try {
		const defaultBranchRef = (
			await gitStdout(worktreeRoot, ['symbolic-ref', '--quiet', 'refs/remotes/origin/HEAD'])
		).trim();
		if (defaultBranchRef.length === 0) {
			return null;
		}
		return await gitMergeBaseOrNull(worktreeRoot, defaultBranchRef);
	} catch {
		return null;
	}
}

async function gitMergeBaseOrNull(
	worktreeRoot: string,
	candidateRef: string,
): Promise<string | null> {
	try {
		const mergeBase = (await gitStdout(worktreeRoot, ['merge-base', 'HEAD', candidateRef])).trim();
		return mergeBase.length === 0 ? null : mergeBase;
	} catch {
		return null;
	}
}

export async function readWorktreeFileText(props: {
	readonly path: string;
	readonly worktreeRoot: string;
}): Promise<string> {
	const absolutePath = resolve(props.worktreeRoot, props.path);
	if (!isPathInsideRoot({ absolutePath, rootPath: props.worktreeRoot })) {
		throw new Error(`Bridge worktree path escapes root: ${props.path}`);
	}
	const realAbsolutePath = await realpath(absolutePath);
	if (!isPathInsideRoot({ absolutePath: realAbsolutePath, rootPath: props.worktreeRoot })) {
		throw new Error(`Bridge worktree path escapes root: ${props.path}`);
	}
	return await readFile(realAbsolutePath, 'utf8');
}

function isPathInsideRoot(props: {
	readonly absolutePath: string;
	readonly rootPath: string;
}): boolean {
	const relativePath = relative(props.rootPath, props.absolutePath);
	return (
		!relativePath.startsWith('..') && relativePath !== '' && !relativePath.split(sep).includes('..')
	);
}

async function gitShowOrNull(
	worktreeRoot: string,
	baseRef: string,
	path: string,
): Promise<string | null> {
	try {
		return await gitStdout(worktreeRoot, ['show', `${baseRef}:${path}`]);
	} catch {
		return null;
	}
}

async function gitStdout(cwd: string, args: readonly string[]): Promise<string> {
	// Dev-server only: production Swift-side Bridge git data prep must use agentstudio-git.
	const result = await execFileAsync('git', [...args], { cwd, maxBuffer: 32 * 1024 * 1024 });
	return result.stdout;
}

function countLineDelta(
	baseContent: string | null,
	headContent: string | null,
): { readonly additions: number; readonly deletions: number } {
	if (baseContent === null) {
		return { additions: lineCount(headContent), deletions: 0 };
	}
	if (headContent === null) {
		return { additions: 0, deletions: lineCount(baseContent) };
	}
	const baseLines = new Set(linesForDiff(baseContent));
	const headLines = new Set(linesForDiff(headContent));
	return {
		additions: [...headLines].filter((line) => !baseLines.has(line)).length,
		deletions: [...baseLines].filter((line) => !headLines.has(line)).length,
	};
}

function linesForDiff(content: string): readonly string[] {
	return content.split('\n').filter((line) => line.length > 0);
}

function lineCount(content: string | null | undefined): number {
	return linesForDiff(content ?? '').length;
}

export function renderLineCount(content: string): number {
	if (content.length === 0) {
		return 0;
	}
	const renderedContent = content.endsWith('\n') ? content.slice(0, -1) : content;
	return renderedContent.split('\n').length;
}

export function extensionForPath(path: string): string {
	const extension = extname(path).replace(/^\./u, '');
	return extension.length === 0 ? 'txt' : extension;
}

export function languageForExtension(extension: string): string {
	switch (extension) {
		case 'md':
		case 'mdx':
			return 'markdown';
		case 'swift':
			return 'swift';
		case 'ts':
		case 'tsx':
			return 'typescript';
		case 'js':
		case 'jsx':
			return 'javascript';
		case 'json':
			return 'json';
		case 'yml':
		case 'yaml':
			return 'yaml';
		default:
			return 'text';
	}
}

export function mimeTypeForExtension(extension: string): string {
	switch (extension) {
		case 'md':
		case 'mdx':
			return 'text/markdown';
		case 'ts':
		case 'tsx':
			return 'text/typescript';
		case 'js':
		case 'jsx':
			return 'text/javascript';
		case 'json':
			return 'application/json';
		default:
			return 'text/plain';
	}
}

export function hashText(text: string): string {
	return createHash('sha256').update(text).digest('hex');
}

export function byteLength(text: string): number {
	return new TextEncoder().encode(text).byteLength;
}

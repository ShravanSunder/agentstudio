import { execFile } from 'node:child_process';
import { createHash } from 'node:crypto';
import { readFile, realpath } from 'node:fs/promises';
import { extname, relative, resolve, sep } from 'node:path';
import { promisify } from 'node:util';

import { z } from 'zod';

import type {
	BridgeAttachedResourceDescriptor,
	BridgeResourceDescriptor,
} from '../../src/core/models/bridge-resource-descriptor.js';
import { bridgeAttachedResourceDescriptorSchema } from '../../src/core/models/bridge-resource-descriptor.js';
import type {
	WorktreeFileDescriptor,
	WorktreeFileProtocolFrame,
	WorktreeFileSurfaceSourceIdentity,
	WorktreeTreeVirtualizedSizeFacts,
} from '../../src/features/worktree-file/models/worktree-file-protocol-models.js';
import { countFlattenedWorktreeFileTreeRows } from '../../src/features/worktree-file/models/worktree-file-tree-size.js';

const execFileAsync = promisify(execFile);
const worktreeFileSubscriptionGeneration = 1;
const worktreeFileProtocol = 'worktree-file';
const worktreeFilePaneId = 'bridge-worktree-dev-pane';
const worktreeFileSourceId = 'dev-worktree-source';
const worktreeFileStreamId = `${worktreeFileProtocol}:${worktreeFilePaneId}`;
const worktreeFileRowHeightPixels = 24;

export const bridgeWorktreeDevScenarioNameSchema = z.enum(['current-worktree']);
export type BridgeWorktreeDevScenarioName = z.infer<typeof bridgeWorktreeDevScenarioNameSchema>;

export const bridgeWorktreeDevProviderConfigSchema = z
	.object({
		baseRef: z.string().min(1),
		scenarioName: bridgeWorktreeDevScenarioNameSchema,
		worktreeRoot: z.string().min(1),
	})
	.strict();

export type BridgeWorktreeDevProviderConfig = z.infer<typeof bridgeWorktreeDevProviderConfigSchema>;

export interface ResolveBridgeWorktreeDevProviderConfigProps {
	readonly env: Readonly<Record<string, string | undefined>>;
	readonly packageRoot: string;
	readonly requestUrl: string | null;
}

export interface BridgeWorktreeDevProviderWorktreeFileContentRequest {
	readonly descriptorId: string;
	readonly sourceCursor: string;
	readonly subscriptionGeneration: number;
}

export interface BridgeWorktreeDevProviderWorktreeFileSurface {
	readonly frames: readonly WorktreeFileProtocolFrame[];
	readonly provenance: BridgeWorktreeDevProviderProvenance;
	readonly source: WorktreeFileSurfaceSourceIdentity;
	readonly treeSizeFacts: WorktreeTreeVirtualizedSizeFacts;
}

export interface BridgeWorktreeDevProviderProvenance {
	readonly baseRef: string;
	readonly scenarioName: BridgeWorktreeDevScenarioName;
	readonly worktreeRootToken: string;
}

export interface BridgeWorktreeDevProvider {
	readonly loadWorktreeFileContent: (
		request: BridgeWorktreeDevProviderWorktreeFileContentRequest,
	) => Promise<string>;
	readonly loadWorktreeFileSurface: () => Promise<BridgeWorktreeDevProviderWorktreeFileSurface>;
}

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

interface ProviderState {
	readonly fingerprint: string;
	readonly revision: number;
	readonly worktreeFileContentByDescriptorId: ReadonlyMap<string, string>;
	readonly worktreeFileSurface: BridgeWorktreeDevProviderWorktreeFileSurface;
}

export interface BridgeWorktreeDevSnapshot {
	readonly changedFiles: readonly BridgeWorktreeChangedFile[];
	readonly fingerprint: string;
}

interface GitNameStatusRecord {
	readonly basePath: string | null;
	readonly changeKind: WorktreeFileChangeKind;
	readonly headPath: string | null;
	readonly path: string;
}

export async function resolveBridgeWorktreeDevProviderConfig(
	props: ResolveBridgeWorktreeDevProviderConfigProps,
): Promise<BridgeWorktreeDevProviderConfig> {
	const requestSearchParams = searchParamsForRequestUrl(props.requestUrl);
	rejectRawPathOverrides(requestSearchParams);
	const scenarioName = parseBridgeWorktreeDevScenarioName(
		firstNonEmptyStringOrNull([
			requestSearchParams.get('scenario'),
			props.env['BRIDGE_WEB_DEV_SCENARIO'],
			'current-worktree',
		]) ?? 'current-worktree',
	);
	const worktreeRoot = await resolveAllowedWorktreeRoot(
		firstNonEmptyStringOrNull([
			props.env['BRIDGE_WEB_DEV_WORKTREE'],
			resolve(props.packageRoot, '..'),
		]) ?? resolve(props.packageRoot, '..'),
	);
	const baseRef =
		firstNonEmptyStringOrNull([
			requestSearchParams.get('base'),
			props.env['BRIDGE_WEB_DEV_BASE'],
			null,
		]) ?? (await resolveDefaultBaseRef(worktreeRoot));
	return bridgeWorktreeDevProviderConfigSchema.parse({ baseRef, scenarioName, worktreeRoot });
}

export async function createBridgeWorktreeDevProvider(
	config: BridgeWorktreeDevProviderConfig,
): Promise<BridgeWorktreeDevProvider> {
	const parsedConfig = bridgeWorktreeDevProviderConfigSchema.parse(config);
	const worktreeRoot = await resolveAllowedWorktreeRoot(parsedConfig.worktreeRoot);
	const worktreeRootToken = await bridgeWorktreeDevRootTokenForPath(worktreeRoot);
	let state: ProviderState | null = null;

	const loadCurrentState = async (): Promise<ProviderState> => {
		const snapshot = await loadBridgeWorktreeDevSnapshot({
			baseRef: parsedConfig.baseRef,
			worktreeRoot,
		});
		const revision =
			state === null
				? 1
				: state.fingerprint === snapshot.fingerprint
					? state.revision
					: state.revision + 1;
		const currentState = makeProviderState({
			config: parsedConfig,
			revision,
			snapshot,
			worktreeRootToken,
		});
		state = currentState;
		return currentState;
	};

	return {
		loadWorktreeFileContent: async (
			request: BridgeWorktreeDevProviderWorktreeFileContentRequest,
		): Promise<string> => {
			const cachedContent = contentFromProviderState({
				request,
				state,
			});
			if (cachedContent !== null) {
				return cachedContent;
			}
			const currentState = await loadCurrentState();
			const currentSource = currentState.worktreeFileSurface.source;
			if (request.subscriptionGeneration !== currentSource.subscriptionGeneration) {
				throw new Error(
					`Rejected stale Bridge worktree file content generation: ${request.subscriptionGeneration}`,
				);
			}
			if (request.sourceCursor !== currentSource.sourceCursor) {
				throw new Error(
					`Rejected stale Bridge worktree file content cursor: ${request.sourceCursor}`,
				);
			}
			const content = currentState.worktreeFileContentByDescriptorId.get(request.descriptorId);
			if (content === undefined) {
				throw new Error(`Unknown Bridge worktree file content descriptor: ${request.descriptorId}`);
			}
			return content;
		},
		loadWorktreeFileSurface: async (): Promise<BridgeWorktreeDevProviderWorktreeFileSurface> => {
			const currentState = await loadCurrentState();
			return currentState.worktreeFileSurface;
		},
	};
}

function contentFromProviderState(props: {
	readonly request: BridgeWorktreeDevProviderWorktreeFileContentRequest;
	readonly state: ProviderState | null;
}): string | null {
	if (props.state === null) {
		return null;
	}
	const currentSource = props.state.worktreeFileSurface.source;
	if (
		props.request.subscriptionGeneration !== currentSource.subscriptionGeneration ||
		props.request.sourceCursor !== currentSource.sourceCursor
	) {
		return null;
	}
	return props.state.worktreeFileContentByDescriptorId.get(props.request.descriptorId) ?? null;
}

export async function loadBridgeWorktreeDevSnapshot(props: {
	readonly baseRef: string;
	readonly worktreeRoot: string;
}): Promise<BridgeWorktreeDevSnapshot> {
	const worktreeRoot = await realpath(props.worktreeRoot);
	const changedFiles = await readChangedFiles({
		baseRef: props.baseRef,
		worktreeRoot,
	});
	return {
		changedFiles,
		fingerprint: fingerprintChangedFiles(changedFiles),
	};
}

function makeProviderState(props: {
	readonly config: BridgeWorktreeDevProviderConfig;
	readonly revision: number;
	readonly snapshot: BridgeWorktreeDevSnapshot;
	readonly worktreeRootToken: string;
}): ProviderState {
	const sourceCursor = `cursor-${props.snapshot.fingerprint.slice(0, 32)}`;
	const sourceIdentity: WorktreeFileSurfaceSourceIdentity = {
		sourceId: worktreeFileSourceId,
		repoId: 'dev-worktree-repo',
		worktreeId: 'dev-worktree',
		subscriptionGeneration: worktreeFileSubscriptionGeneration,
		sourceCursor,
		rootRevisionToken: props.snapshot.fingerprint,
	};
	const worktreeFileContentByDescriptorId = new Map<string, string>();
	const flattenedTreeRowCount = countFlattenedWorktreeFileTreeRows(
		props.snapshot.changedFiles.map((changedFile) => changedFile.path),
	);
	const treeSizeFacts: WorktreeTreeVirtualizedSizeFacts = {
		pathCount: props.snapshot.changedFiles.length,
		estimatedTotalHeightPixels: flattenedTreeRowCount * worktreeFileRowHeightPixels,
		windowStartIndex: 0,
		windowRowCount: flattenedTreeRowCount,
		rowHeightPixels: worktreeFileRowHeightPixels,
	};
	const treeDescriptor = makeWorktreeAttachedDescriptor({
		content: {
			expectedBytes: byteLength(
				JSON.stringify(props.snapshot.changedFiles.map((changedFile) => changedFile.path)),
			),
			mediaType: 'application/json',
		},
		descriptorId: `dev-tree-window-${props.revision}`,
		resourceKind: 'worktree.treeWindow',
		sourceIdentity,
	});
	const worktreeFileDescriptors = props.snapshot.changedFiles.flatMap(
		(changedFile): readonly WorktreeFileDescriptor[] =>
			worktreeFileDescriptorForChangedFile({
				changedFile,
				sourceIdentity,
				worktreeFileContentByDescriptorId,
			}),
	);
	const worktreeFileSurface: BridgeWorktreeDevProviderWorktreeFileSurface = {
		frames: [
			{
				kind: 'snapshot',
				streamId: worktreeFileStreamId,
				generation: sourceIdentity.subscriptionGeneration,
				sequence: 0,
				frameKind: 'worktree.snapshot',
				source: sourceIdentity,
				treeDescriptor,
				treeSizeFacts,
			},
			...worktreeFileDescriptors.map(
				(descriptor, index): WorktreeFileProtocolFrame => ({
					kind: 'delta',
					streamId: worktreeFileStreamId,
					generation: sourceIdentity.subscriptionGeneration,
					sequence: index + 1,
					frameKind: 'worktree.fileDescriptor',
					descriptor,
				}),
			),
		],
		provenance: {
			baseRef: props.config.baseRef,
			scenarioName: props.config.scenarioName,
			worktreeRootToken: props.worktreeRootToken,
		},
		source: sourceIdentity,
		treeSizeFacts,
	};
	return {
		fingerprint: props.snapshot.fingerprint,
		revision: props.revision,
		worktreeFileContentByDescriptorId,
		worktreeFileSurface,
	};
}

export async function bridgeWorktreeDevRootTokenForPath(path: string): Promise<string> {
	return `root-${hashText(await realpath(path)).slice(0, 32)}`;
}

function worktreeFileDescriptorForChangedFile(props: {
	readonly changedFile: BridgeWorktreeChangedFile;
	readonly sourceIdentity: WorktreeFileSurfaceSourceIdentity;
	readonly worktreeFileContentByDescriptorId: Map<string, string>;
}): readonly WorktreeFileDescriptor[] {
	if (props.changedFile.changeKind === 'deleted') {
		return [
			unavailableWorktreeFileDescriptorForChangedFile({
				changedFile: props.changedFile,
				sourceIdentity: props.sourceIdentity,
			}),
		];
	}
	const content = props.changedFile.headContent ?? props.changedFile.baseContent;
	if (content === null) {
		return [];
	}
	const pathHash = hashText(props.changedFile.path).slice(0, 16);
	const contentHash = hashText(content);
	const descriptorId = `dev-file-${pathHash}-${contentHash.slice(0, 16)}`;
	props.worktreeFileContentByDescriptorId.set(descriptorId, content);
	const extension = extensionForPath(props.changedFile.path);
	return [
		{
			path: props.changedFile.path,
			fileId: `dev-file-id-${pathHash}`,
			contentHandle: descriptorId,
			contentDescriptor: makeWorktreeAttachedDescriptor({
				content: {
					expectedBytes: byteLength(content),
					mediaType: mimeTypeForExtension(extension),
				},
				descriptorId,
				resourceKind: 'worktree.fileContent',
				sourceIdentity: props.sourceIdentity,
			}),
			contentHash: `sha256:${hashText(content)}`,
			sourceIdentity: props.sourceIdentity,
			sizeBytes: byteLength(content),
			virtualizedExtentKind: 'exactLineCount',
			lineCount: renderLineCount(content),
			isBinary: false,
			language: languageForExtension(extension),
			fileExtension: extension,
		},
	];
}

function unavailableWorktreeFileDescriptorForChangedFile(props: {
	readonly changedFile: BridgeWorktreeChangedFile;
	readonly sourceIdentity: WorktreeFileSurfaceSourceIdentity;
}): WorktreeFileDescriptor {
	const pathHash = hashText(props.changedFile.path).slice(0, 16);
	const descriptorId = `dev-file-unavailable-${pathHash}`;
	const extension = extensionForPath(props.changedFile.path);
	const content = props.changedFile.baseContent ?? '';
	return {
		path: props.changedFile.path,
		fileId: `dev-file-id-${pathHash}`,
		contentHandle: descriptorId,
		contentDescriptor: makeWorktreeAttachedDescriptor({
			content: {
				expectedBytes: byteLength(content),
				mediaType: mimeTypeForExtension(extension),
			},
			descriptorId,
			resourceKind: 'worktree.fileContent',
			sourceIdentity: props.sourceIdentity,
		}),
		contentHash: `sha256:${hashText(content)}`,
		sourceIdentity: props.sourceIdentity,
		sizeBytes: byteLength(content),
		virtualizedExtentKind: 'unavailable',
		isBinary: false,
		language: languageForExtension(extension),
		fileExtension: extension,
	};
}

function makeWorktreeAttachedDescriptor(props: {
	readonly content: {
		readonly expectedBytes: number;
		readonly mediaType: string;
	};
	readonly descriptorId: string;
	readonly resourceKind: 'worktree.fileContent' | 'worktree.treeWindow';
	readonly sourceIdentity: WorktreeFileSurfaceSourceIdentity;
}): BridgeAttachedResourceDescriptor {
	const identity = {
		paneId: worktreeFilePaneId,
		protocol: worktreeFileProtocol,
		sourceId: props.sourceIdentity.sourceId,
		generation: props.sourceIdentity.subscriptionGeneration,
		streamId: worktreeFileStreamId,
		cursor: props.sourceIdentity.sourceCursor,
	};
	const descriptor = {
		descriptorId: props.descriptorId,
		protocol: worktreeFileProtocol,
		resourceKind: props.resourceKind,
		resourceUrl: `agentstudio://resource/${worktreeFileProtocol}/${props.resourceKind}/${props.descriptorId}?generation=${props.sourceIdentity.subscriptionGeneration}&cursor=${props.sourceIdentity.sourceCursor}`,
		identity,
		content: {
			mediaType: props.content.mediaType,
			encoding: 'utf-8',
			expectedBytes: props.content.expectedBytes,
			maxBytes: Math.max(props.content.expectedBytes, 1),
		},
	} satisfies BridgeResourceDescriptor;
	return bridgeAttachedResourceDescriptorSchema.parse({
		ref: {
			descriptorId: descriptor.descriptorId,
			expectedProtocol: descriptor.protocol,
			expectedResourceKind: descriptor.resourceKind,
			expectedIdentity: descriptor.identity,
		},
		descriptor,
	});
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

function fingerprintChangedFiles(changedFiles: readonly BridgeWorktreeChangedFile[]): string {
	return hashText(
		JSON.stringify(
			changedFiles.map((changedFile) => ({
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
		),
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

async function resolveAllowedWorktreeRoot(rawWorktreeRoot: string): Promise<string> {
	const worktreeRoot = await realpath(resolve(rawWorktreeRoot));
	const gitRoot = (await gitStdout(worktreeRoot, ['rev-parse', '--show-toplevel'])).trim();
	const realGitRoot = await realpath(gitRoot);
	if (worktreeRoot !== realGitRoot) {
		throw new Error(`Bridge worktree dev provider root must be the git root: ${realGitRoot}`);
	}
	return worktreeRoot;
}

async function resolveDefaultBaseRef(worktreeRoot: string): Promise<string> {
	const mergeBaseCandidates = await Promise.all(
		['origin/main', 'main', 'origin/master', 'master'].map(
			async (candidateRef): Promise<string | null> =>
				await gitMergeBaseOrNull(worktreeRoot, candidateRef),
		),
	);
	return mergeBaseCandidates.find((mergeBase): mergeBase is string => mergeBase !== null) ?? 'HEAD';
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

function searchParamsForRequestUrl(requestUrl: string | null): URLSearchParams {
	if (requestUrl === null) {
		return new URLSearchParams();
	}
	const parsedUrl = new URL(requestUrl, 'http://127.0.0.1');
	if (requestUrl.includes('://') && !isLoopbackHostname(parsedUrl.hostname)) {
		throw new Error('Bridge worktree dev provider request URL must use a loopback host');
	}
	return parsedUrl.searchParams;
}

function isLoopbackHostname(hostname: string): boolean {
	return hostname === '127.0.0.1' || hostname === 'localhost' || hostname === '[::1]';
}

function rejectRawPathOverrides(searchParams: URLSearchParams): void {
	for (const rawPathOverrideName of ['worktree', 'repo', 'base']) {
		if (searchParams.has(rawPathOverrideName)) {
			throw new Error(
				'Bridge worktree dev provider rejects raw worktree, repo, or base query parameters; use scenario instead',
			);
		}
	}
}

function parseBridgeWorktreeDevScenarioName(
	rawScenarioName: string,
): BridgeWorktreeDevScenarioName {
	const parsedScenarioName = bridgeWorktreeDevScenarioNameSchema.safeParse(rawScenarioName);
	if (!parsedScenarioName.success) {
		throw new Error(
			`Invalid Bridge worktree dev provider config: unknown scenario ${rawScenarioName}`,
		);
	}
	return parsedScenarioName.data;
}

function firstNonEmptyStringOrNull(values: readonly (string | null | undefined)[]): string | null {
	return (
		values.find(
			(candidate): candidate is string =>
				candidate !== null && candidate !== undefined && candidate.length > 0,
		) ?? null
	);
}

async function readWorktreeFileText(props: {
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

function renderLineCount(content: string): number {
	if (content.length === 0) {
		return 0;
	}
	const renderedContent = content.endsWith('\n') ? content.slice(0, -1) : content;
	return renderedContent.split('\n').length;
}

function extensionForPath(path: string): string {
	const extension = extname(path).replace(/^\./u, '');
	return extension.length === 0 ? 'txt' : extension;
}

function languageForExtension(extension: string): string {
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

function mimeTypeForExtension(extension: string): string {
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

function hashText(text: string): string {
	return createHash('sha256').update(text).digest('hex');
}

function byteLength(text: string): number {
	return new TextEncoder().encode(text).byteLength;
}

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
import type {
	BridgeContentHandle,
	BridgeContentRole,
	BridgeFileChangeKind,
	BridgeFileClass,
	BridgeReviewItemDescriptor,
	BridgeReviewPackage,
	BridgeReviewPackageSummary,
	BridgeSourceEndpoint,
	BridgeViewFilter,
} from '../../src/foundation/review-package/bridge-review-package.js';

const execFileAsync = promisify(execFile);
const reviewGeneration = 1;
const schemaVersion = 1;
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

export interface BridgeWorktreeDevProviderContentRequest {
	readonly handleId: string;
	readonly reviewGeneration: number;
	readonly revision: number;
}

export interface BridgeWorktreeDevProviderWorktreeFileContentRequest {
	readonly descriptorId: string;
	readonly sourceCursor: string;
	readonly subscriptionGeneration: number;
}

export interface BridgeWorktreeDevProviderWorktreeFileSurface {
	readonly frames: readonly WorktreeFileProtocolFrame[];
	readonly source: WorktreeFileSurfaceSourceIdentity;
	readonly treeSizeFacts: WorktreeTreeVirtualizedSizeFacts;
}

export interface BridgeWorktreeDevProvider {
	readonly loadContent: (request: BridgeWorktreeDevProviderContentRequest) => Promise<string>;
	readonly loadReviewPackage: () => Promise<BridgeReviewPackage>;
	readonly loadWorktreeFileContent: (
		request: BridgeWorktreeDevProviderWorktreeFileContentRequest,
	) => Promise<string>;
	readonly loadWorktreeFileSurface: () => Promise<BridgeWorktreeDevProviderWorktreeFileSurface>;
}

interface WorktreeChangedFile {
	readonly additions: number;
	readonly baseContent: string | null;
	readonly changeKind: BridgeFileChangeKind;
	readonly deletions: number;
	readonly headContent: string | null;
	readonly path: string;
}

interface ProviderState {
	readonly contentByHandleId: ReadonlyMap<string, string>;
	readonly fingerprint: string;
	readonly reviewPackage: BridgeReviewPackage;
	readonly worktreeFileContentByDescriptorId: ReadonlyMap<string, string>;
	readonly worktreeFileSurface: BridgeWorktreeDevProviderWorktreeFileSurface;
}

interface ProviderSnapshot {
	readonly changedFiles: readonly WorktreeChangedFile[];
	readonly fingerprint: string;
}

interface GitNameStatusRecord {
	readonly changeKind: BridgeFileChangeKind;
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
	let state: ProviderState | null = null;

	const loadCurrentState = async (): Promise<ProviderState> => {
		const snapshot = await loadSnapshot({ baseRef: parsedConfig.baseRef, worktreeRoot });
		const revision =
			state === null
				? 1
				: state.fingerprint === snapshot.fingerprint
					? state.reviewPackage.revision
					: state.reviewPackage.revision + 1;
		const currentState = makeProviderState({
			baseRef: parsedConfig.baseRef,
			revision,
			snapshot,
			worktreeRoot,
		});
		state = currentState;
		return currentState;
	};

	return {
		loadContent: async (request: BridgeWorktreeDevProviderContentRequest): Promise<string> => {
			const currentState = state ?? (await loadCurrentState());
			if (request.reviewGeneration !== currentState.reviewPackage.reviewGeneration) {
				throw new Error(
					`Rejected stale Bridge worktree content generation: ${request.reviewGeneration}`,
				);
			}
			if (request.revision !== currentState.reviewPackage.revision) {
				throw new Error(`Rejected stale Bridge worktree content revision: ${request.revision}`);
			}
			const content = currentState.contentByHandleId.get(request.handleId);
			if (content === undefined) {
				throw new Error(`Unknown Bridge worktree content handle: ${request.handleId}`);
			}
			return content;
		},
		loadReviewPackage: async (): Promise<BridgeReviewPackage> => {
			const currentState = await loadCurrentState();
			return currentState.reviewPackage;
		},
		loadWorktreeFileContent: async (
			request: BridgeWorktreeDevProviderWorktreeFileContentRequest,
		): Promise<string> => {
			const currentState = state ?? (await loadCurrentState());
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

async function loadSnapshot(props: {
	readonly baseRef: string;
	readonly worktreeRoot: string;
}): Promise<ProviderSnapshot> {
	const changedFiles = await readChangedFiles(props);
	return {
		changedFiles,
		fingerprint: fingerprintChangedFiles(changedFiles),
	};
}

function makeProviderState(props: {
	readonly baseRef: string;
	readonly revision: number;
	readonly snapshot: ProviderSnapshot;
	readonly worktreeRoot: string;
}): ProviderState {
	const contentByHandleId = new Map<string, string>();
	const items = props.snapshot.changedFiles.map((changedFile) =>
		makeReviewItem({
			changedFile,
			contentByHandleId,
			revision: props.revision,
			worktreeRoot: props.worktreeRoot,
		}),
	);
	const itemsById = Object.fromEntries(items.map((item) => [item.itemId, item]));
	const summary = summarizeItems(items);
	const sourceCursor = `cursor-${props.snapshot.fingerprint.slice(0, 32)}`;
	const sourceIdentity: WorktreeFileSurfaceSourceIdentity = {
		sourceId: worktreeFileSourceId,
		repoId: 'dev-worktree-repo',
		worktreeId: 'dev-worktree',
		subscriptionGeneration: reviewGeneration,
		sourceCursor,
		rootRevisionToken: props.snapshot.fingerprint,
	};
	const worktreeFileContentByDescriptorId = new Map<string, string>();
	const treeSizeFacts: WorktreeTreeVirtualizedSizeFacts = {
		pathCount: props.snapshot.changedFiles.length,
		windowStartIndex: 0,
		windowRowCount: props.snapshot.changedFiles.length,
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
		source: sourceIdentity,
		treeSizeFacts,
	};
	const reviewPackage: BridgeReviewPackage = {
		packageId: 'dev-worktree',
		schemaVersion,
		reviewGeneration,
		revision: props.revision,
		query: {
			queryId: 'dev-worktree-query',
			queryKind: 'compare',
			repoId: 'dev-worktree-repo',
			worktreeId: 'dev-worktree',
			baseEndpointId: 'dev-base',
			headEndpointId: 'dev-head',
			comparisonSemantics: 'workingTreeDelta',
			pathScope: [],
			fileTarget: null,
			viewFilter: defaultViewFilter(),
			grouping: { kind: 'flat', label: null },
			provenanceFilter: {
				paneIds: [],
				agentSessionIds: [],
				promptIds: [],
				operationIds: [],
				createdAfterUnixMilliseconds: null,
				createdBeforeUnixMilliseconds: null,
				sourceKinds: [],
			},
		},
		baseEndpoint: makeSourceEndpoint({
			endpointId: 'dev-base',
			kind: 'gitRef',
			label: props.baseRef,
			providerIdentity: props.baseRef,
		}),
		headEndpoint: makeSourceEndpoint({
			endpointId: 'dev-head',
			kind: 'workingTree',
			label: 'Working tree',
			providerIdentity: props.worktreeRoot,
		}),
		orderedItemIds: items.map((item) => item.itemId),
		itemsById,
		groups: [],
		summary,
		filterState: defaultViewFilter(),
		generatedAtUnixMilliseconds: Date.now(),
	};
	return {
		contentByHandleId,
		fingerprint: props.snapshot.fingerprint,
		reviewPackage,
		worktreeFileContentByDescriptorId,
		worktreeFileSurface,
	};
}

function worktreeFileDescriptorForChangedFile(props: {
	readonly changedFile: WorktreeChangedFile;
	readonly sourceIdentity: WorktreeFileSurfaceSourceIdentity;
	readonly worktreeFileContentByDescriptorId: Map<string, string>;
}): readonly WorktreeFileDescriptor[] {
	const content = props.changedFile.headContent ?? props.changedFile.baseContent;
	if (content === null) {
		return [];
	}
	const pathHash = hashText(props.changedFile.path).slice(0, 16);
	const descriptorId = `dev-file-${pathHash}`;
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
			lineCount: lineCount(content),
			isBinary: false,
			language: languageForExtension(extension),
			fileExtension: extension,
		},
	];
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
}): Promise<readonly WorktreeChangedFile[]> {
	const records = await gitNameStatusRecords(props);
	const changedFiles = await Promise.all(
		records.map(async (record): Promise<WorktreeChangedFile> => {
			const [baseContent, headContent] = await Promise.all([
				record.changeKind === 'added'
					? Promise.resolve(null)
					: gitShowOrNull(props.worktreeRoot, props.baseRef, record.path),
				record.changeKind === 'deleted'
					? Promise.resolve(null)
					: readWorktreeFileText({ path: record.path, worktreeRoot: props.worktreeRoot }),
			]);
			const lineDelta = countLineDelta(baseContent, headContent);
			return {
				additions: lineDelta.additions,
				baseContent,
				changeKind: record.changeKind,
				deletions: lineDelta.deletions,
				headContent,
				path: record.path,
			};
		}),
	);
	return changedFiles;
}

function fingerprintChangedFiles(changedFiles: readonly WorktreeChangedFile[]): string {
	return hashText(
		JSON.stringify(
			changedFiles.map((changedFile) => ({
				additions: changedFile.additions,
				baseContentHash:
					changedFile.baseContent === null ? null : hashText(changedFile.baseContent),
				changeKind: changedFile.changeKind,
				deletions: changedFile.deletions,
				headContentHash:
					changedFile.headContent === null ? null : hashText(changedFile.headContent),
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
		.map((path): GitNameStatusRecord => ({ changeKind: 'added', path }));
	const recordByPath = new Map<string, GitNameStatusRecord>();
	for (const record of [...diffRecords, ...untrackedRecords]) {
		recordByPath.set(record.path, record);
	}
	return [...recordByPath.values()].toSorted((left, right) => left.path.localeCompare(right.path));
}

function parseNameStatusLine(line: string): GitNameStatusRecord {
	const columns = line.split('\t');
	const status = columns[0] ?? '';
	const path = status.startsWith('R') || status.startsWith('C') ? columns[2] : columns[1];
	if (path === undefined || path.length === 0) {
		throw new Error(`Invalid git name-status line: ${line}`);
	}
	return {
		changeKind: changeKindForGitStatus(status),
		path,
	};
}

function changeKindForGitStatus(status: string): BridgeFileChangeKind {
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

function makeReviewItem(props: {
	readonly changedFile: WorktreeChangedFile;
	readonly contentByHandleId: Map<string, string>;
	readonly revision: number;
	readonly worktreeRoot: string;
}): BridgeReviewItemDescriptor {
	const itemId = `dev-${hashText(props.changedFile.path).slice(0, 16)}`;
	const extension = extensionForPath(props.changedFile.path);
	const language = languageForExtension(extension);
	const fileClass = fileClassForPath(props.changedFile.path, extension);
	const baseHandle = makeHandleForContent({
		content: props.changedFile.baseContent,
		contentByHandleId: props.contentByHandleId,
		endpointId: 'dev-base',
		extension,
		itemId,
		language,
		path: props.changedFile.path,
		revision: props.revision,
		role: 'base',
	});
	const headHandle = makeHandleForContent({
		content: props.changedFile.headContent,
		contentByHandleId: props.contentByHandleId,
		endpointId: 'dev-head',
		extension,
		itemId,
		language,
		path: props.changedFile.path,
		revision: props.revision,
		role: 'head',
	});
	return {
		itemId,
		itemKind: 'diff',
		itemVersion: 1,
		basePath: props.changedFile.changeKind === 'added' ? null : props.changedFile.path,
		headPath: props.changedFile.changeKind === 'deleted' ? null : props.changedFile.path,
		changeKind: props.changedFile.changeKind,
		fileClass,
		language,
		extension,
		sizeBytes: byteLength(props.changedFile.headContent ?? props.changedFile.baseContent ?? ''),
		baseContentHash: baseHandle?.contentHash ?? null,
		headContentHash: headHandle?.contentHash ?? null,
		contentHashAlgorithm: 'sha256',
		additions: props.changedFile.additions,
		deletions: props.changedFile.deletions,
		isHiddenByDefault: false,
		hiddenReason: null,
		reviewPriority: 'normal',
		contentRoles: { base: baseHandle, head: headHandle, diff: null, file: null },
		cacheKey: `${baseHandle?.cacheKey ?? 'none'}|${headHandle?.cacheKey ?? 'none'}`,
		provenance: {
			paneIds: [],
			agentSessionIds: [],
			promptIds: [],
			operationIds: [],
			sourceKinds: ['dev-worktree'],
		},
		annotationSummary: { threadCount: 0, unresolvedThreadCount: 0, commentCount: 0 },
		reviewState: 'unreviewed',
		collapsed: false,
	};
}

function makeHandleForContent(props: {
	readonly content: string | null;
	readonly contentByHandleId: Map<string, string>;
	readonly endpointId: string;
	readonly extension: string;
	readonly itemId: string;
	readonly language: string;
	readonly path: string;
	readonly revision: number;
	readonly role: BridgeContentRole;
}): BridgeContentHandle | null {
	if (props.content === null) {
		return null;
	}
	const contentHash = `sha256:${hashText(props.content)}`;
	const handleId = `dev-${props.itemId}-${props.role}`;
	props.contentByHandleId.set(handleId, props.content);
	return {
		handleId,
		itemId: props.itemId,
		role: props.role,
		endpointId: props.endpointId,
		reviewGeneration,
		resourceUrl: `agentstudio://resource/review/content/${handleId}?generation=${reviewGeneration}&revision=${props.revision}`,
		contentHash,
		contentHashAlgorithm: 'sha256',
		cacheKey: `${props.itemId}:${props.role}:${contentHash}`,
		mimeType: mimeTypeForExtension(props.extension),
		language: props.language,
		sizeBytes: byteLength(props.content),
		isBinary: false,
	};
}

function summarizeItems(items: readonly BridgeReviewItemDescriptor[]): BridgeReviewPackageSummary {
	return {
		filesChanged: items.length,
		additions: items.reduce((total, item) => total + item.additions, 0),
		deletions: items.reduce((total, item) => total + item.deletions, 0),
		visibleFileCount: items.length,
		hiddenFileCount: 0,
	};
}

function makeSourceEndpoint(props: {
	readonly endpointId: string;
	readonly kind: BridgeSourceEndpoint['kind'];
	readonly label: string;
	readonly providerIdentity: string;
}): BridgeSourceEndpoint {
	return {
		endpointId: props.endpointId,
		kind: props.kind,
		repoId: 'dev-worktree-repo',
		worktreeId: 'dev-worktree',
		label: props.label,
		createdAtUnixMilliseconds: Date.now(),
		contentSetHash: null,
		providerIdentity: props.providerIdentity,
	};
}

function defaultViewFilter(): BridgeViewFilter {
	return {
		includedPathGlobs: [],
		excludedPathGlobs: [],
		includedFileClasses: [],
		excludedFileClasses: [],
		includedExtensions: [],
		excludedExtensions: [],
		changeKinds: [],
		reviewStates: [],
		showHiddenFiles: false,
		showBinaryFiles: false,
		showLargeFiles: true,
	};
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
	const relativePath = relative(props.worktreeRoot, absolutePath);
	if (
		relativePath.startsWith('..') ||
		relativePath === '' ||
		relativePath.split(sep).includes('..')
	) {
		throw new Error(`Bridge worktree path escapes root: ${props.path}`);
	}
	return await readFile(absolutePath, 'utf8');
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

function extensionForPath(path: string): string {
	const extension = extname(path).replace(/^\./u, '');
	return extension.length === 0 ? 'txt' : extension;
}

function fileClassForPath(path: string, extension: string): BridgeFileClass {
	if (path.startsWith('docs/') || extension === 'md' || extension === 'mdx') {
		return 'docs';
	}
	if (path.includes('/test/') || path.includes('/tests/') || path.endsWith('.test.ts')) {
		return 'test';
	}
	if (['json', 'yml', 'yaml', 'toml', 'lock'].includes(extension)) {
		return 'config';
	}
	return 'source';
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

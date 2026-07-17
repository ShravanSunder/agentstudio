import {
	prepareFileTreeInput,
	type FileTreeBatchOperation,
	type FileTreeItemHandle,
	type FileTreeOptions,
	type FileTreePreparedInput,
	type FileTreeResetOptions,
	type GitStatus,
	type GitStatusEntry,
} from '@pierre/trees';

import {
	appendedOnlyPierreTreePaths,
	expandAncestorDirectoriesForPierreTreePaths,
} from '../../app/bridge-pierre-tree-adapter.js';
import { compileBridgeFileTreeSearchPattern } from '../../core/models/bridge-file-tree-search.js';
import type { ReviewTreeRowMetadata } from '../../features/review/models/review-protocol-models.js';
import type { BridgeReviewPackage } from '../../foundation/review-package/bridge-review-package.js';
import type { BridgeTelemetryRecorder } from '../../foundation/telemetry/bridge-telemetry-recorder.js';
import type { BridgeTraceContext } from '../../foundation/telemetry/bridge-trace-context.js';
import { recordBridgeTreeScrollToPathTelemetrySample } from '../../foundation/telemetry/bridge-viewer-telemetry-adapter.js';
import type {
	BridgeReviewProjectionResult,
	BridgeReviewSearchMode,
} from '../models/review-projection-models.js';

export interface BridgeTreesModel {
	readonly resetPaths: (paths: readonly string[], options?: FileTreeResetOptions) => void;
	readonly batch: (operations: readonly FileTreeBatchOperation[]) => void;
	readonly setGitStatus: (gitStatus?: FileTreeOptions['gitStatus']) => void;
	readonly getItem: (path: string) => FileTreeItemHandle | null;
	readonly resolveMountedDirectoryPathFromInput?: (path: string) => string | null;
	readonly focusPath: (path: string) => void;
	readonly scrollToPath: (path: string, options?: { readonly focus?: boolean }) => void;
}

export interface BridgeTreesSource {
	readonly disclosurePolicyIdentity: string;
	readonly presentationPositionKey: string;
	readonly packageId: string;
	readonly reviewGeneration: number;
	readonly revision: number;
	readonly projectionId: string;
	readonly orderedPaths: readonly string[];
	readonly preparedInput: FileTreePreparedInput;
	readonly initialExpandedPaths: readonly string[];
	readonly gitStatusEntries: readonly GitStatusEntry[];
	readonly primaryItemIdByTreePath: Readonly<Record<string, string>>;
	readonly searchError: string | null;
	readonly gitStatusSignature: string;
}

export type BridgeTreesUpdatePlan =
	| { readonly kind: 'none' }
	| { readonly kind: 'reset' }
	| { readonly kind: 'statusOnly' }
	| {
			readonly kind: 'appendOnly';
			readonly addedPaths: readonly string[];
			readonly shouldUpdateGitStatus: boolean;
	  };

export interface CreateBridgeTreesSourceProps {
	readonly presentationPositionKey?: string;
	readonly reviewPackage: BridgeReviewPackage;
	readonly reviewTreeRows?: readonly ReviewTreeRowMetadata[];
	readonly projection: BridgeReviewProjectionResult;
	readonly searchMode?: BridgeReviewSearchMode;
	readonly searchText?: string;
}

export interface PlanBridgeTreesUpdateProps {
	readonly previous: BridgeTreesSource | null;
	readonly next: BridgeTreesSource;
}

export interface BridgeTreesControllerProps {
	readonly isProgrammaticScrollActive?: (() => boolean) | undefined;
	readonly model: BridgeTreesModel;
	readonly telemetryRecorder?: BridgeTelemetryRecorder | undefined;
	readonly telemetryTraceContext?: BridgeTraceContext | null | undefined;
}

export const bridgeTreesDisclosurePolicyIdentity = 'fresh-fully-expanded-v1';

export function createBridgeTreesSource(props: CreateBridgeTreesSourceProps): BridgeTreesSource {
	const treeRowsSource = reviewTreeRowsSourceForProjection({
		projection: props.projection,
		reviewTreeRows: props.reviewTreeRows ?? [],
	});
	const unfilteredSourcePaths =
		treeRowsSource === null ? props.projection.orderedPaths : treeRowsSource.orderedPaths;
	const unfilteredPrimaryItemIdByTreePath =
		treeRowsSource === null
			? props.projection.primaryItemIdByTreePath
			: treeRowsSource.primaryItemIdByTreePath;
	const searchProjection = projectBridgeTreeSourceForSearch({
		orderedPaths: unfilteredSourcePaths,
		primaryItemIdByTreePath: unfilteredPrimaryItemIdByTreePath,
		searchMode: props.searchMode ?? { kind: 'text' },
		searchText: props.searchText ?? '',
	});
	const preparedInput = prepareBridgeTreeInput(searchProjection.orderedPaths);
	const treePaths = preparedInput.paths;
	const initialExpandedPaths = expandedDirectoryPathsForBridgeTreePaths(treePaths);
	const primaryItemIdByTreePath = searchProjection.primaryItemIdByTreePath;
	const gitStatusEntries = createGitStatusEntries({
		primaryItemIdByTreePath,
		reviewPackage: props.reviewPackage,
		treePaths,
	});

	return {
		disclosurePolicyIdentity: bridgeTreesDisclosurePolicyIdentity,
		presentationPositionKey:
			props.presentationPositionKey ??
			legacyBridgeTreesPresentationPositionKey({
				projection: props.projection,
				reviewPackage: props.reviewPackage,
			}),
		packageId: props.reviewPackage.packageId,
		reviewGeneration: props.reviewPackage.reviewGeneration,
		revision: props.reviewPackage.revision,
		projectionId: props.projection.projectionId,
		orderedPaths: treePaths,
		preparedInput,
		initialExpandedPaths,
		gitStatusEntries,
		primaryItemIdByTreePath,
		searchError: searchProjection.searchError,
		gitStatusSignature: gitStatusSignature(gitStatusEntries),
	};
}

function projectBridgeTreeSourceForSearch(props: {
	readonly orderedPaths: readonly string[];
	readonly primaryItemIdByTreePath: Readonly<Record<string, string>>;
	readonly searchMode: BridgeReviewSearchMode;
	readonly searchText: string;
}): {
	readonly orderedPaths: readonly string[];
	readonly primaryItemIdByTreePath: Readonly<Record<string, string>>;
	readonly searchError: string | null;
} {
	const compilation = compileBridgeFileTreeSearchPattern({
		searchMode: props.searchMode.kind,
		searchText: props.searchText,
	});
	if (compilation.searchError !== null) {
		return { orderedPaths: [], primaryItemIdByTreePath: {}, searchError: compilation.searchError };
	}
	if (compilation.pattern === null) {
		return {
			orderedPaths: props.orderedPaths,
			primaryItemIdByTreePath: props.primaryItemIdByTreePath,
			searchError: null,
		};
	}

	const orderedPaths: string[] = [];
	const primaryItemIdByTreePath: Record<string, string> = {};
	for (const path of props.orderedPaths) {
		const itemId = props.primaryItemIdByTreePath[path];
		if (itemId === undefined || !compilation.pattern.test(path)) continue;
		orderedPaths.push(path);
		primaryItemIdByTreePath[path] = itemId;
	}
	return { orderedPaths, primaryItemIdByTreePath, searchError: null };
}

function reviewTreeRowsSourceForProjection(props: {
	readonly reviewTreeRows: readonly ReviewTreeRowMetadata[];
	readonly projection: BridgeReviewProjectionResult;
}): {
	readonly orderedPaths: readonly string[];
	readonly primaryItemIdByTreePath: Readonly<Record<string, string>>;
} | null {
	if (props.reviewTreeRows.length === 0) {
		return null;
	}
	const projectedItemIds = new Set(props.projection.orderedItemIds);
	const orderedPaths: string[] = [];
	const primaryItemIdByTreePath: Record<string, string> = {};
	const seenPaths = new Set<string>();
	for (const row of props.reviewTreeRows) {
		if (!row.isDirectory && (row.itemId === undefined || !projectedItemIds.has(row.itemId))) {
			continue;
		}
		const treePath = bridgeTreePathForReviewRow(row);
		if (seenPaths.has(treePath)) {
			continue;
		}
		seenPaths.add(treePath);
		orderedPaths.push(treePath);
		if (row.itemId !== undefined && projectedItemIds.has(row.itemId)) {
			primaryItemIdByTreePath[treePath] = row.itemId;
		}
	}
	return orderedPaths.length === 0
		? null
		: {
				orderedPaths,
				primaryItemIdByTreePath,
			};
}

function bridgeTreePathForReviewRow(row: ReviewTreeRowMetadata): string {
	return row.isDirectory && !row.path.endsWith('/') ? `${row.path}/` : row.path;
}

export function prepareBridgeTreeInput(paths: readonly string[]): FileTreePreparedInput {
	return prepareFileTreeInput(paths);
}

export function expandedDirectoryPathsForBridgeTreePaths(
	paths: readonly string[],
): readonly string[] {
	const expandedDirectoryPaths = new Set<string>();
	for (const path of paths) {
		const normalizedPath = path.endsWith('/') ? path.slice(0, -1) : path;
		const pathSegments = normalizedPath.split('/').filter((segment): boolean => segment.length > 0);
		const directorySegmentCount = path.endsWith('/')
			? pathSegments.length
			: Math.max(pathSegments.length - 1, 0);
		for (let segmentCount = 1; segmentCount <= directorySegmentCount; segmentCount += 1) {
			expandedDirectoryPaths.add(pathSegments.slice(0, segmentCount).join('/'));
		}
	}
	return [...expandedDirectoryPaths];
}

export function planBridgeTreesUpdate(props: PlanBridgeTreesUpdateProps): BridgeTreesUpdatePlan {
	if (props.previous === null) {
		return { kind: 'reset' };
	}

	if (!sameProjectionIdentity(props.previous, props.next)) {
		return { kind: 'reset' };
	}
	if (props.previous.disclosurePolicyIdentity !== props.next.disclosurePolicyIdentity) {
		return { kind: 'reset' };
	}

	const pathsMatch = arraysEqual(props.previous.orderedPaths, props.next.orderedPaths);
	const gitStatusMatches = props.previous.gitStatusSignature === props.next.gitStatusSignature;

	if (pathsMatch) {
		return gitStatusMatches ? { kind: 'none' } : { kind: 'statusOnly' };
	}

	const addedPaths = appendedOnlyPierreTreePaths({
		nextPaths: props.next.orderedPaths,
		previousPaths: props.previous.orderedPaths,
	});
	if (addedPaths !== null && addedPaths.length > 0) {
		return {
			kind: 'appendOnly',
			addedPaths,
			shouldUpdateGitStatus: !gitStatusMatches,
		};
	}

	return { kind: 'reset' };
}

export class BridgeTreesController {
	readonly #model: BridgeTreesModel;
	#currentSource: BridgeTreesSource | null = null;
	readonly #isProgrammaticScrollActive: () => boolean;
	#selectedTreePath: string | null = null;
	#telemetryRecorder: BridgeTelemetryRecorder | undefined;
	#telemetryTraceContext: BridgeTraceContext | null;

	constructor(props: BridgeTreesControllerProps) {
		this.#model = props.model;
		this.#isProgrammaticScrollActive = props.isProgrammaticScrollActive ?? ((): boolean => false);
		this.#telemetryRecorder = props.telemetryRecorder;
		this.#telemetryTraceContext = props.telemetryTraceContext ?? null;
	}

	setTelemetryContext(props: {
		readonly telemetryRecorder?: BridgeTelemetryRecorder | undefined;
		readonly telemetryTraceContext?: BridgeTraceContext | null | undefined;
	}): void {
		this.#telemetryRecorder = props.telemetryRecorder;
		this.#telemetryTraceContext = props.telemetryTraceContext ?? null;
	}

	applySource(source: BridgeTreesSource): BridgeTreesUpdatePlan {
		const updatePlan = planBridgeTreesUpdate({
			previous: this.#currentSource,
			next: source,
		});

		switch (updatePlan.kind) {
			case 'none':
				break;
			case 'reset':
				this.#model.resetPaths(
					source.orderedPaths,
					resetOptionsForSource({
						model: this.#model,
						previousSource: this.#currentSource,
						source,
					}),
				);
				this.#model.setGitStatus(source.gitStatusEntries);
				if (
					this.#selectedTreePath === null ||
					source.primaryItemIdByTreePath[this.#selectedTreePath] === undefined
				) {
					this.#selectedTreePath = null;
				} else {
					this.#model.getItem(this.#selectedTreePath)?.select();
				}
				break;
			case 'statusOnly':
				this.#model.setGitStatus(source.gitStatusEntries);
				break;
			case 'appendOnly':
				this.#model.batch(
					updatePlan.addedPaths.map(
						(path: string): FileTreeBatchOperation => ({ type: 'add', path }),
					),
				);
				if (updatePlan.shouldUpdateGitStatus) {
					this.#model.setGitStatus(source.gitStatusEntries);
				}
				break;
			default:
				assertNever(updatePlan);
		}

		this.#currentSource = source;
		return updatePlan;
	}

	selectTreePath(path: string): string | null {
		const itemId = this.#currentSource?.primaryItemIdByTreePath[path];
		if (itemId === undefined) {
			return null;
		}
		if (this.#selectedTreePath === path) {
			return itemId;
		}
		this.revealTreePathAncestors(path);
		this.#scrollToPath({
			focus: true,
			options: { focus: true },
			path,
			reason: 'selected_path_effect',
		});
		this.#selectedTreePath = path;
		return itemId;
	}

	markTreePathSelected(path: string): string | null {
		const itemId = this.#currentSource?.primaryItemIdByTreePath[path];
		if (itemId === undefined) {
			return null;
		}
		this.#selectedTreePath = path;
		return itemId;
	}

	selectClickedTreePath(path: string): string | null {
		const itemId = this.markTreePathSelected(path);
		if (itemId === null) {
			return null;
		}
		this.#model.getItem(path)?.select();
		return itemId;
	}

	revealTreePath(
		path: string,
		reason: 'append_reveal' | 'search_match' | 'selection_sync' = 'search_match',
	): void {
		this.revealTreePathAncestors(path);
		this.#scrollToPath({
			focus: false,
			options: undefined,
			path,
			reason,
		});
	}

	revealFirstSearchMatch(
		searchText: string,
		searchMode: BridgeReviewSearchMode = { kind: 'text' },
	): string | null {
		const currentSource = this.#currentSource;
		if (currentSource === null) {
			return null;
		}
		const matchedPath = firstBridgeTreeSearchMatchPath({
			orderedPaths: currentSource.orderedPaths,
			primaryItemIdByTreePath: currentSource.primaryItemIdByTreePath,
			searchMode,
			searchText,
		});
		if (matchedPath === null) {
			return null;
		}
		this.revealTreePath(matchedPath, 'search_match');
		return matchedPath;
	}

	modelSearchTextForFirstSearchMatch(
		searchText: string,
		searchMode: BridgeReviewSearchMode = { kind: 'text' },
	): string {
		if (searchMode.kind === 'regex') {
			return searchText;
		}
		if (!searchText.includes('/') && !searchText.includes('\\')) {
			return searchText;
		}
		const currentSource = this.#currentSource;
		if (currentSource === null) {
			return searchText;
		}
		const matchedPath = firstBridgeTreeSearchMatchPath({
			orderedPaths: currentSource.orderedPaths,
			primaryItemIdByTreePath: currentSource.primaryItemIdByTreePath,
			searchMode,
			searchText,
		});
		if (matchedPath === null) {
			return searchText;
		}
		const leafName = matchedPath.split('/').findLast((segment): boolean => segment.length > 0);
		if (leafName === undefined || leafName.length === 0) {
			return searchText;
		}
		const extensionIndex = leafName.lastIndexOf('.');
		return extensionIndex <= 0 ? leafName : leafName.slice(0, extensionIndex);
	}

	revealTreePathAncestors(path: string): void {
		expandAncestorDirectories({ model: this.#model, path });
	}

	#scrollToPath(props: {
		readonly focus: boolean;
		readonly options: Parameters<BridgeTreesModel['scrollToPath']>[1];
		readonly path: string;
		readonly reason: 'append_reveal' | 'search_match' | 'selected_path_effect' | 'selection_sync';
	}): void {
		const startedAt = performance.now();
		const shouldDropScrollToPath =
			(props.reason === 'search_match' || props.reason === 'selected_path_effect') &&
			this.#isProgrammaticScrollActive();
		if (!shouldDropScrollToPath) {
			this.#model.scrollToPath(props.path, props.options);
		}
		if (this.#telemetryRecorder === undefined) {
			return;
		}
		if (shouldDropScrollToPath) {
			recordBridgeTreeScrollToPathTelemetrySample({
				durationMilliseconds: performance.now() - startedAt,
				focus: props.focus,
				offset: 'none',
				reason: props.reason,
				result: 'dropped',
				telemetryRecorder: this.#telemetryRecorder,
				traceContext: this.#telemetryTraceContext,
				viewer: 'review',
			});
			return;
		}
		recordBridgeTreeScrollToPathTelemetrySample({
			durationMilliseconds: performance.now() - startedAt,
			focus: props.focus,
			offset: 'none',
			reason: props.reason,
			telemetryRecorder: this.#telemetryRecorder,
			traceContext: this.#telemetryTraceContext,
			viewer: 'review',
		});
	}
}

function firstBridgeTreeSearchMatchPath(props: {
	readonly orderedPaths: readonly string[];
	readonly primaryItemIdByTreePath: Readonly<Record<string, string>>;
	readonly searchMode: BridgeReviewSearchMode;
	readonly searchText: string;
}): string | null {
	const compilation = compileBridgeFileTreeSearchPattern({
		searchMode: props.searchMode.kind,
		searchText: props.searchText,
	});
	if (compilation.pattern === null || compilation.searchError !== null) {
		return null;
	}
	const pattern = compilation.pattern;
	return (
		props.orderedPaths.find(
			(path: string): boolean =>
				props.primaryItemIdByTreePath[path] !== undefined && pattern.test(path),
		) ?? null
	);
}

function expandAncestorDirectories(props: {
	readonly model: BridgeTreesModel;
	readonly path: string;
}): void {
	expandAncestorDirectoriesForPierreTreePaths({
		ignoreExpandErrors: true,
		model: props.model,
		paths: [props.path],
	});
}

function createGitStatusEntries(props: {
	readonly primaryItemIdByTreePath: Readonly<Record<string, string>>;
	readonly reviewPackage: BridgeReviewPackage;
	readonly treePaths: readonly string[];
}): readonly GitStatusEntry[] {
	const entries: GitStatusEntry[] = [];

	for (const path of props.treePaths) {
		const itemId = props.primaryItemIdByTreePath[path];
		if (itemId === undefined) {
			continue;
		}
		const item = props.reviewPackage.itemsById[itemId];
		if (item === undefined) {
			continue;
		}
		const status = gitStatusForChangeKind(item.changeKind);
		if (status === null) {
			continue;
		}
		entries.push({ path, status });
	}

	return entries;
}

function gitStatusForChangeKind(changeKind: string): GitStatus | null {
	switch (changeKind) {
		case 'added':
			return 'added';
		case 'deleted':
			return 'deleted';
		case 'modified':
			return 'modified';
		case 'renamed':
			return 'renamed';
		case 'copied':
			return null;
		default:
			return null;
	}
}

function sameProjectionIdentity(left: BridgeTreesSource, right: BridgeTreesSource): boolean {
	return left.presentationPositionKey === right.presentationPositionKey;
}

function arraysEqual(left: readonly string[], right: readonly string[]): boolean {
	return (
		left.length === right.length &&
		left.every((value: string, index: number): boolean => value === right[index])
	);
}

function gitStatusSignature(entries: readonly GitStatusEntry[]): string {
	return entries
		.map((entry: GitStatusEntry): string => `${entry.path}\u0000${entry.status}`)
		.join('\n');
}

function resetOptionsForSource(props: {
	readonly model: BridgeTreesModel;
	readonly previousSource: BridgeTreesSource | null;
	readonly source: BridgeTreesSource;
}): FileTreeResetOptions {
	const previousSource = props.previousSource;
	const initialExpandedPaths =
		previousSource === null ||
		previousSource.presentationPositionKey !== props.source.presentationPositionKey
			? props.source.initialExpandedPaths
			: props.source.initialExpandedPaths.filter((directoryPath): boolean => {
					if (!previousSource.initialExpandedPaths.includes(directoryPath)) return true;
					const directoryItem = props.model.getItem(directoryPath);
					return directoryItem !== null && 'isExpanded' in directoryItem
						? directoryItem.isExpanded()
						: true;
				});
	return {
		preparedInput: props.source.preparedInput,
		initialExpandedPaths,
	};
}

function legacyBridgeTreesPresentationPositionKey(props: {
	readonly projection: Pick<BridgeReviewProjectionResult, 'projectionId'>;
	readonly reviewPackage: Pick<BridgeReviewPackage, 'packageId' | 'reviewGeneration'>;
}): string {
	return [
		'legacy-review-position',
		props.reviewPackage.packageId,
		props.reviewPackage.reviewGeneration,
		props.projection.projectionId,
	].join(':');
}

function assertNever(value: never): never {
	throw new Error(`Unexpected Bridge Trees update plan: ${JSON.stringify(value)}`);
}

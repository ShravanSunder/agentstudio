import {
	prepareFileTreeInput,
	preparePresortedFileTreeInput,
	type FileTreeBatchOperation,
	type FileTreeDirectoryHandle,
	type FileTreeItemHandle,
	type FileTreeOptions,
	type FileTreePreparedInput,
	type FileTreeResetOptions,
	type GitStatus,
	type GitStatusEntry,
} from '@pierre/trees';

import type { BridgeReviewPackage } from '../../foundation/review-package/bridge-review-package.js';
import type { BridgeReviewProjectionResult } from '../models/review-projection-models.js';

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
	readonly packageId: string;
	readonly reviewGeneration: number;
	readonly revision: number;
	readonly projectionId: string;
	readonly orderedPaths: readonly string[];
	readonly preparedInput: FileTreePreparedInput;
	readonly initialExpandedPaths: readonly string[];
	readonly gitStatusEntries: readonly GitStatusEntry[];
	readonly primaryItemIdByTreePath: Readonly<Record<string, string>>;
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
	readonly reviewPackage: BridgeReviewPackage;
	readonly projection: BridgeReviewProjectionResult;
}

export interface PlanBridgeTreesUpdateProps {
	readonly previous: BridgeTreesSource | null;
	readonly next: BridgeTreesSource;
}

export interface BridgeTreesControllerProps {
	readonly model: BridgeTreesModel;
}

const bridgeTreeFullInitialExpansionPathLimit = 500;
const bridgeTreeLargeInitialExpansionPathLimit = 48;
const bridgeTreeAppendRevealPathLimit = 16;

export function createBridgeTreesSource(props: CreateBridgeTreesSourceProps): BridgeTreesSource {
	const preparedInput = prepareBridgeTreeInput(props.projection.orderedPaths);
	const treePaths = preparedInput.paths;
	const gitStatusEntries = createGitStatusEntries({
		reviewPackage: props.reviewPackage,
		projection: props.projection,
	});

	return {
		packageId: props.reviewPackage.packageId,
		reviewGeneration: props.reviewPackage.reviewGeneration,
		revision: props.reviewPackage.revision,
		projectionId: props.projection.projectionId,
		orderedPaths: treePaths,
		preparedInput,
		initialExpandedPaths: createInitialExpandedPaths({
			orderedPaths: treePaths,
			expansionPathLimit:
				treePaths.length > bridgeTreeFullInitialExpansionPathLimit
					? bridgeTreeLargeInitialExpansionPathLimit
					: treePaths.length,
		}),
		gitStatusEntries,
		primaryItemIdByTreePath: props.projection.primaryItemIdByTreePath,
		gitStatusSignature: gitStatusSignature(gitStatusEntries),
	};
}

export function prepareBridgeTreeInput(paths: readonly string[]): FileTreePreparedInput {
	return prepareFileTreeInput(paths);
}

export function prepareBridgePresortedTreeInput(paths: readonly string[]): FileTreePreparedInput {
	return preparePresortedFileTreeInput(paths);
}

export function planBridgeTreesUpdate(props: PlanBridgeTreesUpdateProps): BridgeTreesUpdatePlan {
	if (props.previous === null) {
		return { kind: 'reset' };
	}

	if (!sameProjectionIdentity(props.previous, props.next)) {
		return { kind: 'reset' };
	}

	const pathsMatch = arraysEqual(props.previous.orderedPaths, props.next.orderedPaths);
	const gitStatusMatches = props.previous.gitStatusSignature === props.next.gitStatusSignature;

	if (pathsMatch) {
		return gitStatusMatches ? { kind: 'none' } : { kind: 'statusOnly' };
	}

	if (isAppendOnlyPathChange(props.previous.orderedPaths, props.next.orderedPaths)) {
		return {
			kind: 'appendOnly',
			addedPaths: props.next.orderedPaths.slice(props.previous.orderedPaths.length),
			shouldUpdateGitStatus: !gitStatusMatches,
		};
	}

	return { kind: 'reset' };
}

export class BridgeTreesController {
	readonly #model: BridgeTreesModel;
	#currentSource: BridgeTreesSource | null = null;

	constructor(props: BridgeTreesControllerProps) {
		this.#model = props.model;
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
				this.#model.resetPaths(source.orderedPaths, resetOptionsForSource(source));
				this.#model.setGitStatus(source.gitStatusEntries);
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
				for (const path of updatePlan.addedPaths.slice(0, bridgeTreeAppendRevealPathLimit)) {
					expandAncestorDirectories({ model: this.#model, path });
				}
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
		this.revealTreePathAncestors(path);
		this.#model.scrollToPath(path, { focus: true });
		return itemId;
	}

	revealTreePath(path: string): void {
		this.revealTreePathAncestors(path);
		this.#model.scrollToPath(path);
	}

	revealTreePathAncestors(path: string): void {
		expandAncestorDirectories({ model: this.#model, path });
	}
}

function expandAncestorDirectories(props: {
	readonly model: BridgeTreesModel;
	readonly path: string;
}): void {
	const ancestorPaths = ancestorDirectoryPaths(props.path);
	for (const ancestorPath of ancestorPaths) {
		const item = directoryItemForInputPath({
			model: props.model,
			path: ancestorPath,
		});
		if (isFileTreeDirectoryHandle(item) && !item.isExpanded()) {
			item.expand();
		}
	}
}

function isFileTreeDirectoryHandle(
	item: FileTreeItemHandle | null,
): item is FileTreeDirectoryHandle {
	return item?.isDirectory() === true;
}

function directoryItemForInputPath(props: {
	readonly model: BridgeTreesModel;
	readonly path: string;
}): FileTreeItemHandle | null {
	const slashPath = `${props.path}/`;
	const mountedPath =
		props.model.resolveMountedDirectoryPathFromInput?.(props.path) ??
		props.model.resolveMountedDirectoryPathFromInput?.(slashPath) ??
		null;
	if (mountedPath !== null) {
		return props.model.getItem(mountedPath);
	}
	return props.model.getItem(props.path) ?? props.model.getItem(slashPath);
}

function ancestorDirectoryPaths(path: string): readonly string[] {
	const segments = path.split('/').filter((segment: string): boolean => segment.length > 0);
	const ancestorPaths: string[] = [];
	let currentPath = '';
	for (const segment of segments.slice(0, -1)) {
		currentPath = currentPath.length === 0 ? segment : `${currentPath}/${segment}`;
		ancestorPaths.push(currentPath);
	}
	return ancestorPaths;
}

function createGitStatusEntries(props: CreateBridgeTreesSourceProps): readonly GitStatusEntry[] {
	const entries: GitStatusEntry[] = [];

	for (const path of props.projection.orderedPaths) {
		const itemId = props.projection.primaryItemIdByTreePath[path];
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
	return (
		left.packageId === right.packageId &&
		left.reviewGeneration === right.reviewGeneration &&
		left.projectionId === right.projectionId
	);
}

function arraysEqual(left: readonly string[], right: readonly string[]): boolean {
	return (
		left.length === right.length &&
		left.every((value: string, index: number): boolean => value === right[index])
	);
}

function isAppendOnlyPathChange(
	previousPaths: readonly string[],
	nextPaths: readonly string[],
): boolean {
	if (nextPaths.length <= previousPaths.length) {
		return false;
	}

	return previousPaths.every((path: string, index: number): boolean => path === nextPaths[index]);
}

function gitStatusSignature(entries: readonly GitStatusEntry[]): string {
	return entries
		.map((entry: GitStatusEntry): string => `${entry.path}\u0000${entry.status}`)
		.join('\n');
}

interface CreateInitialExpandedPathsProps {
	readonly orderedPaths: readonly string[];
	readonly expansionPathLimit: number;
}

function createInitialExpandedPaths(props: CreateInitialExpandedPathsProps): readonly string[] {
	const expandedPaths: string[] = [];
	const seenPaths = new Set<string>();

	for (const path of props.orderedPaths.slice(0, props.expansionPathLimit)) {
		const pathSegments = path.split('/').filter((segment: string): boolean => segment.length > 0);
		let currentPath = '';
		for (const pathSegment of pathSegments.slice(0, -1)) {
			currentPath = currentPath.length === 0 ? pathSegment : `${currentPath}/${pathSegment}`;
			if (seenPaths.has(currentPath)) {
				continue;
			}
			seenPaths.add(currentPath);
			expandedPaths.push(currentPath);
		}
	}

	return expandedPaths;
}

function resetOptionsForSource(source: BridgeTreesSource): FileTreeResetOptions {
	return {
		preparedInput: source.preparedInput,
		initialExpandedPaths: source.initialExpandedPaths,
	};
}

function assertNever(value: never): never {
	throw new Error(`Unexpected Bridge Trees update plan: ${JSON.stringify(value)}`);
}

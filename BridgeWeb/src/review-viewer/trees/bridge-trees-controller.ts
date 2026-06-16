import {
	preparePresortedFileTreeInput,
	type FileTreeBatchOperation,
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

export function createBridgeTreesSource(props: CreateBridgeTreesSourceProps): BridgeTreesSource {
	const gitStatusEntries = createGitStatusEntries({
		reviewPackage: props.reviewPackage,
		projection: props.projection,
	});

	return {
		packageId: props.reviewPackage.packageId,
		reviewGeneration: props.reviewPackage.reviewGeneration,
		revision: props.reviewPackage.revision,
		projectionId: props.projection.projectionId,
		orderedPaths: props.projection.orderedPaths,
		preparedInput: prepareBridgePresortedTreeInput(props.projection.orderedPaths),
		initialExpandedPaths: createInitialExpandedPaths(props.projection.orderedPaths),
		gitStatusEntries,
		primaryItemIdByTreePath: props.projection.primaryItemIdByTreePath,
		gitStatusSignature: gitStatusSignature(gitStatusEntries),
	};
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
		this.#model.focusPath(path);
		this.#model.scrollToPath(path, { focus: true });
		return itemId;
	}
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

function createInitialExpandedPaths(orderedPaths: readonly string[]): readonly string[] {
	const expandedPaths: string[] = [];
	const seenPaths = new Set<string>();

	for (const path of orderedPaths) {
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

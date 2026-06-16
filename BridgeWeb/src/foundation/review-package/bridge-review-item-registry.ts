import { applyBridgeReviewDelta, type BridgeReviewDelta } from './bridge-review-delta.js';
import { orderedReviewItems } from './bridge-review-package-adapter.js';
import type {
	BridgeFileChangeKind,
	BridgeFileClass,
	BridgeFileReviewState,
	BridgeReviewItemDescriptor,
	BridgeReviewPackage,
	BridgeReviewPriority,
} from './bridge-review-package.js';

export interface CreateBridgeReviewItemRegistryProps {
	readonly reviewPackage: BridgeReviewPackage;
	readonly selectedItemId: string | null;
}

export interface BridgeReviewVisiblePriorityFact {
	readonly itemId: string;
	readonly pathLabel: string;
	readonly reviewPriority: BridgeReviewPriority;
	readonly isSelected: boolean;
}

export interface BridgeReviewItemRegistry {
	readonly reviewPackage: BridgeReviewPackage;
	readonly selectedItemId: string | null;
	readonly selectedItem: BridgeReviewItemDescriptor | null;
	readonly orderedItems: readonly BridgeReviewItemDescriptor[];
	readonly visibleItems: readonly BridgeReviewItemDescriptor[];
	readonly visiblePriorityFacts: readonly BridgeReviewVisiblePriorityFact[];
}

export type BridgeReviewDeltaRejectionReason =
	| 'packageMismatch'
	| 'generationMismatch'
	| 'revisionGap';

export type BridgeReviewItemRegistryDeltaResult =
	| {
			readonly accepted: true;
			readonly registry: BridgeReviewItemRegistry;
	  }
	| {
			readonly accepted: false;
			readonly reason: BridgeReviewDeltaRejectionReason;
			readonly registry: BridgeReviewItemRegistry;
	  };

export function createBridgeReviewItemRegistry(
	props: CreateBridgeReviewItemRegistryProps,
): BridgeReviewItemRegistry {
	const orderedItems = orderedReviewItems(props.reviewPackage);
	const selectedItem =
		props.selectedItemId === null
			? null
			: (props.reviewPackage.itemsById[props.selectedItemId] ?? null);
	const visibleItems = orderedItems.filter((item: BridgeReviewItemDescriptor): boolean =>
		isReviewItemVisible(props.reviewPackage, item),
	);
	return {
		reviewPackage: props.reviewPackage,
		selectedItemId: selectedItem?.itemId ?? null,
		selectedItem,
		orderedItems,
		visibleItems,
		visiblePriorityFacts: visibleItems.map(
			(item: BridgeReviewItemDescriptor): BridgeReviewVisiblePriorityFact => ({
				itemId: item.itemId,
				pathLabel: reviewItemPathLabel(item),
				reviewPriority: item.reviewPriority,
				isSelected: selectedItem?.itemId === item.itemId,
			}),
		),
	};
}

export function applyDeltaToBridgeReviewItemRegistry(
	registry: BridgeReviewItemRegistry,
	delta: BridgeReviewDelta,
): BridgeReviewItemRegistryDeltaResult {
	if (registry.reviewPackage.packageId !== delta.packageId) {
		return {
			accepted: false,
			reason: 'packageMismatch',
			registry,
		};
	}
	if (registry.reviewPackage.reviewGeneration !== delta.reviewGeneration) {
		return {
			accepted: false,
			reason: 'generationMismatch',
			registry,
		};
	}
	if (delta.revision !== registry.reviewPackage.revision + 1) {
		return {
			accepted: false,
			reason: 'revisionGap',
			registry,
		};
	}

	return {
		accepted: true,
		registry: createBridgeReviewItemRegistry({
			reviewPackage: applyBridgeReviewDelta(registry.reviewPackage, delta),
			selectedItemId: registry.selectedItemId,
		}),
	};
}

export function reviewItemPathLabel(item: BridgeReviewItemDescriptor): string {
	return item.headPath ?? item.basePath ?? item.itemId;
}

function isReviewItemVisible(
	reviewPackage: BridgeReviewPackage,
	item: BridgeReviewItemDescriptor,
): boolean {
	const filter = reviewPackage.filterState;
	if (item.isHiddenByDefault && !filter.showHiddenFiles) {
		return false;
	}
	if (item.fileClass === 'binary' && !filter.showBinaryFiles) {
		return false;
	}
	if (item.fileClass === 'large' && !filter.showLargeFiles) {
		return false;
	}
	if (!isIncludedBySet(filter.includedFileClasses, item.fileClass)) {
		return false;
	}
	if (filter.excludedFileClasses.includes(item.fileClass)) {
		return false;
	}
	if (!isIncludedBySet(filter.changeKinds, item.changeKind)) {
		return false;
	}
	if (!isIncludedBySet(filter.reviewStates, item.reviewState)) {
		return false;
	}
	if (
		item.extension !== null &&
		item.extension !== undefined &&
		filter.excludedExtensions.includes(item.extension)
	) {
		return false;
	}
	if (
		filter.includedExtensions.length > 0 &&
		(item.extension === null ||
			item.extension === undefined ||
			!filter.includedExtensions.includes(item.extension))
	) {
		return false;
	}
	if (!isIncludedByPathScope(reviewPackage.query.pathScope, item)) {
		return false;
	}
	if (!isIncludedByPathGlobs(filter.includedPathGlobs, item)) {
		return false;
	}
	if (isExcludedByPathGlobs(filter.excludedPathGlobs, item)) {
		return false;
	}
	return true;
}

function isIncludedBySet<
	TValue extends BridgeFileClass | BridgeFileChangeKind | BridgeFileReviewState,
>(values: readonly TValue[], value: TValue): boolean {
	return values.length === 0 || values.includes(value);
}

function isIncludedByPathScope(
	pathScopeGlobs: readonly string[],
	item: BridgeReviewItemDescriptor,
): boolean {
	return isIncludedByPathGlobs(pathScopeGlobs, item);
}

function isIncludedByPathGlobs(
	pathGlobs: readonly string[],
	item: BridgeReviewItemDescriptor,
): boolean {
	return (
		pathGlobs.length === 0 ||
		reviewItemCandidatePaths(item).some((path: string): boolean =>
			pathGlobs.some((glob: string): boolean => matchesBridgePathGlob(path, glob)),
		)
	);
}

function isExcludedByPathGlobs(
	pathGlobs: readonly string[],
	item: BridgeReviewItemDescriptor,
): boolean {
	return reviewItemCandidatePaths(item).some((path: string): boolean =>
		pathGlobs.some((glob: string): boolean => matchesBridgePathGlob(path, glob)),
	);
}

function reviewItemCandidatePaths(item: BridgeReviewItemDescriptor): readonly string[] {
	return [item.headPath, item.basePath].filter(
		(path: string | null): path is string => path !== null,
	);
}

function matchesBridgePathGlob(path: string, glob: string): boolean {
	if (glob.length === 0) {
		return false;
	}
	const pathSegments = path.split('/').filter((segment: string): boolean => segment.length > 0);
	const globSegments = glob.split('/').filter((segment: string): boolean => segment.length > 0);
	return matchesGlobSegments(pathSegments, globSegments);
}

function matchesGlobSegments(
	pathSegments: readonly string[],
	globSegments: readonly string[],
): boolean {
	if (globSegments.length === 0) {
		return pathSegments.length === 0;
	}
	const [globHead, ...globTail] = globSegments;
	if (globHead === '**') {
		return (
			matchesGlobSegments(pathSegments, globTail) ||
			(pathSegments.length > 0 && matchesGlobSegments(pathSegments.slice(1), globSegments))
		);
	}
	if (pathSegments.length === 0 || !matchesGlobSegment(pathSegments[0] ?? '', globHead ?? '')) {
		return false;
	}
	return matchesGlobSegments(pathSegments.slice(1), globTail);
}

function matchesGlobSegment(pathSegment: string, globSegment: string): boolean {
	if (globSegment === '*') {
		return true;
	}
	if (!globSegment.includes('*')) {
		return pathSegment === globSegment;
	}
	const escaped = globSegment
		.split('*')
		.map((part: string): string => escapeRegExp(part))
		.join('.*');
	return new RegExp(`^${escaped}$`).test(pathSegment);
}

function escapeRegExp(value: string): string {
	return value.replaceAll(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

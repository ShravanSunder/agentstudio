import {
	contentHandlesForItem,
	orderedReviewItems,
} from '../../foundation/review-package/bridge-review-package-adapter.js';
import type {
	BridgeContentRole,
	BridgeFileChangeKind,
	BridgeFileReviewState,
	BridgeReviewItemDescriptor,
	BridgeReviewPackage,
	BridgeReviewPriority,
} from '../../foundation/review-package/bridge-review-package.js';
import type {
	BridgeCurrentChangeSetScope,
	BridgeReviewFacetCounts,
	BridgeReviewProjection,
	BridgeReviewProjectionInput,
	BridgeReviewProjectionInputItem,
	BridgeReviewProjectionMode,
	BridgeReviewProjectionFacet,
	BridgeReviewProjectionRequest,
} from '../models/review-projection-models.js';
import {
	bridgeReviewProjectionInputSchema,
	bridgeReviewProjectionSchema,
} from '../models/review-projection-models.js';

export interface BuildBridgeReviewProjectionProps {
	readonly reviewPackage: BridgeReviewPackage;
	readonly request: BridgeReviewProjectionRequest;
}

export interface BuildBridgeReviewProjectionFromInputProps {
	readonly projectionInput: BridgeReviewProjectionInput;
	readonly request: BridgeReviewProjectionRequest;
}

interface ProjectionVisibility {
	readonly includeHidden: boolean;
	readonly includeBinary: boolean;
	readonly includeLarge: boolean;
}

interface ProjectionMaps {
	readonly orderedPaths: readonly string[];
	readonly primaryDisplayPathByItemId: Record<string, string>;
	readonly primaryItemIdByTreePath: Record<string, string>;
	readonly secondaryItemIdsByTreePath: Record<string, readonly string[]>;
	readonly candidatePathsByItemId: Record<string, readonly string[]>;
	readonly itemIdsByDisplayPath: Record<string, readonly string[]>;
	readonly availableContentRolesByItemId: Record<string, readonly BridgeContentRole[]>;
}

const changedKinds = new Set<BridgeFileChangeKind>([
	'added',
	'modified',
	'deleted',
	'renamed',
	'copied',
]);
const priorityRank: Record<BridgeReviewPriority, number> = {
	high: 0,
	normal: 1,
	low: 2,
};
const reviewStateRank: Record<BridgeFileReviewState, number> = {
	unreviewed: 0,
	viewed: 1,
	annotated: 2,
	resolved: 3,
};

export function makeBridgeReviewProjectionInput(
	reviewPackage: BridgeReviewPackage,
): BridgeReviewProjectionInput {
	const projectionInput = {
		packageId: reviewPackage.packageId,
		reviewGeneration: reviewPackage.reviewGeneration,
		revision: reviewPackage.revision,
		orderedItems: orderedReviewItems(reviewPackage).map(
			(item: BridgeReviewItemDescriptor): BridgeReviewProjectionInputItem => {
				const contentHandles = contentHandlesForItem(item);
				return {
					itemId: item.itemId,
					basePath: item.basePath ?? null,
					headPath: item.headPath ?? null,
					changeKind: item.changeKind,
					fileClass: item.fileClass,
					language: item.language ?? null,
					extension: item.extension ?? null,
					isHiddenByDefault: item.isHiddenByDefault,
					reviewPriority: item.reviewPriority,
					reviewState: item.reviewState,
					contentRoles: contentHandles.map((handle): BridgeContentRole => handle.role),
					mimeTypes: uniqueStrings(contentHandles.map((handle): string => handle.mimeType)),
					provenance: {
						promptIds: item.provenance.promptIds,
						agentSessionIds: item.provenance.agentSessionIds,
						operationIds: item.provenance.operationIds,
					},
				};
			},
		),
	};

	return bridgeReviewProjectionInputSchema.parse(projectionInput);
}

export function buildBridgeReviewProjection(
	props: BuildBridgeReviewProjectionProps,
): BridgeReviewProjection {
	return buildBridgeReviewProjectionFromInput({
		projectionInput: makeBridgeReviewProjectionInput(props.reviewPackage),
		request: props.request,
	});
}

export function buildBridgeReviewProjectionFromInput(
	props: BuildBridgeReviewProjectionFromInputProps,
): BridgeReviewProjection {
	const visibility = visibilityForRequest(props.request.facets);
	const baseItems = props.projectionInput.orderedItems.filter(
		(item: BridgeReviewProjectionInputItem): boolean => isVisibleByDefault(item, visibility),
	);
	const projectedItems = [
		...applyProjectionFacets(itemsForMode(baseItems, props.request.mode), props.request.facets),
	];
	// oxlint-disable-next-line unicorn/no-array-sort -- WebKit engines older than Safari 16.4 do not support Array#toSorted.
	projectedItems.sort(
		(left: BridgeReviewProjectionInputItem, right: BridgeReviewProjectionInputItem): number =>
			compareForMode(props.request.mode, left, right),
	);
	const orderedItemIds = projectedItems.map(
		(item: BridgeReviewProjectionInputItem): string => item.itemId,
	);
	const maps = buildProjectionMaps(projectedItems);
	const projection = {
		...props.request,
		projectionId: projectionIdForRequest(props.projectionInput, props.request),
		label: labelForMode(props.request.mode),
		orderedItemIds,
		...maps,
		facetCounts: facetCountsForItems(projectedItems),
	};

	return bridgeReviewProjectionSchema.parse(projection);
}

function itemsForMode(
	items: readonly BridgeReviewProjectionInputItem[],
	mode: BridgeReviewProjectionMode,
): readonly BridgeReviewProjectionInputItem[] {
	switch (mode.kind) {
		case 'normalReview':
			return items.filter((item: BridgeReviewProjectionInputItem): boolean =>
				changedKinds.has(item.changeKind),
			);
		case 'guidedReview':
			return items.filter((item: BridgeReviewProjectionInputItem): boolean =>
				changedKinds.has(item.changeKind),
			);
		case 'plansAndSpecs':
			return items.filter(isDocsOrPlanItem);
	}

	return assertNever(mode);
}

function itemMatchesCurrentChangeSet(
	item: BridgeReviewProjectionInputItem,
	scope: BridgeCurrentChangeSetScope,
): boolean {
	if (scope.kind === 'activePackage') {
		return changedKinds.has(item.changeKind);
	}

	switch (scope.provenanceKind) {
		case 'prompt':
			return item.provenance.promptIds.includes(scope.provenanceId);
		case 'session':
			return item.provenance.agentSessionIds.includes(scope.provenanceId);
		case 'operation':
			return item.provenance.operationIds.includes(scope.provenanceId);
	}

	return assertNever(scope.provenanceKind);
}

function applyProjectionFacets(
	items: readonly BridgeReviewProjectionInputItem[],
	facets: readonly BridgeReviewProjectionFacet[],
): readonly BridgeReviewProjectionInputItem[] {
	return facets.reduce(
		(
			currentItems: readonly BridgeReviewProjectionInputItem[],
			refinement: BridgeReviewProjectionFacet,
		): readonly BridgeReviewProjectionInputItem[] => {
			if (refinement.kind === 'visibility') {
				return currentItems;
			}

			return currentItems.filter((item: BridgeReviewProjectionInputItem): boolean =>
				itemMatchesFacet(item, refinement),
			);
		},
		items,
	);
}

function itemMatchesFacet(
	item: BridgeReviewProjectionInputItem,
	refinement: Exclude<BridgeReviewProjectionFacet, { readonly kind: 'visibility' }>,
): boolean {
	switch (refinement.kind) {
		case 'folder':
			return candidatePathsForItem(item).some((path: string): boolean =>
				isPathInsideFolder(path, refinement.folderPath),
			);
		case 'extension':
			return item.extension !== null && refinement.extensions.includes(item.extension);
		case 'language':
			return item.language !== null && refinement.languages.includes(item.language);
		case 'mime':
			return item.mimeTypes.some((mimeType: string): boolean =>
				refinement.mimeTypes.includes(mimeType),
			);
		case 'fileClass':
			return refinement.fileClasses.includes(item.fileClass);
		case 'gitStatus':
			return refinement.statuses.includes(item.changeKind);
		case 'changeScope':
			return itemMatchesCurrentChangeSet(item, refinement.scope);
	}

	return assertNever(refinement);
}

function visibilityForRequest(
	facets: readonly BridgeReviewProjectionFacet[],
): ProjectionVisibility {
	const visibility = facets.find(
		(
			refinement: BridgeReviewProjectionFacet,
		): refinement is Extract<BridgeReviewProjectionFacet, { readonly kind: 'visibility' }> =>
			refinement.kind === 'visibility',
	);

	return {
		includeHidden: visibility?.includeHidden ?? false,
		includeBinary: visibility?.includeBinary ?? false,
		includeLarge: visibility?.includeLarge ?? false,
	};
}

function isVisibleByDefault(
	item: BridgeReviewProjectionInputItem,
	visibility: ProjectionVisibility,
): boolean {
	if (item.isHiddenByDefault && !visibility.includeHidden) {
		return false;
	}
	if (item.fileClass === 'binary' && !visibility.includeBinary) {
		return false;
	}
	if (item.fileClass === 'large' && !visibility.includeLarge) {
		return false;
	}
	return true;
}

function buildProjectionMaps(items: readonly BridgeReviewProjectionInputItem[]): ProjectionMaps {
	const primaryDisplayPathByItemId: Record<string, string> = {};
	const primaryItemIdByTreePath: Record<string, string> = {};
	const mutableSecondaryItemIdsByTreePath: Record<string, string[]> = {};
	const candidatePathsByItemId: Record<string, readonly string[]> = {};
	const mutableItemIdsByDisplayPath: Record<string, string[]> = {};
	const availableContentRolesByItemId: Record<string, readonly BridgeContentRole[]> = {};
	const orderedPaths: string[] = [];

	for (const item of items) {
		const displayPath = displayPathForItem(item);
		primaryDisplayPathByItemId[item.itemId] = displayPath;
		candidatePathsByItemId[item.itemId] = candidatePathsForItem(item);
		availableContentRolesByItemId[item.itemId] = item.contentRoles;
		mutableItemIdsByDisplayPath[displayPath] = [
			...(mutableItemIdsByDisplayPath[displayPath] ?? []),
			item.itemId,
		];

		if (primaryItemIdByTreePath[displayPath] === undefined) {
			primaryItemIdByTreePath[displayPath] = item.itemId;
			orderedPaths.push(displayPath);
		} else {
			mutableSecondaryItemIdsByTreePath[displayPath] = [
				...(mutableSecondaryItemIdsByTreePath[displayPath] ?? []),
				item.itemId,
			];
		}
	}

	return {
		orderedPaths,
		primaryDisplayPathByItemId,
		primaryItemIdByTreePath,
		secondaryItemIdsByTreePath: mutableSecondaryItemIdsByTreePath,
		candidatePathsByItemId,
		itemIdsByDisplayPath: mutableItemIdsByDisplayPath,
		availableContentRolesByItemId,
	};
}

function facetCountsForItems(
	items: readonly BridgeReviewProjectionInputItem[],
): BridgeReviewFacetCounts {
	const facetCounts: BridgeReviewFacetCounts = {
		fileClasses: {},
		extensions: {},
		changeKinds: {},
		reviewStates: {},
		hidden: 0,
		binary: 0,
		large: 0,
	};

	for (const item of items) {
		incrementFacet(facetCounts.fileClasses, item.fileClass);
		incrementFacet(facetCounts.changeKinds, item.changeKind);
		incrementFacet(facetCounts.reviewStates, item.reviewState);
		if (item.extension !== null) {
			incrementFacet(facetCounts.extensions, item.extension);
		}
		if (item.isHiddenByDefault) {
			facetCounts.hidden += 1;
		}
		if (item.fileClass === 'binary') {
			facetCounts.binary += 1;
		}
		if (item.fileClass === 'large') {
			facetCounts.large += 1;
		}
	}

	return facetCounts;
}

function compareForMode(
	mode: BridgeReviewProjectionMode,
	left: BridgeReviewProjectionInputItem,
	right: BridgeReviewProjectionInputItem,
): number {
	if (mode.kind !== 'guidedReview') {
		return 0;
	}

	return (
		guidedRank(left) - guidedRank(right) ||
		reviewStateRank[left.reviewState] - reviewStateRank[right.reviewState] ||
		priorityRank[left.reviewPriority] - priorityRank[right.reviewPriority] ||
		displayPathForItem(left).localeCompare(displayPathForItem(right)) ||
		left.itemId.localeCompare(right.itemId)
	);
}

function guidedRank(item: BridgeReviewProjectionInputItem): number {
	if (
		item.reviewState === 'unreviewed' &&
		item.reviewPriority === 'high' &&
		(item.fileClass === 'source' || item.fileClass === 'config')
	) {
		return 0;
	}
	if (
		item.reviewState === 'unreviewed' &&
		item.reviewPriority === 'normal' &&
		item.fileClass === 'source'
	) {
		return 1;
	}
	if (item.fileClass === 'test') {
		return 2;
	}
	if (item.fileClass === 'docs' || item.fileClass === 'config' || isDocsOrPlanItem(item)) {
		return 3;
	}
	if (
		item.fileClass === 'generated' ||
		item.fileClass === 'vendor' ||
		item.fileClass === 'large' ||
		item.fileClass === 'binary' ||
		item.isHiddenByDefault
	) {
		return 5;
	}
	return 4;
}

function isDocsOrPlanItem(item: BridgeReviewProjectionInputItem): boolean {
	return (
		item.fileClass === 'docs' ||
		candidatePathsForItem(item).some((path: string): boolean => {
			const lowerPath = path.toLowerCase();
			const basename = lowerPath.split('/').at(-1) ?? lowerPath;
			return (
				lowerPath.startsWith('docs/') ||
				lowerPath.endsWith('.md') ||
				lowerPath.endsWith('.mdx') ||
				basename.includes('plan') ||
				basename.includes('spec') ||
				basename.includes('design') ||
				basename.includes('handoff')
			);
		})
	);
}

function projectionIdForRequest(
	projectionInput: BridgeReviewProjectionInput,
	request: BridgeReviewProjectionRequest,
): string {
	return `${projectionInput.packageId}:${projectionInput.reviewGeneration}:${JSON.stringify(request)}`;
}

function labelForMode(mode: BridgeReviewProjectionMode): string {
	switch (mode.kind) {
		case 'normalReview':
			return 'Normal review';
		case 'guidedReview':
			return 'Guided review';
		case 'plansAndSpecs':
			return 'Plans and specs';
	}

	return assertNever(mode);
}

function displayPathForItem(item: BridgeReviewProjectionInputItem): string {
	return item.headPath ?? item.basePath ?? item.itemId;
}

function candidatePathsForItem(item: BridgeReviewProjectionInputItem): readonly string[] {
	return uniqueStrings(
		[item.headPath, item.basePath].filter(
			(path: string | null | undefined): path is string => path !== null && path !== undefined,
		),
	);
}

function isPathInsideFolder(path: string, folderPath: string): boolean {
	const normalizedFolder = folderPath.endsWith('/') ? folderPath.slice(0, -1) : folderPath;
	return path === normalizedFolder || path.startsWith(`${normalizedFolder}/`);
}

function incrementFacet(record: Record<string, number>, key: string): void {
	record[key] = (record[key] ?? 0) + 1;
}

function uniqueStrings(values: readonly string[]): readonly string[] {
	return Array.from(new Set(values));
}

function assertNever(value: never): never {
	throw new Error(`Unexpected review projection variant: ${String(value)}`);
}

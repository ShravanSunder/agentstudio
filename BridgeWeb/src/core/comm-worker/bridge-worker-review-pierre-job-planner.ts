import type { BridgeWorkerReviewRenderSemantics } from './bridge-worker-contracts.js';
import {
	buildBridgeWorkerPierreRenderJob,
	type BridgeWorkerDemandRank,
	type BridgeWorkerPierreRenderBudget,
	type BridgeWorkerPierreRenderJob,
	type BridgeWorkerPierreRenderWindow,
} from './bridge-worker-pierre-render-job.js';
import type { BridgeWorkerFetchedReviewContentResource } from './bridge-worker-review-content-fetch.js';

export interface PlanBridgeWorkerReviewPierreRenderJobProps {
	readonly bridgeDemandRank: BridgeWorkerDemandRank;
	readonly budget: BridgeWorkerPierreRenderBudget;
	readonly resources: readonly BridgeWorkerFetchedReviewContentResource[];
	readonly semantics: BridgeWorkerReviewRenderSemantics;
}

type BridgeWorkerReviewContentRole = BridgeWorkerFetchedReviewContentResource['role'];
type BridgeWorkerFetchedResourceByRole = ReadonlyMap<
	BridgeWorkerReviewContentRole,
	BridgeWorkerFetchedReviewContentResource
>;

const bridgeWorkerEmptyContentIdentity = 'empty';
const bridgeWorkerPlainTextLanguage = 'text';

export function planBridgeWorkerReviewPierreRenderJob(
	props: PlanBridgeWorkerReviewPierreRenderJobProps,
): BridgeWorkerPierreRenderJob | null {
	const resourcesByRole = new Map(
		props.resources.map((resource) => [resource.role, resource] as const),
	);
	if (shouldRenderReviewItemAsDiff(props.semantics)) {
		return planReviewDiffRenderJob({ ...props, resourcesByRole });
	}
	return planReviewFileRenderJob({ ...props, resourcesByRole });
}

interface PlanBridgeWorkerReviewRenderJobWithResourcesProps extends PlanBridgeWorkerReviewPierreRenderJobProps {
	readonly resourcesByRole: BridgeWorkerFetchedResourceByRole;
}

function planReviewDiffRenderJob(
	props: PlanBridgeWorkerReviewRenderJobWithResourcesProps,
): BridgeWorkerPierreRenderJob | null {
	const diffSides = diffResourcesForReviewSemantics(props);
	if (diffSides === null) {
		return null;
	}
	const presentResources = [diffSides.base, diffSides.head].filter(
		(resource): resource is BridgeWorkerFetchedReviewContentResource => resource !== null,
	);
	if (presentResources.length === 0) {
		return null;
	}
	return buildBridgeWorkerPierreRenderJob({
		itemId: props.semantics.itemId,
		renderKind: 'reviewDiff',
		contentCacheKey: `${contentCacheKeyForNullableResource(diffSides.base)}|${contentCacheKeyForNullableResource(diffSides.head)}`,
		contentHash: `${contentHashForNullableResource(diffSides.base)}|${contentHashForNullableResource(diffSides.head)}`,
		language: languageForReviewRenderJob({
			resources: [diffSides.head, diffSides.base],
			semantics: props.semantics,
		}),
		bridgeDemandRank: props.bridgeDemandRank,
		window: renderWindowForRoles({
			budget: props.budget,
			roles: presentResources.map((resource) => resource.role),
			semantics: props.semantics,
		}),
		payload: {
			kind: 'diffTextWindow',
			baseTextBytes: diffSides.base?.textBytes ?? null,
			headTextBytes: diffSides.head?.textBytes ?? null,
		},
		budget: props.budget,
	});
}

function planReviewFileRenderJob(
	props: PlanBridgeWorkerReviewRenderJobWithResourcesProps,
): BridgeWorkerPierreRenderJob | null {
	const resource = firstReviewResourceForRoles(props.resourcesByRole, [
		'head',
		'file',
		'diff',
		'base',
	]);
	if (resource === null) {
		return null;
	}
	return buildBridgeWorkerPierreRenderJob({
		itemId: props.semantics.itemId,
		renderKind: 'fileText',
		contentCacheKey: contentCacheKeyForResource(resource),
		contentHash: resource.contentHash,
		language: languageForReviewRenderJob({
			resources: [resource],
			semantics: props.semantics,
		}),
		bridgeDemandRank: props.bridgeDemandRank,
		window: renderWindowForRoles({
			budget: props.budget,
			roles: [resource.role],
			semantics: props.semantics,
		}),
		payload: {
			kind: 'textWindow',
			textBytes: resource.textBytes,
		},
		budget: props.budget,
	});
}

function diffResourcesForReviewSemantics(
	props: PlanBridgeWorkerReviewRenderJobWithResourcesProps,
): {
	readonly base: BridgeWorkerFetchedReviewContentResource | null;
	readonly head: BridgeWorkerFetchedReviewContentResource | null;
} | null {
	switch (props.semantics.changeKind) {
		case 'added': {
			const head = firstReviewResourceForRoles(props.resourcesByRole, ['head', 'file']);
			return head === null ? null : { base: null, head };
		}
		case 'deleted': {
			const base = firstReviewResourceForRoles(props.resourcesByRole, ['base', 'diff']);
			return base === null ? null : { base, head: null };
		}
		case 'modified':
		case 'renamed':
		case 'copied':
			if (props.semantics.itemKind !== 'diff') {
				return null;
			}
			return diffResourcesForTwoSidedReviewItem(props.resourcesByRole);
	}
	const exhaustiveChangeKind: never = props.semantics.changeKind;
	void exhaustiveChangeKind;
	throw new Error('Unhandled Bridge worker review change kind.');
}

function shouldRenderReviewItemAsDiff(semantics: BridgeWorkerReviewRenderSemantics): boolean {
	if (semantics.changeKind === 'added' || semantics.changeKind === 'deleted') {
		return true;
	}
	return semantics.itemKind === 'diff';
}

function diffResourcesForTwoSidedReviewItem(resourcesByRole: BridgeWorkerFetchedResourceByRole): {
	readonly base: BridgeWorkerFetchedReviewContentResource;
	readonly head: BridgeWorkerFetchedReviewContentResource;
} | null {
	const base = resourcesByRole.get('base') ?? null;
	const head = resourcesByRole.get('head') ?? null;
	return base === null || head === null ? null : { base, head };
}

function firstReviewResourceForRoles(
	resourcesByRole: BridgeWorkerFetchedResourceByRole,
	roles: readonly BridgeWorkerReviewContentRole[],
): BridgeWorkerFetchedReviewContentResource | null {
	for (const role of roles) {
		const resource = resourcesByRole.get(role);
		if (resource !== undefined) {
			return resource;
		}
	}
	return null;
}

function renderWindowForRoles(props: {
	readonly budget: BridgeWorkerPierreRenderBudget;
	readonly roles: readonly BridgeWorkerReviewContentRole[];
	readonly semantics: BridgeWorkerReviewRenderSemantics;
}): BridgeWorkerPierreRenderWindow {
	const totalLineCount = Math.max(
		0,
		...props.roles.map((role) => props.semantics.contentLineCountsByRole[role] ?? 0),
	);
	return {
		startLine: 1,
		endLine: Math.min(totalLineCount, props.budget.maxWindowLines),
		totalLineCount,
	};
}

function languageForReviewRenderJob(props: {
	readonly resources: readonly (BridgeWorkerFetchedReviewContentResource | null)[];
	readonly semantics: BridgeWorkerReviewRenderSemantics;
}): string {
	for (const resource of props.resources) {
		const language = normalizedLanguageOrNull(resource?.language ?? null);
		if (language !== null) {
			return language;
		}
	}
	return normalizedLanguageOrNull(props.semantics.language) ?? bridgeWorkerPlainTextLanguage;
}

function normalizedLanguageOrNull(language: string | null): string | null {
	const normalizedLanguage = language?.trim() ?? '';
	return normalizedLanguage.length === 0 ? null : normalizedLanguage;
}

function contentCacheKeyForNullableResource(
	resource: BridgeWorkerFetchedReviewContentResource | null,
): string {
	return resource === null ? 'pierre-content:empty' : contentCacheKeyForResource(resource);
}

function contentCacheKeyForResource(resource: BridgeWorkerFetchedReviewContentResource): string {
	return `pierre-content:${resource.contentHashAlgorithm}:${resource.contentHash}`;
}

function contentHashForNullableResource(
	resource: BridgeWorkerFetchedReviewContentResource | null,
): string {
	return resource?.contentHash ?? bridgeWorkerEmptyContentIdentity;
}

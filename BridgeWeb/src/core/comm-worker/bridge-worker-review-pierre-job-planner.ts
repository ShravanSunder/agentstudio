import { parseDiffFromFile, type FileContents } from '@pierre/diffs';

import {
	BRIDGE_WORKER_WIRE_VERSION,
	type BridgeWorkerPierreRenderJobEvent,
	type BridgeWorkerReviewRenderSemantics,
} from './bridge-worker-contracts.js';
import {
	buildBridgeWorkerPierreRenderJob,
	bridgeWorkerPierreRenderPayloadByteLength,
	type BridgeWorkerCodeViewDiffItem,
	type BridgeWorkerCodeViewFileItem,
	type BridgeWorkerDemandRank,
	type BridgeWorkerPierreRenderBudget,
	type BridgeWorkerPierreRenderJob,
	type BridgeWorkerPierreRenderPayload,
	type BridgeWorkerPierreRenderWindow,
} from './bridge-worker-pierre-render-job.js';
import type { BridgeWorkerFetchedReviewContentResource } from './bridge-worker-review-content-fetch.js';
import {
	prepareBridgeWorkerStructuredMessage,
	type BridgeWorkerTransferFieldDeclaration,
	type PreparedBridgeWorkerStructuredMessage,
} from './bridge-worker-transfer-list.js';

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
const bridgeWorkerHydratedRenderVersion = 2;

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

export function prepareBridgeWorkerReviewPierreRenderJobEvent(
	props: PlanBridgeWorkerReviewPierreRenderJobProps,
): PreparedBridgeWorkerStructuredMessage<BridgeWorkerPierreRenderJobEvent> | null {
	const job = planBridgeWorkerReviewPierreRenderJob(props);
	if (job === null) {
		return null;
	}
	return prepareBridgeWorkerStructuredMessage({
		message: {
			wireVersion: BRIDGE_WORKER_WIRE_VERSION,
			direction: 'serverWorkerToMain',
			transferDescriptors: [],
			kind: 'pierreRenderJob',
			job,
		},
		declaredFields: transferFieldsForBridgeWorkerPierreRenderPayload(job.payload),
	});
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
	const window = renderWindowForRoles({
		budget: props.budget,
		roles: presentResources.map((resource) => resource.role),
		semantics: props.semantics,
	});
	if (
		windowedResourcesExceedByteBudget({
			budget: props.budget,
			resources: presentResources,
			window,
		})
	) {
		return null;
	}
	const contentCacheKey = `${contentCacheKeyForNullableResource(diffSides.base)}|${contentCacheKeyForNullableResource(diffSides.head)}`;
	const contentHash = `${contentHashForNullableResource(diffSides.base)}|${contentHashForNullableResource(diffSides.head)}`;
	const language = languageForReviewRenderJob({
		resources: [diffSides.head, diffSides.base],
		semantics: props.semantics,
	});
	return buildBridgeWorkerPierreRenderJob({
		itemId: props.semantics.itemId,
		renderKind: 'reviewDiff',
		contentCacheKey,
		contentHash,
		language,
		bridgeDemandRank: props.bridgeDemandRank,
		window,
		payload: {
			kind: 'codeViewDiffItem',
			item: createBridgeWorkerCodeViewDiffItem({
				base: diffSides.base,
				contentCacheKey,
				head: diffSides.head,
				language,
				semantics: props.semantics,
				window,
			}),
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
	const window = renderWindowForRoles({
		budget: props.budget,
		roles: [resource.role],
		semantics: props.semantics,
	});
	if (
		windowedResourcesExceedByteBudget({
			budget: props.budget,
			resources: [resource],
			window,
		})
	) {
		return null;
	}
	const contentCacheKey = contentCacheKeyForResource(resource);
	const language = languageForReviewRenderJob({
		resources: [resource],
		semantics: props.semantics,
	});
	return buildBridgeWorkerPierreRenderJob({
		itemId: props.semantics.itemId,
		renderKind: 'fileText',
		contentCacheKey,
		contentHash: resource.contentHash,
		language,
		bridgeDemandRank: props.bridgeDemandRank,
		window,
		payload: {
			kind: 'codeViewFileItem',
			item: createBridgeWorkerCodeViewFileItem({
				contentCacheKey,
				language,
				resource,
				semantics: props.semantics,
				window,
			}),
		},
		budget: props.budget,
	});
}

function createBridgeWorkerCodeViewDiffItem(props: {
	readonly base: BridgeWorkerFetchedReviewContentResource | null;
	readonly contentCacheKey: string;
	readonly head: BridgeWorkerFetchedReviewContentResource | null;
	readonly language: string;
	readonly semantics: BridgeWorkerReviewRenderSemantics;
	readonly window: BridgeWorkerPierreRenderWindow;
}): BridgeWorkerCodeViewDiffItem {
	const oldFile = createPierreFileContentsForReviewResource({
		cacheKey: contentCacheKeyForNullableResource(props.base),
		language: props.language,
		path: props.semantics.basePath ?? props.semantics.displayPath,
		resource: props.base,
		window: props.window,
	});
	const newFile = createPierreFileContentsForReviewResource({
		cacheKey: contentCacheKeyForNullableResource(props.head),
		language: props.language,
		path: props.semantics.headPath ?? props.semantics.displayPath,
		resource: props.head,
		window: props.window,
	});
	const fileDiff = parseDiffFromFile(oldFile, newFile);
	if (fileDiff.lang === undefined) {
		fileDiff.lang = props.language;
	}
	fileDiff.cacheKey = props.contentCacheKey;
	return {
		id: props.semantics.itemId,
		type: 'diff',
		fileDiff,
		version: codeViewRenderVersionForWindow(props.window),
		bridgeMetadata: bridgeWorkerCodeViewItemMetadata({
			cacheKey: props.contentCacheKey,
			contentRoles: loadedDiffContentRoles({ base: props.base, head: props.head }),
			semantics: props.semantics,
			window: props.window,
		}),
	};
}

function createBridgeWorkerCodeViewFileItem(props: {
	readonly contentCacheKey: string;
	readonly language: string;
	readonly resource: BridgeWorkerFetchedReviewContentResource;
	readonly semantics: BridgeWorkerReviewRenderSemantics;
	readonly window: BridgeWorkerPierreRenderWindow;
}): BridgeWorkerCodeViewFileItem {
	return {
		id: props.semantics.itemId,
		type: 'file',
		file: createPierreFileContentsForReviewResource({
			cacheKey: props.contentCacheKey,
			language: props.language,
			path: props.semantics.headPath ?? props.semantics.basePath ?? props.semantics.displayPath,
			resource: props.resource,
			window: props.window,
		}),
		version: codeViewRenderVersionForWindow(props.window),
		bridgeMetadata: bridgeWorkerCodeViewItemMetadata({
			cacheKey: props.contentCacheKey,
			contentRoles: [props.resource.role],
			semantics: props.semantics,
			window: props.window,
		}),
	};
}

function createPierreFileContentsForReviewResource(props: {
	readonly cacheKey: string;
	readonly language: string;
	readonly path: string;
	readonly resource: BridgeWorkerFetchedReviewContentResource | null;
	readonly window: BridgeWorkerPierreRenderWindow;
}): FileContents {
	const contents =
		props.resource === null
			? ''
			: windowTextForBridgeWorkerCodeView({
					maxLines: props.window.endLine,
					text: props.resource.text,
				});
	const lang = optionalPierreHighlightLanguage(props.resource?.language ?? props.language);
	return {
		name: props.path,
		contents,
		cacheKey: props.cacheKey,
		...(lang === undefined ? {} : { lang }),
	};
}

function bridgeWorkerCodeViewItemMetadata(props: {
	readonly cacheKey: string;
	readonly contentRoles: readonly BridgeWorkerReviewContentRole[];
	readonly semantics: BridgeWorkerReviewRenderSemantics;
	readonly window: BridgeWorkerPierreRenderWindow;
}): BridgeWorkerCodeViewFileItem['bridgeMetadata'] {
	return {
		itemId: props.semantics.itemId,
		displayPath: props.semantics.displayPath,
		contentState: props.window.endLine < props.window.totalLineCount ? 'windowed' : 'hydrated',
		contentRoles: props.contentRoles,
		cacheKey: props.cacheKey,
		lineCount: lineCountForContentRoles({
			contentRoles: props.contentRoles,
			semantics: props.semantics,
		}),
	};
}

function codeViewRenderVersionForWindow(window: BridgeWorkerPierreRenderWindow): number {
	void window;
	return bridgeWorkerHydratedRenderVersion;
}

function loadedDiffContentRoles(props: {
	readonly base: BridgeWorkerFetchedReviewContentResource | null;
	readonly head: BridgeWorkerFetchedReviewContentResource | null;
}): readonly BridgeWorkerReviewContentRole[] {
	const roles: BridgeWorkerReviewContentRole[] = [];
	if (props.base !== null) {
		roles.push('base');
	}
	if (props.head !== null) {
		roles.push('head');
	}
	return roles;
}

function lineCountForContentRoles(props: {
	readonly contentRoles: readonly BridgeWorkerReviewContentRole[];
	readonly semantics: BridgeWorkerReviewRenderSemantics;
}): number | null {
	let totalLineCount = 0;
	let matchedRoleCount = 0;
	for (const role of props.contentRoles) {
		const lineCount = props.semantics.contentLineCountsByRole[role];
		if (lineCount === null || lineCount === undefined) {
			continue;
		}
		totalLineCount += lineCount;
		matchedRoleCount += 1;
	}
	return matchedRoleCount === 0 ? null : totalLineCount;
}

function windowTextForBridgeWorkerCodeView(props: {
	readonly maxLines: number;
	readonly text: string;
}): string {
	const maxLines = Math.max(1, Math.floor(props.maxLines));
	let currentIndex = 0;
	for (let lineIndex = 0; lineIndex < maxLines; lineIndex += 1) {
		const newlineIndex = props.text.indexOf('\n', currentIndex);
		if (newlineIndex === -1) {
			return props.text;
		}
		currentIndex = newlineIndex + 1;
	}
	return props.text.slice(0, currentIndex);
}

function windowedResourcesExceedByteBudget(props: {
	readonly budget: BridgeWorkerPierreRenderBudget;
	readonly resources: readonly BridgeWorkerFetchedReviewContentResource[];
	readonly window: BridgeWorkerPierreRenderWindow;
}): boolean {
	return (
		props.resources.reduce(
			(totalByteLength, resource): number =>
				totalByteLength +
				bridgeWorkerStringByteLength(
					windowTextForBridgeWorkerCodeView({
						maxLines: props.window.endLine,
						text: resource.text,
					}),
				),
			0,
		) > props.budget.maxBytes
	);
}

function bridgeWorkerStringByteLength(value: string): number {
	return new TextEncoder().encode(value).byteLength;
}

function optionalPierreHighlightLanguage(language: string | null | undefined): string | undefined {
	const normalizedLanguage = language?.trim() ?? '';
	return normalizedLanguage.length === 0 ? undefined : normalizedLanguage;
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

function transferFieldsForBridgeWorkerPierreRenderPayload(
	payload: BridgeWorkerPierreRenderPayload,
): readonly BridgeWorkerTransferFieldDeclaration[] {
	switch (payload.kind) {
		case 'codeViewFileItem':
		case 'codeViewDiffItem':
			return [
				{
					fieldPath: ['job', 'payload'],
					mode: 'clone',
					byteLength: bridgeWorkerPierreRenderPayloadByteLength(payload),
				},
			];
	}
	const exhaustivePayload: never = payload;
	void exhaustivePayload;
	throw new Error('Unhandled Bridge worker Pierre render payload kind.');
}

import { parseDiffFromFile, type FileContents } from '@pierre/diffs';

import { demandRankForContentRole } from '../demand/bridge-content-demand-policy.js';
import {
	BRIDGE_WORKER_WIRE_VERSION,
	type BridgeWorkerReviewPierreRenderJobEvent,
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
	type BridgeWorkerRenderSourceCorrelation,
} from './bridge-worker-pierre-render-job.js';
import type { BridgeWorkerRenderReceiptIdentity } from './bridge-worker-render-fulfillment.js';
import type { BridgeWorkerFetchedReviewContentResource } from './bridge-worker-review-content-fetch.js';
import {
	prepareBridgeWorkerStructuredMessage,
	type BridgeWorkerTransferFieldDeclaration,
	type PreparedBridgeWorkerStructuredMessage,
} from './bridge-worker-transfer-list.js';

export interface PlanBridgeWorkerReviewPierreRenderJobProps {
	readonly bridgeDemandRank: BridgeWorkerDemandRank;
	readonly currentBridgeDemandRank?: () => BridgeWorkerDemandRank;
	readonly budget: BridgeWorkerPierreRenderBudget;
	readonly resources: readonly BridgeWorkerFetchedReviewContentResource[];
	readonly semantics: BridgeWorkerReviewRenderSemantics;
}

export interface PrepareBridgeWorkerReviewPierreRenderJobEventProps extends PlanBridgeWorkerReviewPierreRenderJobProps {
	readonly publicationSequence: number;
	readonly renderReceiptIdentity: BridgeWorkerRenderReceiptIdentity;
	readonly workerDerivationEpoch: number;
}

export type BridgeWorkerReviewPierreRenderJobPlanningStepResult =
	| { readonly status: 'pending' }
	| { readonly job: BridgeWorkerPierreRenderJob | null; readonly status: 'complete' };

export interface BridgeWorkerReviewPierreRenderJobPlanningSession {
	readonly runNextStage: () => BridgeWorkerReviewPierreRenderJobPlanningStepResult;
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
	const planningSession = createBridgeWorkerReviewPierreRenderJobPlanningSession(props);
	while (true) {
		const result = planningSession.runNextStage();
		if (result.status === 'complete') return result.job;
	}
}

export function createBridgeWorkerReviewPierreRenderJobPlanningSession(
	props: PlanBridgeWorkerReviewPierreRenderJobProps,
): BridgeWorkerReviewPierreRenderJobPlanningSession {
	let planningStage: BridgeWorkerReviewPierreRenderJobPlanningStage = 'select';
	let selectedPlan: BridgeWorkerReviewSelectedPlan | null = null;
	let baseFile: FileContents | null = null;
	let headFile: FileContents | null = null;
	let file: FileContents | null = null;
	let payload: BridgeWorkerPierreRenderPayload | null = null;

	return {
		runNextStage: (): BridgeWorkerReviewPierreRenderJobPlanningStepResult => {
			switch (planningStage) {
				case 'select': {
					selectedPlan = selectBridgeWorkerReviewPlan(props);
					if (selectedPlan === null) return { job: null, status: 'complete' };
					planningStage = selectedPlan.kind === 'diff' ? 'prepareDiffBase' : 'prepareFile';
					return { status: 'pending' };
				}
				case 'prepareDiffBase': {
					const diffPlan = requireBridgeWorkerReviewDiffPlan(selectedPlan);
					baseFile = createPierreFileContentsForReviewResource({
						cacheKey: contentCacheKeyForNullableResource(diffPlan.base),
						language: diffPlan.language,
						path: props.semantics.basePath ?? props.semantics.displayPath,
						resource: diffPlan.base,
						window: diffPlan.window,
					});
					planningStage = 'prepareDiffHead';
					return { status: 'pending' };
				}
				case 'prepareDiffHead': {
					const diffPlan = requireBridgeWorkerReviewDiffPlan(selectedPlan);
					headFile = createPierreFileContentsForReviewResource({
						cacheKey: contentCacheKeyForNullableResource(diffPlan.head),
						language: diffPlan.language,
						path: props.semantics.headPath ?? props.semantics.displayPath,
						resource: diffPlan.head,
						window: diffPlan.window,
					});
					planningStage = 'validateWindowBytes';
					return { status: 'pending' };
				}
				case 'prepareFile': {
					const filePlan = requireBridgeWorkerReviewFilePlan(selectedPlan);
					file = createPierreFileContentsForReviewResource({
						cacheKey: filePlan.contentCacheKey,
						language: filePlan.language,
						path:
							props.semantics.headPath ?? props.semantics.basePath ?? props.semantics.displayPath,
						resource: filePlan.resource,
						window: filePlan.window,
					});
					planningStage = 'validateWindowBytes';
					return { status: 'pending' };
				}
				case 'validateWindowBytes': {
					const windowByteLength =
						selectedPlan?.kind === 'diff'
							? bridgeWorkerStringByteLength(
									requireBridgeWorkerReviewPlanningValue(baseFile, 'base FileContents').contents,
								) +
								bridgeWorkerStringByteLength(
									requireBridgeWorkerReviewPlanningValue(headFile, 'head FileContents').contents,
								)
							: bridgeWorkerStringByteLength(
									requireBridgeWorkerReviewPlanningValue(file, 'file FileContents').contents,
								);
					if (windowByteLength > props.budget.maxBytes) {
						return { job: null, status: 'complete' };
					}
					planningStage = 'preparePayload';
					return { status: 'pending' };
				}
				case 'preparePayload': {
					if (selectedPlan?.kind === 'diff') {
						const preparedBaseFile = requireBridgeWorkerReviewPlanningValue(
							baseFile,
							'base FileContents',
						);
						const preparedHeadFile = requireBridgeWorkerReviewPlanningValue(
							headFile,
							'head FileContents',
						);
						const fileDiff = parseDiffFromFile(preparedBaseFile, preparedHeadFile);
						if (fileDiff.lang === undefined) fileDiff.lang = selectedPlan.language;
						fileDiff.cacheKey = selectedPlan.contentCacheKey;
						payload = {
							kind: 'codeViewDiffItem',
							item: createBridgeWorkerCodeViewDiffItem({
								base: selectedPlan.base,
								contentCacheKey: selectedPlan.contentCacheKey,
								fileDiff,
								head: selectedPlan.head,
								semantics: props.semantics,
								window: selectedPlan.window,
							}),
						};
					} else {
						const filePlan = requireBridgeWorkerReviewFilePlan(selectedPlan);
						const preparedFile = requireBridgeWorkerReviewPlanningValue(file, 'file FileContents');
						payload = {
							kind: 'codeViewFileItem',
							item: createBridgeWorkerCodeViewFileItem({
								contentCacheKey: filePlan.contentCacheKey,
								file: preparedFile,
								resource: filePlan.resource,
								semantics: props.semantics,
								window: filePlan.window,
							}),
						};
					}
					planningStage = 'buildJob';
					return { status: 'pending' };
				}
				case 'buildJob': {
					const bridgeDemandRank = props.currentBridgeDemandRank?.() ?? props.bridgeDemandRank;
					const rankedPayload = bridgeWorkerReviewPayloadWithDemandRank({
						bridgeDemandRank,
						payload: requireBridgeWorkerReviewPlanningValue(payload, 'render payload'),
					});
					return {
						job: buildBridgeWorkerReviewPierreRenderJob({
							bridgeDemandRank,
							budget: props.budget,
							payload: rankedPayload,
							selectedPlan: requireBridgeWorkerReviewPlanningValue(selectedPlan, 'selected plan'),
							semantics: props.semantics,
						}),
						status: 'complete',
					};
				}
				default:
					return assertNeverBridgeWorkerReviewPierreRenderJobPlanningStage(planningStage);
			}
		},
	};
}

function bridgeWorkerReviewPayloadWithDemandRank(props: {
	readonly bridgeDemandRank: BridgeWorkerDemandRank;
	readonly payload: BridgeWorkerPierreRenderPayload;
}): BridgeWorkerPierreRenderPayload {
	const numericDemandRank = demandRankForContentRole(props.bridgeDemandRank.lane);
	if (props.payload.kind === 'codeViewFileItem') {
		Object.assign(props.payload.item.file, { bridgeDemandRank: numericDemandRank });
	} else {
		Object.assign(props.payload.item.fileDiff, { bridgeDemandRank: numericDemandRank });
	}
	return props.payload;
}

function assertNeverBridgeWorkerReviewPierreRenderJobPlanningStage(planningStage: never): never {
	throw new Error(
		`Unsupported Bridge worker Review Pierre planning stage: ${String(planningStage)}`,
	);
}

export function prepareBridgeWorkerReviewPierreRenderJobEvent(
	props: PrepareBridgeWorkerReviewPierreRenderJobEventProps,
): PreparedBridgeWorkerStructuredMessage<BridgeWorkerReviewPierreRenderJobEvent> | null {
	const job = planBridgeWorkerReviewPierreRenderJob(props);
	if (job !== null) assertBridgeWorkerReviewRenderReceiptCorrelation(props);
	return job === null
		? null
		: prepareBridgeWorkerReviewPierreRenderJobEventFromJob({
				job,
				renderReceiptIdentity: props.renderReceiptIdentity,
			});
}

function assertBridgeWorkerReviewRenderReceiptCorrelation(
	props: Pick<
		PrepareBridgeWorkerReviewPierreRenderJobEventProps,
		'publicationSequence' | 'renderReceiptIdentity' | 'workerDerivationEpoch'
	>,
): void {
	if (
		props.renderReceiptIdentity.publicationSequence !== props.publicationSequence ||
		props.renderReceiptIdentity.surface !== 'review' ||
		props.renderReceiptIdentity.workerDerivationEpoch !== props.workerDerivationEpoch
	) {
		throw new Error(
			'Bridge worker Review render receipt identity does not match publication authority.',
		);
	}
}

export function prepareBridgeWorkerReviewPierreRenderJobEventFromJob(props: {
	readonly job: BridgeWorkerPierreRenderJob;
	readonly renderReceiptIdentity: BridgeWorkerRenderReceiptIdentity;
}): PreparedBridgeWorkerStructuredMessage<BridgeWorkerReviewPierreRenderJobEvent> {
	if (
		props.renderReceiptIdentity.itemId !== props.job.itemId ||
		props.renderReceiptIdentity.surface !== 'review'
	) {
		throw new Error('Bridge worker Review render receipt identity does not match its job.');
	}
	return prepareBridgeWorkerStructuredMessage({
		message: {
			wireVersion: BRIDGE_WORKER_WIRE_VERSION,
			direction: 'serverWorkerToMain',
			transferDescriptors: [],
			kind: 'reviewPierreRenderJob',
			job: props.job,
			publicationSequence: props.renderReceiptIdentity.publicationSequence,
			renderReceiptIdentity: props.renderReceiptIdentity,
			surface: 'review',
			workerDerivationEpoch: props.renderReceiptIdentity.workerDerivationEpoch,
		},
		declaredFields: transferFieldsForBridgeWorkerPierreRenderPayload(props.job.payload),
	});
}

interface PlanBridgeWorkerReviewRenderJobWithResourcesProps extends PlanBridgeWorkerReviewPierreRenderJobProps {
	readonly resourcesByRole: BridgeWorkerFetchedResourceByRole;
}

type BridgeWorkerReviewPierreRenderJobPlanningStage =
	| 'select'
	| 'prepareDiffBase'
	| 'prepareDiffHead'
	| 'prepareFile'
	| 'validateWindowBytes'
	| 'preparePayload'
	| 'buildJob';

interface BridgeWorkerReviewDiffPlan {
	readonly base: BridgeWorkerFetchedReviewContentResource | null;
	readonly contentCacheKey: string;
	readonly contentHash: string;
	readonly head: BridgeWorkerFetchedReviewContentResource | null;
	readonly kind: 'diff';
	readonly language: string;
	readonly window: BridgeWorkerPierreRenderWindow;
}

interface BridgeWorkerReviewFilePlan {
	readonly contentCacheKey: string;
	readonly contentHash: string;
	readonly kind: 'file';
	readonly language: string;
	readonly resource: BridgeWorkerFetchedReviewContentResource;
	readonly window: BridgeWorkerPierreRenderWindow;
}

type BridgeWorkerReviewSelectedPlan = BridgeWorkerReviewDiffPlan | BridgeWorkerReviewFilePlan;

function requireBridgeWorkerReviewDiffPlan(
	plan: BridgeWorkerReviewSelectedPlan | null,
): BridgeWorkerReviewDiffPlan {
	if (plan?.kind !== 'diff') throw new Error('Bridge worker Review diff plan is not prepared.');
	return plan;
}

function requireBridgeWorkerReviewFilePlan(
	plan: BridgeWorkerReviewSelectedPlan | null,
): BridgeWorkerReviewFilePlan {
	if (plan?.kind !== 'file') throw new Error('Bridge worker Review file plan is not prepared.');
	return plan;
}

function requireBridgeWorkerReviewPlanningValue<TValue>(
	value: TValue | null,
	label: string,
): TValue {
	if (value === null) throw new Error(`Bridge worker Review ${label} is not prepared.`);
	return value;
}

function selectBridgeWorkerReviewPlan(
	props: PlanBridgeWorkerReviewPierreRenderJobProps,
): BridgeWorkerReviewSelectedPlan | null {
	const resourcesByRole = new Map(
		props.resources.map((resource) => [resource.role, resource] as const),
	);
	const planProps = { ...props, resourcesByRole };
	return shouldRenderReviewItemAsDiff(props.semantics)
		? selectBridgeWorkerReviewDiffPlan(planProps)
		: selectBridgeWorkerReviewFilePlan(planProps);
}

function selectBridgeWorkerReviewDiffPlan(
	props: PlanBridgeWorkerReviewRenderJobWithResourcesProps,
): BridgeWorkerReviewDiffPlan | null {
	const diffSides = diffResourcesForReviewSemantics(props);
	if (diffSides === null) return null;
	const presentResources = [diffSides.base, diffSides.head].filter(
		(resource): resource is BridgeWorkerFetchedReviewContentResource => resource !== null,
	);
	if (presentResources.length === 0) return null;
	const window = renderWindowForRoles({
		budget: props.budget,
		resourcesByRole: props.resourcesByRole,
		roles: presentResources.map((resource) => resource.role),
	});
	const contentCacheKey = `${contentCacheKeyForNullableResource(diffSides.base)}|${contentCacheKeyForNullableResource(diffSides.head)}`;
	const contentHash = `${contentHashForNullableResource(diffSides.base)}|${contentHashForNullableResource(diffSides.head)}`;
	const language = languageForReviewRenderJob({
		resources: [diffSides.head, diffSides.base],
		semantics: props.semantics,
	});
	return {
		base: diffSides.base,
		contentCacheKey,
		contentHash,
		head: diffSides.head,
		kind: 'diff',
		language,
		window,
	};
}

function selectBridgeWorkerReviewFilePlan(
	props: PlanBridgeWorkerReviewRenderJobWithResourcesProps,
): BridgeWorkerReviewFilePlan | null {
	const resource = firstReviewResourceForRoles(props.resourcesByRole, [
		'head',
		'file',
		'diff',
		'base',
	]);
	if (resource === null) return null;
	const window = renderWindowForRoles({
		budget: props.budget,
		resourcesByRole: props.resourcesByRole,
		roles: [resource.role],
	});
	const contentCacheKey = contentCacheKeyForResource(resource);
	const language = languageForReviewRenderJob({
		resources: [resource],
		semantics: props.semantics,
	});
	return {
		contentCacheKey,
		contentHash: resource.contentHash,
		kind: 'file',
		language,
		resource,
		window,
	};
}

function buildBridgeWorkerReviewPierreRenderJob(props: {
	readonly bridgeDemandRank: BridgeWorkerDemandRank;
	readonly budget: BridgeWorkerPierreRenderBudget;
	readonly payload: BridgeWorkerPierreRenderPayload;
	readonly selectedPlan: BridgeWorkerReviewSelectedPlan;
	readonly semantics: BridgeWorkerReviewRenderSemantics;
}): BridgeWorkerPierreRenderJob {
	return buildBridgeWorkerPierreRenderJob({
		itemId: props.semantics.itemId,
		renderKind: props.selectedPlan.kind === 'diff' ? 'reviewDiff' : 'fileText',
		contentCacheKey: props.selectedPlan.contentCacheKey,
		contentHash: props.selectedPlan.contentHash,
		language: props.selectedPlan.language,
		bridgeDemandRank: props.bridgeDemandRank,
		window: props.selectedPlan.window,
		payload: props.payload,
		budget: props.budget,
		sourceCorrelations: reviewRenderSourceCorrelations(props.selectedPlan),
	});
}

function reviewRenderSourceCorrelations(
	selectedPlan: BridgeWorkerReviewSelectedPlan,
): readonly BridgeWorkerRenderSourceCorrelation[] {
	const resources =
		selectedPlan.kind === 'diff'
			? [selectedPlan.base, selectedPlan.head].filter(
					(resource): resource is BridgeWorkerFetchedReviewContentResource => resource !== null,
				)
			: [selectedPlan.resource];
	return resources.map((resource) => ({
		descriptorId: resource.descriptorId,
		itemId: resource.itemId,
		observedSha256: resource.observedSha256,
		position: resource.sourcePosition,
		requestId: resource.requestId,
		role: resource.role,
		sourceGeneration: resource.sourceGeneration,
		sourceIdentity: resource.sourceIdentity,
	}));
}

function createBridgeWorkerCodeViewDiffItem(props: {
	readonly base: BridgeWorkerFetchedReviewContentResource | null;
	readonly contentCacheKey: string;
	readonly fileDiff: BridgeWorkerCodeViewDiffItem['fileDiff'];
	readonly head: BridgeWorkerFetchedReviewContentResource | null;
	readonly semantics: BridgeWorkerReviewRenderSemantics;
	readonly window: BridgeWorkerPierreRenderWindow;
}): BridgeWorkerCodeViewDiffItem {
	return {
		id: props.semantics.itemId,
		type: 'diff',
		fileDiff: props.fileDiff,
		version: codeViewRenderVersionForWindow(props.window),
		bridgeMetadata: bridgeWorkerCodeViewItemMetadata({
			cacheKey: props.contentCacheKey,
			contentRoles: loadedDiffContentRoles({ base: props.base, head: props.head }),
			observedLineCount: lineCountForFetchedReviewResources([props.base, props.head]),
			semantics: props.semantics,
			window: props.window,
		}),
	};
}

function createBridgeWorkerCodeViewFileItem(props: {
	readonly contentCacheKey: string;
	readonly file: FileContents;
	readonly resource: BridgeWorkerFetchedReviewContentResource;
	readonly semantics: BridgeWorkerReviewRenderSemantics;
	readonly window: BridgeWorkerPierreRenderWindow;
}): BridgeWorkerCodeViewFileItem {
	return {
		id: props.semantics.itemId,
		type: 'file',
		file: props.file,
		version: codeViewRenderVersionForWindow(props.window),
		bridgeMetadata: bridgeWorkerCodeViewItemMetadata({
			cacheKey: props.contentCacheKey,
			contentRoles: [props.resource.role],
			observedLineCount: lineCountForFetchedReviewResources([props.resource]),
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
	readonly observedLineCount: number;
	readonly semantics: BridgeWorkerReviewRenderSemantics;
	readonly window: BridgeWorkerPierreRenderWindow;
}): BridgeWorkerCodeViewFileItem['bridgeMetadata'] {
	return {
		itemId: props.semantics.itemId,
		displayPath: props.semantics.displayPath,
		contentState: props.window.endLine < props.window.totalLineCount ? 'windowed' : 'hydrated',
		contentRoles: props.contentRoles,
		cacheKey: props.cacheKey,
		lineCount: props.observedLineCount,
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

function lineCountForFetchedReviewResources(
	resources: readonly (BridgeWorkerFetchedReviewContentResource | null)[],
): number {
	return resources.reduce(
		(totalLineCount, resource) =>
			totalLineCount + lineCountForFetchedReviewContent(resource?.text ?? ''),
		0,
	);
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
	readonly resourcesByRole: BridgeWorkerFetchedResourceByRole;
	readonly roles: readonly BridgeWorkerReviewContentRole[];
}): BridgeWorkerPierreRenderWindow {
	const totalLineCount = Math.max(
		0,
		...props.roles.map((role) =>
			lineCountForFetchedReviewContent(props.resourcesByRole.get(role)?.text ?? ''),
		),
	);
	return {
		startLine: 1,
		endLine: Math.min(totalLineCount, props.budget.maxWindowLines),
		totalLineCount,
	};
}

function lineCountForFetchedReviewContent(text: string): number {
	if (text.length === 0) return 0;
	let newlineCount = 0;
	for (let characterIndex = 0; characterIndex < text.length; characterIndex += 1) {
		if (text.charCodeAt(characterIndex) === 10) newlineCount += 1;
	}
	return text.endsWith('\n') ? newlineCount : newlineCount + 1;
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

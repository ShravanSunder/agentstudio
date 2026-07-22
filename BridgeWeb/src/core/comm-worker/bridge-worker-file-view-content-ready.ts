import type { BridgeCommWorkerStore } from './bridge-comm-worker-store.js';
import type {
	BridgeWorkerFilePierreRenderJobEvent,
	BridgeWorkerFileRenderPatch,
	BridgeWorkerFileRenderPatchEvent,
	BridgeWorkerFileViewContentMetadata,
	BridgeWorkerServerToMainMessage,
} from './bridge-worker-contracts.js';
import {
	BRIDGE_WORKER_WIRE_VERSION,
	bridgeWorkerFileRenderPatchEventSchema,
} from './bridge-worker-contracts.js';
import type { BridgeWorkerFetchedFileViewContentResource } from './bridge-worker-file-view-content-fetch.js';
import {
	buildBridgeWorkerPierreRenderJob,
	type BridgeWorkerDemandRank,
	type BridgeWorkerPierreRenderBudget,
	type BridgeWorkerPierreRenderJob,
	type BridgeWorkerPierreRenderWindow,
} from './bridge-worker-pierre-render-job.js';
import type { BridgeWorkerRenderReceiptIdentity } from './bridge-worker-render-fulfillment.js';
import {
	prepareBridgeWorkerStructuredMessage,
	type BridgeWorkerTransferFieldDeclaration,
	type PreparedBridgeWorkerStructuredMessage,
} from './bridge-worker-transfer-list.js';

export interface PlanBridgeWorkerFileViewPierreRenderJobProps {
	readonly bridgeDemandRank: BridgeWorkerDemandRank;
	readonly budget: BridgeWorkerPierreRenderBudget;
	readonly metadata: BridgeWorkerFileViewContentMetadata;
	readonly resource: BridgeWorkerFetchedFileViewContentResource;
}

export interface PrepareBridgeWorkerFileViewContentReadyEventsProps extends PlanBridgeWorkerFileViewPierreRenderJobProps {
	readonly publicationSequence: number;
	readonly renderReceiptIdentity: BridgeWorkerRenderReceiptIdentity;
	readonly workerDerivationEpoch: number;
}

export interface CommitBridgeWorkerFileViewContentReadyRenderPatchProps {
	readonly preparedJobEvent: PreparedBridgeWorkerStructuredMessage<BridgeWorkerFilePierreRenderJobEvent>;
	readonly publicationSequence: number;
	readonly store: BridgeCommWorkerStore;
	readonly workerDerivationEpoch: number;
}

export interface BridgeWorkerFileViewContentReadyRenderPatchCommit {
	readonly touchedKeys: readonly string[];
	readonly preparedMessage: PreparedBridgeWorkerStructuredMessage<BridgeWorkerFileRenderPatchEvent>;
}

const bridgeWorkerPlainTextLanguage = 'text';

export function prepareBridgeWorkerFileViewContentRenderJobEvent(
	props: PrepareBridgeWorkerFileViewContentReadyEventsProps,
): PreparedBridgeWorkerStructuredMessage<BridgeWorkerFilePierreRenderJobEvent> | null {
	const job = planBridgeWorkerFileViewPierreRenderJob(props);
	if (job === null) {
		return null;
	}
	assertBridgeWorkerFileRenderReceiptCorrelation(props);
	return prepareBridgeWorkerFileViewContentRenderJobEventFromJob({
		job,
		renderReceiptIdentity: props.renderReceiptIdentity,
	});
}

function assertBridgeWorkerFileRenderReceiptCorrelation(
	props: Pick<
		PrepareBridgeWorkerFileViewContentReadyEventsProps,
		'publicationSequence' | 'renderReceiptIdentity' | 'workerDerivationEpoch'
	>,
): void {
	if (
		props.renderReceiptIdentity.publicationSequence !== props.publicationSequence ||
		props.renderReceiptIdentity.surface !== 'file' ||
		props.renderReceiptIdentity.workerDerivationEpoch !== props.workerDerivationEpoch
	) {
		throw new Error(
			'Bridge worker File render receipt identity does not match publication authority.',
		);
	}
}

export function prepareBridgeWorkerFileViewContentRenderJobEventFromJob(props: {
	readonly job: BridgeWorkerPierreRenderJob;
	readonly renderReceiptIdentity: BridgeWorkerRenderReceiptIdentity;
}): PreparedBridgeWorkerStructuredMessage<BridgeWorkerFilePierreRenderJobEvent> {
	if (
		props.renderReceiptIdentity.itemId !== props.job.itemId ||
		props.renderReceiptIdentity.surface !== 'file'
	) {
		throw new Error('Bridge worker File render receipt identity does not match its job.');
	}
	return prepareBridgeWorkerStructuredMessage({
		message: {
			wireVersion: BRIDGE_WORKER_WIRE_VERSION,
			direction: 'serverWorkerToMain',
			transferDescriptors: [],
			kind: 'filePierreRenderJob',
			job: props.job,
			publicationSequence: props.renderReceiptIdentity.publicationSequence,
			renderReceiptIdentity: props.renderReceiptIdentity,
			surface: 'file',
			workerDerivationEpoch: props.renderReceiptIdentity.workerDerivationEpoch,
		},
		declaredFields: transferFieldsForBridgeWorkerPierreRenderPayload(props.job.payloadByteLength),
	});
}

export function commitBridgeWorkerFileViewContentReadyRenderPatch(
	props: CommitBridgeWorkerFileViewContentReadyRenderPatchProps,
): BridgeWorkerFileViewContentReadyRenderPatchCommit {
	const contentReadyResult = props.store.actions.applyContentReady({
		itemId: props.preparedJobEvent.message.job.itemId,
		contentCacheKey: props.preparedJobEvent.message.job.contentCacheKey,
	});
	const slicePatchEvent = props.store.actions.takePendingSlicePatchEvent({
		epoch: props.workerDerivationEpoch,
		sequence: props.publicationSequence,
	});
	const fileRenderPatches = bridgeWorkerFileRenderPatchesFromSlicePatchEvent(slicePatchEvent);

	return {
		touchedKeys: contentReadyResult.touchedKeys,
		preparedMessage: prepareBridgeWorkerFileRenderPatchEvent({
			patches: fileRenderPatches,
			publicationSequence: props.publicationSequence,
			workerDerivationEpoch: props.workerDerivationEpoch,
		}),
	};
}

export function prepareBridgeWorkerFileRenderPatchEvent(props: {
	readonly patches: readonly BridgeWorkerFileRenderPatch[];
	readonly publicationSequence: number;
	readonly workerDerivationEpoch: number;
}): PreparedBridgeWorkerStructuredMessage<BridgeWorkerFileRenderPatchEvent> {
	return prepareBridgeWorkerStructuredMessage({
		message: bridgeWorkerFileRenderPatchEventSchema.parse({
			direction: 'serverWorkerToMain',
			kind: 'fileRenderPatch',
			patches: props.patches,
			publicationSequence: props.publicationSequence,
			surface: 'file',
			transferDescriptors: [],
			wireVersion: BRIDGE_WORKER_WIRE_VERSION,
			workerDerivationEpoch: props.workerDerivationEpoch,
		}),
		declaredFields: [],
	});
}

export function planBridgeWorkerFileViewPierreRenderJob(
	props: PlanBridgeWorkerFileViewPierreRenderJobProps,
): BridgeWorkerPierreRenderJob | null {
	if (!fileViewResourceMatchesMetadata(props)) {
		return null;
	}
	const contentHash = props.resource.contentHash;
	if (contentHash === undefined) {
		return null;
	}
	const window = completeRenderWindowForFileViewResource(props.metadata);
	const completeText = props.resource.text;
	const language = languageForFileViewRenderJob({
		metadata: props.metadata,
		resource: props.resource,
	});
	const contentCacheKey = props.metadata.cacheKey;
	const publicationCapacity = completeFilePublicationCapacity({
		budgetClassName: props.budget.className,
		completeText,
		window,
	});

	return buildBridgeWorkerPierreRenderJob({
		itemId: props.metadata.itemId,
		renderKind: 'fileText',
		contentCacheKey,
		contentHash,
		language,
		bridgeDemandRank: props.bridgeDemandRank,
		window,
		payload: {
			kind: 'codeViewFileItem',
			item: {
				id: `file:${props.metadata.itemId}`,
				type: 'file',
				file: {
					name: props.metadata.path,
					contents: completeText,
					cacheKey: contentCacheKey,
					...(optionalPierreHighlightLanguage(language) === undefined
						? {}
						: { lang: optionalPierreHighlightLanguage(language) }),
				},
				bridgeMetadata: {
					itemId: props.metadata.itemId,
					displayPath: props.metadata.path,
					contentState: 'hydrated',
					contentRoles: ['file'],
					cacheKey: contentCacheKey,
					lineCount: props.metadata.payloadLineCount,
				},
			},
		},
		budget: publicationCapacity,
		sourceCorrelations: [
			{
				descriptorId: props.resource.descriptorId,
				itemId: props.resource.itemId,
				observedSha256: props.resource.contentHash,
				position: props.resource.sourcePosition,
				requestId: props.resource.requestId,
				role: 'file',
				sourceGeneration: props.resource.sourceGeneration,
				sourceIdentity: props.resource.sourceIdentity,
			},
		],
	});
}

function fileViewResourceMatchesMetadata(
	props: PlanBridgeWorkerFileViewPierreRenderJobProps,
): boolean {
	const completeTextSemantics = deriveCompleteFileTextSemantics(props.resource.textBytes);
	return (
		props.metadata.canFetchContent &&
		!props.metadata.isBinary &&
		props.metadata.encoding === 'utf-8' &&
		!props.metadata.endsMidLine &&
		props.metadata.endsWithNewline === completeTextSemantics.endsWithNewline &&
		props.metadata.truncationKind === 'none' &&
		props.metadata.virtualizedExtentKind === 'exactLineCount' &&
		props.metadata.payloadLineCount === completeTextSemantics.lineCount &&
		props.metadata.totalLineCount === props.metadata.payloadLineCount &&
		props.resource.itemId === props.metadata.itemId &&
		props.resource.path === props.metadata.path &&
		props.resource.descriptorId === props.metadata.descriptorId &&
		props.resource.contentHash === props.metadata.contentHash &&
		props.resource.language === props.metadata.language &&
		props.resource.sizeBytes === props.metadata.sizeBytes &&
		props.resource.byteLength === props.metadata.payloadByteCount &&
		props.resource.textBytes.byteLength === props.resource.byteLength
	);
}

interface CompleteFileTextSemantics {
	readonly endsWithNewline: boolean;
	readonly lineCount: number;
}

function deriveCompleteFileTextSemantics(textBytes: ArrayBuffer): CompleteFileTextSemantics {
	const bytes = new Uint8Array(textBytes);
	let lineFeedCount = 0;
	for (const byte of bytes) {
		if (byte === 0x0a) lineFeedCount += 1;
	}
	const endsWithNewline = bytes.byteLength > 0 && bytes.at(-1) === 0x0a;
	return {
		endsWithNewline,
		lineCount: lineFeedCount + (bytes.byteLength > 0 && !endsWithNewline ? 1 : 0),
	};
}

function completeRenderWindowForFileViewResource(
	metadata: BridgeWorkerFileViewContentMetadata,
): BridgeWorkerPierreRenderWindow {
	const totalLineCount = metadata.payloadLineCount;
	return {
		startLine: 1,
		endLine: totalLineCount,
		totalLineCount,
	};
}

function completeFilePublicationCapacity(props: {
	readonly budgetClassName: BridgeWorkerPierreRenderBudget['className'];
	readonly completeText: string;
	readonly window: BridgeWorkerPierreRenderWindow;
}): BridgeWorkerPierreRenderBudget {
	return {
		className: props.budgetClassName,
		maxBytes: bridgeWorkerStringByteLength(props.completeText),
		maxWindowLines: Math.max(0, props.window.endLine - props.window.startLine + 1),
	};
}

function languageForFileViewRenderJob(props: {
	readonly metadata: BridgeWorkerFileViewContentMetadata;
	readonly resource: BridgeWorkerFetchedFileViewContentResource;
}): string {
	return (
		normalizedLanguageOrNull(props.resource.language) ??
		normalizedLanguageOrNull(props.metadata.language) ??
		bridgeWorkerPlainTextLanguage
	);
}

function transferFieldsForBridgeWorkerPierreRenderPayload(
	payloadByteLength: number,
): readonly BridgeWorkerTransferFieldDeclaration[] {
	return [
		{
			fieldPath: ['job', 'payload'],
			byteLength: payloadByteLength,
			mode: 'clone',
		},
	];
}

function normalizedLanguageOrNull(language: string | null | undefined): string | null {
	const normalizedLanguage = language?.trim() ?? '';
	return normalizedLanguage.length === 0 ? null : normalizedLanguage;
}

function optionalPierreHighlightLanguage(language: string): string | undefined {
	const normalizedLanguage = normalizedLanguageOrNull(language);
	return normalizedLanguage ?? undefined;
}

function bridgeWorkerStringByteLength(value: string): number {
	return new TextEncoder().encode(value).byteLength;
}

export function bridgeWorkerFileRenderPatchesFromSlicePatchEvent(
	event: BridgeWorkerServerToMainMessage | null,
): readonly BridgeWorkerFileRenderPatch[] {
	if (event === null) {
		throw new Error('Bridge worker File View content-ready commit produced no render patch event.');
	}
	if (event.kind !== 'slicePatch') {
		throw new Error(
			'Bridge worker File View content-ready commit produced an invalid patch event.',
		);
	}
	return event.patches.map((patch): BridgeWorkerFileRenderPatch => {
		if (
			patch.slice !== 'rowPaint' &&
			patch.slice !== 'contentAvailability' &&
			patch.slice !== 'panelChrome'
		) {
			throw new Error('Bridge worker File View content-ready commit produced a non-render patch.');
		}
		return patch;
	});
}

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
import {
	prepareBridgeWorkerStructuredMessage,
	type BridgeWorkerTransferFieldDeclaration,
	type PreparedBridgeWorkerStructuredMessage,
} from './bridge-worker-transfer-list.js';

export interface PrepareBridgeWorkerFileViewContentReadyEventsProps {
	readonly bridgeDemandRank: BridgeWorkerDemandRank;
	readonly budget: BridgeWorkerPierreRenderBudget;
	readonly metadata: BridgeWorkerFileViewContentMetadata;
	readonly publicationSequence: number;
	readonly resource: BridgeWorkerFetchedFileViewContentResource;
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
	return prepareBridgeWorkerStructuredMessage({
		message: {
			wireVersion: BRIDGE_WORKER_WIRE_VERSION,
			direction: 'serverWorkerToMain',
			transferDescriptors: [],
			kind: 'filePierreRenderJob',
			job,
			publicationSequence: props.publicationSequence,
			surface: 'file',
			workerDerivationEpoch: props.workerDerivationEpoch,
		},
		declaredFields: transferFieldsForBridgeWorkerPierreRenderPayload(job.payloadByteLength),
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

function planBridgeWorkerFileViewPierreRenderJob(
	props: PrepareBridgeWorkerFileViewContentReadyEventsProps,
): BridgeWorkerPierreRenderJob | null {
	if (!fileViewResourceMatchesMetadata(props)) {
		return null;
	}
	const contentHash = props.resource.contentHash;
	if (contentHash === undefined) {
		return null;
	}
	const window = renderWindowForFileViewResource({
		budget: props.budget,
		metadata: props.metadata,
		resource: props.resource,
	});
	const windowedText = windowTextForBridgeWorkerCodeView({
		maxLines: window.endLine,
		text: props.resource.text,
	});
	if (bridgeWorkerStringByteLength(windowedText) > props.budget.maxBytes) {
		return null;
	}
	const language = languageForFileViewRenderJob({
		metadata: props.metadata,
		resource: props.resource,
	});
	const contentCacheKey = props.metadata.cacheKey;

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
					contents: windowedText,
					cacheKey: contentCacheKey,
					...(optionalPierreHighlightLanguage(language) === undefined
						? {}
						: { lang: optionalPierreHighlightLanguage(language) }),
				},
				bridgeMetadata: {
					itemId: props.metadata.itemId,
					displayPath: props.metadata.path,
					contentState:
						props.metadata.truncationKind !== 'none' || window.endLine < window.totalLineCount
							? 'windowed'
							: 'hydrated',
					contentRoles: ['file'],
					cacheKey: contentCacheKey,
					lineCount: props.metadata.payloadLineCount,
				},
			},
		},
		budget: props.budget,
	});
}

function fileViewResourceMatchesMetadata(
	props: PrepareBridgeWorkerFileViewContentReadyEventsProps,
): boolean {
	return (
		props.metadata.canFetchContent &&
		!props.metadata.isBinary &&
		props.resource.itemId === props.metadata.itemId &&
		props.resource.path === props.metadata.path &&
		props.resource.descriptorId === props.metadata.descriptorId &&
		props.resource.contentHash === props.metadata.contentHash &&
		props.resource.language === props.metadata.language &&
		props.resource.sizeBytes === props.metadata.sizeBytes
	);
}

function renderWindowForFileViewResource(props: {
	readonly budget: BridgeWorkerPierreRenderBudget;
	readonly metadata: BridgeWorkerFileViewContentMetadata;
	readonly resource: BridgeWorkerFetchedFileViewContentResource;
}): BridgeWorkerPierreRenderWindow {
	const totalLineCount = props.metadata.payloadLineCount;
	return {
		startLine: 1,
		endLine: Math.min(totalLineCount, props.budget.maxWindowLines),
		totalLineCount,
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
		if (patch.slice !== 'rowPaint' && patch.slice !== 'contentAvailability') {
			throw new Error('Bridge worker File View content-ready commit produced a non-render patch.');
		}
		return patch;
	});
}

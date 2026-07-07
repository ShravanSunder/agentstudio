import type { BridgeCommWorkerStore } from './bridge-comm-worker-store.js';
import type {
	BridgeWorkerFileViewContentMetadata,
	BridgeWorkerPierreRenderJobEvent,
	BridgeWorkerServerToMainMessage,
} from './bridge-worker-contracts.js';
import { BRIDGE_WORKER_WIRE_VERSION } from './bridge-worker-contracts.js';
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
	readonly resource: BridgeWorkerFetchedFileViewContentResource;
}

export interface CommitBridgeWorkerFileViewContentReadySlicePatchProps {
	readonly epoch: number;
	readonly preparedJobEvent: PreparedBridgeWorkerStructuredMessage<BridgeWorkerPierreRenderJobEvent>;
	readonly sequence: number;
	readonly store: BridgeCommWorkerStore;
}

export interface BridgeWorkerFileViewContentReadySlicePatchCommit {
	readonly touchedKeys: readonly string[];
	readonly preparedMessage: BridgeWorkerPreparedServerToMainMessage;
}

export type BridgeWorkerPreparedServerToMainMessage =
	PreparedBridgeWorkerStructuredMessage<BridgeWorkerServerToMainMessage>;

const bridgeWorkerPlainTextLanguage = 'text';

export function prepareBridgeWorkerFileViewContentRenderJobEvent(
	props: PrepareBridgeWorkerFileViewContentReadyEventsProps,
): PreparedBridgeWorkerStructuredMessage<BridgeWorkerPierreRenderJobEvent> | null {
	const job = planBridgeWorkerFileViewPierreRenderJob(props);
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
		declaredFields: transferFieldsForBridgeWorkerPierreRenderPayload(job.payloadByteLength),
	});
}

export function commitBridgeWorkerFileViewContentReadySlicePatch(
	props: CommitBridgeWorkerFileViewContentReadySlicePatchProps,
): BridgeWorkerFileViewContentReadySlicePatchCommit {
	const contentReadyResult = props.store.actions.applyContentReady({
		itemId: props.preparedJobEvent.message.job.itemId,
		contentCacheKey: props.preparedJobEvent.message.job.contentCacheKey,
	});
	const slicePatchEvent = props.store.actions.takePendingSlicePatchEvent({
		epoch: props.epoch,
		sequence: props.sequence,
	});

	return {
		touchedKeys: contentReadyResult.touchedKeys,
		preparedMessage: prepareBridgeWorkerStructuredMessage({
			message: assertBridgeWorkerSlicePatchEvent(slicePatchEvent),
			declaredFields: [],
		}),
	};
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
	const reservedWindowedText = textPaddedToMinimumRenderedLineCountWithinByteBudget({
		maxBytes: props.budget.maxBytes,
		minimumLineCount: window.totalLineCount,
		text: windowedText,
	});
	if (bridgeWorkerStringByteLength(reservedWindowedText) > props.budget.maxBytes) {
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
					contents: reservedWindowedText,
					cacheKey: contentCacheKey,
					...(optionalPierreHighlightLanguage(language) === undefined
						? {}
						: { lang: optionalPierreHighlightLanguage(language) }),
				},
				bridgeMetadata: {
					itemId: props.metadata.itemId,
					displayPath: props.metadata.path,
					contentState: window.endLine < window.totalLineCount ? 'windowed' : 'hydrated',
					contentRoles: ['file'],
					cacheKey: contentCacheKey,
					lineCount: props.metadata.lineCount ?? null,
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
		props.resource.handleId === props.metadata.contentHandle &&
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
	const totalLineCount =
		props.metadata.lineCount ?? renderedLineCountForPierreFileContent(props.resource.text);
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

function renderedLineCountForPierreFileContent(text: string): number {
	if (text.length === 0) {
		return 0;
	}
	return (text.match(/\n/gu)?.length ?? 0) + 1;
}

function textPaddedToMinimumRenderedLineCountWithinByteBudget(props: {
	readonly maxBytes: number;
	readonly minimumLineCount: number;
	readonly text: string;
}): string {
	if (props.minimumLineCount <= 0) {
		return props.text;
	}
	const currentLineCount = renderedLineCountForPierreFileContent(props.text);
	const missingLineCount = Math.max(props.minimumLineCount - currentLineCount, 0);
	if (missingLineCount === 0) {
		return props.text;
	}
	const currentByteLength = bridgeWorkerStringByteLength(props.text);
	const availablePaddingBytes = Math.max(props.maxBytes - currentByteLength, 0);
	if (availablePaddingBytes <= 1) {
		return props.text;
	}
	const boundedMissingLineCount = Math.min(missingLineCount, availablePaddingBytes - 1);
	return `${props.text}${'\n'.repeat(boundedMissingLineCount)} `;
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

function assertBridgeWorkerSlicePatchEvent(
	event: BridgeWorkerServerToMainMessage | null,
): BridgeWorkerServerToMainMessage {
	if (event === null) {
		throw new Error('Bridge worker File View content-ready commit produced no slice patch event.');
	}
	return event;
}

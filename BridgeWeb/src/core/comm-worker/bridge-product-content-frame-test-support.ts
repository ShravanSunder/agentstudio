import type {
	BridgeProductContentFrame,
	BridgeProductContentRequestFor,
	BridgeProductFileContentIdentity,
	BridgeProductReviewContentIdentity,
} from './bridge-product-content-contracts.js';

export const abcSha256 = 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad';

export type BridgeProductContentFrameOfKind<
	TContentFrameKind extends BridgeProductContentFrame['header']['kind'],
> = {
	readonly header: Extract<
		BridgeProductContentFrame['header'],
		{ readonly kind: TContentFrameKind }
	>;
	readonly payload: Uint8Array;
};

type BridgeProductFileContentAcceptedFrame = {
	readonly header: Extract<
		BridgeProductContentFrame['header'],
		{ readonly kind: 'content.accepted' }
	> & { readonly identity: BridgeProductFileContentIdentity };
	readonly payload: Uint8Array;
};

type BridgeProductReviewContentAcceptedFrame = {
	readonly header: Extract<
		BridgeProductContentFrame['header'],
		{ readonly kind: 'content.accepted' }
	> & { readonly identity: BridgeProductReviewContentIdentity };
	readonly payload: Uint8Array;
};

const fileContentIdentity = {
	contentKind: 'file.content',
	descriptorId: 'file-descriptor-1',
	fileId: 'file-1',
	source: {
		repoId: '00000000-0000-4000-8000-000000000001',
		rootRevisionToken: null,
		sourceCursor: 'source-cursor-1',
		sourceId: 'source-1',
		subscriptionGeneration: 11,
		worktreeId: '00000000-0000-4000-8000-000000000002',
	},
	window: { kind: 'prefix', maximumBytes: 3, maximumLines: 10_000, startByte: 0 },
} as const;

const reviewContentIdentity = {
	contentDigest: {
		algorithm: 'sha256',
		authority: 'authoritative',
		value: abcSha256,
	},
	contentKind: 'review.content',
	descriptorId: 'review-descriptor-1',
	endpointId: 'review-endpoint-1',
	handleId: 'review-handle-1',
	itemId: 'review-item-1',
	packageId: 'review-package-1',
	reviewGeneration: 7,
	role: 'head',
	sourceIdentity: 'review-source-1',
	wholeByteLength: 12,
	window: { kind: 'byteRange', maximumBytes: 3, startByte: 0 },
} as const;

export function contentRequest(): BridgeProductContentRequestFor<'file.content'> {
	return {
		contentKind: 'file.content',
		contentRequestId: 'content-request-1',
		descriptor: {
			contentKind: fileContentIdentity.contentKind,
			declaredByteLength: 3,
			descriptorId: fileContentIdentity.descriptorId,
			encoding: 'utf-8',
			expectedSha256: abcSha256,
			fileId: fileContentIdentity.fileId,
			maximumBytes: fileContentIdentity.window.maximumBytes,
			source: fileContentIdentity.source,
			window: fileContentIdentity.window,
		},
		kind: 'content.open',
		leaseId: 'lease-1',
		paneSessionId: 'pane-session-1',
		wireVersion: 2,
		workerDerivationEpoch: 2,
		workerInstanceId: 'worker-instance-1',
	};
}

export function contentRequestForAccepted(
	acceptedFrame: BridgeProductFileContentAcceptedFrame,
): BridgeProductContentRequestFor<'file.content'> {
	const request = contentRequest();
	if (
		acceptedFrame.header.declaredByteLength === null ||
		acceptedFrame.header.expectedSha256 === null
	) {
		throw new Error('File content acceptance requires exact length and SHA-256.');
	}
	return {
		...request,
		contentKind: acceptedFrame.header.identity.contentKind,
		contentRequestId: acceptedFrame.header.contentRequestId,
		descriptor: {
			...request.descriptor,
			contentKind: acceptedFrame.header.identity.contentKind,
			declaredByteLength: acceptedFrame.header.declaredByteLength,
			descriptorId: acceptedFrame.header.identity.descriptorId,
			expectedSha256: acceptedFrame.header.expectedSha256,
			fileId: acceptedFrame.header.identity.fileId,
			maximumBytes: acceptedFrame.header.maximumBytes,
			source: acceptedFrame.header.identity.source,
			window: acceptedFrame.header.identity.window,
		},
		leaseId: acceptedFrame.header.leaseId,
		paneSessionId: acceptedFrame.header.paneSessionId,
		wireVersion: acceptedFrame.header.wireVersion,
		workerDerivationEpoch: acceptedFrame.header.workerDerivationEpoch,
		workerInstanceId: acceptedFrame.header.workerInstanceId,
	};
}

export function contentAcceptedFrame(): BridgeProductFileContentAcceptedFrame {
	return {
		header: {
			contentSequence: 0,
			declaredByteLength: 3,
			expectedSha256: abcSha256,
			identity: fileContentIdentity,
			kind: 'content.accepted',
			leaseId: 'lease-1',
			maximumBytes: 3,
			paneSessionId: 'pane-session-1',
			contentRequestId: 'content-request-1',
			wireVersion: 2,
			workerDerivationEpoch: 2,
			workerInstanceId: 'worker-instance-1',
		},
		payload: new Uint8Array(),
	};
}

export function contentAcceptedFrameForByteCount(
	declaredByteLength: number,
	maximumBytes: number,
	expectedSha256 = abcSha256,
): BridgeProductFileContentAcceptedFrame {
	const acceptedFrame = contentAcceptedFrame();
	return {
		header: {
			...acceptedFrame.header,
			declaredByteLength,
			expectedSha256,
			identity: {
				...acceptedFrame.header.identity,
				window: { ...acceptedFrame.header.identity.window, maximumBytes },
			},
			maximumBytes,
		},
		payload: new Uint8Array(),
	};
}

export function reviewContentRequest(): BridgeProductContentRequestFor<'review.content'> {
	return {
		contentKind: 'review.content',
		contentRequestId: 'review-content-request-1',
		descriptor: {
			...reviewContentIdentity,
			declaredByteLength: 3,
			encoding: 'utf-8',
			expectedSha256: abcSha256,
			isBinary: false,
			language: 'text',
			maximumBytes: reviewContentIdentity.window.maximumBytes,
			mimeType: 'text/plain',
		},
		kind: 'content.open',
		leaseId: 'review-lease-1',
		paneSessionId: 'pane-session-1',
		wireVersion: 2,
		workerDerivationEpoch: 2,
		workerInstanceId: 'worker-instance-1',
	};
}

export function reviewContentAcceptedFrame(): BridgeProductReviewContentAcceptedFrame {
	return {
		header: {
			contentRequestId: 'review-content-request-1',
			contentSequence: 0,
			declaredByteLength: 3,
			expectedSha256: abcSha256,
			identity: reviewContentIdentity,
			kind: 'content.accepted',
			leaseId: 'review-lease-1',
			maximumBytes: reviewContentIdentity.window.maximumBytes,
			paneSessionId: 'pane-session-1',
			wireVersion: 2,
			workerDerivationEpoch: 2,
			workerInstanceId: 'worker-instance-1',
		},
		payload: new Uint8Array(),
	};
}

export function contentDataFrame(): BridgeProductContentFrameOfKind<'content.data'> {
	return {
		header: {
			contentSequence: 1,
			kind: 'content.data',
			offsetBytes: 0,
		},
		payload: Uint8Array.from([97, 98, 99]),
	};
}

export function contentDataFrameForPayload(
	contentSequence: number,
	offsetBytes: number,
	payload: Uint8Array,
): BridgeProductContentFrameOfKind<'content.data'> {
	const dataFrame = contentDataFrame();
	return {
		header: {
			...dataFrame.header,
			contentSequence,
			offsetBytes,
		},
		payload,
	};
}

export function contentEndFrame(): BridgeProductContentFrameOfKind<'content.end'> {
	return {
		header: {
			contentSequence: 2,
			endOfSource: true,
			kind: 'content.end',
			observedByteLength: 3,
			observedSha256: abcSha256,
		},
		payload: new Uint8Array(),
	};
}

export function contentEndFrameForByteCount(
	contentSequence: number,
	observedByteLength: number,
): BridgeProductContentFrameOfKind<'content.end'> {
	const endFrame = contentEndFrame();
	return {
		header: {
			...endFrame.header,
			contentSequence,
			observedByteLength,
		},
		payload: new Uint8Array(),
	};
}

export function contentErrorFrame(): BridgeProductContentFrameOfKind<'content.error'> {
	return {
		header: {
			code: 'internal',
			contentSequence: 2,
			kind: 'content.error',
			retryable: false,
			safeMessage: null,
		},
		payload: new Uint8Array(),
	};
}

export function contentResetFrame(): BridgeProductContentFrameOfKind<'content.reset'> {
	return {
		header: {
			contentSequence: 1,
			kind: 'content.reset',
			reason: 'stale_source',
		},
		payload: new Uint8Array(),
	};
}

export function contentAcceptedControlBody(
	frame: BridgeProductContentFrameOfKind<'content.accepted'> = contentAcceptedFrame(),
): Omit<(typeof frame)['header'], 'contentSequence' | 'kind'> {
	const { contentSequence, kind, ...controlBody } = frame.header;
	void contentSequence;
	void kind;
	return controlBody;
}

export function contentEndControlBody(
	frame: BridgeProductContentFrameOfKind<'content.end'> = contentEndFrame(),
): Readonly<{ endOfSource: boolean; observedByteLength: number; observedSha256: string }> {
	return {
		endOfSource: frame.header.endOfSource,
		observedByteLength: frame.header.observedByteLength,
		observedSha256: frame.header.observedSha256,
	};
}

export function concatenateBytes(...parts: readonly Uint8Array[]): Uint8Array {
	const result = new Uint8Array(parts.reduce((total, part) => total + part.byteLength, 0));
	let offset = 0;
	for (const part of parts) {
		result.set(part, offset);
		offset += part.byteLength;
	}
	return result;
}

export function encodeMinimalControlFrame(
	tag: number,
	contentSequence: number,
	controlBody: unknown,
): Uint8Array<ArrayBuffer> {
	const controlBodyJSON = JSON.stringify(controlBody);
	if (controlBodyJSON === undefined) {
		throw new Error('Test control body must be JSON serializable.');
	}
	return encodeMinimalControlFrameBytes(
		tag,
		contentSequence,
		new TextEncoder().encode(controlBodyJSON),
	);
}

export function encodeMinimalControlFrameBytes(
	tag: number,
	contentSequence: number,
	controlBodyBytes: Uint8Array,
): Uint8Array<ArrayBuffer> {
	const frameBodyByteLength = 1 + 4 + controlBodyBytes.byteLength;
	const frame = new Uint8Array(4 + frameBodyByteLength);
	const view = new DataView(frame.buffer);
	view.setUint32(0, frameBodyByteLength, false);
	frame[4] = tag;
	view.setUint32(5, contentSequence, false);
	frame.set(controlBodyBytes, 9);
	return frame;
}

export function encodeMinimalDataFrame(
	contentSequence: number,
	offsetBytes: number,
	payload: Uint8Array,
): Uint8Array<ArrayBuffer> {
	const frameBodyByteLength = 1 + 4 + 4 + payload.byteLength;
	const frame = new Uint8Array(4 + frameBodyByteLength);
	const view = new DataView(frame.buffer);
	view.setUint32(0, frameBodyByteLength, false);
	frame[4] = 0x02;
	view.setUint32(5, contentSequence, false);
	view.setUint32(9, offsetBytes, false);
	frame.set(payload, 13);
	return frame;
}

export function parseMinimalControlBody(frame: Uint8Array): unknown {
	return JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(frame.subarray(9))) as unknown;
}

export function readUint32BigEndian(bytes: Uint8Array, offset: number): number {
	return new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength).getUint32(offset, false);
}

export function countByteSubsequence(bytes: Uint8Array, subsequence: Uint8Array): number {
	let matchCount = 0;
	for (let offset = 0; offset <= bytes.byteLength - subsequence.byteLength; offset += 1) {
		if (subsequence.every((byte, index) => bytes[offset + index] === byte)) {
			matchCount += 1;
		}
	}
	return matchCount;
}

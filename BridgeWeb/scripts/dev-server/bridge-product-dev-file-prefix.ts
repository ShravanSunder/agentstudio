import { createHash } from 'node:crypto';

export type BridgeProductDevFileTruncationKind = 'none' | 'byteLimit' | 'lineLimit' | 'both';

export interface BridgeProductDevFilePrefix {
	readonly bytes: Uint8Array;
	readonly didReachEnd: boolean;
	readonly endsMidLine: boolean;
	readonly endsWithNewline: boolean;
	readonly isBinary: boolean;
	readonly isValidUTF8: boolean;
	readonly payloadLineCount: number;
	readonly sha256: string;
	readonly truncationKind: BridgeProductDevFileTruncationKind;
}

interface BridgeProductDevFilePrefixLimits {
	readonly maximumBytes: number;
	readonly maximumLines: number;
}

interface IncompleteUTF8Scalar {
	readonly expectedByteCount: number;
	readonly retainedByteCount: number;
}

const strictUTF8Decoder = new TextDecoder('utf-8', { fatal: true });

export function deriveBridgeProductDevFilePrefix(
	sourceBytes: Uint8Array,
	limits: BridgeProductDevFilePrefixLimits,
): BridgeProductDevFilePrefix {
	assertPositiveSafeInteger(limits.maximumBytes, 'maximumBytes');
	assertPositiveSafeInteger(limits.maximumLines, 'maximumLines');

	let boundaryOffset = 0;
	let isBinary = false;
	let newlineCount = 0;
	let reachedByteLimit = false;
	let reachedLineLimit = false;
	while (boundaryOffset < sourceBytes.byteLength && !reachedByteLimit && !reachedLineLimit) {
		const byte = sourceBytes[boundaryOffset];
		if (byte === undefined) {
			throw new Error('Bridge product dev File prefix source ended before its boundary.');
		}
		boundaryOffset += 1;
		isBinary ||= byte === 0;
		if (byte === 0x0a) newlineCount += 1;
		reachedByteLimit = boundaryOffset === limits.maximumBytes;
		reachedLineLimit = newlineCount === limits.maximumLines;
	}

	const sourceHasMoreBytes = boundaryOffset < sourceBytes.byteLength;
	let payloadBytes = Uint8Array.from(sourceBytes.subarray(0, boundaryOffset));
	let isValidUTF8 = isValidUTF8Bytes(payloadBytes);
	if (!isValidUTF8 && reachedByteLimit && sourceHasMoreBytes) {
		const canonicalBytes = canonicalizeSplitUTF8Scalar(payloadBytes, sourceBytes, boundaryOffset);
		if (canonicalBytes !== null) {
			payloadBytes = canonicalBytes;
			isValidUTF8 = true;
		}
	}

	const endsWithNewline = payloadBytes.at(-1) === 0x0a;
	const payloadLineCount =
		payloadBytes.byteLength === 0 ? 0 : newlineCount + (endsWithNewline ? 0 : 1);
	return {
		bytes: payloadBytes,
		didReachEnd: !sourceHasMoreBytes,
		endsMidLine: sourceHasMoreBytes && !endsWithNewline,
		endsWithNewline,
		isBinary,
		isValidUTF8,
		payloadLineCount,
		sha256: createHash('sha256').update(payloadBytes).digest('hex'),
		truncationKind: truncationKindForPrefix({
			payloadLineCount,
			reachedByteLimit,
			reachedLineLimit,
			sourceHasMoreBytes,
			maximumLines: limits.maximumLines,
		}),
	};
}

function canonicalizeSplitUTF8Scalar(
	payloadBytes: Uint8Array,
	sourceBytes: Uint8Array,
	boundaryOffset: number,
): Uint8Array<ArrayBuffer> | null {
	const incompleteScalar = incompleteUTF8Scalar(payloadBytes);
	if (incompleteScalar === null) return null;
	const requiredContinuationByteCount =
		incompleteScalar.expectedByteCount - incompleteScalar.retainedByteCount;
	const scalarStartOffset = payloadBytes.byteLength - incompleteScalar.retainedByteCount;
	const boundaryScalar = new Uint8Array(incompleteScalar.expectedByteCount);
	boundaryScalar.set(payloadBytes.subarray(scalarStartOffset), 0);
	boundaryScalar.set(
		sourceBytes.subarray(boundaryOffset, boundaryOffset + requiredContinuationByteCount),
		incompleteScalar.retainedByteCount,
	);
	const candidate = Uint8Array.from(payloadBytes.subarray(0, scalarStartOffset));
	return isValidUTF8Bytes(boundaryScalar) && isValidUTF8Bytes(candidate) ? candidate : null;
}

function incompleteUTF8Scalar(payloadBytes: Uint8Array): IncompleteUTF8Scalar | null {
	const finalByte = payloadBytes.at(-1);
	if (finalByte === undefined || finalByte < 0x80) return null;
	let scalarStart = payloadBytes.byteLength - 1;
	while (scalarStart > 0 && isUTF8ContinuationByte(payloadBytes[scalarStart] ?? 0)) {
		scalarStart -= 1;
	}
	const leadByte = payloadBytes[scalarStart];
	if (leadByte === undefined) return null;
	const expectedByteCount = utf8ScalarByteCount(leadByte);
	const retainedByteCount = payloadBytes.byteLength - scalarStart;
	return expectedByteCount > retainedByteCount ? { expectedByteCount, retainedByteCount } : null;
}

function utf8ScalarByteCount(leadByte: number): number {
	if ((leadByte & 0xe0) === 0xc0) return 2;
	if ((leadByte & 0xf0) === 0xe0) return 3;
	if ((leadByte & 0xf8) === 0xf0) return 4;
	return 1;
}

function isUTF8ContinuationByte(byte: number): boolean {
	return (byte & 0xc0) === 0x80;
}

function isValidUTF8Bytes(bytes: Uint8Array): boolean {
	try {
		strictUTF8Decoder.decode(bytes);
		return true;
	} catch {
		return false;
	}
}

function truncationKindForPrefix(props: {
	readonly maximumLines: number;
	readonly payloadLineCount: number;
	readonly reachedByteLimit: boolean;
	readonly reachedLineLimit: boolean;
	readonly sourceHasMoreBytes: boolean;
}): BridgeProductDevFileTruncationKind {
	if (!props.sourceHasMoreBytes) return 'none';
	const hitByteLimit = props.reachedByteLimit;
	const hitLineLimit = props.reachedLineLimit || props.payloadLineCount === props.maximumLines;
	if (hitByteLimit && hitLineLimit) return 'both';
	if (hitLineLimit) return 'lineLimit';
	return 'byteLimit';
}

function assertPositiveSafeInteger(value: number, name: string): void {
	if (!Number.isSafeInteger(value) || value <= 0) {
		throw new Error(`Bridge product dev File prefix ${name} must be a positive safe integer.`);
	}
}

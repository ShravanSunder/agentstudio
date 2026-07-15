import { expect } from 'vitest';

import {
	countFileContentByte,
	fileContentSha256Hex,
	logicalFileContentLineCount,
	makeFileDescriptor,
	makeSourceAcceptedMetadataEvent,
	makeTreeWindowMetadataEvent,
	type FileDescriptorReadyEvent,
	type FileMetadataEvent,
} from './bridge-file-viewer-browser-test-fixtures.js';
import { actFrame, openFileState } from './bridge-file-viewer-browser-test-harness.js';

export const completeFileDeepScrollTreeRowCount = 3_420;
const completeFileDeepScrollTreeWindowRowCount = 256;

export const completeFileDeepScrollFixture = createCompleteFileDeepScrollFixture();

export interface DeepScrollSurfacePaintSnapshot {
	readonly clientRectCount: number;
	readonly height: number;
	readonly opacity: string;
	readonly visibility: string;
	readonly width: number;
}

export function makeCompleteFileDeepScrollDescriptor(props: {
	readonly contentHandle: string;
	readonly fileId: string;
	readonly path: string;
}): FileDescriptorReadyEvent {
	return makeFileDescriptor({
		contentExpectedBytes: completeFileDeepScrollFixture.byteCount,
		contentExpectedSha256: completeFileDeepScrollFixture.sha256,
		contentHandle: props.contentHandle,
		contentMaxBytes: completeFileDeepScrollFixture.byteCount,
		endsWithNewline: false,
		fileId: props.fileId,
		lineCount: completeFileDeepScrollFixture.lineCount,
		path: props.path,
	});
}

export function makeCompleteFileDeepScrollMetadataEvents(
	descriptor: FileDescriptorReadyEvent,
): readonly FileMetadataEvent[] {
	const treeWindowEvents: FileMetadataEvent[] = [];
	for (
		let startIndex = 0;
		startIndex < completeFileDeepScrollTreeRowCount;
		startIndex += completeFileDeepScrollTreeWindowRowCount
	) {
		treeWindowEvents.push(
			makeTreeWindowMetadataEvent({
				rowCount: Math.min(
					completeFileDeepScrollTreeWindowRowCount,
					completeFileDeepScrollTreeRowCount - startIndex,
				),
				sequence: startIndex / completeFileDeepScrollTreeWindowRowCount + 1,
				sourceIdentity: descriptor.source,
				startIndex,
				totalPathCount: completeFileDeepScrollTreeRowCount,
			}),
		);
	}
	return [makeSourceAcceptedMetadataEvent(descriptor.source), ...treeWindowEvents, descriptor];
}

export async function assertCompleteFileDeepScrollSourceOracle(): Promise<void> {
	expect(completeFileDeepScrollFixture.bytes.byteLength).toBe(
		completeFileDeepScrollFixture.byteCount,
	);
	expect(completeFileDeepScrollFixture.bytes.byteLength).toBeGreaterThan(2 * 1024 * 1024);
	expect(logicalFileContentLineCount(completeFileDeepScrollFixture.bytes)).toBe(
		completeFileDeepScrollFixture.lineCount,
	);
	expect(countFileContentByte(completeFileDeepScrollFixture.bytes, 0x0d)).toBe(10_000);
	expect(countFileContentByte(completeFileDeepScrollFixture.bytes, 0x0a)).toBe(10_000);
	expect(
		completeFileDeepScrollFixture.text.endsWith(completeFileDeepScrollFixture.finalSourceText),
	).toBe(true);
	expect(
		completeFileDeepScrollFixture.text.split(completeFileDeepScrollFixture.finalSourceText),
	).toHaveLength(2);
	expect(completeFileDeepScrollFixture.text.endsWith('\n')).toBe(false);
	expect(await fileContentSha256Hex(completeFileDeepScrollFixture.bytes)).toBe(
		completeFileDeepScrollFixture.sha256,
	);
}

export function makeCorruptedCompleteFileDeepScrollContent(): {
	readonly bytes: Uint8Array<ArrayBuffer>;
	readonly text: string;
} {
	const bytes = completeFileDeepScrollFixture.bytes.slice();
	for (let index = Math.floor(bytes.byteLength / 2); index < bytes.byteLength; index += 1) {
		if (bytes[index] !== 0x78) continue;
		bytes[index] = 0x79;
		return { bytes, text: new TextDecoder('utf-8', { fatal: true }).decode(bytes) };
	}
	throw new Error('Complete File corruption fixture contains no middle filler byte.');
}

export async function waitForCompleteFileDeepScrollTerminalState(
	attempt = 0,
): Promise<'failed' | 'ready' | 'unavailable'> {
	const state = openFileState();
	if (state === 'failed' || state === 'ready' || state === 'unavailable') return state;
	if (attempt >= 120) {
		throw new Error(`Complete File digest witness did not terminate; state=${state}.`);
	}
	await actFrame();
	return waitForCompleteFileDeepScrollTerminalState(attempt + 1);
}

function createCompleteFileDeepScrollFixture(): {
	readonly byteCount: number;
	readonly bytes: Uint8Array<ArrayBuffer>;
	readonly finalSourceText: string;
	readonly firstSourceText: string;
	readonly lineCount: number;
	readonly sha256: string;
	readonly text: string;
} {
	const byteCount = 2_097_217;
	const lineCount = 10_001;
	const finalSourceText = 'line-10001: __BRIDGE_FILE_COMPLETE_FINAL_CANARY_8B3F27D1__ λ😀';
	const regularCRLFLineByteCount = 209;
	const boundaryLineByteCount = 2 * 1024 * 1024 - (lineCount - 2) * regularCRLFLineByteCount;
	const lines = Array.from({ length: lineCount - 2 }, (_value, lineOffset) =>
		makeExactCompleteFileCRLFLine({
			prefix: `line-${String(lineOffset + 1).padStart(5, '0')}: λ😀 `,
			totalByteCount: regularCRLFLineByteCount,
		}),
	);
	lines.push(
		makeExactCompleteFileCRLFLine({
			prefix: 'line-10000: boundary λ😀 ',
			totalByteCount: boundaryLineByteCount,
		}),
	);
	const text = `${lines.join('')}${finalSourceText}`;
	return {
		byteCount,
		bytes: new TextEncoder().encode(text),
		finalSourceText,
		firstSourceText: 'line-00001: λ😀',
		lineCount,
		sha256: 'c15344b0a2aabc7a0f63ddda2d79d604bce142de7228fc3f36162db775a6cbda',
		text,
	};
}

function makeExactCompleteFileCRLFLine(props: {
	readonly prefix: string;
	readonly totalByteCount: number;
}): string {
	const prefixByteCount = new TextEncoder().encode(props.prefix).byteLength;
	const fillerByteCount = props.totalByteCount - prefixByteCount - 2;
	if (!Number.isSafeInteger(fillerByteCount) || fillerByteCount < 0) {
		throw new Error('Complete File source line cannot satisfy its exact byte contract.');
	}
	return `${props.prefix}${'x'.repeat(fillerByteCount)}\r\n`;
}

import type { BridgeWorkerTransferDescriptor } from './bridge-worker-contracts.js';

export type BridgeWorkerTransferMode = 'transfer' | 'clone';

export interface BridgeWorkerTransferFieldDeclaration {
	readonly fieldPath: readonly string[];
	readonly mode: BridgeWorkerTransferMode;
}

export interface BuildBridgeWorkerTransferListProps {
	readonly messageKind: string;
	readonly payload: Record<string, unknown>;
	readonly declaredFields: readonly BridgeWorkerTransferFieldDeclaration[];
}

export interface BridgeWorkerTransferPlan {
	readonly descriptors: readonly BridgeWorkerTransferDescriptor[];
	readonly transferList: readonly Transferable[];
}

export function buildBridgeWorkerTransferList(
	props: BuildBridgeWorkerTransferListProps,
): BridgeWorkerTransferPlan {
	const declaredPaths = new Set(
		props.declaredFields.map((field) => serializeBridgeWorkerFieldPath(field.fieldPath)),
	);
	for (const discoveredPath of findArrayBufferPaths(props.payload)) {
		if (!declaredPaths.has(serializeBridgeWorkerFieldPath(discoveredPath))) {
			throw new Error(
				`Bridge worker payload contains undeclared ArrayBuffer at ${discoveredPath.join('.')}.`,
			);
		}
	}

	const descriptors: BridgeWorkerTransferDescriptor[] = [];
	const transferList: Transferable[] = [];
	for (const field of props.declaredFields) {
		const value = readBridgeWorkerFieldPath(props.payload, field.fieldPath);
		const buffer = normalizeArrayBuffer(value);
		if (buffer === null) {
			throw new Error(
				`Bridge worker transfer field ${field.fieldPath.join('.')} is not an ArrayBuffer.`,
			);
		}
		descriptors.push({
			messageKind: props.messageKind,
			fieldPath: [...field.fieldPath],
			byteLength: buffer.byteLength,
			mode: field.mode,
		});
		if (field.mode === 'transfer') {
			transferList.push(buffer);
		}
	}

	return {
		descriptors,
		transferList,
	};
}

function serializeBridgeWorkerFieldPath(fieldPath: readonly string[]): string {
	return fieldPath.join('\u0000');
}

function readBridgeWorkerFieldPath(value: unknown, fieldPath: readonly string[]): unknown {
	let currentValue = value;
	for (const segment of fieldPath) {
		if (!isRecord(currentValue)) {
			return undefined;
		}
		currentValue = currentValue[segment];
	}
	return currentValue;
}

function findArrayBufferPaths(value: unknown, path: readonly string[] = []): readonly string[][] {
	const buffer = normalizeArrayBuffer(value);
	if (buffer !== null) {
		return [[...path]];
	}
	if (Array.isArray(value)) {
		return value.flatMap((item, index) => findArrayBufferPaths(item, [...path, String(index)]));
	}
	if (!isRecord(value)) {
		return [];
	}
	return Object.entries(value).flatMap(([key, entry]) =>
		findArrayBufferPaths(entry, [...path, key]),
	);
}

function normalizeArrayBuffer(value: unknown): ArrayBuffer | null {
	if (value instanceof ArrayBuffer) {
		return value;
	}
	if (ArrayBuffer.isView(value)) {
		return value.buffer instanceof ArrayBuffer ? value.buffer : null;
	}
	return null;
}

function isRecord(value: unknown): value is Record<string, unknown> {
	return typeof value === 'object' && value !== null;
}

import type {
	BridgeWorkerMainToServerMessage,
	BridgeWorkerServerToMainMessage,
	BridgeWorkerTransferDescriptor,
} from './bridge-worker-contracts.js';

export type BridgeWorkerTransferMode = 'transfer' | 'clone';

export interface BridgeWorkerTransferFieldDeclaration {
	readonly fieldPath: readonly string[];
	readonly mode: BridgeWorkerTransferMode;
	readonly byteLength?: number;
}

export type BridgeWorkerMessageWithTransferDescriptors =
	| BridgeWorkerMainToServerMessage
	| BridgeWorkerServerToMainMessage;

export type BridgeWorkerPreparedStructuredMessage<
	TMessage extends BridgeWorkerMessageWithTransferDescriptors,
> = TMessage & {
	readonly transferDescriptors: readonly BridgeWorkerTransferDescriptor[];
};

export interface BuildBridgeWorkerTransferListProps<TPayload extends object> {
	readonly messageKind: string;
	readonly payload: TPayload;
	readonly declaredFields: readonly BridgeWorkerTransferFieldDeclaration[];
}

export interface BridgeWorkerTransferPlan {
	readonly descriptors: readonly BridgeWorkerTransferDescriptor[];
	readonly transferList: readonly Transferable[];
}

export interface PrepareBridgeWorkerStructuredMessageProps<
	TMessage extends BridgeWorkerMessageWithTransferDescriptors,
> {
	readonly message: TMessage;
	readonly declaredFields: readonly BridgeWorkerTransferFieldDeclaration[];
}

export interface PreparedBridgeWorkerStructuredMessage<
	TMessage extends BridgeWorkerMessageWithTransferDescriptors,
> {
	readonly message: BridgeWorkerPreparedStructuredMessage<TMessage>;
	readonly transferList: readonly Transferable[];
}

export function buildBridgeWorkerTransferList<TPayload extends object>(
	props: BuildBridgeWorkerTransferListProps<TPayload>,
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
		const byteLength = bridgeWorkerDeclaredFieldByteLength({ field, value });
		descriptors.push({
			messageKind: props.messageKind,
			fieldPath: [...field.fieldPath],
			byteLength,
			mode: field.mode,
		});
		if (field.mode === 'transfer') {
			const buffer = normalizeArrayBuffer(value);
			if (buffer === null) {
				throw new Error(
					`Bridge worker transfer field ${field.fieldPath.join('.')} is not an ArrayBuffer.`,
				);
			}
			transferList.push(buffer);
		}
	}

	return {
		descriptors,
		transferList,
	};
}

function bridgeWorkerDeclaredFieldByteLength(props: {
	readonly field: BridgeWorkerTransferFieldDeclaration;
	readonly value: unknown;
}): number {
	if (props.field.mode === 'clone' && props.value === undefined) {
		throw new Error(
			`Bridge worker clone field ${props.field.fieldPath.join('.')} does not resolve.`,
		);
	}
	if (props.field.byteLength !== undefined) {
		return Math.max(0, Math.floor(props.field.byteLength));
	}
	const buffer = normalizeArrayBuffer(props.value);
	if (buffer !== null) {
		return buffer.byteLength;
	}
	if (typeof props.value === 'string') {
		return new TextEncoder().encode(props.value).byteLength;
	}
	if (props.field.mode === 'clone') {
		throw new Error(
			`Bridge worker clone field ${props.field.fieldPath.join('.')} requires a declared byte length.`,
		);
	}
	throw new Error(
		`Bridge worker transfer field ${props.field.fieldPath.join('.')} is not an ArrayBuffer.`,
	);
}

export function prepareBridgeWorkerStructuredMessage<
	TMessage extends BridgeWorkerMessageWithTransferDescriptors,
>(
	props: PrepareBridgeWorkerStructuredMessageProps<TMessage>,
): PreparedBridgeWorkerStructuredMessage<TMessage> {
	const transferPlan = buildBridgeWorkerTransferList({
		messageKind: props.message.kind,
		payload: props.message,
		declaredFields: props.declaredFields,
	});
	const message = {
		...props.message,
		transferDescriptors: transferPlan.descriptors,
	};
	return {
		message,
		transferList: transferPlan.transferList,
	};
}

export function cloneBridgeWorkerStructuredMessage<
	TMessage extends BridgeWorkerMessageWithTransferDescriptors,
>(message: TMessage): TMessage {
	return structuredClone(message);
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

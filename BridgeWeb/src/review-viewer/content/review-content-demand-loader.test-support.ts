import { expect } from 'vitest';

import type {
	BridgeAttachedResourceDescriptor,
	BridgeDescriptorRef,
} from '../../core/models/bridge-resource-descriptor.js';
import { bridgeAttachedResourceDescriptorSchema } from '../../core/models/bridge-resource-descriptor.js';
import { createBridgeResourceDescriptorRegistry } from '../../core/resources/bridge-resource-registry.js';
import type { BridgeTextResourceStreamResult } from '../../core/resources/bridge-resource-stream.js';
import { makeBridgeReviewPackage } from '../../foundation/review-package/bridge-review-package-test-support.js';
import type { BridgeContentHandle } from '../../foundation/review-package/bridge-review-package.js';
import type { BridgeTelemetrySample } from '../../foundation/telemetry/bridge-telemetry-event.js';
import type {
	BridgeTelemetryFlushProps,
	BridgeTelemetryMeasureProps,
	BridgeTelemetryRecorder,
} from '../../foundation/telemetry/bridge-telemetry-recorder.js';
import type { BridgeTelemetryScope } from '../../foundation/telemetry/bridge-telemetry-scope.js';

export interface TestTelemetryRecorder extends BridgeTelemetryRecorder {
	readonly samples: BridgeTelemetrySample[];
	readonly flushForces: readonly boolean[];
}

export function makeTelemetryRecorder(): TestTelemetryRecorder {
	const samples: BridgeTelemetrySample[] = [];
	const flushForces: boolean[] = [];
	return {
		samples,
		flushForces,
		isEnabled: (scope: BridgeTelemetryScope): boolean => scope === 'web',
		record: (sample: BridgeTelemetrySample): void => {
			samples.push(sample);
		},
		measure: <TResult>(props: BridgeTelemetryMeasureProps<TResult>): TResult => props.operation(),
		flush: (props?: BridgeTelemetryFlushProps): boolean => {
			flushForces.push(props?.force === true);
			return true;
		},
	};
}

export interface Deferred<TValue> {
	readonly promise: Promise<TValue>;
	readonly resolve: (value: TValue) => void;
}

export function createDeferred<TValue>(): Deferred<TValue> {
	let resolveDeferred: ((value: TValue) => void) | null = null;
	const promise = new Promise<TValue>((resolve): void => {
		resolveDeferred = resolve;
	});
	if (resolveDeferred === null) {
		throw new Error('Deferred was not initialized.');
	}
	return {
		promise,
		resolve: resolveDeferred,
	};
}

export async function flushMicrotasks(count: number): Promise<void> {
	let flushPromise = Promise.resolve();
	for (let index = 0; index < count; index += 1) {
		flushPromise = flushPromise.then((): void => {});
	}
	await flushPromise;
}

export function totalRequestCount(
	requestCountsByDescriptorId: ReadonlyMap<string, number>,
): number {
	let requestCount = 0;
	for (const descriptorRequestCount of requestCountsByDescriptorId.values()) {
		requestCount += descriptorRequestCount;
	}
	return requestCount;
}

interface RegisterPackageContentDescriptorsProps {
	readonly registry: ReturnType<typeof createBridgeResourceDescriptorRegistry>;
	readonly reviewPackage: ReturnType<typeof makeBridgeReviewPackage>;
}

export function registerPackageContentDescriptors(
	props: RegisterPackageContentDescriptorsProps,
): ReadonlyMap<string, BridgeAttachedResourceDescriptor> {
	const descriptorsByHandleId = new Map<string, BridgeAttachedResourceDescriptor>();
	for (const item of Object.values(props.reviewPackage.itemsById)) {
		for (const handle of [
			item.contentRoles.base,
			item.contentRoles.head,
			item.contentRoles.diff,
			item.contentRoles.file,
		]) {
			if (handle === null || handle === undefined) {
				continue;
			}
			const attachedDescriptor = attachedDescriptorForHandle(handle);
			expect(props.registry.register(attachedDescriptor)).toEqual({ ok: true });
			descriptorsByHandleId.set(handle.handleId, attachedDescriptor);
		}
	}
	return descriptorsByHandleId;
}

function attachedDescriptorForHandle(
	handle: BridgeContentHandle,
): BridgeAttachedResourceDescriptor {
	const descriptorId = `descriptor-${handle.handleId}`;
	const identity = {
		paneId: 'pane-1',
		protocol: 'review',
		sourceId: 'source-1',
		packageId: 'package-1',
		generation: handle.reviewGeneration,
		revision: 1,
	};
	const descriptor = {
		descriptorId,
		protocol: 'review',
		resourceKind: 'content',
		resourceUrl: `agentstudio://resource/review/content/${descriptorId}?generation=1&revision=1`,
		identity,
		content: {
			mediaType: handle.mimeType,
			encoding: 'utf-8',
			expectedBytes: handle.sizeBytes,
			maxBytes: 1024,
		},
	};
	return bridgeAttachedResourceDescriptorSchema.parse({
		ref: {
			descriptorId,
			expectedProtocol: 'review',
			expectedResourceKind: 'content',
			expectedIdentity: identity,
		},
		descriptor,
	});
}

export function makeUnrelatedDescriptorRef(): BridgeDescriptorRef {
	return {
		descriptorId: 'unrelated-descriptor',
		expectedProtocol: 'review',
		expectedResourceKind: 'content',
		expectedIdentity: {
			paneId: 'pane-1',
			protocol: 'review',
			sourceId: 'source-1',
			packageId: 'other-package',
			generation: 1,
			revision: 1,
		},
	};
}

export function makeTextStreamResult(text: string): BridgeTextResourceStreamResult {
	return {
		authoritative: true,
		byteLength: new TextEncoder().encode(text).byteLength,
		readText: (): string => text,
	};
}

export function makeBridgeReviewPackageWithContentRoleBytes(
	sizeBytes: number,
): ReturnType<typeof makeBridgeReviewPackage> {
	const reviewPackage = makeBridgeReviewPackage();
	const sourceItem = reviewPackage.itemsById['item-source'];
	if (sourceItem === undefined) {
		throw new Error('expected source item fixture');
	}
	return {
		...reviewPackage,
		itemsById: {
			...reviewPackage.itemsById,
			'item-source': {
				...sourceItem,
				contentRoles: {
					...sourceItem.contentRoles,
					base: contentHandleWithSize(sourceItem.contentRoles.base, sizeBytes),
					head: contentHandleWithSize(sourceItem.contentRoles.head, sizeBytes),
				},
			},
		},
	};
}

function contentHandleWithSize(
	handle: BridgeContentHandle | null | undefined,
	sizeBytes: number,
): BridgeContentHandle | null {
	return handle === null || handle === undefined ? null : { ...handle, sizeBytes };
}

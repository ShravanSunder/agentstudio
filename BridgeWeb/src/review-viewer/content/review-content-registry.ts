import { z } from 'zod';

import { parseBridgeResourceUrl } from '../../bridge/bridge-resource-url.js';
import {
	loadBridgeContentResource,
	type BridgeContentResource,
	type BridgeLoadedContentResource,
	type LoadBridgeContentResourceProps,
} from '../../foundation/content/content-resource-loader.js';
import type { BridgeContentHandle } from '../../foundation/review-package/bridge-review-package.js';

export const bridgeReviewContentRegistryIdentitySchema = z
	.object({
		packageId: z.string().min(1),
		reviewGeneration: z.number().int().nonnegative(),
		revision: z.number().int().nonnegative(),
	})
	.strict();

export type BridgeReviewContentRegistryIdentity = z.infer<
	typeof bridgeReviewContentRegistryIdentitySchema
>;

export interface BridgeReviewContentRegistry {
	readonly clear: () => void;
	readonly evictResourceKeys: (resourceKeys: readonly string[]) => number;
	readonly load: (props: LoadBridgeContentResourceProps) => Promise<BridgeLoadedContentResource>;
	readonly peekResource: (handle: BridgeContentHandle) => BridgeLoadedContentResource | null;
	readonly setActiveIdentity: (identity: BridgeReviewContentRegistryIdentity | null) => void;
	readonly storeResource: (props: StoreBridgeReviewContentResourceProps) => void;
	readonly snapshot: () => BridgeReviewContentRegistrySnapshot;
}

export interface StoreBridgeReviewContentResourceProps {
	readonly resource: BridgeContentResource;
}

export interface BridgeReviewContentRegistrySnapshot {
	readonly activeIdentity: BridgeReviewContentRegistryIdentity | null;
	readonly cachedResourceCount: number;
	readonly inFlightRequestCount: number;
	readonly cachedResourceKeys: readonly string[];
}

export interface CreateBridgeReviewContentRegistryProps {
	readonly maxEntries?: number;
}

interface RegistryEntry {
	readonly generation: number;
	readonly revision: number | null;
	readonly resource: BridgeLoadedContentResource;
}

const defaultMaxEntries = 96;

export function createBridgeReviewContentRegistry(
	props: CreateBridgeReviewContentRegistryProps = {},
): BridgeReviewContentRegistry {
	const maxEntries = Math.max(1, props.maxEntries ?? defaultMaxEntries);
	const entriesByResourceKey = new Map<string, RegistryEntry>();
	const inFlightByResourceKey = new Map<string, Promise<BridgeLoadedContentResource>>();
	let activeIdentity: BridgeReviewContentRegistryIdentity | null = null;
	let registryEpoch = 0;

	const clear = (): void => {
		registryEpoch += 1;
		entriesByResourceKey.clear();
		inFlightByResourceKey.clear();
	};

	const setActiveIdentity = (identity: BridgeReviewContentRegistryIdentity | null): void => {
		const parsedIdentity =
			identity === null ? null : bridgeReviewContentRegistryIdentitySchema.parse(identity);
		if (!registryIdentitiesMatch(activeIdentity, parsedIdentity)) {
			clear();
			activeIdentity = parsedIdentity;
			return;
		}
		activeIdentity = parsedIdentity;
	};

	const load = async (
		loadProps: LoadBridgeContentResourceProps,
	): Promise<BridgeLoadedContentResource> => {
		const resourceKey = canonicalContentResourceKey(loadProps.handle);
		const identity = activeIdentity;
		if (identity !== null) {
			const handleRevision = revisionForHandle(loadProps.handle);
			if (
				loadProps.handle.reviewGeneration !== identity.reviewGeneration ||
				(handleRevision !== null && handleRevision !== identity.revision)
			) {
				throw new Error('Bridge content registry rejected stale content identity');
			}
		}

		const cachedEntry = entriesByResourceKey.get(resourceKey);
		if (cachedEntry !== undefined) {
			entriesByResourceKey.delete(resourceKey);
			entriesByResourceKey.set(resourceKey, cachedEntry);
			return cachedEntry.resource;
		}

		const inFlight = inFlightByResourceKey.get(resourceKey);
		if (inFlight !== undefined) {
			return await inFlight;
		}

		const requestEpoch = registryEpoch;
		const request = loadBridgeContentResource(sharedRequestProps(loadProps))
			.then((resource: BridgeLoadedContentResource): BridgeLoadedContentResource => {
				if (requestEpoch !== registryEpoch) {
					throw new Error('Bridge content registry discarded stale in-flight content');
				}
				if (resource.authoritative) {
					entriesByResourceKey.set(resourceKey, {
						generation: loadProps.handle.reviewGeneration,
						revision: revisionForHandle(loadProps.handle),
						resource,
					});
					evictOldEntries(entriesByResourceKey, maxEntries);
				}
				return resource;
			})
			.finally((): void => {
				inFlightByResourceKey.delete(resourceKey);
			});
		inFlightByResourceKey.set(resourceKey, request);
		return await request;
	};

	const matchesActiveIdentity = (handle: BridgeContentHandle): boolean => {
		const identity = activeIdentity;
		if (identity === null) {
			return true;
		}
		const handleRevision = revisionForHandle(handle);
		return (
			handle.reviewGeneration === identity.reviewGeneration &&
			(handleRevision === null || handleRevision === identity.revision)
		);
	};

	// Peek/store are opportunistic cache operations: identity mismatch during
	// a package switch is a miss, not a programmer error like `load`'s throw.
	const peekResource = (handle: BridgeContentHandle): BridgeLoadedContentResource | null => {
		if (!matchesActiveIdentity(handle)) {
			return null;
		}
		const resourceKey = canonicalContentResourceKey(handle);
		const cachedEntry = entriesByResourceKey.get(resourceKey);
		if (cachedEntry === undefined) {
			return null;
		}
		entriesByResourceKey.delete(resourceKey);
		entriesByResourceKey.set(resourceKey, cachedEntry);
		return cachedEntry.resource;
	};

	const storeResource = (storeProps: StoreBridgeReviewContentResourceProps): void => {
		const resource = storeProps.resource;
		if (resource.authoritative !== true || typeof resource.byteLength !== 'number') {
			return;
		}
		if (!matchesActiveIdentity(resource.handle)) {
			return;
		}
		const resourceKey = canonicalContentResourceKey(resource.handle);
		entriesByResourceKey.delete(resourceKey);
		entriesByResourceKey.set(resourceKey, {
			generation: resource.handle.reviewGeneration,
			revision: revisionForHandle(resource.handle),
			resource: {
				authoritative: resource.authoritative,
				byteLength: resource.byteLength,
				handle: resource.handle,
				readText: (): string => resource.readText(),
			},
		});
		evictOldEntries(entriesByResourceKey, maxEntries);
	};

	const evictResourceKeys = (resourceKeys: readonly string[]): number => {
		let evictedCount = 0;
		for (const resourceKey of resourceKeys) {
			if (entriesByResourceKey.delete(resourceKey)) {
				evictedCount += 1;
			}
		}
		return evictedCount;
	};

	const snapshot = (): BridgeReviewContentRegistrySnapshot => ({
		activeIdentity,
		cachedResourceCount: entriesByResourceKey.size,
		inFlightRequestCount: inFlightByResourceKey.size,
		cachedResourceKeys: [...entriesByResourceKey.keys()],
	});

	return {
		clear,
		evictResourceKeys,
		load,
		peekResource,
		setActiveIdentity,
		storeResource,
		snapshot,
	};
}

function sharedRequestProps(
	loadProps: LoadBridgeContentResourceProps,
): LoadBridgeContentResourceProps {
	return {
		handle: loadProps.handle,
		...(loadProps.fetchContent === undefined ? {} : { fetchContent: loadProps.fetchContent }),
		...(loadProps.integrity === undefined ? {} : { integrity: loadProps.integrity }),
		...(loadProps.maxBytes === undefined ? {} : { maxBytes: loadProps.maxBytes }),
		...(loadProps.traceContext === undefined ? {} : { traceContext: loadProps.traceContext }),
		...(loadProps.sendTraceparentHeader === undefined
			? {}
			: { sendTraceparentHeader: loadProps.sendTraceparentHeader }),
		...(loadProps.telemetryRecorder === undefined
			? {}
			: { telemetryRecorder: loadProps.telemetryRecorder }),
	};
}

export function canonicalContentResourceKey(handle: BridgeContentHandle): string {
	const parsedResourceUrl = parseBridgeResourceUrl(handle.resourceUrl);
	if (parsedResourceUrl?.kind !== 'content') {
		throw new Error('Bridge content registry requires a content resource URL');
	}
	if (
		parsedResourceUrl.handleId !== handle.handleId ||
		parsedResourceUrl.generation !== handle.reviewGeneration
	) {
		throw new Error('Bridge content registry resource URL does not match content handle');
	}
	return parsedResourceUrl.canonicalUrl;
}

function revisionForHandle(handle: BridgeContentHandle): number | null {
	const parsedResourceUrl = parseBridgeResourceUrl(handle.resourceUrl);
	if (parsedResourceUrl?.kind !== 'content') {
		throw new Error('Bridge content registry requires a content resource URL');
	}
	return parsedResourceUrl.revision ?? null;
}

function registryIdentitiesMatch(
	left: BridgeReviewContentRegistryIdentity | null,
	right: BridgeReviewContentRegistryIdentity | null,
): boolean {
	return (
		left?.packageId === right?.packageId &&
		left?.reviewGeneration === right?.reviewGeneration &&
		left?.revision === right?.revision
	);
}

function evictOldEntries(
	entriesByResourceKey: Map<string, RegistryEntry>,
	maxEntries: number,
): void {
	while (entriesByResourceKey.size > maxEntries) {
		const oldestResourceKey = entriesByResourceKey.keys().next().value;
		if (typeof oldestResourceKey !== 'string') {
			return;
		}
		entriesByResourceKey.delete(oldestResourceKey);
	}
}

import { z } from 'zod';

import { parseBridgeCoreResourceUrl } from '../../core/resources/bridge-resource-url.js';
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
const reviewContentResourceKindsByProtocol = {
	review: new Set(['content']),
};

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

	// Revision-only changes retain the cache: entries are keyed by content
	// hash, so an unchanged file at a new revision is still a valid hit and
	// a changed file misses by construction. Package/generation changes are
	// stream epochs and clear everything.
	const setActiveIdentity = (identity: BridgeReviewContentRegistryIdentity | null): void => {
		const parsedIdentity =
			identity === null ? null : bridgeReviewContentRegistryIdentitySchema.parse(identity);
		if (!registryIdentitiesRetainContent(activeIdentity, parsedIdentity)) {
			clear();
		}
		activeIdentity = parsedIdentity;
	};

	const load = async (
		loadProps: LoadBridgeContentResourceProps,
	): Promise<BridgeLoadedContentResource> => {
		const inFlightKey = canonicalContentResourceKey(loadProps.handle);
		const contentKey = contentAddressedResourceKey(loadProps.handle);
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

		if (contentKey !== null) {
			const cachedEntry = entriesByResourceKey.get(contentKey);
			if (cachedEntry !== undefined) {
				entriesByResourceKey.delete(contentKey);
				entriesByResourceKey.set(contentKey, cachedEntry);
				return resourceForHandle(cachedEntry.resource, loadProps.handle);
			}
		}

		const inFlight = inFlightByResourceKey.get(inFlightKey);
		if (inFlight !== undefined) {
			return await inFlight;
		}

		const requestEpoch = registryEpoch;
		const request = loadBridgeContentResource(sharedRequestProps(loadProps))
			.then((resource: BridgeLoadedContentResource): BridgeLoadedContentResource => {
				if (requestEpoch !== registryEpoch) {
					throw new Error('Bridge content registry discarded stale in-flight content');
				}
				if (resource.authoritative && contentKey !== null) {
					entriesByResourceKey.set(contentKey, {
						generation: loadProps.handle.reviewGeneration,
						revision: revisionForHandle(loadProps.handle),
						resource,
					});
					evictOldEntries(entriesByResourceKey, maxEntries);
				}
				return resource;
			})
			.finally((): void => {
				inFlightByResourceKey.delete(inFlightKey);
			});
		inFlightByResourceKey.set(inFlightKey, request);
		return await request;
	};

	// Generation is the only identity gate for cache participation: the
	// content hash in the key carries per-file freshness across revisions.
	const matchesActiveIdentity = (handle: BridgeContentHandle): boolean => {
		const identity = activeIdentity;
		return identity === null || handle.reviewGeneration === identity.reviewGeneration;
	};

	// Peek/store are opportunistic cache operations: identity mismatch during
	// a package switch is a miss, not a programmer error like `load`'s throw.
	const peekResource = (handle: BridgeContentHandle): BridgeLoadedContentResource | null => {
		if (!matchesActiveIdentity(handle)) {
			return null;
		}
		const contentKey = contentAddressedResourceKey(handle);
		if (contentKey === null) {
			return null;
		}
		const cachedEntry = entriesByResourceKey.get(contentKey);
		if (cachedEntry === undefined) {
			return null;
		}
		entriesByResourceKey.delete(contentKey);
		entriesByResourceKey.set(contentKey, cachedEntry);
		return resourceForHandle(cachedEntry.resource, handle);
	};

	const storeResource = (storeProps: StoreBridgeReviewContentResourceProps): void => {
		const resource = storeProps.resource;
		if (resource.authoritative !== true || typeof resource.byteLength !== 'number') {
			return;
		}
		if (!matchesActiveIdentity(resource.handle)) {
			return;
		}
		const contentKey = contentAddressedResourceKey(resource.handle);
		if (contentKey === null) {
			return;
		}
		entriesByResourceKey.delete(contentKey);
		entriesByResourceKey.set(contentKey, {
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
	const parsedResourceUrl = parseReviewContentResourceUrl(handle.resourceUrl);
	if (parsedResourceUrl === null) {
		throw new Error('Bridge content registry requires a content resource URL');
	}
	if (
		parsedResourceUrl.opaqueId !== handle.handleId ||
		parsedResourceUrl.generation !== handle.reviewGeneration
	) {
		throw new Error('Bridge content registry resource URL does not match content handle');
	}
	return parsedResourceUrl.canonicalUrl;
}

function revisionForHandle(handle: BridgeContentHandle): number | null {
	const parsedResourceUrl = parseReviewContentResourceUrl(handle.resourceUrl);
	if (parsedResourceUrl === null) {
		throw new Error('Bridge content registry requires a content resource URL');
	}
	return parsedResourceUrl.revision ?? null;
}

function parseReviewContentResourceUrl(
	resourceUrl: string,
): ReturnType<typeof parseBridgeCoreResourceUrl> {
	const parsedResourceUrl = parseBridgeCoreResourceUrl(resourceUrl, {
		allowedResourceKindsByProtocol: reviewContentResourceKindsByProtocol,
	});
	return parsedResourceUrl?.protocol === 'review' && parsedResourceUrl.resourceKind === 'content'
		? parsedResourceUrl
		: null;
}

function registryIdentitiesRetainContent(
	left: BridgeReviewContentRegistryIdentity | null,
	right: BridgeReviewContentRegistryIdentity | null,
): boolean {
	return left?.packageId === right?.packageId && left?.reviewGeneration === right?.reviewGeneration;
}

/** Content-addressed cache key, or null for sentinel hashes the native side
 * emits when a git OID is unavailable ("unknown", "missing-base", or a diff
 * composite with a missing side) — those identities are ambiguous between
 * different dirty states and must never be cached. */
export function contentAddressedResourceKey(handle: BridgeContentHandle): string | null {
	if (!isCacheableContentHash(handle.contentHash)) {
		return null;
	}
	return [handle.itemId, handle.role, handle.contentHashAlgorithm, handle.contentHash].join(
		'\u0000',
	);
}

function isCacheableContentHash(contentHash: string): boolean {
	if (contentHash.length === 0 || contentHash === 'unknown' || contentHash === 'missing-base') {
		return false;
	}
	return !contentHash.includes('none');
}

/** A cache hit for a new-revision handle re-attaches the requesting handle:
 * the body is content-identical, but consumers read handle metadata (resource
 * URLs, revision) from the resource and must see the current identity. */
function resourceForHandle(
	resource: BridgeLoadedContentResource,
	handle: BridgeContentHandle,
): BridgeLoadedContentResource {
	if (resource.handle === handle) {
		return resource;
	}
	return {
		authoritative: resource.authoritative,
		byteLength: resource.byteLength,
		handle,
		readText: (): string => resource.readText(),
	};
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

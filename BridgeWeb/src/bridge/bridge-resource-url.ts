import { z } from 'zod';

export const bridgeResourceKindSchema = z.enum(['content', 'worktreeResource']);
export const bridgeWorktreeResourceKindSchema = z.enum([
	'worktree.fileContent',
	'worktree.fileRange',
]);

export const bridgeWholeResourceRangeSchema = z.object({ kind: z.literal('whole') }).strict();
export const bridgeCursorResourceRangeSchema = z
	.object({
		kind: z.literal('cursor'),
		cursor: z.string().min(1),
		depth: z.number().int().nonnegative(),
	})
	.strict();

export const bridgeResourceRangeSchema = z.discriminatedUnion('kind', [
	bridgeWholeResourceRangeSchema,
	bridgeCursorResourceRangeSchema,
]);

export type BridgeResourceKind = z.infer<typeof bridgeResourceKindSchema>;
export type BridgeWorktreeResourceKind = z.infer<typeof bridgeWorktreeResourceKindSchema>;
export type BridgeResourceRange = z.infer<typeof bridgeResourceRangeSchema>;
export type BridgeWholeResourceRange = z.infer<typeof bridgeWholeResourceRangeSchema>;
export type BridgeCursorResourceRange = z.infer<typeof bridgeCursorResourceRangeSchema>;

export interface BridgeContentResourceUrl {
	readonly kind?: 'content';
	readonly handleId: string;
	readonly generation: number;
	readonly revision?: number;
	readonly range?: BridgeWholeResourceRange;
	readonly canonicalUrl?: string;
}

export interface BridgeWorkerFetchProbeContentResourceUrlProps {
	readonly handleId: string;
	readonly generation: number;
	readonly revision?: number;
}

export interface BridgeParsedContentResourceUrl {
	readonly kind: 'content';
	readonly handleId: string;
	readonly generation: number;
	readonly revision?: number;
	readonly range: BridgeWholeResourceRange;
	readonly canonicalUrl: string;
}

export interface BridgeWorktreeResourceUrl {
	readonly kind: 'worktreeResource';
	readonly resourceKind: BridgeWorktreeResourceKind;
	readonly resourceId: string;
	readonly generation: number;
	readonly cursor: string;
	readonly canonicalUrl: string;
}

export type BridgeResourceUrl = BridgeParsedContentResourceUrl | BridgeWorktreeResourceUrl;

type QueryEntries = ReadonlyMap<string, readonly string[]>;

const resourceProtocol = 'agentstudio:';
const resourceHost = 'resource';
const traversalPattern = /(?:^|\/)\.\.?(?:\/|$)/u;

export function parseBridgeResourceUrl(resourceUrl: string): BridgeResourceUrl | null {
	const parsedUrl = parseUrl(resourceUrl);
	if (parsedUrl === null) {
		return null;
	}
	const pathSegments = resourcePathSegments(parsedUrl);
	if (pathSegments === null || pathSegments.length !== 3) {
		return null;
	}
	const [protocolId, resourceKind, resourceId] = pathSegments;
	if (
		protocolId === undefined ||
		resourceKind === undefined ||
		resourceId === undefined ||
		!isAllowedResourceRoute(protocolId, resourceKind) ||
		!isOpaqueResourceId(resourceId)
	) {
		return null;
	}
	const queryEntries = queryEntriesFor(parsedUrl);

	switch (resourceKind) {
		case 'content':
			return parseContentResource(resourceId, queryEntries);
		case 'worktree.fileContent':
		case 'worktree.fileRange':
			return parseWorktreeResource(resourceKind, resourceId, queryEntries);
		default:
			return null;
	}
}

export function parseBridgeContentResourceUrl(
	resourceUrl: string,
): BridgeContentResourceUrl | null {
	const parsedResourceUrl = parseBridgeResourceUrl(resourceUrl);
	if (parsedResourceUrl?.kind !== 'content') {
		return null;
	}
	return {
		handleId: parsedResourceUrl.handleId,
		generation: parsedResourceUrl.generation,
		...(parsedResourceUrl.revision === undefined ? {} : { revision: parsedResourceUrl.revision }),
	};
}

export function buildBridgeWorkerFetchProbeContentResourceUrl(
	props: BridgeWorkerFetchProbeContentResourceUrlProps,
): string {
	if (!isOpaqueResourceId(props.handleId)) {
		throw new Error('Bridge worker fetch probe requires an opaque content handle id');
	}
	if (!Number.isSafeInteger(props.generation) || props.generation < 0) {
		throw new Error('Bridge worker fetch probe requires a nonnegative generation');
	}
	if (
		props.revision !== undefined &&
		(!Number.isSafeInteger(props.revision) || props.revision < 0)
	) {
		throw new Error('Bridge worker fetch probe requires a nonnegative revision');
	}
	const queryPairs: (readonly [string, string])[] = [['generation', String(props.generation)]];
	if (props.revision !== undefined) {
		queryPairs.push(['revision', String(props.revision)]);
	}
	return canonicalResourceUrl({
		protocolId: 'review',
		resourceKind: 'content',
		resourceId: props.handleId,
		queryPairs,
	});
}

function parseUrl(resourceUrl: string): URL | null {
	let parsedUrl: URL;
	try {
		parsedUrl = new URL(resourceUrl);
	} catch {
		return null;
	}
	if (parsedUrl.protocol !== resourceProtocol || parsedUrl.hostname !== resourceHost) {
		return null;
	}
	return parsedUrl;
}

function resourcePathSegments(parsedUrl: URL): readonly string[] | null {
	const decodedPath = stableDecodePathComponentOrNull(parsedUrl.pathname);
	if (decodedPath === null) {
		return null;
	}
	if (traversalPattern.test(decodedPath)) {
		return null;
	}
	const decodedSegments: string[] = [];
	for (const segment of parsedUrl.pathname
		.split('/')
		.filter((pathSegment: string): boolean => pathSegment.length > 0)) {
		const decodedSegment = stableDecodePathComponentOrNull(segment);
		if (decodedSegment === null || decodedSegment.includes('/')) {
			return null;
		}
		decodedSegments.push(decodedSegment);
	}
	return decodedSegments;
}

function decodePathComponentOrNull(value: string): string | null {
	try {
		return decodeURIComponent(value);
	} catch {
		return null;
	}
}

function stableDecodePathComponentOrNull(value: string): string | null {
	let decodedValue = value;
	let previousValue: string | null = null;
	while (decodedValue !== previousValue) {
		previousValue = decodedValue;
		const nextValue = decodePathComponentOrNull(decodedValue);
		if (nextValue === null) {
			return null;
		}
		decodedValue = nextValue;
	}
	return decodedValue;
}

function queryEntriesFor(parsedUrl: URL): QueryEntries {
	const entries = new Map<string, string[]>();
	for (const [key, value] of parsedUrl.searchParams.entries()) {
		entries.set(key, [...(entries.get(key) ?? []), value]);
	}
	return entries;
}

function parseContentResource(
	handleId: string,
	queryEntries: QueryEntries,
): BridgeParsedContentResourceUrl | null {
	if (!hasOnlyQueryKeys(queryEntries, ['generation', 'revision', 'rangeKind', 'interest'])) {
		return null;
	}
	const generationText = scalarQueryValue(queryEntries, 'generation');
	if (generationText === null) {
		return null;
	}
	const generation = nonnegativeInteger(generationText);
	if (generation === null) {
		return null;
	}
	const revisionText = optionalScalarQueryValue(queryEntries, 'revision');
	const revision = revisionText === null ? undefined : nonnegativeInteger(revisionText);
	if (revision === null) {
		return null;
	}
	const rangeKind = optionalScalarQueryValue(queryEntries, 'rangeKind') ?? 'whole';
	if (rangeKind !== 'whole') {
		return null;
	}
	const interest = optionalScalarQueryValue(queryEntries, 'interest');
	if (interest !== null && !isAllowedContentDemandInterest(interest)) {
		return null;
	}
	const queryPairs: (readonly [string, string])[] = [['generation', String(generation)]];
	if (revision !== undefined) {
		queryPairs.push(['revision', String(revision)]);
	}
	return {
		kind: 'content',
		handleId,
		generation,
		...(revision === undefined ? {} : { revision }),
		range: { kind: 'whole' },
		canonicalUrl: canonicalResourceUrl({
			resourceKind: 'content',
			protocolId: 'review',
			resourceId: handleId,
			queryPairs,
		}),
	};
}

function parseWorktreeResource(
	resourceKind: BridgeWorktreeResourceKind,
	resourceId: string,
	queryEntries: QueryEntries,
): BridgeWorktreeResourceUrl | null {
	if (!hasOnlyQueryKeys(queryEntries, ['generation', 'cursor'])) {
		return null;
	}
	const generationText = scalarQueryValue(queryEntries, 'generation');
	const cursor = scalarQueryValue(queryEntries, 'cursor');
	if (generationText === null || cursor === null) {
		return null;
	}
	const generation = nonnegativeInteger(generationText);
	if (generation === null) {
		return null;
	}
	return {
		kind: 'worktreeResource',
		resourceKind,
		resourceId,
		generation,
		cursor,
		canonicalUrl: canonicalResourceUrl({
			resourceKind,
			protocolId: 'worktree-file',
			resourceId,
			queryPairs: [
				['generation', String(generation)],
				['cursor', cursor],
			],
		}),
	};
}

function scalarQueryValue(queryEntries: QueryEntries, key: string): string | null {
	const values = queryEntries.get(key);
	if (values === undefined || values.length !== 1) {
		return null;
	}
	return values[0] ?? null;
}

function optionalScalarQueryValue(queryEntries: QueryEntries, key: string): string | null {
	if (!queryEntries.has(key)) {
		return null;
	}
	return scalarQueryValue(queryEntries, key);
}

function hasOnlyQueryKeys(queryEntries: QueryEntries, allowedKeys: readonly string[]): boolean {
	const allowed = new Set(allowedKeys);
	for (const [key, values] of queryEntries.entries()) {
		if (!allowed.has(key) || values.length !== 1) {
			return false;
		}
	}
	return true;
}

function nonnegativeInteger(value: string): number | null {
	if (!/^(?:0|[1-9]\d*)$/u.test(value)) {
		return null;
	}
	const parsedValue = Number(value);
	return Number.isSafeInteger(parsedValue) ? parsedValue : null;
}

function isOpaqueResourceId(value: string): boolean {
	return value.length > 0 && !value.includes('/') && !traversalPattern.test(value);
}

function isAllowedResourceRoute(protocolId: string, resourceKind: string): boolean {
	if (protocolId === 'review') {
		return resourceKind === 'content';
	}
	if (protocolId === 'worktree-file') {
		return resourceKind === 'worktree.fileContent' || resourceKind === 'worktree.fileRange';
	}
	return false;
}

function isAllowedContentDemandInterest(value: string): boolean {
	return (
		value === 'selected' ||
		value === 'visible' ||
		value === 'nearby' ||
		value === 'speculative' ||
		value === 'background'
	);
}

interface CanonicalResourceUrlProps {
	readonly protocolId: string;
	readonly resourceKind: string;
	readonly resourceId: string;
	readonly queryPairs: readonly (readonly [string, string])[];
}

function canonicalResourceUrl(props: CanonicalResourceUrlProps): string {
	const query = new URLSearchParams();
	for (const [key, value] of props.queryPairs.toSorted(([leftKey], [rightKey]): number =>
		leftKey.localeCompare(rightKey),
	)) {
		query.append(key, value);
	}
	return `agentstudio://resource/${props.protocolId}/${props.resourceKind}/${encodeURIComponent(
		props.resourceId,
	)}?${query.toString()}`;
}

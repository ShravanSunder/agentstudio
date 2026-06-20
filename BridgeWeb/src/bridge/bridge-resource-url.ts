import { z } from 'zod';

export const bridgeResourceKindSchema = z.enum(['reviewPackage', 'reviewItems', 'content', 'tree']);

export const bridgeWholeResourceRangeSchema = z.object({ kind: z.literal('whole') }).strict();
export const bridgeItemWindowResourceRangeSchema = z
	.object({
		kind: z.literal('itemWindow'),
		cursor: z.string().min(1),
		start: z.number().int().nonnegative(),
		end: z.number().int().nonnegative(),
	})
	.strict();
export const bridgeListResourceRangeSchema = z
	.object({
		kind: z.literal('list'),
		itemIds: z.array(z.string().min(1)).min(1),
	})
	.strict();
export const bridgeCursorResourceRangeSchema = z
	.object({
		kind: z.literal('cursor'),
		cursor: z.string().min(1),
		depth: z.number().int().nonnegative(),
	})
	.strict();

export const bridgeResourceRangeSchema = z.discriminatedUnion('kind', [
	bridgeWholeResourceRangeSchema,
	bridgeItemWindowResourceRangeSchema,
	bridgeListResourceRangeSchema,
	bridgeCursorResourceRangeSchema,
]);

export type BridgeResourceKind = z.infer<typeof bridgeResourceKindSchema>;
export type BridgeResourceRange = z.infer<typeof bridgeResourceRangeSchema>;
export type BridgeWholeResourceRange = z.infer<typeof bridgeWholeResourceRangeSchema>;
export type BridgeItemWindowResourceRange = z.infer<typeof bridgeItemWindowResourceRangeSchema>;
export type BridgeListResourceRange = z.infer<typeof bridgeListResourceRangeSchema>;
export type BridgeCursorResourceRange = z.infer<typeof bridgeCursorResourceRangeSchema>;

export interface BridgeReviewPackageResourceUrl {
	readonly kind: 'reviewPackage';
	readonly packageId: string;
	readonly generation: number;
	readonly revision: number;
	readonly canonicalUrl: string;
}

export interface BridgeReviewItemsResourceUrl {
	readonly kind: 'reviewItems';
	readonly packageId: string;
	readonly generation: number;
	readonly revision: number;
	readonly range: BridgeItemWindowResourceRange | BridgeListResourceRange;
	readonly canonicalUrl: string;
}

export interface BridgeContentResourceUrl {
	readonly kind?: 'content';
	readonly handleId: string;
	readonly generation: number;
	readonly revision?: number;
	readonly range?: BridgeWholeResourceRange;
	readonly canonicalUrl?: string;
}

export interface BridgeParsedContentResourceUrl {
	readonly kind: 'content';
	readonly handleId: string;
	readonly generation: number;
	readonly revision?: number;
	readonly range: BridgeWholeResourceRange;
	readonly canonicalUrl: string;
}

export interface BridgeTreeResourceUrl {
	readonly kind: 'tree';
	readonly treeId: string;
	readonly generation: number;
	readonly revision: number;
	readonly range: BridgeCursorResourceRange;
	readonly canonicalUrl: string;
}

export type BridgeResourceUrl =
	| BridgeReviewPackageResourceUrl
	| BridgeReviewItemsResourceUrl
	| BridgeParsedContentResourceUrl
	| BridgeTreeResourceUrl;

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
	if (pathSegments === null || pathSegments.length !== 2) {
		return null;
	}
	const [resourceKind, resourceId] = pathSegments;
	if (resourceKind === undefined || resourceId === undefined || !isOpaqueResourceId(resourceId)) {
		return null;
	}
	const queryEntries = queryEntriesFor(parsedUrl);

	switch (resourceKind) {
		case 'review-package':
			return parseReviewPackageResource(resourceId, queryEntries);
		case 'review-items':
			return parseReviewItemsResource(resourceId, queryEntries);
		case 'content':
			return parseContentResource(resourceId, queryEntries);
		case 'tree':
			return parseTreeResource(resourceId, queryEntries);
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
	const decodedPath = decodePathComponentOrNull(parsedUrl.pathname);
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
		const decodedSegment = decodePathComponentOrNull(segment);
		if (decodedSegment === null) {
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

function queryEntriesFor(parsedUrl: URL): QueryEntries {
	const entries = new Map<string, string[]>();
	for (const [key, value] of parsedUrl.searchParams.entries()) {
		entries.set(key, [...(entries.get(key) ?? []), value]);
	}
	return entries;
}

function parseReviewPackageResource(
	packageId: string,
	queryEntries: QueryEntries,
): BridgeReviewPackageResourceUrl | null {
	if (!hasOnlyQueryKeys(queryEntries, ['generation', 'revision'])) {
		return null;
	}
	const generationText = scalarQueryValue(queryEntries, 'generation');
	const revisionText = scalarQueryValue(queryEntries, 'revision');
	if (generationText === null || revisionText === null) {
		return null;
	}
	const generation = nonnegativeInteger(generationText);
	const revision = nonnegativeInteger(revisionText);
	if (generation === null || revision === null) {
		return null;
	}
	return {
		kind: 'reviewPackage',
		packageId,
		generation,
		revision,
		canonicalUrl: canonicalResourceUrl({
			resourceKind: 'review-package',
			resourceId: packageId,
			queryPairs: [
				['generation', String(generation)],
				['revision', String(revision)],
			],
		}),
	};
}

function parseReviewItemsResource(
	packageId: string,
	queryEntries: QueryEntries,
): BridgeReviewItemsResourceUrl | null {
	if (
		!hasOnlyQueryKeys(queryEntries, [
			'generation',
			'revision',
			'rangeKind',
			'cursor',
			'start',
			'end',
			'itemIds',
		])
	) {
		return null;
	}
	const generationText = scalarQueryValue(queryEntries, 'generation');
	const revisionText = scalarQueryValue(queryEntries, 'revision');
	const rangeKind = scalarQueryValue(queryEntries, 'rangeKind');
	if (generationText === null || revisionText === null || rangeKind === null) {
		return null;
	}
	const generation = nonnegativeInteger(generationText);
	const revision = nonnegativeInteger(revisionText);
	if (generation === null || revision === null) {
		return null;
	}
	if (rangeKind === 'itemWindow') {
		const cursor = scalarQueryValue(queryEntries, 'cursor');
		const startText = scalarQueryValue(queryEntries, 'start');
		const endText = scalarQueryValue(queryEntries, 'end');
		if (cursor === null || startText === null || endText === null || queryEntries.has('itemIds')) {
			return null;
		}
		const start = nonnegativeInteger(startText);
		const end = nonnegativeInteger(endText);
		if (start === null || end === null || end <= start) {
			return null;
		}
		const range = bridgeItemWindowResourceRangeSchema.parse({
			kind: 'itemWindow',
			cursor,
			start,
			end,
		});
		return {
			kind: 'reviewItems',
			packageId,
			generation,
			revision,
			range,
			canonicalUrl: canonicalResourceUrl({
				resourceKind: 'review-items',
				resourceId: packageId,
				queryPairs: [
					['generation', String(generation)],
					['revision', String(revision)],
					['rangeKind', 'itemWindow'],
					['cursor', range.cursor],
					['start', String(range.start)],
					['end', String(range.end)],
				],
			}),
		};
	}
	if (rangeKind === 'list') {
		const itemIdsText = scalarQueryValue(queryEntries, 'itemIds');
		if (
			itemIdsText === null ||
			queryEntries.has('cursor') ||
			queryEntries.has('start') ||
			queryEntries.has('end')
		) {
			return null;
		}
		const itemIds = itemIdsText.split(',');
		if (
			itemIds.length === 0 ||
			itemIds.some((itemId: string): boolean => !isOpaqueResourceId(itemId))
		) {
			return null;
		}
		const range = bridgeListResourceRangeSchema.parse({
			kind: 'list',
			itemIds,
		});
		return {
			kind: 'reviewItems',
			packageId,
			generation,
			revision,
			range,
			canonicalUrl: canonicalResourceUrl({
				resourceKind: 'review-items',
				resourceId: packageId,
				queryPairs: [
					['generation', String(generation)],
					['revision', String(revision)],
					['rangeKind', 'list'],
					['itemIds', range.itemIds.join(',')],
				],
			}),
		};
	}
	return null;
}

function parseContentResource(
	handleId: string,
	queryEntries: QueryEntries,
): BridgeParsedContentResourceUrl | null {
	if (!hasOnlyQueryKeys(queryEntries, ['generation', 'revision', 'rangeKind'])) {
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
			resourceId: handleId,
			queryPairs,
		}),
	};
}

function parseTreeResource(
	treeId: string,
	queryEntries: QueryEntries,
): BridgeTreeResourceUrl | null {
	if (!hasOnlyQueryKeys(queryEntries, ['generation', 'revision', 'cursor', 'depth'])) {
		return null;
	}
	const generationText = scalarQueryValue(queryEntries, 'generation');
	const revisionText = scalarQueryValue(queryEntries, 'revision');
	const cursor = scalarQueryValue(queryEntries, 'cursor');
	const depthText = scalarQueryValue(queryEntries, 'depth');
	if (generationText === null || revisionText === null || cursor === null || depthText === null) {
		return null;
	}
	const generation = nonnegativeInteger(generationText);
	const revision = nonnegativeInteger(revisionText);
	const depth = nonnegativeInteger(depthText);
	if (generation === null || revision === null || depth === null) {
		return null;
	}
	const range = bridgeCursorResourceRangeSchema.parse({
		kind: 'cursor',
		cursor,
		depth,
	});
	return {
		kind: 'tree',
		treeId,
		generation,
		revision,
		range,
		canonicalUrl: canonicalResourceUrl({
			resourceKind: 'tree',
			resourceId: treeId,
			queryPairs: [
				['generation', String(generation)],
				['revision', String(revision)],
				['cursor', range.cursor],
				['depth', String(range.depth)],
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

interface CanonicalResourceUrlProps {
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
	return `agentstudio://resource/${props.resourceKind}/${encodeURIComponent(
		props.resourceId,
	)}?${query.toString()}`;
}

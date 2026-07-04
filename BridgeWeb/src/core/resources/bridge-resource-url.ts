export interface BridgeAllowedResourceKindsByProtocol {
	readonly [protocol: string]: ReadonlySet<string>;
}

export interface ParseBridgeCoreResourceUrlOptions {
	readonly allowedResourceKindsByProtocol: BridgeAllowedResourceKindsByProtocol;
}

export interface BridgeCoreResourceUrl {
	readonly protocol: string;
	readonly resourceKind: string;
	readonly opaqueId: string;
	readonly generation?: number;
	readonly revision?: number;
	readonly cursor?: string;
	readonly canonicalUrl: string;
}

export type BridgeContentDemandInterest =
	| 'selected'
	| 'visible'
	| 'nearby'
	| 'speculative'
	| 'background';

type BridgeResourceQueryKey = 'generation' | 'revision' | 'cursor' | 'interest';

const agentStudioResourceProtocol = 'agentstudio:';
const agentStudioResourceHost = 'resource';
const allowedQueryKeys: ReadonlySet<string> = new Set<BridgeResourceQueryKey>([
	'generation',
	'revision',
	'cursor',
	'interest',
]);
const traversalPathPattern = /(?:^|\/)\.\.?(?:\/|$)/u;
const cursorPattern = /^[A-Za-z0-9._:-]+$/u;
const bridgeContentDemandInterests = new Set<BridgeContentDemandInterest>([
	'selected',
	'visible',
	'nearby',
	'speculative',
	'background',
]);

export function parseBridgeCoreResourceUrl(
	resourceUrl: string,
	options: ParseBridgeCoreResourceUrlOptions,
): BridgeCoreResourceUrl | null {
	const parsedUrl = parseAgentStudioResourceUrl(resourceUrl);
	if (parsedUrl === null) {
		return null;
	}
	const pathSegments = parseResourcePathSegments(parsedUrl);
	if (pathSegments === null || pathSegments.length !== 3) {
		return null;
	}
	const [protocol, resourceKind, opaqueId] = pathSegments;
	if (
		protocol === undefined ||
		resourceKind === undefined ||
		opaqueId === undefined ||
		!isRegisteredResourceKind(protocol, resourceKind, options.allowedResourceKindsByProtocol)
	) {
		return null;
	}
	const queryValues = parseResourceQueryValues(parsedUrl);
	if (queryValues === null) {
		return null;
	}
	const generation = optionalNonnegativeInteger(queryValues.generation);
	const revision = optionalNonnegativeInteger(queryValues.revision);
	const cursor = optionalCursor(queryValues.cursor);
	const interest = optionalContentDemandInterest(queryValues.interest);
	if (generation === null || revision === null || cursor === null || interest === null) {
		return null;
	}
	return {
		protocol,
		resourceKind,
		opaqueId,
		...(generation === undefined ? {} : { generation }),
		...(revision === undefined ? {} : { revision }),
		...(cursor === undefined ? {} : { cursor }),
		canonicalUrl: canonicalBridgeCoreResourceUrl(
			optionalCanonicalProps({
				protocol,
				resourceKind,
				opaqueId,
				generation,
				revision,
				cursor,
			}),
		),
	};
}

export function bridgeResourceUrlWithContentInterest(
	resourceUrl: string,
	interest: BridgeContentDemandInterest,
): string {
	const parsedUrl = new URL(resourceUrl);
	parsedUrl.searchParams.set('interest', interest);
	return parsedUrl.toString();
}

function parseAgentStudioResourceUrl(resourceUrl: string): URL | null {
	let parsedUrl: URL;
	try {
		parsedUrl = new URL(resourceUrl);
	} catch {
		return null;
	}
	if (
		parsedUrl.protocol !== agentStudioResourceProtocol ||
		parsedUrl.hostname !== agentStudioResourceHost
	) {
		return null;
	}
	return parsedUrl;
}

function parseResourcePathSegments(parsedUrl: URL): readonly string[] | null {
	const rawPath = parsedUrl.pathname;
	const decodedPath = stableDecodeURIComponentOrNull(rawPath);
	if (decodedPath === null || traversalPathPattern.test(decodedPath)) {
		return null;
	}
	const segments: string[] = [];
	for (const rawSegment of rawPath
		.split('/')
		.filter((segment: string): boolean => segment.length > 0)) {
		const decodedSegment = stableDecodeURIComponentOrNull(rawSegment);
		if (
			decodedSegment === null ||
			decodedSegment.length === 0 ||
			decodedSegment.includes('/') ||
			traversalPathPattern.test(decodedSegment)
		) {
			return null;
		}
		segments.push(decodedSegment);
	}
	return segments;
}

function stableDecodeURIComponentOrNull(value: string): string | null {
	let currentValue = value;
	let previousValue: string | undefined;
	while (currentValue !== previousValue) {
		previousValue = currentValue;
		try {
			currentValue = decodeURIComponent(currentValue);
		} catch {
			return null;
		}
	}
	return currentValue;
}

function isRegisteredResourceKind(
	protocol: string,
	resourceKind: string,
	allowedResourceKindsByProtocol: BridgeAllowedResourceKindsByProtocol,
): boolean {
	return allowedResourceKindsByProtocol[protocol]?.has(resourceKind) ?? false;
}

interface BridgeCoreResourceQueryValues {
	readonly generation: string | undefined;
	readonly revision: string | undefined;
	readonly cursor: string | undefined;
	readonly interest: string | undefined;
}

function parseResourceQueryValues(parsedUrl: URL): BridgeCoreResourceQueryValues | null {
	const queryValues: Record<BridgeResourceQueryKey, string | undefined> = {
		generation: undefined,
		revision: undefined,
		cursor: undefined,
		interest: undefined,
	};
	for (const [key, value] of parsedUrl.searchParams.entries()) {
		if (!isBridgeResourceQueryKey(key)) {
			return null;
		}
		if (queryValues[key] !== undefined) {
			return null;
		}
		queryValues[key] = value;
	}
	return queryValues;
}

function isBridgeResourceQueryKey(key: string): key is BridgeResourceQueryKey {
	return allowedQueryKeys.has(key);
}

function optionalNonnegativeInteger(value: string | undefined): number | undefined | null {
	if (value === undefined) {
		return undefined;
	}
	if (!/^(0|[1-9][0-9]*)$/u.test(value)) {
		return null;
	}
	return Number(value);
}

function optionalCursor(value: string | undefined): string | undefined | null {
	if (value === undefined) {
		return undefined;
	}
	return cursorPattern.test(value) ? value : null;
}

function optionalContentDemandInterest(
	value: string | undefined,
): BridgeContentDemandInterest | undefined | null {
	if (value === undefined) {
		return undefined;
	}
	return bridgeContentDemandInterests.has(value as BridgeContentDemandInterest)
		? (value as BridgeContentDemandInterest)
		: null;
}

interface CanonicalBridgeCoreResourceUrlProps {
	readonly protocol: string;
	readonly resourceKind: string;
	readonly opaqueId: string;
	readonly generation?: number;
	readonly revision?: number;
	readonly cursor?: string;
}

interface CanonicalBridgeCoreResourceUrlInput {
	readonly protocol: string;
	readonly resourceKind: string;
	readonly opaqueId: string;
	readonly generation: number | undefined;
	readonly revision: number | undefined;
	readonly cursor: string | undefined;
}

function optionalCanonicalProps(
	props: CanonicalBridgeCoreResourceUrlInput,
): CanonicalBridgeCoreResourceUrlProps {
	return {
		protocol: props.protocol,
		resourceKind: props.resourceKind,
		opaqueId: props.opaqueId,
		...(props.generation === undefined ? {} : { generation: props.generation }),
		...(props.revision === undefined ? {} : { revision: props.revision }),
		...(props.cursor === undefined ? {} : { cursor: props.cursor }),
	};
}

function canonicalBridgeCoreResourceUrl(props: CanonicalBridgeCoreResourceUrlProps): string {
	const queryPairs: string[] = [];
	if (props.generation !== undefined) {
		queryPairs.push(`generation=${String(props.generation)}`);
	}
	if (props.revision !== undefined) {
		queryPairs.push(`revision=${String(props.revision)}`);
	}
	if (props.cursor !== undefined) {
		queryPairs.push(`cursor=${encodeURIComponent(props.cursor)}`);
	}
	const query = queryPairs.length === 0 ? '' : `?${queryPairs.join('&')}`;
	return `agentstudio://resource/${encodeURIComponent(props.protocol)}/${encodeURIComponent(
		props.resourceKind,
	)}/${encodeURIComponent(props.opaqueId)}${query}`;
}

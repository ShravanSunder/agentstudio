import { z } from 'zod';

import {
	bridgeReviewItemsResourceBudgetSchema,
	parseBridgeResourceUrl,
	type BridgeItemWindowResourceRange,
	type BridgeListResourceRange,
	type BridgeReviewItemsResourceBudget,
} from '../../bridge/bridge-resource-url.js';
import type {
	BridgeReviewItemDescriptor,
	BridgeReviewPackage,
} from '../../foundation/review-package/bridge-review-package.js';
import type { BridgeReviewProjectionResult } from '../models/review-projection-models.js';

export const bridgeReviewItemWindowRegistryIdentitySchema = z
	.object({
		packageId: z.string().min(1),
		reviewGeneration: z.number().int().nonnegative(),
		revision: z.number().int().nonnegative(),
	})
	.strict();

export type BridgeReviewItemWindowRegistryIdentity = z.infer<
	typeof bridgeReviewItemWindowRegistryIdentitySchema
>;

export const bridgeReviewItemWindowRangeSchema = z.discriminatedUnion('kind', [
	z.object({
		kind: z.literal('itemWindow'),
		cursor: z.string().min(1),
		start: z.number().int().nonnegative(),
		end: z.number().int().nonnegative(),
	}),
	z.object({
		kind: z.literal('list'),
		itemIds: z.array(z.string().min(1)).min(1).readonly(),
	}),
]);

export type BridgeReviewItemWindowRange = z.infer<typeof bridgeReviewItemWindowRangeSchema>;

export const bridgeReviewItemWindowResourceIdentitySchema =
	bridgeReviewItemWindowRegistryIdentitySchema.extend({
		range: bridgeReviewItemWindowRangeSchema,
	});

export type BridgeReviewItemWindowResourceIdentity = z.infer<
	typeof bridgeReviewItemWindowResourceIdentitySchema
>;

export interface BridgeReviewItemWindow {
	readonly identity: BridgeReviewItemWindowResourceIdentity;
	readonly itemIds: readonly string[];
	readonly items: readonly BridgeReviewItemDescriptor[];
	readonly resourceKey: string;
}

export interface RegisterBridgeReviewItemWindowCursorProps {
	readonly cursor: string;
	readonly identity: BridgeReviewItemWindowRegistryIdentity;
	readonly orderedItemIds: readonly string[];
}

export interface ReadBridgeReviewItemWindowProps {
	readonly reviewPackage: BridgeReviewPackage;
	readonly projection: BridgeReviewProjectionResult;
	readonly resourceUrl: string;
}

export interface BridgeReviewItemWindowRegistrySnapshot {
	readonly activeIdentity: BridgeReviewItemWindowRegistryIdentity | null;
	readonly cachedWindowCount: number;
	readonly cursorCount: number;
	readonly cachedWindowKeys: readonly string[];
}

export interface BridgeReviewItemWindowRegistry {
	readonly clear: () => void;
	readonly readWindow: (props: ReadBridgeReviewItemWindowProps) => BridgeReviewItemWindow;
	readonly registerCursor: (props: RegisterBridgeReviewItemWindowCursorProps) => void;
	readonly setActiveIdentity: (identity: BridgeReviewItemWindowRegistryIdentity | null) => void;
	readonly snapshot: () => BridgeReviewItemWindowRegistrySnapshot;
}

interface CursorEntry {
	readonly identity: BridgeReviewItemWindowRegistryIdentity;
	readonly orderedItemIds: readonly string[];
}

export interface CreateBridgeReviewItemWindowRegistryProps {
	readonly budget?: BridgeReviewItemsResourceBudget;
}

export function createBridgeReviewItemWindowRegistry(
	props: CreateBridgeReviewItemWindowRegistryProps = {},
): BridgeReviewItemWindowRegistry {
	const budget =
		props.budget === undefined
			? undefined
			: bridgeReviewItemsResourceBudgetSchema.parse(props.budget);
	const windowsByResourceKey = new Map<string, BridgeReviewItemWindow>();
	const cursorsById = new Map<string, CursorEntry>();
	let activeIdentity: BridgeReviewItemWindowRegistryIdentity | null = null;

	const clear = (): void => {
		windowsByResourceKey.clear();
		cursorsById.clear();
	};

	const setActiveIdentity = (identity: BridgeReviewItemWindowRegistryIdentity | null): void => {
		const parsedIdentity =
			identity === null ? null : bridgeReviewItemWindowRegistryIdentitySchema.parse(identity);
		if (!registryIdentitiesMatch(activeIdentity, parsedIdentity)) {
			clear();
			activeIdentity = parsedIdentity;
			return;
		}
		activeIdentity = parsedIdentity;
	};

	const registerCursor = (cursorProps: RegisterBridgeReviewItemWindowCursorProps): void => {
		const identity = bridgeReviewItemWindowRegistryIdentitySchema.parse(cursorProps.identity);
		assertActiveIdentity({ activeIdentity, identity });
		cursorsById.set(cursorProps.cursor, {
			identity,
			orderedItemIds: [...cursorProps.orderedItemIds],
		});
	};

	const readWindow = (readProps: ReadBridgeReviewItemWindowProps): BridgeReviewItemWindow => {
		const parsedUrl = parseBridgeResourceUrl(
			readProps.resourceUrl,
			budget === undefined ? {} : { reviewItemsBudget: budget },
		);
		if (parsedUrl?.kind !== 'reviewItems') {
			throw new Error('Bridge review item window registry requires a review-items resource URL');
		}
		const identity = bridgeReviewItemWindowRegistryIdentitySchema.parse({
			packageId: parsedUrl.packageId,
			reviewGeneration: parsedUrl.generation,
			revision: parsedUrl.revision,
		});
		assertActiveIdentity({ activeIdentity, identity });
		assertPackageIdentity({ reviewPackage: readProps.reviewPackage, identity });

		const cachedWindow = windowsByResourceKey.get(parsedUrl.canonicalUrl);
		if (cachedWindow !== undefined) {
			return cachedWindow;
		}

		const itemIds = itemIdsForRange({
			range: parsedUrl.range,
			cursorsById,
			identity,
		});
		assertItemIdsBelongToProjection({ itemIds, projection: readProps.projection });
		const items = itemIds.map((itemId: string): BridgeReviewItemDescriptor => {
			const item = readProps.reviewPackage.itemsById[itemId];
			if (item === undefined) {
				throw new Error('Bridge review item window contains item outside active package');
			}
			return item;
		});
		const window = {
			identity: { ...identity, range: parsedUrl.range },
			itemIds,
			items,
			resourceKey: parsedUrl.canonicalUrl,
		} satisfies BridgeReviewItemWindow;
		windowsByResourceKey.set(parsedUrl.canonicalUrl, window);
		return window;
	};

	const snapshot = (): BridgeReviewItemWindowRegistrySnapshot => ({
		activeIdentity,
		cachedWindowCount: windowsByResourceKey.size,
		cursorCount: cursorsById.size,
		cachedWindowKeys: [...windowsByResourceKey.keys()],
	});

	return { clear, readWindow, registerCursor, setActiveIdentity, snapshot };
}

export interface MakeBridgeReviewItemsResourceUrlProps {
	readonly packageId: string;
	readonly generation: number;
	readonly revision: number;
	readonly range: BridgeItemWindowResourceRange | BridgeListResourceRange;
}

export function makeBridgeReviewItemsResourceUrl(
	props: MakeBridgeReviewItemsResourceUrlProps,
): string {
	const queryPairs: (readonly [string, string])[] = [
		['generation', String(props.generation)],
		['revision', String(props.revision)],
		['rangeKind', props.range.kind],
	];
	if (props.range.kind === 'itemWindow') {
		queryPairs.push(
			['cursor', props.range.cursor],
			['start', String(props.range.start)],
			['end', String(props.range.end)],
		);
	} else {
		queryPairs.push(['itemIds', props.range.itemIds.join(',')]);
	}

	const query = new URLSearchParams();
	for (const [key, value] of queryPairs.toSorted(([leftKey], [rightKey]): number =>
		leftKey.localeCompare(rightKey),
	)) {
		query.append(key, value);
	}
	return `agentstudio://resource/review/review-items/${encodeURIComponent(props.packageId)}?${query.toString()}`;
}

function itemIdsForRange(props: {
	readonly range: BridgeItemWindowResourceRange | BridgeListResourceRange;
	readonly cursorsById: ReadonlyMap<string, CursorEntry>;
	readonly identity: BridgeReviewItemWindowRegistryIdentity;
}): readonly string[] {
	if (props.range.kind === 'list') {
		return [...props.range.itemIds];
	}
	const cursorEntry = props.cursorsById.get(props.range.cursor);
	if (cursorEntry === undefined || !registryIdentitiesMatch(cursorEntry.identity, props.identity)) {
		throw new Error('Bridge review item window cursor is stale or unknown');
	}
	if (props.range.end > cursorEntry.orderedItemIds.length) {
		throw new Error('Bridge review item window range exceeds cursor bounds');
	}
	return cursorEntry.orderedItemIds.slice(props.range.start, props.range.end);
}

function assertActiveIdentity(props: {
	readonly activeIdentity: BridgeReviewItemWindowRegistryIdentity | null;
	readonly identity: BridgeReviewItemWindowRegistryIdentity;
}): void {
	if (!registryIdentitiesMatch(props.activeIdentity, props.identity)) {
		throw new Error('Bridge review item window rejected stale package identity');
	}
}

function assertPackageIdentity(props: {
	readonly reviewPackage: BridgeReviewPackage;
	readonly identity: BridgeReviewItemWindowRegistryIdentity;
}): void {
	if (
		props.reviewPackage.packageId !== props.identity.packageId ||
		props.reviewPackage.reviewGeneration !== props.identity.reviewGeneration ||
		props.reviewPackage.revision !== props.identity.revision
	) {
		throw new Error('Bridge review item window resource does not match active package');
	}
}

function assertItemIdsBelongToProjection(props: {
	readonly itemIds: readonly string[];
	readonly projection: BridgeReviewProjectionResult;
}): void {
	const activeProjectionItemIds = new Set(props.projection.orderedItemIds);
	for (const itemId of props.itemIds) {
		if (!activeProjectionItemIds.has(itemId)) {
			throw new Error('Bridge review item window contains item outside active projection');
		}
	}
}

function registryIdentitiesMatch(
	left: BridgeReviewItemWindowRegistryIdentity | null,
	right: BridgeReviewItemWindowRegistryIdentity | null,
): boolean {
	return (
		left?.packageId === right?.packageId &&
		left?.reviewGeneration === right?.reviewGeneration &&
		left?.revision === right?.revision
	);
}

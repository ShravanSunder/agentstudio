import { describe, expect, test } from 'vitest';

import type { ReviewMaterializerDelta } from '../features/review/materialization/review-materializer.js';
import { makeBridgeReviewPackage } from '../foundation/review-package/bridge-review-package-test-support.js';
import {
	BridgeCodeViewController,
	bridgeCodeViewApplyResultDidRenderContent,
} from '../review-viewer/code-view/bridge-code-view-controller.js';
import {
	type BridgeCodeViewContentResources,
	type BridgeCodeViewItem,
	materializeBridgeCodeViewItem,
} from '../review-viewer/code-view/bridge-code-view-materialization.js';
import {
	makeSelectedContentResourcesKey,
	reviewContentValidityDropReason,
	selectedContentDemandStartedAtMillisecondsForCurrentSelection,
	selectedContentResourcesForCurrentSelection,
} from './bridge-app-review-selection-state.js';
import { applyReviewMetadataDeltaToReviewPackage } from './bridge-app.js';

type ReviewDeltaMaterializerDelta = Extract<
	ReviewMaterializerDelta,
	{ readonly kind: 'metadataDelta' }
>;

function extentFactDelta(props: {
	readonly packageId: string;
	readonly fromRevision: number;
	readonly facts: readonly {
		readonly itemId: string;
		readonly contentRole: 'base' | 'head';
		readonly lineCount: number;
	}[];
	readonly summary: ReturnType<typeof makeBridgeReviewPackage>['summary'];
}): ReviewDeltaMaterializerDelta {
	return {
		kind: 'metadataDelta',
		packageId: props.packageId,
		fromRevision: props.fromRevision,
		toRevision: props.fromRevision + 1,
		operations: [{ kind: 'upsertExtentFacts', facts: [...props.facts] }],
		summary: props.summary,
		registeredContentDescriptorRefs: [],
		contentDescriptors: [],
	};
}

// The review content-validity key must be content-addressed: benign metadata re-delivery (extent
// facts, path/summary/tree updates) bumps the package revision constantly in a busy multi-worktree
// workspace, but must NOT invalidate already-loaded content whose contentHash is unchanged. A real
// contentHash change or a generation rotation must still invalidate. See
// makeReviewItemContentResourcesKey.
describe('review content-validity key is content-addressed, not revision-stamped', () => {
	test('keeps loaded selected content across an extent-fact revision bump (contentHash unchanged)', () => {
		const reviewPackage = makeBridgeReviewPackage();
		const item = reviewPackage.itemsById['item-source'];
		const baseHandle = item?.contentRoles.base ?? null;
		const headHandle = item?.contentRoles.head ?? null;
		if (item === undefined || baseHandle === null || headHandle === null) {
			throw new Error('Expected modified item with base/head handles');
		}
		const loadedState = {
			itemId: 'item-source',
			contentKey: makeSelectedContentResourcesKey(reviewPackage, 'item-source'),
			status: 'ready' as const,
			resources: {
				base: { handle: baseHandle, readText: (): string => 'base body' },
				head: { handle: headHandle, readText: (): string => 'head body' },
			},
		};
		expect(
			selectedContentResourcesForCurrentSelection({
				reviewPackage,
				selectedItemId: 'item-source',
				selectedContentResourcesState: loadedState,
			}),
		).not.toBeNull();

		const nextReviewPackage = applyReviewMetadataDeltaToReviewPackage({
			reviewPackage,
			deltaFrame: extentFactDelta({
				packageId: reviewPackage.packageId,
				fromRevision: reviewPackage.revision,
				facts: [
					{ itemId: 'item-source', contentRole: 'base', lineCount: 17 },
					{ itemId: 'item-source', contentRole: 'head', lineCount: 23 },
				],
				summary: reviewPackage.summary,
			}),
		});
		if (nextReviewPackage === null) {
			throw new Error('Expected extent-fact delta to apply');
		}
		// Extent facts preserve the content handles / contentHash (only line counts + cacheKey move).
		expect(nextReviewPackage.itemsById['item-source']?.contentRoles.head?.contentHash).toBe(
			headHandle.contentHash,
		);
		// The loaded content must survive the revision bump because the key is content-addressed.
		expect(
			selectedContentResourcesForCurrentSelection({
				reviewPackage: nextReviewPackage,
				selectedItemId: 'item-source',
				selectedContentResourcesState: loadedState,
			}),
		).not.toBeNull();
	});

	test('keeps the content key stable when a load lands after a revision bump (same contentHash)', () => {
		const reviewPackage = makeBridgeReviewPackage();
		const keyAtLoadStart = makeSelectedContentResourcesKey(reviewPackage, 'item-source');
		const nextReviewPackage = applyReviewMetadataDeltaToReviewPackage({
			reviewPackage,
			deltaFrame: extentFactDelta({
				packageId: reviewPackage.packageId,
				fromRevision: reviewPackage.revision,
				facts: [{ itemId: 'item-source', contentRole: 'head', lineCount: 41 }],
				summary: reviewPackage.summary,
			}),
		});
		if (nextReviewPackage === null) {
			throw new Error('Expected extent-fact delta to apply');
		}
		// A load started at the old revision still matches when it lands at the new revision.
		expect(makeSelectedContentResourcesKey(nextReviewPackage, 'item-source')).toBe(keyAtLoadStart);
	});

	test('invalidates loaded selected content when the contentHash actually changes', () => {
		const reviewPackage = makeBridgeReviewPackage();
		const item = reviewPackage.itemsById['item-source'];
		const headHandle = item?.contentRoles.head ?? null;
		if (item === undefined || headHandle === null) {
			throw new Error('Expected modified item with head handle');
		}
		const loadedState = {
			itemId: 'item-source',
			contentKey: makeSelectedContentResourcesKey(reviewPackage, 'item-source'),
			demandStartedAtMilliseconds: 123,
			status: 'ready' as const,
			resources: { head: { handle: headHandle, readText: (): string => 'head body' } },
		};
		const changedPackage = {
			...reviewPackage,
			itemsById: {
				...reviewPackage.itemsById,
				'item-source': {
					...item,
					contentRoles: {
						...item.contentRoles,
						head: { ...headHandle, contentHash: `${headHandle.contentHash}:changed` },
					},
				},
			},
		};
		expect(
			selectedContentResourcesForCurrentSelection({
				reviewPackage: changedPackage,
				selectedItemId: 'item-source',
				selectedContentResourcesState: loadedState,
			}),
		).toBeNull();
	});

	test('invalidates loaded selected content when the review generation rotates', () => {
		const reviewPackage = makeBridgeReviewPackage();
		const item = reviewPackage.itemsById['item-source'];
		const headHandle = item?.contentRoles.head ?? null;
		if (item === undefined || headHandle === null) {
			throw new Error('Expected modified item with head handle');
		}
		const loadedState = {
			itemId: 'item-source',
			contentKey: makeSelectedContentResourcesKey(reviewPackage, 'item-source'),
			demandStartedAtMilliseconds: 123,
			status: 'ready' as const,
			resources: { head: { handle: headHandle, readText: (): string => 'head body' } },
		};
		const rotatedPackage = {
			...reviewPackage,
			reviewGeneration: reviewPackage.reviewGeneration + 1,
		};
		expect(
			selectedContentResourcesForCurrentSelection({
				reviewPackage: rotatedPackage,
				selectedItemId: 'item-source',
				selectedContentResourcesState: loadedState,
			}),
		).toBeNull();
	});

	test('keeps loaded selected content when a metadata re-touch drops the descriptor (metadata-only-keep)', () => {
		const reviewPackage = makeBridgeReviewPackage();
		const item = reviewPackage.itemsById['item-source'];
		const headHandle = item?.contentRoles.head ?? null;
		if (item === undefined || headHandle === null) {
			throw new Error('Expected modified item with head handle');
		}
		const loadedState = {
			itemId: 'item-source',
			contentKey: makeSelectedContentResourcesKey(reviewPackage, 'item-source'),
			demandStartedAtMilliseconds: 123,
			status: 'ready' as const,
			resources: { head: { handle: headHandle, readText: (): string => 'head body' } },
		};
		// A metadata-only re-touch (delta/window/snapshot with no fresher descriptor) downgrades the
		// item to null role handles. With gate-only defense (intake preservation deferred), the loaded
		// content must be KEPT — the item has no fresher content identity, and a reload would fail.
		const downgradedPackage = {
			...reviewPackage,
			itemsById: {
				...reviewPackage.itemsById,
				'item-source': {
					...item,
					contentRoles: { ...item.contentRoles, base: null, head: null },
				},
			},
		};
		expect(
			selectedContentResourcesForCurrentSelection({
				reviewPackage: downgradedPackage,
				selectedItemId: 'item-source',
				selectedContentResourcesState: loadedState,
			}),
		).not.toBeNull();
		expect(
			reviewContentValidityDropReason({
				reviewPackage: downgradedPackage,
				selectedItemId: 'item-source',
				selectedContentResourcesState: loadedState,
			}),
		).toBe('valid');
		expect(
			selectedContentDemandStartedAtMillisecondsForCurrentSelection({
				reviewPackage: downgradedPackage,
				selectedItemId: 'item-source',
				selectedContentResourcesState: loadedState,
			}),
		).toBe(123);
	});
});

// The gate-drop telemetry contract requires that every drop of an already-loaded, ready
// SelectedContentResourcesState be attributable to a specific cause. reviewContentValidityDropReason
// is the pure classifier behind that telemetry: it must never silently return an unlabeled drop.
describe('reviewContentValidityDropReason classifies why a ready selected-content load was dropped', () => {
	test('returns no_selection when there is no package, no selection, or no ready loaded state', () => {
		const reviewPackage = makeBridgeReviewPackage();
		const readyState = {
			itemId: 'item-source',
			contentKey: makeSelectedContentResourcesKey(reviewPackage, 'item-source'),
			status: 'ready' as const,
			resources: null,
		};
		expect(
			reviewContentValidityDropReason({
				reviewPackage: null,
				selectedItemId: 'item-source',
				selectedContentResourcesState: readyState,
			}),
		).toBe('no_selection');
		expect(
			reviewContentValidityDropReason({
				reviewPackage,
				selectedItemId: null,
				selectedContentResourcesState: readyState,
			}),
		).toBe('no_selection');
		expect(
			reviewContentValidityDropReason({
				reviewPackage,
				selectedItemId: 'item-source',
				selectedContentResourcesState: null,
			}),
		).toBe('no_selection');
		expect(
			reviewContentValidityDropReason({
				reviewPackage,
				selectedItemId: 'item-source',
				selectedContentResourcesState: { ...readyState, itemId: 'other-item' },
			}),
		).toBe('no_selection');
		expect(
			reviewContentValidityDropReason({
				reviewPackage,
				selectedItemId: 'item-source',
				selectedContentResourcesState: { ...readyState, status: 'loading' as const },
			}),
		).toBe('no_selection');
		expect(
			reviewContentValidityDropReason({
				reviewPackage,
				selectedItemId: 'missing-item',
				selectedContentResourcesState: { ...readyState, itemId: 'missing-item' },
			}),
		).toBe('no_selection');
	});

	test('returns valid when the loaded state matches the current content key', () => {
		const reviewPackage = makeBridgeReviewPackage();
		const readyState = {
			itemId: 'item-source',
			contentKey: makeSelectedContentResourcesKey(reviewPackage, 'item-source'),
			status: 'ready' as const,
			resources: null,
		};
		expect(
			reviewContentValidityDropReason({
				reviewPackage,
				selectedItemId: 'item-source',
				selectedContentResourcesState: readyState,
			}),
		).toBe('valid');
	});

	test('returns valid across an extent-fact revision bump (revision churn must not classify as a drop)', () => {
		const reviewPackage = makeBridgeReviewPackage();
		const readyState = {
			itemId: 'item-source',
			contentKey: makeSelectedContentResourcesKey(reviewPackage, 'item-source'),
			status: 'ready' as const,
			resources: null,
		};
		const nextReviewPackage = applyReviewMetadataDeltaToReviewPackage({
			reviewPackage,
			deltaFrame: extentFactDelta({
				packageId: reviewPackage.packageId,
				fromRevision: reviewPackage.revision,
				facts: [{ itemId: 'item-source', contentRole: 'head', lineCount: 41 }],
				summary: reviewPackage.summary,
			}),
		});
		if (nextReviewPackage === null) {
			throw new Error('Expected extent-fact delta to apply');
		}
		expect(
			reviewContentValidityDropReason({
				reviewPackage: nextReviewPackage,
				selectedItemId: 'item-source',
				selectedContentResourcesState: readyState,
			}),
		).toBe('valid');
	});

	test('returns generation_rotation when the review generation rotates', () => {
		const reviewPackage = makeBridgeReviewPackage();
		const item = reviewPackage.itemsById['item-source'];
		const headHandle = item?.contentRoles.head ?? null;
		if (item === undefined || headHandle === null) {
			throw new Error('Expected modified item with head handle');
		}
		const loadedState = {
			itemId: 'item-source',
			contentKey: makeSelectedContentResourcesKey(reviewPackage, 'item-source'),
			status: 'ready' as const,
			resources: { head: { handle: headHandle, readText: (): string => 'head body' } },
		};
		const rotatedPackage = {
			...reviewPackage,
			reviewGeneration: reviewPackage.reviewGeneration + 1,
		};
		expect(
			reviewContentValidityDropReason({
				reviewPackage: rotatedPackage,
				selectedItemId: 'item-source',
				selectedContentResourcesState: loadedState,
			}),
		).toBe('generation_rotation');
	});

	test('returns contenthash_change when a role handle contentHash changes', () => {
		const reviewPackage = makeBridgeReviewPackage();
		const item = reviewPackage.itemsById['item-source'];
		const headHandle = item?.contentRoles.head ?? null;
		if (item === undefined || headHandle === null) {
			throw new Error('Expected modified item with head handle');
		}
		const loadedState = {
			itemId: 'item-source',
			contentKey: makeSelectedContentResourcesKey(reviewPackage, 'item-source'),
			status: 'ready' as const,
			resources: { head: { handle: headHandle, readText: (): string => 'head body' } },
		};
		const changedPackage = {
			...reviewPackage,
			itemsById: {
				...reviewPackage.itemsById,
				'item-source': {
					...item,
					contentRoles: {
						...item.contentRoles,
						head: { ...headHandle, contentHash: `${headHandle.contentHash}:changed` },
					},
				},
			},
		};
		expect(
			reviewContentValidityDropReason({
				reviewPackage: changedPackage,
				selectedItemId: 'item-source',
				selectedContentResourcesState: loadedState,
			}),
		).toBe('contenthash_change');
	});

	test('returns revision_churn as a sentinel when the key diverges without a generation or contentHash change', () => {
		// This state is deliberately contrived: a well-formed content-addressed key can only diverge
		// from the current key via a generation rotation or a contentHash change, so this proves the
		// sentinel fallback still labels the drop instead of silently returning null.
		const reviewPackage = makeBridgeReviewPackage();
		const item = reviewPackage.itemsById['item-source'];
		const baseHandle = item?.contentRoles.base ?? null;
		const headHandle = item?.contentRoles.head ?? null;
		if (item === undefined || baseHandle === null || headHandle === null) {
			throw new Error('Expected modified item with base/head handles');
		}
		const staleState = {
			itemId: 'item-source',
			contentKey: 'stale-key-not-derived-from-current-handles',
			status: 'ready' as const,
			resources: {
				base: { handle: baseHandle, readText: (): string => 'base body' },
				head: { handle: headHandle, readText: (): string => 'head body' },
			},
		};
		expect(
			reviewContentValidityDropReason({
				reviewPackage,
				selectedItemId: 'item-source',
				selectedContentResourcesState: staleState,
			}),
		).toBe('revision_churn');
	});
});

// Live drift-then-snap flicker acceptance: content staying is necessary but not sufficient. The
// visible cycle is a height-reflow re-render, so a post-load extent-fact delta must produce ZERO
// item re-render. Pierre (CodeView.syncItemRecord) short-circuits when item.version === nextItem
// .version, and materializeBridgeCodeViewItem stamps version = codeViewRenderVersion(itemVersion,
// contentState). reviewItemWithExtentFacts preserves itemVersion and the content-addressed gate keeps
// the item hydrated, so the version is identical and no DOM swap (hence no reflow, no drift) occurs.
describe('content-addressed key produces zero item re-render on a benign extent-fact delta', () => {
	test('keeps the materialized Pierre render version identical across a post-load extent-fact delta', () => {
		const reviewPackage = makeBridgeReviewPackage();
		const item = reviewPackage.itemsById['item-source'];
		const baseHandle = item?.contentRoles.base ?? null;
		const headHandle = item?.contentRoles.head ?? null;
		if (item === undefined || baseHandle === null || headHandle === null) {
			throw new Error('Expected modified item with base/head handles');
		}
		const resources: BridgeCodeViewContentResources = {
			base: { handle: baseHandle, readText: (): string => 'base body' },
			head: { handle: headHandle, readText: (): string => 'head body' },
		};
		const itemBeforeDelta = materializeBridgeCodeViewItem({ item, resources });
		if (itemBeforeDelta === null) {
			throw new Error('Expected the loaded item to materialize before the delta');
		}

		const nextReviewPackage = applyReviewMetadataDeltaToReviewPackage({
			reviewPackage,
			deltaFrame: extentFactDelta({
				packageId: reviewPackage.packageId,
				fromRevision: reviewPackage.revision,
				facts: [
					{ itemId: 'item-source', contentRole: 'base', lineCount: 31 },
					{ itemId: 'item-source', contentRole: 'head', lineCount: 42 },
				],
				summary: reviewPackage.summary,
			}),
		});
		if (nextReviewPackage === null) {
			throw new Error('Expected extent-fact delta to apply');
		}
		const nextItem = nextReviewPackage.itemsById['item-source'];
		if (nextItem === undefined) {
			throw new Error('Expected the item to survive the extent-fact delta');
		}
		const itemAfterDelta = materializeBridgeCodeViewItem({ item: nextItem, resources });
		if (itemAfterDelta === null) {
			throw new Error('Expected the loaded item to materialize after the delta');
		}

		// itemVersion is preserved by the delta (the no-op precondition) and the render version — the
		// exact value Pierre compares to decide a DOM swap — is unchanged, so the item is not re-rendered.
		expect(nextItem.itemVersion).toBe(item.itemVersion);
		expect(itemAfterDelta.version).toBe(itemBeforeDelta.version);
	});
});

// A version-faithful stand-in for Pierre's CodeView model: updateItem swaps (returns true) only when
// the item's version changes, mirroring CodeView.syncItemRecord (item.version === next.version →
// return false). This lets the apply result be DERIVED from real materialized versions rather than
// assumed, so the "painted fires once" proof rests on the same version identity the panel relies on.
class VersionKeyedCodeViewModel {
	readonly #itemsById = new Map<string, BridgeCodeViewItem>();

	addItems(items: readonly BridgeCodeViewItem[]): void {
		for (const item of items) {
			this.#itemsById.set(item.id, item);
		}
	}

	getItem(id: string): BridgeCodeViewItem | undefined {
		return this.#itemsById.get(id);
	}

	updateItem(item: BridgeCodeViewItem): boolean {
		const previous = this.#itemsById.get(item.id);
		this.#itemsById.set(item.id, item);
		return previous !== undefined && previous.version !== item.version;
	}

	updateItemId(): boolean {
		return true;
	}

	scrollTo(): void {}

	setSelectedLines(): void {}
}

// Drift-then-snap acceptance (final form): a click must produce EXACTLY ONE content render. The panel
// schedules selected_content_painted iff the apply rendered content (bridgeCodeViewApplyResultDidRender
// Content). This proves that after the initial hydrating apply, a benign extent-fact delta re-applies
// the same-version item as a no-op ('unchanged'), so no second paint fires — one paint per selection.
describe('a benign extent-fact delta paints selected content exactly once (no second apply)', () => {
	test('applies the selected item once, then no-ops the post-delta re-apply, so painted fires once', () => {
		const reviewPackage = makeBridgeReviewPackage();
		const item = reviewPackage.itemsById['item-source'];
		const baseHandle = item?.contentRoles.base ?? null;
		const headHandle = item?.contentRoles.head ?? null;
		if (item === undefined || baseHandle === null || headHandle === null) {
			throw new Error('Expected modified item with base/head handles');
		}
		const resources: BridgeCodeViewContentResources = {
			base: { handle: baseHandle, readText: (): string => 'base body' },
			head: { handle: headHandle, readText: (): string => 'head body' },
		};
		const materializedBeforeDelta = materializeBridgeCodeViewItem({ item, resources });
		if (materializedBeforeDelta === null) {
			throw new Error('Expected the loaded item to materialize before the delta');
		}

		const controller = new BridgeCodeViewController({ model: new VersionKeyedCodeViewModel() });
		let paintCount = 0;
		const applyAndCountPaint = (nextItem: BridgeCodeViewItem): void => {
			if (bridgeCodeViewApplyResultDidRenderContent(controller.applyItemUpdate(nextItem))) {
				paintCount += 1;
			}
		};

		// The click's hydrating apply renders content once.
		applyAndCountPaint(materializedBeforeDelta);
		expect(paintCount).toBe(1);

		const nextReviewPackage = applyReviewMetadataDeltaToReviewPackage({
			reviewPackage,
			deltaFrame: extentFactDelta({
				packageId: reviewPackage.packageId,
				fromRevision: reviewPackage.revision,
				facts: [
					{ itemId: 'item-source', contentRole: 'base', lineCount: 31 },
					{ itemId: 'item-source', contentRole: 'head', lineCount: 42 },
				],
				summary: reviewPackage.summary,
			}),
		});
		if (nextReviewPackage === null) {
			throw new Error('Expected extent-fact delta to apply');
		}
		const nextItem = nextReviewPackage.itemsById['item-source'];
		if (nextItem === undefined) {
			throw new Error('Expected the item to survive the extent-fact delta');
		}
		const materializedAfterDelta = materializeBridgeCodeViewItem({ item: nextItem, resources });
		if (materializedAfterDelta === null) {
			throw new Error('Expected the loaded item to materialize after the delta');
		}

		// The benign delta re-applies the same-version item → Pierre no-ops ('unchanged') → no second
		// paint. Exactly one content render per selection.
		applyAndCountPaint(materializedAfterDelta);
		expect(paintCount).toBe(1);
	});
});

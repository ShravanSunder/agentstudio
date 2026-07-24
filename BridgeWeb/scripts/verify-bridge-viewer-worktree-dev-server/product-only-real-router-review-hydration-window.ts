import { errors, type Page } from 'playwright';

import { bridgeViewerProductOnlySelectors } from './product-only-real-router-contract.ts';

export interface FreshReviewHydrationWindowSnapshot {
	readonly hydratedNonSelectedItemIds: readonly string[];
	readonly scrollTop: number;
	readonly visibleNonSelectedItemIds: readonly string[];
}

export function previousFreshReviewTraversalScrollTop(props: {
	readonly codeScroll: {
		readonly clientHeight: number;
		readonly scrollTop: number;
	};
	readonly visibleItems: readonly { readonly hostTopOffset: number }[];
}): number {
	const viewportAdvance = Math.max(1, props.codeScroll.clientHeight * 0.8);
	const firstVisibleHostTopOffset = props.visibleItems.reduce(
		(minimumTopOffset, item): number =>
			Number.isFinite(item.hostTopOffset)
				? Math.min(minimumTopOffset, item.hostTopOffset)
				: minimumTopOffset,
		Number.POSITIVE_INFINITY,
	);
	const hydratedHostAdvance = Number.isFinite(firstVisibleHostTopOffset)
		? Math.max(0, -firstVisibleHostTopOffset + props.codeScroll.clientHeight * 0.1)
		: 0;
	return Math.max(
		0,
		Math.floor(props.codeScroll.scrollTop - Math.max(viewportAdvance, hydratedHostAdvance)),
	);
}

export async function waitForFreshReviewHydrationWindowSnapshot(props: {
	readonly excludedItemIds: readonly string[];
	readonly page: Page;
	readonly selectedItemId: string | null;
	readonly timeoutMilliseconds: number;
}): Promise<FreshReviewHydrationWindowSnapshot | null> {
	try {
		const snapshotHandle = await props.page.waitForFunction(
			({ excludedItemIds, selectedItemId, selectors }) => {
				const codePanel = document.querySelector(selectors.reviewCodePanel);
				const codeScrollOwner = document.querySelector(selectors.reviewCodeScrollOwner);
				if (!(codeScrollOwner instanceof HTMLElement)) return false;
				const excludedItemIdSet = new Set(excludedItemIds);
				const codeScrollRect = codeScrollOwner.getBoundingClientRect();
				const visibleItems = queryAllInOpenShadowRoots(
					codePanel ?? document,
					'diffs-container',
				).flatMap((reviewItemHost) => {
					const marker = bridgeReviewHostElement(reviewItemHost, '[data-bridge-code-view-item-id]');
					const itemId = marker?.getAttribute('data-bridge-code-view-item-id');
					if (itemId === null || itemId === undefined) return [];
					const hostRect = reviewItemHost.getBoundingClientRect();
					if (hostRect.bottom <= codeScrollRect.top || hostRect.top >= codeScrollRect.bottom) {
						return [];
					}
					const contentState = bridgeReviewHostElement(
						reviewItemHost,
						'[data-bridge-code-view-content-state]',
					)?.getAttribute('data-bridge-code-view-content-state');
					const publicationId = reviewItemHost.getAttribute('data-bridge-painted-publication-id');
					const sourceCorrelations = reviewItemHost.getAttribute(
						'data-bridge-painted-source-correlations',
					);
					return [{ contentState, itemId, publicationId, sourceCorrelations }];
				});
				const visibleCandidates = visibleItems.filter(
					(item) => item.itemId !== selectedItemId && !excludedItemIdSet.has(item.itemId),
				);
				if (
					visibleCandidates.length === 0 ||
					visibleCandidates.some(
						(item) => item.contentState !== 'hydrated' && item.contentState !== 'windowed',
					) ||
					visibleItems.some((item) => {
						if (item.publicationId === null || item.sourceCorrelations === null) return true;
						try {
							const sourceCorrelations: unknown = JSON.parse(item.sourceCorrelations);
							return (
								!Array.isArray(sourceCorrelations) ||
								sourceCorrelations.length === 0 ||
								sourceCorrelations.some(
									(sourceCorrelation): boolean =>
										typeof sourceCorrelation !== 'object' ||
										sourceCorrelation === null ||
										Reflect.get(sourceCorrelation, 'itemId') !== item.itemId ||
										Reflect.get(sourceCorrelation, 'pierreItemId') !== item.itemId ||
										Reflect.get(sourceCorrelation, 'semanticItemId') !== item.itemId ||
										Reflect.get(sourceCorrelation, 'publicationId') !== item.publicationId,
								)
							);
						} catch {
							return true;
						}
					})
				) {
					return false;
				}
				return {
					hydratedNonSelectedItemIds: visibleCandidates.map((item) => item.itemId),
					scrollTop: codeScrollOwner.scrollTop,
					visibleNonSelectedItemIds: visibleCandidates.map((item) => item.itemId),
				};

				function bridgeReviewHostElement(host: Element, selector: string): Element | null {
					return host.querySelector(selector) ?? host.shadowRoot?.querySelector(selector) ?? null;
				}

				function queryAllInOpenShadowRoots(
					root: Document | Element | ShadowRoot,
					selector: string,
				): Element[] {
					const matches = [...root.querySelectorAll(selector)];
					for (const descendant of root.querySelectorAll('*')) {
						if (descendant.shadowRoot === null) continue;
						matches.push(...queryAllInOpenShadowRoots(descendant.shadowRoot, selector));
					}
					return matches;
				}
			},
			{
				excludedItemIds: props.excludedItemIds,
				selectedItemId: props.selectedItemId,
				selectors: bridgeViewerProductOnlySelectors,
			},
			{ timeout: props.timeoutMilliseconds },
		);
		const snapshot = await snapshotHandle.jsonValue();
		return snapshot === false ? null : snapshot;
	} catch (error: unknown) {
		if (error instanceof errors.TimeoutError) return null;
		throw error;
	}
}

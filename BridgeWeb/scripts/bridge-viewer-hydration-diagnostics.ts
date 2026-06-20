/* oxlint-disable unicorn/consistent-function-scoping -- The DOM collector is serialized into Playwright page.evaluate, so helpers must stay self-contained. */

import { z } from 'zod';

export const bridgeViewerSelectedHydrationDiagnosticsSchema = z.object({
	cacheKeyCount: z.number().int().nonnegative(),
	characterCount: z.number().int().nonnegative(),
	contentState: z.string().nullable(),
	displayPath: z.string().nullable(),
	itemId: z.string().nullable(),
	lineCount: z.number().int().nonnegative(),
	materializedAdditionLineCount: z.number().int().nonnegative(),
	materializedDeletionLineCount: z.number().int().nonnegative(),
	materializedFileLineCount: z.number().int().nonnegative(),
	materializedItemType: z.string().nullable(),
	materializedItemVersion: z.number().int().nonnegative().nullable(),
	materializedUpdateResult: z.string().nullable(),
	roleCount: z.number().int().nonnegative(),
});

export const bridgeViewerHydrationDiagnosticsSchema = z.object({
	codeViewItemCount: z.number().int().nonnegative(),
	emptyExpandedHeaderCount: z.number().int().nonnegative(),
	hasEmptyExpandedHeaders: z.boolean(),
	renderedItemIdCount: z.number().int().nonnegative(),
	renderedItemIds: z.array(z.string()),
	renderedItemsWithoutIdsCount: z.number().int().nonnegative(),
	selected: bridgeViewerSelectedHydrationDiagnosticsSchema,
	visibleHydratedCacheCount: z.number().int().nonnegative().nullable(),
	visibleHydratedCacheCountAvailable: z.boolean(),
});

export type BridgeViewerHydrationDiagnostics = z.infer<
	typeof bridgeViewerHydrationDiagnosticsSchema
>;

export function collectBridgeViewerHydrationDiagnosticsFromRoot(
	root: Document = document,
): BridgeViewerHydrationDiagnostics {
	function numericAttribute(element: Element | null, attributeName: string): number {
		const value = element?.getAttribute(attributeName);
		if (value === null || value === undefined || value.trim().length === 0) {
			return 0;
		}
		const numericValue = Number(value);
		return Number.isFinite(numericValue) && numericValue >= 0 ? numericValue : 0;
	}

	function nullableStringAttribute(element: Element | null, attributeName: string): string | null {
		const value = element?.getAttribute(attributeName);
		return value === undefined ? null : value;
	}

	function nullableNumericAttribute(element: Element | null, attributeName: string): number | null {
		const value = element?.getAttribute(attributeName);
		if (value === null || value === undefined || value.trim().length === 0) {
			return null;
		}
		const numericValue = Number(value);
		return Number.isFinite(numericValue) && numericValue >= 0 ? numericValue : null;
	}

	function itemIdForRenderedContainer(container: Element): string | null {
		for (const attributeName of ['data-item-id', 'data-code-view-item-id', 'item-id', 'id']) {
			const itemId = container.getAttribute(attributeName);
			if (itemId !== null && itemId.trim().length > 0) {
				return itemId;
			}
		}
		return null;
	}

	function expandedHeaderIsEmpty(container: Element): boolean {
		const shadowRoot = container.shadowRoot;
		if (shadowRoot === null) {
			return false;
		}
		const collapseButton = shadowRoot.querySelector(
			'[data-testid="bridge-code-view-header-collapse-button"]',
		);
		if (collapseButton?.getAttribute('aria-expanded') !== 'true') {
			return false;
		}
		const lineCount = shadowRoot.querySelectorAll('[data-line-index], [data-line]').length;
		return lineCount === 0 && (shadowRoot.textContent ?? '').trim().length === 0;
	}

	const panel = root.querySelector('[data-testid="bridge-code-view-panel"]');
	const renderedContainers = Array.from(root.querySelectorAll('diffs-container'));
	const renderedItemIds = renderedContainers.flatMap((container: Element): readonly string[] => {
		const itemId = itemIdForRenderedContainer(container);
		return itemId === null ? [] : [itemId];
	});
	const emptyExpandedHeaderCount = renderedContainers.filter(expandedHeaderIsEmpty).length;

	return {
		codeViewItemCount: numericAttribute(panel, 'data-code-view-item-count'),
		emptyExpandedHeaderCount,
		hasEmptyExpandedHeaders: emptyExpandedHeaderCount > 0,
		renderedItemIdCount: renderedItemIds.length,
		renderedItemIds,
		renderedItemsWithoutIdsCount: renderedContainers.length - renderedItemIds.length,
		selected: {
			cacheKeyCount: numericAttribute(panel, 'data-selected-content-cache-key-count'),
			characterCount: numericAttribute(panel, 'data-selected-content-character-count'),
			contentState: nullableStringAttribute(panel, 'data-selected-content-state'),
			displayPath: nullableStringAttribute(panel, 'data-selected-display-path'),
			itemId: nullableStringAttribute(panel, 'data-selected-item-id'),
			lineCount: numericAttribute(panel, 'data-selected-content-line-count'),
			materializedAdditionLineCount: numericAttribute(
				panel,
				'data-selected-materialized-addition-line-count',
			),
			materializedDeletionLineCount: numericAttribute(
				panel,
				'data-selected-materialized-deletion-line-count',
			),
			materializedFileLineCount: numericAttribute(
				panel,
				'data-selected-materialized-file-line-count',
			),
			materializedItemType: nullableStringAttribute(panel, 'data-selected-materialized-item-type'),
			materializedItemVersion: nullableNumericAttribute(
				panel,
				'data-selected-materialized-item-version',
			),
			materializedUpdateResult: nullableStringAttribute(
				panel,
				'data-selected-materialized-update-result',
			),
			roleCount: numericAttribute(panel, 'data-selected-content-role-count'),
		},
		visibleHydratedCacheCount: nullableNumericAttribute(
			panel,
			'data-code-view-rendered-content-resource-count',
		),
		visibleHydratedCacheCountAvailable:
			panel?.hasAttribute('data-code-view-rendered-content-resource-count') === true,
	};
}

export function parseBridgeViewerHydrationDiagnostics(
	value: unknown,
): BridgeViewerHydrationDiagnostics {
	return bridgeViewerHydrationDiagnosticsSchema.parse(value);
}

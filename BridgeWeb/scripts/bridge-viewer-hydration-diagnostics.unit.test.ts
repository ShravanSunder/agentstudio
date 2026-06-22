// @vitest-environment jsdom

import { describe, expect, test } from 'vitest';

import {
	bridgeViewerHydrationDiagnosticsSchema,
	collectBridgeViewerHydrationDiagnosticsFromRoot,
} from './bridge-viewer-hydration-diagnostics.ts';

describe('bridge viewer hydration diagnostics', () => {
	test('collects selected file and CodeView hydration facts from DOM diagnostics', () => {
		document.body.innerHTML = `
			<section
				data-testid="bridge-code-view-panel"
				data-code-view-item-count="42"
				data-selected-content-cache-key-count="2"
				data-selected-content-character-count="128"
				data-selected-content-line-count="8"
				data-selected-content-role-count="1"
				data-selected-content-state="ready"
				data-selected-display-path="Sources/App/Selected.swift"
				data-selected-item-id="item-selected"
				data-selected-materialized-addition-line-count="5"
				data-selected-materialized-deletion-line-count="3"
				data-selected-materialized-file-line-count="0"
				data-selected-materialized-item-type="diff"
				data-selected-materialized-item-version="7"
				data-selected-materialized-update-result="updated"
			></section>
			<div class="bridge-code-view-scroll-owner"></div>
		`;
		const hydratedContainer = document.createElement('diffs-container');
		hydratedContainer.setAttribute('data-item-id', 'item-selected');
		const hydratedShadow = hydratedContainer.attachShadow({ mode: 'open' });
		hydratedShadow.innerHTML = `
			<button data-testid="bridge-code-view-header-collapse-button" aria-expanded="true">
				Sources/App/Selected.swift
			</button>
			<div data-line-index="0">line one</div>
			<div data-line-index="1">line two</div>
		`;
		document.body.append(hydratedContainer);

		const emptyExpandedContainer = document.createElement('diffs-container');
		emptyExpandedContainer.setAttribute('data-item-id', 'item-empty');
		const emptyShadow = emptyExpandedContainer.attachShadow({ mode: 'open' });
		emptyShadow.innerHTML = `
			<button data-testid="bridge-code-view-header-collapse-button" aria-expanded="true"></button>
		`;
		document.body.append(emptyExpandedContainer);

		const diagnostics = collectBridgeViewerHydrationDiagnosticsFromRoot(document);

		expect(bridgeViewerHydrationDiagnosticsSchema.parse(diagnostics)).toEqual({
			codeViewItemCount: 42,
			emptyExpandedHeaderCount: 1,
			hasEmptyExpandedHeaders: true,
			renderedItemIdCount: 2,
			renderedItemIds: ['item-selected', 'item-empty'],
			renderedItemsWithoutIdsCount: 0,
			selected: {
				cacheKeyCount: 2,
				characterCount: 128,
				contentState: 'ready',
				displayPath: 'Sources/App/Selected.swift',
				itemId: 'item-selected',
				lineCount: 8,
				materializedAdditionLineCount: 5,
				materializedDeletionLineCount: 3,
				materializedFileLineCount: 0,
				materializedItemType: 'diff',
				materializedItemVersion: 7,
				materializedUpdateResult: 'updated',
				roleCount: 1,
			},
			visibleHydratedCacheCount: null,
			visibleHydratedCacheCountAvailable: false,
		});
	});

	test('counts expanded headers with only header text as empty rendered bodies', () => {
		document.body.innerHTML = `
			<section data-testid="bridge-code-view-panel"></section>
		`;
		const emptyExpandedContainer = document.createElement('diffs-container');
		emptyExpandedContainer.setAttribute('data-item-id', 'item-header-only');
		const shadowRoot = emptyExpandedContainer.attachShadow({ mode: 'open' });
		shadowRoot.innerHTML = `
			<header data-diffs-header="default">
				<button data-testid="bridge-code-view-header-collapse-button" aria-expanded="true">
					BridgeWeb/src/review-viewer/placeholder.ts
				</button>
			</header>
		`;
		document.body.append(emptyExpandedContainer);

		const diagnostics = collectBridgeViewerHydrationDiagnosticsFromRoot(document);

		expect(diagnostics.emptyExpandedHeaderCount).toBe(1);
		expect(diagnostics.hasEmptyExpandedHeaders).toBe(true);
	});
});

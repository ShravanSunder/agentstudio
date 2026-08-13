import { afterEach, describe, expect, test } from 'vitest';
import { cleanup, render } from 'vitest-browser-react';

// oxlint-disable-next-line import/no-unassigned-import -- Browser Mode must load production app CSS.
import '../../app/bridge-app.css';
import { BridgeReviewViewerShellBoundary } from '../../app/bridge-app-review-viewer-shell-boundary.js';

describe('Bridge Review comparison shell Browser Mode', () => {
	afterEach(async (): Promise<void> => {
		await cleanup();
	});

	test('preserves the ordinary fallback canvas layout without a comparison banner', async () => {
		const rendered = await render(
			<BridgeReviewViewerShellBoundary
				comparisonPaneState={{ kind: 'settled' }}
				isActive
				onRetryComparison={(): void => {}}
				presentationState={{ status: 'empty' }}
				viewerContextSwitcher={<div>Files and Review</div>}
				viewerHeaderControls={<div>Review controls</div>}
			/>,
		);

		await expect.element(rendered.getByTestId('bridge-review-empty-shell')).toBeVisible();
		const fallbackCanvas = rendered.getByTestId('bridge-review-fallback-canvas').element();
		expect(fallbackCanvas.parentElement?.className).toContain('grid-rows-[auto_minmax(0,1fr)]');
	});

	test('keeps initial comparison loading inside the content pane while navigation remains available', async () => {
		const rendered = await render(
			<BridgeReviewViewerShellBoundary
				comparisonPaneState={{
					kind: 'loadingInitial',
					requestedTargetLabel: 'feature/new-target',
				}}
				isActive
				onRetryComparison={(): void => {}}
				presentationState={{ status: 'empty' }}
				viewerContextSwitcher={<button type="button">Files and Review</button>}
				viewerHeaderControls={<div>Review controls</div>}
			/>,
		);

		await expect
			.element(rendered.getByRole('status'))
			.toHaveTextContent('Loading comparison with feature/new-target');
		await expect
			.element(rendered.getByTestId('bridge-review-comparison-loading-spinner'))
			.toBeVisible();
		expect(rendered.getByRole('progressbar').query()).toBeNull();
		await expect
			.element(rendered.getByTestId('bridge-review-comparison-initial-shell'))
			.toBeVisible();
		const contextSwitcher = rendered.getByRole('button', { name: 'Files and Review' }).element();
		expect(
			contextSwitcher.closest('[data-testid="bridge-review-rail-toolbar-leading"]'),
		).not.toBeNull();
		expect(
			contextSwitcher.closest('[data-testid="bridge-viewer-content-topbar-controls"]'),
		).toBeNull();
	});
});

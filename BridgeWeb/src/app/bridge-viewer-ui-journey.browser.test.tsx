import { act } from 'react';
import { afterEach, describe, expect, test } from 'vitest';
import { cleanup } from 'vitest-browser-react';
import { page, userEvent } from 'vitest/browser';

// oxlint-disable-next-line import/no-unassigned-import -- Browser Mode must load production app CSS.
import './bridge-app.css';
import {
	advanceBridgeReviewRecoveryWitnessFrames,
	disposeBridgeReviewRecoveryWitnessHarnesses,
	makeBridgeReviewRecoveryWitnessFiles,
	renderBridgeReviewRecoveryWitness,
} from '../review-viewer/test-support/bridge-viewer-browser.recovery-witness.test-support.js';

const defaultViewport = { height: 972, width: 1_728 } as const;
const narrowViewport = { height: 860, width: 1_024 } as const;

describe('Bridge viewer synthetic production-shell journey', () => {
	afterEach(async (): Promise<void> => {
		await cleanup();
		disposeBridgeReviewRecoveryWitnessHarnesses();
		await advanceBridgeReviewRecoveryWitnessFrames(2);
		document.body.replaceChildren();
		await page.viewport(defaultViewport.width, defaultViewport.height);
	});

	test('preserves Review selection through search, filters, settings, focus, and narrow layout', async () => {
		// Arrange: the established boundary supplies worker events, while the mounted viewer,
		// Pierre tree/code surfaces, toolbar, menus, and settings are production components.
		await page.viewport(defaultViewport.width, defaultViewport.height);
		const files = makeBridgeReviewRecoveryWitnessFiles({
			count: 6,
			lineCount: 5,
			markerPrefix: 'STYLE_JOURNEY',
		}).map((file, index) =>
			Object.assign({}, file, {
				changeKind: index < 3 ? ('added' as const) : ('modified' as const),
				fileClass: index < 3 ? ('source' as const) : ('test' as const),
			}),
		);
		const harness = await renderBridgeReviewRecoveryWitness(files);
		await harness.publishDisplay();
		await harness.publishCompleteContent();
		await expect.element(harness.renderResult.getByTestId('review-viewer-shell')).toBeVisible();

		const selectedFile = files[4];
		if (selectedFile === undefined) throw new Error('Review style journey selection is missing.');
		const selectedTreeRow = await harness.scrollTreePathIntoView(selectedFile.path);
		await act(async (): Promise<void> => {
			await userEvent.click(selectedTreeRow);
			await userEvent.unhover(selectedTreeRow);
		});
		await advanceBridgeReviewRecoveryWitnessFrames(2);
		await expectSelectedPath(harness.renderResult.container, selectedFile.path);
		expect(harness.codeText()).toContain(selectedFile.contentMarker);

		// Assert: the normal clean-Chrome viewport resolves the compact canonical scale.
		const filterTrigger = requireHTMLElement(
			document.querySelector('[data-testid="bridge-review-facet-menu-control"]'),
		);
		const searchTrigger = requireHTMLElement(
			document.querySelector('[data-testid="bridge-review-search-toggle"]'),
		);
		const settingsTrigger = requireHTMLElement(
			document.querySelector('[data-testid="bridge-review-view-settings-trigger"]'),
		);
		for (const control of [filterTrigger, searchTrigger, settingsTrigger]) {
			expect(compactControlGeometry(control)).toEqual({
				fontSize: '11px',
				height: 24,
				width: 24,
			});
		}

		// Act: search the real Pierre tree, clear without closing, then close with Escape.
		await clickAndSettle(searchTrigger);
		const searchInput = requireInput(
			document.querySelector('[data-testid="bridge-review-search-input"]'),
		);
		expect(document.activeElement).toBe(searchInput);
		await act(async (): Promise<void> => {
			await harness.renderResult.getByTestId('bridge-review-search-input').fill('RecoveryFile005');
		});
		await advanceBridgeReviewRecoveryWitnessFrames(2);
		expect(mountedTreePaths(harness.pierreTreeHost())).toContain(selectedFile.path);
		await expectSelectedPath(harness.renderResult.container, selectedFile.path);

		await clickAndSettle(
			requireHTMLElement(document.querySelector('[data-testid="bridge-review-search-clear"]')),
		);
		await expect
			.element(harness.renderResult.getByTestId('bridge-review-search-input'))
			.toHaveValue('');
		await expectSelectedPath(harness.renderResult.container, selectedFile.path);
		await clickAndSettle(searchInput);
		await act(async (): Promise<void> => {
			await userEvent.keyboard('{Escape}');
		});
		await advanceBridgeReviewRecoveryWitnessFrames(2);
		await expect
			.poll((): Element | null =>
				document.querySelector('[data-testid="bridge-review-search-input"]'),
			)
			.toBeNull();
		await expect
			.poll((): string | undefined => deepActiveElement()?.dataset['itemPath']?.replace(/\/$/u, ''))
			.toBe(selectedFile.path);

		// Act: filter to the selected file's real change class, then restore the full tree.
		await clickAndSettle(filterTrigger);
		const facetPopup = requireHTMLElement(
			document.querySelector('[data-testid="bridge-review-facet-popover"]'),
		);
		await finishAnimations(facetPopup);
		assertInsideViewport(facetPopup, defaultViewport);
		const disabledFacetClear = requireHTMLElement(
			document.querySelector('[data-testid="bridge-review-facet-clear"]'),
		);
		expect(disabledFacetClear.getBoundingClientRect().height).toBe(28);
		expect(getComputedStyle(disabledFacetClear).opacity).toBe('1');
		expect(disabledFacetClear.hasAttribute('data-disabled')).toBe(true);

		const modifiedOption = findFacetOption('Modified');
		expect(modifiedOption.getBoundingClientRect().height).toBe(28);
		await clickAndSettle(modifiedOption);
		await advanceBridgeReviewRecoveryWitnessFrames(2);
		expect(mountedTreePaths(harness.pierreTreeHost())).toEqual([
			'Sources',
			'Sources/RecoveryGroup02',
			...files.slice(3).map((file) => file.path),
		]);
		await expectSelectedPath(harness.renderResult.container, selectedFile.path);
		await clickAndSettle(
			requireHTMLElement(document.querySelector('[data-testid="bridge-review-facet-clear"]')),
		);
		await advanceBridgeReviewRecoveryWitnessFrames(2);
		expect(mountedTreePaths(harness.pierreTreeHost())).toHaveLength(9);
		await expectSelectedPath(harness.renderResult.container, selectedFile.path);
		await act(async (): Promise<void> => {
			await userEvent.keyboard('{Escape}');
		});
		await finishAnimations(facetPopup);
		await advanceBridgeReviewRecoveryWitnessFrames(2);
		expect(document.activeElement).toBe(filterTrigger);

		// Act: change a renderer-backed view setting and reset it through the same menu.
		await clickAndSettle(settingsTrigger);
		const settingsPopup = requireHTMLElement(
			document.querySelector('[data-testid="bridge-review-view-settings-content"]'),
		);
		await finishAnimations(settingsPopup);
		assertInsideViewport(settingsPopup, defaultViewport);
		const settingsRows = menuRows(settingsPopup);
		expect(settingsRows.length).toBeGreaterThan(0);
		for (const row of settingsRows) expect(row.getBoundingClientRect().height).toBe(28);
		const disabledReset = requireHTMLElement(
			document.querySelector('[data-testid="bridge-review-view-settings-reset"]'),
		);
		expect(disabledReset.hasAttribute('data-disabled')).toBe(true);
		expect(getComputedStyle(disabledReset).opacity).toBe('1');

		await clickAndSettle(findViewSettingsRow(settingsPopup, 'Word wrap'));
		await expect.poll(() => codeViewOverflow(harness.renderResult.container)).toContain('scroll');
		await expectSelectedPath(harness.renderResult.container, selectedFile.path);
		const enabledReset = requireHTMLElement(
			document.querySelector('[data-testid="bridge-review-view-settings-reset"]'),
		);
		expect(enabledReset.hasAttribute('data-disabled')).toBe(false);
		await clickAndSettle(enabledReset);
		await expect.poll(() => codeViewOverflow(harness.renderResult.container)).toContain('wrap');
		await expectSelectedPath(harness.renderResult.container, selectedFile.path);

		// Assert: the reused harness supports a bounded 1024px host surface. Keep Chrome's
		// configured viewport stable because its mounted floating observers are viewport-aware.
		const fixtureRoot = requireHTMLElement(
			document.querySelector('[data-testid="bridge-review-recovery-witness-root"]'),
		);
		await act(async (): Promise<void> => {
			fixtureRoot.style.width = `${narrowViewport.width}px`;
			await Promise.resolve();
		});
		await advanceBridgeReviewRecoveryWitnessFrames(2);
		const fixtureBounds = fixtureRoot.getBoundingClientRect();
		assertInsideBounds(filterTrigger, fixtureBounds);
		assertInsideBounds(searchTrigger, fixtureBounds);
		assertInsideBounds(settingsTrigger, fixtureBounds);
		expect(document.activeElement).toBe(settingsTrigger);
		await expectSelectedPath(harness.renderResult.container, selectedFile.path);
		await page.screenshot({
			element: fixtureRoot,
			path: '../../../tmp/bridge-viewer-ui-journey-review-settings-1024.png',
		});
	});
});

async function clickAndSettle(element: HTMLElement): Promise<void> {
	await act(async (): Promise<void> => {
		await userEvent.click(element);
		await userEvent.unhover(element);
	});
	await advanceBridgeReviewRecoveryWitnessFrames(2);
}

async function expectSelectedPath(container: HTMLElement, expectedPath: string): Promise<void> {
	await expect
		.poll(
			(): string | undefined =>
				container.querySelector<HTMLElement>('[data-testid="review-viewer-shell"]')?.dataset[
					'selectedDisplayPath'
				],
		)
		.toBe(expectedPath);
}

function compactControlGeometry(element: HTMLElement): {
	readonly fontSize: string;
	readonly height: number;
	readonly width: number;
} {
	const bounds = element.getBoundingClientRect();
	return {
		fontSize: getComputedStyle(element).fontSize,
		height: bounds.height,
		width: bounds.width,
	};
}

function mountedTreePaths(treeHost: HTMLElement | null): readonly string[] {
	if (treeHost?.shadowRoot === null || treeHost?.shadowRoot === undefined) return [];
	return [...treeHost.shadowRoot.querySelectorAll<HTMLElement>('[data-item-path]')]
		.map((row): string => row.dataset['itemPath']?.replace(/\/$/u, '') ?? '')
		.filter((path): boolean => path.length > 0)
		.filter((path, index, paths): boolean => paths.indexOf(path) === index)
		.toSorted();
}

function findFacetOption(label: string): HTMLElement {
	const option = [
		...document.querySelectorAll<HTMLElement>('[data-testid="bridge-review-facet-option"]'),
	].find(
		(candidate): boolean =>
			candidate
				.querySelector('[data-testid="bridge-review-facet-option-label"]')
				?.textContent?.trim() === label,
	);
	if (option === undefined) throw new Error(`Expected Review facet option ${label}.`);
	return option;
}

function findViewSettingsRow(popup: HTMLElement, label: string): HTMLElement {
	const row = menuRows(popup).find(
		(candidate): boolean =>
			candidate.querySelector('[data-bridge-view-settings-row-label]')?.textContent?.trim() ===
			label,
	);
	if (row === undefined) throw new Error(`Expected Review view-settings row ${label}.`);
	return row;
}

function menuRows(popup: HTMLElement): readonly HTMLElement[] {
	return [
		...popup.querySelectorAll<HTMLElement>(
			'[role="menuitem"], [role="menuitemcheckbox"], [role="menuitemradio"]',
		),
	];
}

function codeViewOverflow(container: HTMLElement): readonly string[] {
	return allElementsIncludingOpenShadowRoots(container)
		.map((element): string | null => element.getAttribute('data-bridge-code-view-overflow'))
		.filter((value): value is string => value !== null);
}

function allElementsIncludingOpenShadowRoots(root: ParentNode): readonly HTMLElement[] {
	const rootElements = [...root.querySelectorAll<HTMLElement>('*')];
	const elements = [...rootElements];
	for (const element of rootElements) {
		if (element.shadowRoot !== null)
			elements.push(...allElementsIncludingOpenShadowRoots(element.shadowRoot));
	}
	return elements;
}

function deepActiveElement(root: Document | ShadowRoot = document): HTMLElement | null {
	const activeElement = root.activeElement;
	if (!(activeElement instanceof HTMLElement)) return null;
	return activeElement.shadowRoot === null
		? activeElement
		: (deepActiveElement(activeElement.shadowRoot) ?? activeElement);
}

function assertInsideViewport(
	element: HTMLElement,
	viewport: Readonly<{ height: number; width: number }>,
): void {
	const bounds = element.getBoundingClientRect();
	expect(bounds.left).toBeGreaterThanOrEqual(0);
	expect(bounds.top).toBeGreaterThanOrEqual(0);
	expect(bounds.right).toBeLessThanOrEqual(viewport.width);
	expect(bounds.bottom).toBeLessThanOrEqual(viewport.height);
}

function assertInsideBounds(element: HTMLElement, containingBounds: DOMRect): void {
	const bounds = element.getBoundingClientRect();
	expect(bounds.left).toBeGreaterThanOrEqual(containingBounds.left);
	expect(bounds.top).toBeGreaterThanOrEqual(containingBounds.top);
	expect(bounds.right).toBeLessThanOrEqual(containingBounds.right);
	expect(bounds.bottom).toBeLessThanOrEqual(containingBounds.bottom);
}

async function finishAnimations(element: HTMLElement): Promise<void> {
	await act(async (): Promise<void> => {
		await Promise.all(
			element.getAnimations({ subtree: true }).map(async (animation) => animation.finished),
		);
	});
}

function requireHTMLElement(element: Element | null): HTMLElement {
	if (!(element instanceof HTMLElement)) throw new Error('Expected a real Browser Mode element.');
	return element;
}

function requireInput(element: Element | null): HTMLInputElement {
	if (!(element instanceof HTMLInputElement)) {
		throw new Error('Expected a real Browser Mode input.');
	}
	return element;
}

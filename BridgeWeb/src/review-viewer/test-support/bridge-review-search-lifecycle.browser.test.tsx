import { act } from 'react';
import { afterEach, describe, expect, test } from 'vitest';
import { cleanup } from 'vitest-browser-react';

// oxlint-disable-next-line import/no-unassigned-import -- Browser Mode must load production app CSS.
import '../../app/bridge-app.css';
import {
	advanceBridgeReviewRecoveryWitnessFrames,
	disposeBridgeReviewRecoveryWitnessHarnesses,
	makeBridgeReviewRecoveryWitnessFiles,
	renderBridgeReviewRecoveryWitness,
} from './bridge-viewer-browser.recovery-witness.test-support.js';

describe('Bridge Review Search lifecycle', () => {
	afterEach(async (): Promise<void> => {
		await cleanup();
		disposeBridgeReviewRecoveryWitnessHarnesses();
		await advanceBridgeReviewRecoveryWitnessFrames(2);
		document.body.replaceChildren();
	});

	test('shares atomic visible and semantic admission without changing selection or demand', async () => {
		const harness = await renderBridgeReviewRecoveryWitness(
			makeBridgeReviewRecoveryWitnessFiles({ count: 6, lineCount: 3, markerPrefix: 'SEARCH' }),
		);
		await harness.publishDisplay();
		await expect
			.element(harness.renderResult.getByTestId('bridge-review-search-toggle'))
			.toBeEnabled();
		await act(async (): Promise<void> => {
			await harness.renderResult.getByTestId('bridge-review-search-toggle').click();
			await harness.renderResult.getByTestId('bridge-review-regex-toggle').click();
			await harness.renderResult
				.getByTestId('bridge-review-search-input')
				.fill(String.raw`RecoveryFile005\.swift$`);
		});
		await advanceBridgeReviewRecoveryWitnessFrames(2);
		const acceptedPaths = mountedReviewTreePaths(harness.pierreTreeHost());
		const selectionCount = harness.selectedItemCommandCount();
		const viewportCommands = harness.viewportCommandVisibleItemIds();

		await act(async (): Promise<void> => {
			await harness.renderResult.getByTestId('bridge-review-search-input').fill('[');
		});
		await expect
			.element(harness.renderResult.getByTestId('bridge-review-tree-search-status'))
			.toHaveTextContent('Invalid regex');
		expect(mountedReviewTreePaths(harness.pierreTreeHost())).toEqual(acceptedPaths);

		await act(async (): Promise<void> => {
			await harness.renderResult.getByTestId('bridge-review-search-input').fill('a'.repeat(4_097));
		});
		await expect
			.element(harness.renderResult.getByTestId('bridge-review-search-input'))
			.toHaveValue('[');
		await expect
			.element(harness.renderResult.getByTestId('bridge-review-tree-search-status'))
			.toHaveTextContent('Search query is too long');

		await dispatchSearchCommand({ mode: 'regex', query: String.raw`RecoveryFile005\.swift$` });
		await dispatchSearchCommand({ mode: 'regex', query: '[' });
		await expect
			.element(harness.renderResult.getByTestId('bridge-review-search-input'))
			.toHaveValue('[');
		expect(mountedReviewTreePaths(harness.pierreTreeHost())).toEqual(acceptedPaths);

		await dispatchSearchCommand({ mode: 'text', query: 'a'.repeat(4_097) });
		expect(window.bridgeReviewControlProbe?.reason).toBe('search_query_too_long');
		await expect
			.element(harness.renderResult.getByTestId('bridge-review-search-input'))
			.toHaveValue('[');
		expect(harness.selectedItemCommandCount()).toBe(selectionCount);
		expect(harness.viewportCommandVisibleItemIds()).toEqual(viewportCommands);
	});

	test('Clear stays open with text, closes when empty, and retains mode', async () => {
		const harness = await renderBridgeReviewRecoveryWitness(
			makeBridgeReviewRecoveryWitnessFiles({ count: 2, lineCount: 2, markerPrefix: 'CLEAR' }),
		);
		await harness.publishDisplay();
		await act(async (): Promise<void> => {
			await harness.renderResult.getByTestId('bridge-review-search-toggle').click();
			await harness.renderResult.getByTestId('bridge-review-regex-toggle').click();
			await harness.renderResult.getByTestId('bridge-review-search-input').fill('Recovery');
			await harness.renderResult.getByTestId('bridge-review-search-clear').click();
		});
		await expect
			.element(harness.renderResult.getByTestId('bridge-review-search-input'))
			.toHaveValue('');

		await act(async (): Promise<void> => {
			await harness.renderResult.getByTestId('bridge-review-search-clear').click();
			await harness.renderResult.getByTestId('bridge-review-search-toggle').click();
		});
		await expect
			.element(harness.renderResult.getByTestId('bridge-review-regex-toggle'))
			.toHaveAttribute('aria-pressed', 'true');
	});

	test('announces closed semantic rejection without opening Search or moving focus', async () => {
		const harness = await renderBridgeReviewRecoveryWitness(
			makeBridgeReviewRecoveryWitnessFiles({ count: 2, lineCount: 2, markerPrefix: 'CLOSED' }),
		);
		await harness.publishDisplay();
		const previousFocusOwner = harness.renderResult
			.getByTestId('bridge-review-search-toggle')
			.element();
		if (!(previousFocusOwner instanceof HTMLElement))
			throw new Error('Expected Review focus owner.');
		previousFocusOwner.focus();

		await dispatchSearchCommand({ mode: 'text', query: 'a'.repeat(4_097) });

		expect(document.querySelector('[data-testid="bridge-review-search-input"]')).toBeNull();
		expect(document.activeElement).toBe(previousFocusOwner);
		await expect
			.element(harness.renderResult.getByTestId('bridge-review-tree-search-status'))
			.toHaveTextContent('Search query is too long');
	});

	test('rejected Review read-back retains the immediately preceding semantic criteria', async () => {
		const harness = await renderBridgeReviewRecoveryWitness(
			makeBridgeReviewRecoveryWitnessFiles({ count: 3, lineCount: 2, markerPrefix: 'PROBE' }),
		);
		await harness.publishDisplay();

		await act(async (): Promise<void> => {
			dispatchSearchCommandWithoutSettlement({ mode: 'regex', query: 'RecoveryFile002' });
			dispatchSearchCommandWithoutSettlement({ mode: 'text', query: 'a'.repeat(4_097) });
		});
		await advanceBridgeReviewRecoveryWitnessFrames(2);

		expect(window.bridgeReviewControlProbe).toMatchObject({
			reason: 'search_query_too_long',
			status: 'rejected',
			treeSearchMode: { kind: 'regex' },
			treeSearchText: 'RecoveryFile002',
		});
	});

	test('restores Review focus by eligible path and falls back when it is excluded', async () => {
		const files = makeBridgeReviewRecoveryWitnessFiles({
			count: 3,
			lineCount: 2,
			markerPrefix: 'FOCUS',
		});
		const harness = await renderBridgeReviewRecoveryWitness(files);
		await harness.publishDisplay();
		const focusedFile = files[1];
		if (focusedFile === undefined) throw new Error('Expected Review focus fixture.');
		await expect.poll(() => harness.pierreTreePath(focusedFile.path)).not.toBeNull();
		const originalRow = harness.pierreTreePath(focusedFile.path);
		if (!(originalRow instanceof HTMLElement)) throw new Error('Expected Review tree row.');
		originalRow.focus();
		expect(deepActiveElement()).toBe(originalRow);

		await act(async (): Promise<void> => {
			await harness.renderResult.getByTestId('bridge-review-search-toggle').click();
			await harness.renderResult.getByTestId('bridge-review-search-input').fill('RecoveryFile002');
		});
		await advanceBridgeReviewRecoveryWitnessFrames(2);
		const eligibleRow = harness.pierreTreePath(focusedFile.path);
		if (!(eligibleRow instanceof HTMLElement)) throw new Error('Expected eligible Review row.');
		const searchInput = harness.pierreSearchInput();
		if (!(searchInput instanceof HTMLInputElement))
			throw new Error('Expected Review Search input.');
		await act(async (): Promise<void> => {
			searchInput.dispatchEvent(new KeyboardEvent('keydown', { bubbles: true, key: 'Escape' }));
		});
		expect(deepActiveElement()?.getAttribute('data-item-path')).toBe(focusedFile.path);

		const currentEligibleRow = harness.pierreTreePath(focusedFile.path);
		if (!(currentEligibleRow instanceof HTMLElement)) {
			throw new Error('Expected current eligible Review row.');
		}
		currentEligibleRow.focus();
		await act(async (): Promise<void> => {
			await harness.renderResult.getByTestId('bridge-review-search-toggle').click();
			await harness.renderResult.getByTestId('bridge-review-search-input').fill('NoSuchPath');
		});
		await advanceBridgeReviewRecoveryWitnessFrames(2);
		const excludedSearchInput = harness.pierreSearchInput();
		if (!(excludedSearchInput instanceof HTMLInputElement)) {
			throw new Error('Expected excluded Review Search input.');
		}
		await act(async (): Promise<void> => {
			excludedSearchInput.dispatchEvent(
				new KeyboardEvent('keydown', { bubbles: true, key: 'Escape' }),
			);
		});
		expect(document.activeElement).toBe(
			harness.renderResult.getByTestId('bridge-review-search-toggle').element(),
		);
	});
});

async function dispatchSearchCommand(props: {
	readonly mode: 'regex' | 'text';
	readonly query: string;
}): Promise<void> {
	await act(async (): Promise<void> => {
		window.dispatchEvent(
			new CustomEvent('__bridge_review_control', {
				detail: {
					method: 'bridge.fileTree.search',
					searchMode: { kind: props.mode },
					searchText: props.query,
				},
			}),
		);
	});
	await advanceBridgeReviewRecoveryWitnessFrames(2);
}

function dispatchSearchCommandWithoutSettlement(props: {
	readonly mode: 'regex' | 'text';
	readonly query: string;
}): void {
	window.dispatchEvent(
		new CustomEvent('__bridge_review_control', {
			detail: {
				method: 'bridge.fileTree.search',
				searchMode: { kind: props.mode },
				searchText: props.query,
			},
		}),
	);
}

function mountedReviewTreePaths(treeHost: HTMLElement | null): readonly string[] {
	if (treeHost?.shadowRoot === null || treeHost?.shadowRoot === undefined) return [];
	return [...treeHost.shadowRoot.querySelectorAll<HTMLElement>('[data-item-path]')]
		.map((row): string => row.dataset['itemPath']?.replace(/\/$/u, '') ?? '')
		.filter((path): boolean => path.length > 0)
		.filter((path, index, paths): boolean => paths.indexOf(path) === index)
		.toSorted();
}

function deepActiveElement(): Element | null {
	let activeElement = document.activeElement;
	while (activeElement instanceof HTMLElement) {
		const shadowActiveElement = activeElement.shadowRoot?.activeElement;
		if (shadowActiveElement === null || shadowActiveElement === undefined) break;
		activeElement = shadowActiveElement;
	}
	return activeElement;
}

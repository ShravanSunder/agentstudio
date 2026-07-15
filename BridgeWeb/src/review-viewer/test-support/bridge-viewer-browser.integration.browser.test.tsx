import { act, useCallback, useRef, useState, type ReactElement } from 'react';
import { afterEach, describe, expect, test } from 'vitest';
import { cleanup, render } from 'vitest-browser-react';

// oxlint-disable-next-line import/no-unassigned-import -- Browser Mode must load production app CSS.
import '../../app/bridge-app.css';
import {
	useBridgeReviewNavigationController,
	type BridgeReviewNavigationTarget,
	type BridgeReviewNavigationSelectionSource,
} from '../../app/bridge-app-review-navigation-controller.js';
import {
	useBridgeReviewSelectionController,
	type BridgeReviewSelectionSource,
} from '../../app/bridge-app-review-selection-controller.js';
import {
	BridgeReviewViewerShellBoundary,
	type BridgeReviewViewerPresentationState,
} from '../../app/bridge-app-review-viewer-shell-boundary.js';
import type { BridgeViewerNavigationCommand } from '../../app/bridge-viewer-navigation-models.js';
import { createBridgeReviewItemRegistry } from '../../foundation/review-package/bridge-review-item-registry.js';
import { makeBridgeReviewPackage } from '../../foundation/review-package/bridge-review-package-test-support.js';
import { buildBridgeReviewProjection } from '../navigation/review-projection.js';
import {
	advanceBridgeReviewRecoveryWitnessFrames,
	disposeBridgeReviewRecoveryWitnessHarnesses,
	makeBridgeReviewRecoveryWitnessFiles,
	renderBridgeReviewRecoveryWitness,
} from './bridge-viewer-browser.recovery-witness.test-support.js';

describe('Bridge Review production recovery Browser witnesses', () => {
	afterEach(async (): Promise<void> => {
		cleanup();
		disposeBridgeReviewRecoveryWitnessHarnesses();
		await advanceBridgeReviewRecoveryWitnessFrames(2);
		document.body.replaceChildren();
	});

	test('mounts hierarchical Review navigation through Pierre Trees', async () => {
		// Arrange
		const files = makeBridgeReviewRecoveryWitnessFiles({
			count: 6,
			lineCount: 3,
			markerPrefix: 'HIERARCHY',
		});
		const harness = renderBridgeReviewRecoveryWitness(files);
		await expect
			.element(harness.renderResult.getByTestId('bridge-review-fallback-frame'))
			.toBeVisible();

		// Act
		await harness.publishDisplay();
		await expect.element(harness.renderResult.getByTestId('review-viewer-shell')).toBeVisible();
		await advanceBridgeReviewRecoveryWitnessFrames(2);

		// Assert
		await expect
			.poll(() => harness.pierreTreeHost(), {
				message:
					'G0 REVIEW HIERARCHY MISSING: expected the production Review rail to mount hierarchical @pierre/trees instead of flat depth-only rows.',
			})
			.not.toBeNull();
		await expect.poll(() => harness.pierreTreePath('Sources')).not.toBeNull();
		await expect.poll(() => harness.pierreTreePath('Sources/RecoveryGroup01')).not.toBeNull();
		await expect.poll(() => harness.pierreTreePath(files[0]?.path ?? '')).not.toBeNull();
		expect(harness.expandedTreePaths().toSorted()).toEqual(expectedExpandedRecoveryTreePaths());
		for (const directoryPath of expectedExpandedRecoveryTreePaths()) {
			expect(harness.pierreTreePath(directoryPath)?.getAttribute('aria-expanded')).toBe('true');
		}
	});

	test('opens and updates recovered Review tree search synchronously', async () => {
		// Arrange
		const files = makeBridgeReviewRecoveryWitnessFiles({
			count: 6,
			lineCount: 3,
			markerPrefix: 'SEARCH',
		});
		const harness = renderBridgeReviewRecoveryWitness(files);
		await harness.publishDisplay();
		await expect.element(harness.renderResult.getByTestId('review-viewer-shell')).toBeVisible();

		// Act
		await act(async (): Promise<void> => {
			await harness.renderResult.getByTestId('bridge-review-search-toggle').click();
		});

		// Assert
		await expect
			.element(harness.renderResult.getByTestId('bridge-review-search-toggle'))
			.toHaveAttribute('aria-pressed', 'true');
		await expect
			.poll(() => harness.pierreSearchInput(), {
				message:
					'J1 REVIEW SEARCH INERT: expected the production search control to synchronously open and focus Pierre Trees search.',
			})
			.not.toBeNull();
		const searchInput = harness.pierreSearchInput();
		if (!(searchInput instanceof HTMLInputElement)) {
			throw new Error('J1 REVIEW SEARCH INPUT MISSING');
		}
		const searchRoot = searchInput.getRootNode();
		expect(searchRoot).toBeInstanceOf(ShadowRoot);
		if (!(searchRoot instanceof ShadowRoot)) throw new Error('J1 REVIEW SEARCH ROOT MISSING');
		expect(searchRoot.activeElement).toBe(searchInput);

		// Act
		const expectedMatch = files[4];
		if (expectedMatch === undefined) throw new Error('J1 REVIEW SEARCH FIXTURE MISSING');
		await act(async (): Promise<void> => {
			searchInput.value = 'RecoveryFile005';
			searchInput.dispatchEvent(new InputEvent('input', { bubbles: true }));
			await Promise.resolve();
		});
		await advanceBridgeReviewRecoveryWitnessFrames(2);

		// Assert
		expect(searchInput.value).toBe('recoveryfile005');
		const activeDescendantId = searchInput.getAttribute('aria-activedescendant');
		expect(activeDescendantId).not.toBeNull();
		const activeDescendant = searchRoot.getElementById(activeDescendantId ?? '');
		expect(activeDescendant?.getAttribute('data-item-path')).toBe(expectedMatch.path);

		// Act
		await act(async (): Promise<void> => {
			await harness.renderResult.getByTestId('bridge-review-regex-toggle').click();
		});

		// Assert
		await expect
			.element(harness.renderResult.getByTestId('bridge-review-regex-toggle'))
			.toHaveAttribute('aria-pressed', 'true');
	});

	test('reveals ancestors for explicit Review navigation without changing fresh disclosure', async () => {
		// Arrange
		const files = makeBridgeReviewRecoveryWitnessFiles({
			count: 6,
			lineCount: 3,
			markerPrefix: 'EXPLICIT_REVEAL',
		});
		const targetFile = files[4];
		if (targetFile === undefined) throw new Error('J1 REVIEW EXPLICIT REVEAL FIXTURE MISSING');
		const harness = renderBridgeReviewRecoveryWitness(files, {
			navigationCommand: reviewNavigationCommand('explicit-reveal-command', targetFile.itemId),
		});

		// Act
		await harness.publishDisplay();
		await expect.poll(() => harness.selectedItemCommandCount()).toBe(1);

		// Assert
		await expect.poll(() => harness.pierreTreePath(targetFile.path)).not.toBeNull();
		const targetRow = harness.pierreTreePath(targetFile.path);
		expect(targetRow?.hasAttribute('data-item-selected')).toBe(true);
		expect(harness.expandedTreePaths().toSorted()).toEqual(expectedExpandedRecoveryTreePaths());
		expect(harness.pierreTreePath('Sources/RecoveryGroup01')?.getAttribute('aria-expanded')).toBe(
			'true',
		);
	});

	test('resets a fresh Review epoch fully expanded without replaying an old selection reveal', async () => {
		// Arrange
		const files = makeBridgeReviewRecoveryWitnessFiles({
			count: 6,
			lineCount: 3,
			markerPrefix: 'EPOCH_DISCLOSURE',
		});
		const targetFile = files[4];
		if (targetFile === undefined) throw new Error('Review epoch disclosure fixture is incomplete.');
		const harness = renderBridgeReviewRecoveryWitness(files, {
			navigationCommand: reviewNavigationCommand('epoch-disclosure-command', targetFile.itemId),
		});
		await harness.publishDisplay();
		await expect.poll(() => harness.pierreTreePath(targetFile.path)).not.toBeNull();
		expect(harness.expandedTreePaths().toSorted()).toEqual(expectedExpandedRecoveryTreePaths());
		const initialSelectionScrollCount = harness.selectionScrollToPathSampleCount();

		// Act
		await harness.publishDisplayAtEpoch(2);

		// Assert
		expect(
			harness.expandedTreePaths().toSorted(),
			'Fresh Review epochs must not replay a stale selection-reveal request from the prior tree.',
		).toEqual(expectedExpandedRecoveryTreePaths());
		expect(harness.pierreTreePath('Sources')?.getAttribute('aria-expanded')).toBe('true');
		expect(harness.selectionScrollToPathSampleCount()).toBe(initialSelectionScrollCount);
	});

	test('does not replay an old selection reveal after a same-generation Review package replacement', async () => {
		// Arrange: Vite can replace package/source identity while retaining generation 1.
		const files = makeBridgeReviewRecoveryWitnessFiles({
			count: 6,
			lineCount: 3,
			markerPrefix: 'PACKAGE_DISCLOSURE',
		});
		const targetFile = files[4];
		if (targetFile === undefined)
			throw new Error('Review package disclosure fixture is incomplete.');
		const harness = renderBridgeReviewRecoveryWitness(files, {
			navigationCommand: reviewNavigationCommand('package-disclosure-command', targetFile.itemId),
		});
		await harness.publishDisplay();
		await expect.poll(() => harness.pierreTreePath(targetFile.path)).not.toBeNull();
		expect(harness.expandedTreePaths().toSorted()).toEqual(expectedExpandedRecoveryTreePaths());
		const initialSelectionScrollCount = harness.selectionScrollToPathSampleCount();

		// Act: replace the package at the same worker generation without issuing new navigation.
		await harness.publishDisplayAtPackageIdentity('review-recovery-replacement-window');

		// Assert
		expect(
			harness.expandedTreePaths().toSorted(),
			'REVIEW_STALE_PACKAGE_REVEAL: a prior package reveal must not reselect an item after replacement.',
		).toEqual(expectedExpandedRecoveryTreePaths());
		expect(harness.pierreTreePath('Sources')?.getAttribute('aria-expanded')).toBe('true');
		expect(harness.selectionScrollToPathSampleCount()).toBe(initialSelectionScrollCount);
	});

	test('defers an inactive ready presentation and resets it after a fallback state', async () => {
		// Arrange
		const readyPresentation = makeReadyReviewPresentationState('activation-review');
		const rendered = await renderInsideAct(
			<ReviewBoundaryActivationProbe readyPresentation={readyPresentation} />,
		);
		await expect
			.element(rendered.getByTestId('bridge-review-projection-pending-shell'))
			.toBeVisible();

		// Act
		await act(async (): Promise<void> => {
			await rendered.getByRole('button', { name: 'Show empty Review fallback' }).click();
		});

		// Assert
		await expect.element(rendered.getByTestId('bridge-review-empty-shell')).toBeVisible();

		// Act
		await act(async (): Promise<void> => {
			await rendered.getByRole('button', { name: 'Restore ready Review presentation' }).click();
		});

		// Assert
		await expect
			.element(rendered.getByTestId('bridge-review-projection-pending-shell'))
			.toBeVisible();
	});

	test('keeps selection local-first and mark-viewed retries bounded across A to B to A', async () => {
		// Arrange
		const events: string[] = [];
		const rendered = await renderInsideAct(<ReviewSelectionControllerProbe events={events} />);

		// Act
		await act(async (): Promise<void> => {
			await rendered.getByRole('button', { name: 'Select unknown Review item' }).click();
		});

		// Assert
		expect(events).toEqual([]);

		// Act
		await act(async (): Promise<void> => {
			await rendered.getByRole('button', { name: 'Select Review item A' }).click();
		});
		await expect.poll(() => events.includes('mark:item-a:1')).toBe(true);

		// Assert
		expect(events.slice(0, 3)).toEqual(['local:item-a', 'intent:item-a:user', 'mark:item-a:1']);

		// Act
		await act(async (): Promise<void> => {
			await rendered.getByRole('button', { name: 'Select Review item A' }).click();
		});
		await expect.poll(() => events.includes('mark:item-a:2')).toBe(true);
		await act(async (): Promise<void> => {
			await rendered.getByRole('button', { name: 'Select Review item A' }).click();
			await Promise.resolve();
		});

		// Assert
		expect(events.filter((event) => event.startsWith('mark:item-a:'))).toHaveLength(2);

		// Act
		await act(async (): Promise<void> => {
			await rendered.getByRole('button', { name: 'Select Review item B' }).click();
		});
		await expect.poll(() => events.includes('mark:item-b:1')).toBe(true);
		await act(async (): Promise<void> => {
			await rendered.getByRole('button', { name: 'Select Review item A' }).click();
		});
		await expect.poll(() => events.includes('mark:item-a:3')).toBe(true);

		// Assert
		expect(events.filter((event) => event.startsWith('local:'))).toEqual([
			'local:item-a',
			'local:item-b',
			'local:item-a',
		]);
		expect(events.filter((event) => event.startsWith('intent:'))).toEqual([
			'intent:item-a:user',
			'intent:item-b:keyboard',
			'intent:item-a:user',
		]);
	});

	test('paints local Review selection before sending the typed worker intent', async () => {
		// Arrange
		const files = makeBridgeReviewRecoveryWitnessFiles({
			count: 3,
			lineCount: 3,
			markerPrefix: 'POST_PAINT',
		});
		const harness = renderBridgeReviewRecoveryWitness(files);
		await harness.publishDisplay();
		await expect.poll(() => harness.selectedItemCommandCount()).toBe(1);
		await expect.poll(() => harness.markFileViewedCommandCount()).toBe(1);
		await expect.poll(() => harness.pierreTreePath('Sources/RecoveryGroup01')).not.toBeNull();
		const targetFile = files[1];
		if (targetFile === undefined) throw new Error('J1 REVIEW POST-PAINT FIXTURE MISSING');
		const targetRow = harness.pierreTreePath(targetFile.path);
		if (!(targetRow instanceof HTMLElement)) {
			throw new Error('J1 REVIEW POST-PAINT TARGET ROW MISSING');
		}
		const frameSamples: Array<{
			readonly selected: boolean;
			readonly selectCommandCount: number;
			readonly timestamp: number;
		}> = [];
		const requestAnimationFrameBeforeProof = globalThis.requestAnimationFrame;
		globalThis.requestAnimationFrame = (callback: FrameRequestCallback): number =>
			requestAnimationFrameBeforeProof((timestamp): void => {
				callback(timestamp);
				frameSamples.push({
					selected: targetRow.hasAttribute('data-item-selected'),
					selectCommandCount: harness.selectedItemCommandCount(),
					timestamp,
				});
			});

		try {
			// Act
			await act(async (): Promise<void> => {
				targetRow.click();
				await Promise.resolve();
			});

			// Assert: local Pierre selection is committed before any later-frame command.
			expect(targetRow.hasAttribute('data-item-selected')).toBe(true);
			expect(harness.selectedItemCommandCount()).toBe(1);
			expect(harness.markFileViewedCommandCount()).toBe(1);
			await act(async (): Promise<void> => {
				await expect.poll(() => harness.selectedItemCommandCount()).toBe(2);
				await expect.poll(() => harness.markFileViewedCommandCount()).toBe(2);
			});
		} finally {
			globalThis.requestAnimationFrame = requestAnimationFrameBeforeProof;
		}

		// Assert: one selected frame precedes the distinct frame that publishes the intent.
		const selectedFrame = frameSamples.find(
			(sample): boolean => sample.selected && sample.selectCommandCount === 1,
		);
		expect(selectedFrame).toBeDefined();
		expect(
			frameSamples.some(
				(sample): boolean =>
					sample.selectCommandCount === 2 &&
					selectedFrame !== undefined &&
					sample.timestamp > selectedFrame.timestamp,
			),
		).toBe(true);
	});

	test('applies an explicit navigation command once without fallback overwriting it', async () => {
		// Arrange
		const events: string[] = [];
		const rendered = await renderInsideAct(<ReviewNavigationControllerProbe events={events} />);

		// Act
		await expect.poll(() => events.filter((event) => event.startsWith('select:')).length).toBe(1);

		// Assert
		expect(events).toEqual(['select:item-two:programmatic']);
		await expect
			.element(rendered.getByTestId('review-navigation-selection'))
			.toHaveTextContent('item-two');

		// Act
		await act(async (): Promise<void> => {
			await rendered.getByRole('button', { name: 'Advance Review catalog revision' }).click();
			await Promise.resolve();
		});

		// Assert
		expect(events.filter((event) => event.startsWith('select:'))).toHaveLength(1);

		// Act
		await act(async (): Promise<void> => {
			await rendered.getByRole('button', { name: 'Navigate outside Review projection' }).click();
		});

		// Assert
		await expect.poll(() => events.includes('outside:item-missing')).toBe(true);
		expect(events.filter((event) => event.startsWith('select:'))).toEqual([
			'select:item-two:programmatic',
		]);
	});

	test('renders every ready Review item in one continuous Pierre CodeView', async () => {
		// Arrange
		const files = makeBridgeReviewRecoveryWitnessFiles({
			count: 3,
			lineCount: 3,
			markerPrefix: 'CONTINUOUS',
		});
		const harness = renderBridgeReviewRecoveryWitness(files);
		await expect
			.element(harness.renderResult.getByTestId('bridge-review-fallback-frame'))
			.toBeVisible();

		// Act
		await harness.publishDisplay();
		await expect.poll(() => harness.selectedItemCommandCount()).toBe(1);
		await harness.publishCompleteContent();
		await expect
			.element(harness.renderResult.getByTestId('review-viewer-shell'))
			.toHaveAttribute('data-selected-content-state', 'ready');
		await advanceBridgeReviewRecoveryWitnessFrames(3);

		// Assert
		const renderedCodeText = harness.codeText();
		expect(renderedCodeText).toContain(files[0]?.contentMarker);
		expect(
			renderedCodeText,
			'G0 REVIEW CONTINUOUS DOCUMENT MISSING: expected one production Pierre CodeView to contain every ready Review item; selected-only rendering omitted middle/final content.',
		).toContain(files[1]?.contentMarker);
		expect(renderedCodeText).toContain(files[2]?.contentMarker);
	});

	test('appends streamed Review metadata into continuous projection order without tree clicks', async () => {
		// Arrange
		const files = makeBridgeReviewRecoveryWitnessFiles({
			count: 3,
			lineCount: 3,
			markerPrefix: 'STREAMED_CONTINUOUS',
		});
		const harness = renderBridgeReviewRecoveryWitness(files);
		await expect
			.element(harness.renderResult.getByTestId('bridge-review-fallback-frame'))
			.toBeVisible();

		// Act
		await harness.publishDisplayInTwoBatches(1);
		await expect.poll(() => harness.selectedItemCommandCount()).toBe(1);
		await expect.poll(() => harness.pierreTreePath('Sources/RecoveryGroup01')).not.toBeNull();
		expect(harness.pierreTreePath(files[0]?.path ?? '')).not.toBeNull();
		await harness.publishCompleteContent();
		await expect
			.element(harness.renderResult.getByTestId('review-viewer-shell'))
			.toHaveAttribute('data-selected-content-state', 'ready');
		await advanceBridgeReviewRecoveryWitnessFrames(4);

		// Assert
		const renderedCodeText = harness.codeText();
		for (const file of files) expect(renderedCodeText).toContain(file.contentMarker);
		expect(harness.selectedItemCommandCount()).toBe(1);
	});

	test('opens streamed directories while preserving an explicit manual collapse', async () => {
		// Arrange
		const files = makeBridgeReviewRecoveryWitnessFiles({
			count: 6,
			lineCount: 3,
			markerPrefix: 'STREAMED_DISCLOSURE',
		});
		const harness = renderBridgeReviewRecoveryWitness(files);

		// Act
		await harness.publishDisplayPrefix(3);
		const firstGroupDirectory = harness.pierreTreePath('Sources/RecoveryGroup01');
		if (!(firstGroupDirectory instanceof HTMLElement)) {
			throw new Error('J1 REVIEW DISCLOSURE FIXTURE MISSING');
		}
		await act(async (): Promise<void> => {
			firstGroupDirectory.click();
			await Promise.resolve();
		});
		await advanceBridgeReviewRecoveryWitnessFrames(2);
		expect(firstGroupDirectory.getAttribute('aria-expanded')).toBe('false');

		await harness.publishDisplayAppendFrom(3);

		// Assert
		const sourceDirectory = harness.pierreTreePath('Sources');
		expect(
			sourceDirectory,
			'J1 REVIEW DISCLOSURE DRIFT: streamed sibling metadata must retain the explicit root directory instead of a stale flattened prefix.',
		).not.toBeNull();
		expect(sourceDirectory?.getAttribute('aria-expanded')).toBe('true');
		expect(harness.pierreTreePath('Sources/RecoveryGroup01')?.getAttribute('aria-expanded')).toBe(
			'false',
		);
		expect(harness.pierreTreePath(files[0]?.path ?? '')).toBeNull();
		expect(harness.pierreTreePath('Sources/RecoveryGroup02')?.getAttribute('aria-expanded')).toBe(
			'true',
		);
		expect(harness.pierreTreePath(files[5]?.path ?? '')).not.toBeNull();
	});
});

function expectedExpandedRecoveryTreePaths(): readonly string[] {
	return ['Sources', 'Sources/RecoveryGroup01', 'Sources/RecoveryGroup02'];
}

function ReviewBoundaryActivationProbe(props: {
	readonly readyPresentation: BridgeReviewViewerPresentationState;
}): ReactElement {
	const [presentationState, setPresentationState] = useState<BridgeReviewViewerPresentationState>(
		props.readyPresentation,
	);
	return (
		<>
			<button onClick={(): void => setPresentationState({ status: 'empty' })} type="button">
				Show empty Review fallback
			</button>
			<button onClick={(): void => setPresentationState(props.readyPresentation)} type="button">
				Restore ready Review presentation
			</button>
			<BridgeReviewViewerShellBoundary
				isActive={false}
				presentationState={presentationState}
				viewerHeaderControls={<div>Review controls</div>}
			/>
		</>
	);
}

function ReviewSelectionControllerProbe(props: { readonly events: string[] }): ReactElement {
	const [selectedItemId, setSelectedItemId] = useState<string | null>(null);
	const markAttemptsByItemIdRef = useRef<Record<string, number>>({});
	const commitLocalSelection = useCallback(
		(itemId: string): void => {
			props.events.push(`local:${itemId}`);
			setSelectedItemId(itemId);
		},
		[props.events],
	);
	const emitSelectIntent = useCallback(
		(itemId: string, selectedSource: BridgeReviewSelectionSource): void => {
			props.events.push(`intent:${itemId}:${selectedSource}`);
		},
		[props.events],
	);
	const markFileViewed = useCallback(
		(itemId: string): boolean => {
			const nextAttempt = (markAttemptsByItemIdRef.current[itemId] ?? 0) + 1;
			markAttemptsByItemIdRef.current[itemId] = nextAttempt;
			props.events.push(`mark:${itemId}:${nextAttempt}`);
			return itemId !== 'item-a' || nextAttempt !== 1;
		},
		[props.events],
	);
	const controller = useBridgeReviewSelectionController({
		commitLocalSelection,
		emitSelectIntent,
		hasReviewItem: (itemId): boolean => itemId === 'item-a' || itemId === 'item-b',
		isActive: true,
		markFileViewed,
		selectedItemId,
	});
	return (
		<>
			<button onClick={(): void => void controller.selectReviewItem('item-a')} type="button">
				Select Review item A
			</button>
			<button
				onClick={(): void => void controller.selectReviewItem('item-b', 'keyboard')}
				type="button"
			>
				Select Review item B
			</button>
			<button onClick={(): void => void controller.selectReviewItem('item-missing')} type="button">
				Select unknown Review item
			</button>
		</>
	);
}

function ReviewNavigationControllerProbe(props: { readonly events: string[] }): ReactElement {
	const [catalogRevision, setCatalogRevision] = useState(1);
	const [navigationCommand, setNavigationCommand] = useState<BridgeViewerNavigationCommand>(() =>
		reviewNavigationCommand('command-two', 'item-two'),
	);
	const [selectedItemId, setSelectedItemId] = useState<string | null>(null);
	const orderedItemIds = ['item-one', 'item-two'] as const;
	const clearReviewSelection = useCallback((): void => {
		props.events.push('clear');
		setSelectedItemId(null);
	}, [props.events]);
	const onTargetOutsideAcceptedProjection = useCallback(
		(target: BridgeReviewNavigationTarget): void => {
			props.events.push(`outside:${target.itemId ?? target.path ?? 'unknown'}`);
		},
		[props.events],
	);
	const selectReviewItem = useCallback(
		(itemId: string, selectedSource: BridgeReviewNavigationSelectionSource): true => {
			props.events.push(`select:${itemId}:${selectedSource}`);
			setSelectedItemId(itemId);
			return true;
		},
		[props.events],
	);
	useBridgeReviewNavigationController({
		catalogRevision,
		clearReviewSelection,
		getReviewItem: (): undefined => undefined,
		isActive: true,
		navigationCommand,
		onTargetOutsideAcceptedProjection,
		orderedItemIds,
		selectedItemId,
		selectInitialReviewItem: selectReviewItem,
		selectReviewItem,
	});
	return (
		<>
			<button onClick={(): void => setCatalogRevision((revision) => revision + 1)} type="button">
				Advance Review catalog revision
			</button>
			<button
				onClick={(): void =>
					setNavigationCommand(reviewNavigationCommand('command-missing', 'item-missing'))
				}
				type="button"
			>
				Navigate outside Review projection
			</button>
			<output data-testid="review-navigation-selection">{selectedItemId ?? 'none'}</output>
		</>
	);
}

function makeReadyReviewPresentationState(
	presentationKey: string,
): BridgeReviewViewerPresentationState {
	const reviewPackage = makeBridgeReviewPackage();
	return {
		presentationKey,
		shellProps: {
			onSelectItem: (): void => {},
			presentationRegistry: createBridgeReviewItemRegistry({ reviewPackage }),
			projection: buildBridgeReviewProjection({
				reviewPackage,
				request: { facets: [], mode: { kind: 'normalReview' } },
			}),
			reviewPackage,
			selectedItemId: null,
		},
		status: 'ready',
	};
}

function reviewNavigationCommand(
	commandId: string,
	reviewItemId: string,
): BridgeViewerNavigationCommand {
	return {
		commandId,
		commandKind: 'activateTarget',
		context: 'review',
		restoreMemory: false,
		source: { sourceId: 'review-fixture', sourceKind: 'fixture' },
		target: {
			comparisonId: 'review-comparison',
			reviewItemId,
			targetKind: 'diff',
		},
	};
}

async function renderInsideAct(element: ReactElement): Promise<ReturnType<typeof render>> {
	let rendered: ReturnType<typeof render> | null = null;
	await act(async (): Promise<void> => {
		rendered = render(element);
		await Promise.resolve();
	});
	return requireRenderResult(rendered);
}

function requireRenderResult(
	rendered: ReturnType<typeof render> | null,
): ReturnType<typeof render> {
	if (rendered === null) throw new Error('Expected Browser render result.');
	return rendered;
}

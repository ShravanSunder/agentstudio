import type { Page } from 'playwright';

import type { CommittedAnnotationOutcome } from './bridge-viewer-vite-annotation-wire-response-observation.ts';
import { readReviewRenderObservation } from './bridge-viewer-vite-review-render-observation.ts';

export async function observeAnnotationReplyInput(page: Page): Promise<void> {
	await page.evaluate((): void => {
		const observations: Readonly<Record<string, unknown>>[] = [];
		const observe = (event: Event): void => {
			if (observations.length >= 12) return;
			const path = event
				.composedPath()
				.filter((target): target is Element => target instanceof Element);
			observations.push({
				kind: event.type,
				target: event.target instanceof Element ? event.target.tagName : null,
				path: path.slice(0, 5).map((element) => ({
					tag: element.tagName,
					label: element.getAttribute('aria-label'),
					thread: element.getAttribute('data-annotation-thread-id'),
				})),
				atMilliseconds: Math.round(performance.now()),
			});
		};
		for (const eventKind of ['pointerdown', 'pointerup', 'click']) {
			document.addEventListener(eventKind, observe, { capture: true });
		}
		Object.defineProperty(globalThis, '__bridgeAnnotationReplyInput', {
			configurable: true,
			value: observations,
		});
	});
}

export async function annotationReplyOpeningDiagnostic(props: {
	readonly canonicalRoot: CommittedAnnotationOutcome;
	readonly page: Page;
}): Promise<Readonly<Record<string, unknown>>> {
	const domSnapshot = await props.page.evaluate(() => {
		const roots: ParentNode[] = [document];
		const elements: Element[] = [];
		for (let rootIndex = 0; rootIndex < roots.length; rootIndex += 1) {
			const root = roots[rootIndex];
			if (root === undefined) continue;
			const rootElements = [...root.querySelectorAll('*')];
			elements.push(...rootElements);
			for (const element of rootElements) {
				if (element.shadowRoot !== null) roots.push(element.shadowRoot);
			}
		}
		// oxlint-disable-next-line unicorn/consistent-function-scoping -- Playwright evaluation must carry this helper into the browser realm.
		const ancestorState = (element: Element): readonly Readonly<Record<string, unknown>>[] => {
			const ancestors: Readonly<Record<string, unknown>>[] = [];
			let current: Element | null = element;
			while (current !== null && ancestors.length < 12) {
				if (
					current.hasAttribute('inert') ||
					current.hasAttribute('aria-hidden') ||
					current.hasAttribute('aria-busy')
				) {
					ancestors.push({
						ariaBusy: current.getAttribute('aria-busy'),
						ariaHidden: current.getAttribute('aria-hidden'),
						inert: current.hasAttribute('inert'),
						tag: current.tagName.toLowerCase(),
						testId: current.getAttribute('data-testid'),
					});
				}
				const root = current.getRootNode();
				current = current.parentElement ?? (root instanceof ShadowRoot ? root.host : null);
			}
			return ancestors;
		};
		const relevantDomButtons = elements
			.filter((element): element is HTMLButtonElement => element instanceof HTMLButtonElement)
			.map((button) => {
				const ariaLabel = button.getAttribute('aria-label');
				const text = button.textContent?.replaceAll(/\s+/gu, ' ').trim().slice(0, 120) ?? '';
				if (!/annotation|reply|save|resolve|reopen/iu.test(ariaLabel ?? text)) return null;
				const bounds = button.getBoundingClientRect();
				return {
					ancestorState: ancestorState(button),
					ariaLabel,
					connected: button.isConnected,
					disabled: button.disabled,
					height: Math.round(bounds.height),
					text,
					width: Math.round(bounds.width),
					x: Math.round(bounds.x),
					y: Math.round(bounds.y),
				};
			})
			.filter((button) => button !== null)
			.slice(0, 40);
		const threadSurfaces = elements
			.filter((element) => element.getAttribute('data-testid') === 'worktree-annotation-thread')
			.slice(0, 16)
			.map((element) => {
				const bounds = element.getBoundingClientRect();
				return {
					ancestorState: ancestorState(element),
					connected: element.isConnected,
					expanded: element.getAttribute('data-annotation-expanded'),
					height: Math.round(bounds.height),
					placement: element.getAttribute('data-annotation-placement'),
					resolution: element.getAttribute('data-annotation-resolution'),
					threadId: element.getAttribute('data-annotation-thread-id'),
					width: Math.round(bounds.width),
					x: Math.round(bounds.x),
					y: Math.round(bounds.y),
				};
			});
		const composerSurfaces = elements
			.filter((element) => element.matches('input, textarea, [contenteditable="true"]'))
			.slice(0, 16)
			.map((element) => ({
				ancestorState: ancestorState(element),
				ariaLabel: element.getAttribute('aria-label'),
				connected: element.isConnected,
				visible: element.getBoundingClientRect().height > 0,
			}));
		const selectedReviewElement = elements.find(
			(element) => element.getAttribute('data-testid') === 'bridge-code-view-panel',
		);
		const reviewShellElement = elements.find(
			(element) => element.getAttribute('data-testid') === 'review-viewer-shell',
		);
		const selectedReviewBounds = selectedReviewElement?.getBoundingClientRect();
		return {
			composerSurfaces,
			relevantDomButtons,
			reviewShell:
				reviewShellElement === undefined
					? null
					: {
							ancestorState: ancestorState(reviewShellElement),
							ariaBusy: reviewShellElement.getAttribute('aria-busy'),
							ariaHidden: reviewShellElement.getAttribute('aria-hidden'),
							canvasBranch: reviewShellElement.getAttribute('data-review-canvas-branch'),
							inert: reviewShellElement.hasAttribute('inert'),
							metadataGeneration: reviewShellElement.getAttribute(
								'data-review-metadata-generation',
							),
							metadataRevision: reviewShellElement.getAttribute('data-review-metadata-revision'),
							selectedContentState: reviewShellElement.getAttribute('data-selected-content-state'),
						},
			selectedReview:
				selectedReviewElement === undefined
					? null
					: {
							ancestorState: ancestorState(selectedReviewElement),
							contentCacheKeys: selectedReviewElement.getAttribute(
								'data-selected-content-cache-keys',
							),
							contentState: selectedReviewElement.getAttribute('data-selected-content-state'),
							height: Math.round(selectedReviewBounds?.height ?? 0),
							itemId: selectedReviewElement.getAttribute('data-selected-item-id'),
							materializedContentState: selectedReviewElement.getAttribute(
								'data-selected-materialized-model-content-state',
							),
							materializedItemType: selectedReviewElement.getAttribute(
								'data-selected-materialized-item-type',
							),
							materializedUpdateResult: selectedReviewElement.getAttribute(
								'data-selected-materialized-update-result',
							),
							presentationKind: selectedReviewElement.getAttribute(
								'data-selected-presentation-kind',
							),
							presentationVersion: selectedReviewElement.getAttribute(
								'data-selected-presentation-version',
							),
							renderedRoles: selectedReviewElement.getAttribute('data-selected-content-roles'),
							width: Math.round(selectedReviewBounds?.width ?? 0),
						},
			threadSurfaces,
		};
	});
	return {
		selectedItemApplies: await props.page.evaluate((): unknown =>
			Reflect.get(globalThis, '__bridgeSelectedItemApplies'),
		),
		inputObservation: await props.page.evaluate((): unknown =>
			Reflect.get(globalThis, '__bridgeAnnotationReplyInput'),
		),
		workerObservation: await readReviewRenderObservation(props.page),
		accessibleReplyButtonCount: await props.page
			.getByRole('button', { name: 'Reply to annotation thread' })
			.count(),
		canonicalRoot: props.canonicalRoot,
		composerCount: domSnapshot.composerSurfaces.length,
		...domSnapshot,
		threadCount: domSnapshot.threadSurfaces.length,
	};
}

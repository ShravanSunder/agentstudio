import type { Page } from 'playwright';

export async function readReplyFailureObservation(page: Page): Promise<unknown> {
	return page.evaluate(() => {
		const roots: ParentNode[] = [document];
		const observations: Readonly<Record<string, unknown>>[] = [];
		for (let rootIndex = 0; rootIndex < roots.length; rootIndex += 1) {
			const root = roots[rootIndex];
			if (root === undefined) continue;
			for (const element of root.querySelectorAll('*')) {
				if (element.shadowRoot !== null) roots.push(element.shadowRoot);
				const testId = element.getAttribute('data-testid');
				const label = element.getAttribute('aria-label');
				if (
					testId !== 'worktree-annotation-thread' &&
					testId !== 'bridge-code-view-panel' &&
					testId !== 'review-viewer-shell' &&
					label !== 'Reply to annotation thread'
				)
					continue;
				const bounds = element.getBoundingClientRect();
				const style = getComputedStyle(element);
				const hiddenAncestors: Readonly<Record<string, unknown>>[] = [];
				let ancestor: Element | null = element;
				while (ancestor !== null) {
					if (ancestor.hasAttribute('inert') || ancestor.getAttribute('aria-hidden') === 'true') {
						hiddenAncestors.push({
							inert: ancestor.hasAttribute('inert'),
							ariaHidden: ancestor.getAttribute('aria-hidden'),
							testId: ancestor.getAttribute('data-testid'),
						});
					}
					const ancestorRoot = ancestor.getRootNode();
					ancestor =
						ancestor.parentElement ??
						(ancestorRoot instanceof ShadowRoot ? ancestorRoot.host : null);
				}
				observations.push({
					testId,
					label,
					hiddenAncestors,
					disabled: element instanceof HTMLButtonElement ? element.disabled : null,
					display: style.display,
					visibility: style.visibility,
					height: bounds.height,
					width: bounds.width,
					threadId: element.getAttribute('data-annotation-thread-id'),
					selectedItemId: element.getAttribute('data-selected-item-id'),
					contentState: element.getAttribute('data-selected-content-state'),
				});
			}
		}
		return {
			presentation: observations,
			selectedItemApplies: Reflect.get(globalThis, '__bridgeSelectedItemApplies'),
			workerObservation: Reflect.get(globalThis, '__bridgeReviewRenderObservation'),
		};
	});
}

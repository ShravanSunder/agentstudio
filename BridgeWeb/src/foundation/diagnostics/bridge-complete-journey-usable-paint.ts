export function reviewUsablePaintIsVisible(): boolean {
	const host = document.querySelector('[data-testid="bridge-viewer-mode-host-review"]');
	const shell = document.querySelector('[data-testid="review-viewer-shell"]');
	const tree = document.querySelector('[data-testid="bridge-review-trees-panel"]');
	const codeView = document.querySelector('[data-testid="bridge-code-view-panel"]');
	const navigationControl = document.querySelector('[data-testid="bridge-viewer-context-file"]');
	const readingControl = document.querySelector(
		'[data-testid="bridge-review-view-settings-trigger"]',
	);
	// oxlint-disable-next-line unicorn/consistent-function-scoping -- Playwright serializes this browser callback without outer helpers.
	const isVisible = (element: Element | null): boolean => {
		if (!(element instanceof HTMLElement)) return false;
		const rectangle = element.getBoundingClientRect();
		const style = window.getComputedStyle(element);
		return (
			style.display !== 'none' &&
			style.visibility !== 'hidden' &&
			rectangle.width > 0 &&
			rectangle.height > 0
		);
	};
	// oxlint-disable-next-line unicorn/consistent-function-scoping -- Playwright serializes this browser callback without outer helpers.
	const isEnabledButton = (control: Element | null): boolean =>
		control instanceof HTMLButtonElement &&
		!control.disabled &&
		control.getAttribute('aria-disabled') !== 'true';
	return (
		host instanceof HTMLElement &&
		host.getAttribute('data-bridge-viewer-mode-active') === 'true' &&
		!host.inert &&
		Number(shell?.getAttribute('data-review-metadata-item-count') ?? '0') > 0 &&
		shell?.getAttribute('data-selected-content-state') === 'ready' &&
		isVisible(shell) &&
		isVisible(tree) &&
		isVisible(codeView) &&
		isEnabledButton(navigationControl) &&
		isEnabledButton(readingControl)
	);
}

export function fileUsablePaintIsVisible(): boolean {
	const host = document.querySelector('[data-testid="bridge-viewer-mode-host-file"]');
	const shell = document.querySelector('[data-testid="bridge-file-viewer-shell"]');
	const tree = document.querySelector('[data-testid="bridge-file-viewer-pierre-file-tree"]');
	const canvas = document.querySelector('[data-testid="bridge-file-viewer-code-canvas"]');
	const navigationControl = document.querySelector('[data-testid="bridge-viewer-context-review"]');
	const readingControl = document.querySelector(
		'[data-testid="bridge-file-view-settings-trigger"]',
	);
	// oxlint-disable-next-line unicorn/consistent-function-scoping -- Playwright serializes this browser callback without outer helpers.
	const isVisible = (element: Element | null): boolean => {
		if (!(element instanceof HTMLElement)) return false;
		const rectangle = element.getBoundingClientRect();
		const style = window.getComputedStyle(element);
		return (
			style.display !== 'none' &&
			style.visibility !== 'hidden' &&
			rectangle.width > 0 &&
			rectangle.height > 0
		);
	};
	// oxlint-disable-next-line unicorn/consistent-function-scoping -- Playwright serializes this browser callback without outer helpers.
	const isEnabledButton = (control: Element | null): boolean =>
		control instanceof HTMLButtonElement &&
		!control.disabled &&
		control.getAttribute('aria-disabled') !== 'true';
	return (
		host instanceof HTMLElement &&
		host.getAttribute('data-bridge-viewer-mode-active') === 'true' &&
		!host.inert &&
		shell?.getAttribute('data-file-display-status') === 'ready' &&
		canvas?.getAttribute('data-worktree-open-file-state') === 'ready' &&
		(canvas?.getAttribute('data-worktree-open-file-path')?.length ?? 0) > 0 &&
		isVisible(shell) &&
		isVisible(tree) &&
		isVisible(canvas) &&
		isEnabledButton(navigationControl) &&
		isEnabledButton(readingControl)
	);
}

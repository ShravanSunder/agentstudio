export function installBridgeViewerBrowserDomAPIs(): void {
	if (!('ResizeObserver' in globalThis)) {
		Object.assign(globalThis, { ResizeObserver: BridgeViewerTestResizeObserver });
	}
	if (HTMLElement.prototype.scrollTo === undefined) {
		HTMLElement.prototype.scrollTo = bridgeViewerTestElementScrollTo;
	}
	if (HTMLElement.prototype.scrollIntoView === undefined) {
		HTMLElement.prototype.scrollIntoView = bridgeViewerTestElementScrollIntoView;
	}
}

export function bridgeViewerRenderedTextContent(): string {
	return `${document.body.textContent ?? ''} ${bridgeViewerCodeTextContent()} ${bridgeViewerTreeTextContent()}`;
}

export function bridgeViewerCodeTextContent(): string {
	return [...document.querySelectorAll('diffs-container')]
		.map((element: Element): string => element.shadowRoot?.textContent ?? '')
		.join(' ');
}

export interface BridgeViewerCodeGeometry {
	readonly containerCount: number;
	readonly firstContainerHeight: number;
	readonly firstContainerWidth: number;
	readonly lineCount: number;
}

export function bridgeViewerCodeGeometry(): BridgeViewerCodeGeometry {
	const containers = [...document.querySelectorAll('diffs-container')];
	const firstContainerRect = containers[0]?.getBoundingClientRect();
	const lineCount = containers.reduce((count: number, element: Element): number => {
		const shadowRoot = element.shadowRoot;
		return shadowRoot === null
			? count
			: count + shadowRoot.querySelectorAll('[data-line-index]').length;
	}, 0);
	return {
		containerCount: containers.length,
		firstContainerHeight: Math.round(firstContainerRect?.height ?? 0),
		firstContainerWidth: Math.round(firstContainerRect?.width ?? 0),
		lineCount,
	};
}

export function bridgeViewerTreeTextContent(): string {
	return [...document.querySelectorAll('file-tree-container')]
		.map((element: Element): string => element.shadowRoot?.textContent ?? '')
		.join(' ');
}

export function bridgeViewerVisibleCodeTextContent(scrollOwner: HTMLElement): string {
	const viewport = scrollOwner.getBoundingClientRect();
	const visibleText: string[] = [];
	for (const element of document.querySelectorAll('diffs-container')) {
		const shadowRoot = element.shadowRoot;
		if (shadowRoot === null) {
			continue;
		}
		for (const lineElement of shadowRoot.querySelectorAll('[data-line-index]')) {
			const lineBox = lineElement.getBoundingClientRect();
			if (lineBox.bottom < viewport.top || lineBox.top > viewport.bottom) {
				continue;
			}
			visibleText.push(lineElement.textContent ?? '');
		}
	}
	return visibleText.join('\n');
}

export function bridgeViewerVisibleTreeTextContent(scrollOwner: HTMLElement): string {
	const viewport = scrollOwner.getBoundingClientRect();
	const fileTreeContainer = document.querySelector('file-tree-container');
	const shadowRoot = fileTreeContainer?.shadowRoot;
	if (shadowRoot === undefined || shadowRoot === null) {
		return '';
	}
	return [...shadowRoot.querySelectorAll('button[data-item-path]')]
		.filter((button: Element): boolean => {
			const buttonBox = button.getBoundingClientRect();
			return buttonBox.bottom >= viewport.top && buttonBox.top <= viewport.bottom;
		})
		.map((button: Element): string => button.textContent ?? '')
		.join('\n');
}

export function bridgeViewerVisibleTreeItemPaths(scrollOwner: HTMLElement): readonly string[] {
	const viewport = scrollOwner.getBoundingClientRect();
	const fileTreeContainer = document.querySelector('file-tree-container');
	const shadowRoot = fileTreeContainer?.shadowRoot;
	if (shadowRoot === undefined || shadowRoot === null) {
		return [];
	}
	return [...shadowRoot.querySelectorAll('button[data-item-path]')]
		.filter((button: Element): button is HTMLButtonElement => {
			if (!(button instanceof HTMLButtonElement)) {
				return false;
			}
			const buttonBox = button.getBoundingClientRect();
			return buttonBox.bottom >= viewport.top && buttonBox.top <= viewport.bottom;
		})
		.map((button: HTMLButtonElement): string | undefined => button.dataset['itemPath'])
		.filter((path: string | undefined): path is string => path !== undefined);
}

export async function waitForBridgeViewerVisibleTreeItemPathAbsent(
	scrollOwner: HTMLElement,
	path: string,
	remainingAttempts = 180,
): Promise<void> {
	if (!bridgeViewerVisibleTreeItemPaths(scrollOwner).includes(path)) {
		return;
	}
	if (remainingAttempts <= 0) {
		throw new Error(`expected visible Bridge viewer tree item path to be absent for ${path}`);
	}
	await Promise.resolve();
	await waitForBridgeViewerAnimationFrame();
	await waitForBridgeViewerVisibleTreeItemPathAbsent(scrollOwner, path, remainingAttempts - 1);
}

export async function waitForBridgeViewerVisibleTreeItemPath(
	scrollOwner: HTMLElement,
	path: string,
	remainingAttempts = 180,
): Promise<void> {
	if (bridgeViewerVisibleTreeItemPaths(scrollOwner).includes(path)) {
		return;
	}
	if (remainingAttempts <= 0) {
		throw new Error(`expected visible Bridge viewer tree item path for ${path}`);
	}
	await Promise.resolve();
	await waitForBridgeViewerAnimationFrame();
	await waitForBridgeViewerVisibleTreeItemPath(scrollOwner, path, remainingAttempts - 1);
}

export function requireBridgeViewerHTMLElement(element: Element | null): HTMLElement {
	if (!(element instanceof HTMLElement)) {
		throw new Error('expected HTML element');
	}
	return element;
}

export async function waitForBridgeViewerAnimationFrame(): Promise<void> {
	await new Promise<void>((resolve) => {
		requestAnimationFrame((): void => {
			resolve();
		});
	});
}

export async function waitForBridgeViewerText(
	text: string,
	remainingAttempts = 180,
): Promise<void> {
	if (bridgeViewerRenderedTextContent().includes(text)) {
		return;
	}
	if (remainingAttempts <= 0) {
		throw new Error(
			`expected rendered Bridge viewer text to contain ${text}; rendered=${bridgeViewerRenderedTextContent().slice(0, 800)}`,
		);
	}
	await Promise.resolve();
	await waitForBridgeViewerAnimationFrame();
	await waitForBridgeViewerText(text, remainingAttempts - 1);
}

export async function waitForBridgeViewerElement(
	selector: string,
	remainingAttempts = 180,
): Promise<Element> {
	const element = document.querySelector(selector);
	if (element !== null) {
		return element;
	}
	if (remainingAttempts <= 0) {
		throw new Error(`expected Bridge viewer element for selector ${selector}`);
	}
	await Promise.resolve();
	await waitForBridgeViewerAnimationFrame();
	return await waitForBridgeViewerElement(selector, remainingAttempts - 1);
}

export async function waitForBridgeViewerAppliedProjectionMode(
	projectionMode: string,
	remainingAttempts = 180,
): Promise<HTMLElement> {
	const shell = document.querySelector(
		`[data-testid="review-viewer-shell"][data-projection-mode="${projectionMode}"]`,
	);
	if (shell instanceof HTMLElement) {
		return shell;
	}
	if (remainingAttempts <= 0) {
		const currentMode = document
			.querySelector('[data-testid="review-viewer-shell"]')
			?.getAttribute('data-projection-mode');
		throw new Error(
			`expected Bridge viewer applied projection mode ${projectionMode}; current=${currentMode ?? 'missing'}`,
		);
	}
	await Promise.resolve();
	await waitForBridgeViewerAnimationFrame();
	return await waitForBridgeViewerAppliedProjectionMode(projectionMode, remainingAttempts - 1);
}

export async function waitForBridgeViewerTreeItemAbsent(
	path: string,
	remainingAttempts = 180,
): Promise<void> {
	if (findBridgeViewerTreeItemButtonForPathCandidates(path) === null) {
		return;
	}
	if (remainingAttempts <= 0) {
		throw new Error(`expected Bridge viewer tree item to be absent for ${path}`);
	}
	await Promise.resolve();
	await waitForBridgeViewerAnimationFrame();
	await waitForBridgeViewerTreeItemAbsent(path, remainingAttempts - 1);
}

export async function collapseBridgeViewerTreeFolder(path: string): Promise<HTMLButtonElement> {
	const folderButton = await waitForBridgeViewerTreeItemButtonForPathCandidates(path);
	if (folderButton.getAttribute('aria-expanded') !== 'true') {
		return folderButton;
	}
	folderButton.click();
	for (let attempt = 0; attempt < 180; attempt += 1) {
		const currentFolderButton = findBridgeViewerTreeItemButtonForPathCandidates(path);
		if (currentFolderButton?.getAttribute('aria-expanded') === 'false') {
			return currentFolderButton;
		}
		// oxlint-disable-next-line no-await-in-loop -- Browser tree state changes need sequential frame observation.
		await waitForBridgeViewerAnimationFrame();
	}
	throw new Error(`expected Bridge viewer tree folder to collapse for ${path}`);
}

export async function expandBridgeViewerTreeFolder(path: string): Promise<HTMLButtonElement> {
	const folderButton = await waitForBridgeViewerTreeItemButtonForPathCandidates(path);
	if (folderButton.getAttribute('aria-expanded') === 'true') {
		return folderButton;
	}
	folderButton.click();
	for (let attempt = 0; attempt < 180; attempt += 1) {
		const currentFolderButton = findBridgeViewerTreeItemButtonForPathCandidates(path);
		if (currentFolderButton?.getAttribute('aria-expanded') === 'true') {
			return currentFolderButton;
		}
		// oxlint-disable-next-line no-await-in-loop -- Browser tree state changes need sequential frame observation.
		await waitForBridgeViewerAnimationFrame();
	}
	throw new Error(`expected Bridge viewer tree folder to expand for ${path}`);
}

export function setBridgeViewerSearchText(searchText: string): void {
	window.dispatchEvent(
		new CustomEvent('__bridge_review_control', {
			detail: {
				method: 'bridge.fileTree.search',
				searchText,
			},
		}),
	);
}

export async function clickBridgeViewerFilterMenuOption(
	testId: string,
	label: string,
	remainingAttempts = 20,
): Promise<void> {
	const menuTrigger = document.querySelector(`[data-testid="${testId}"]`);
	if (menuTrigger === null) {
		throw new Error(`expected Bridge viewer filter menu ${testId}`);
	}
	const menuButton =
		menuTrigger instanceof HTMLButtonElement ? menuTrigger : menuTrigger.querySelector('button');
	if (menuButton instanceof HTMLButtonElement) {
		menuButton.focus();
		menuButton.click();
	}

	await clickBridgeViewerFilterMenuOptionWhenReady({
		label,
		scope: document,
		remainingAttempts,
	});
}

async function clickBridgeViewerFilterMenuOptionWhenReady(props: {
	readonly scope: Document | Element;
	readonly label: string;
	readonly remainingAttempts: number;
}): Promise<void> {
	const option = [
		...props.scope.querySelectorAll('[role="menuitemradio"], [role="menuitemcheckbox"]'),
	].find(
		(candidate: Element): candidate is HTMLElement =>
			candidate instanceof HTMLElement && (candidate.textContent ?? '').includes(props.label),
	);
	if (option !== undefined) {
		option.click();
		return;
	}
	if (props.remainingAttempts <= 0) {
		throw new Error(`expected Bridge viewer filter option ${props.label}`);
	}
	await waitForBridgeViewerAnimationFrame();
	await clickBridgeViewerFilterMenuOptionWhenReady({
		...props,
		remainingAttempts: props.remainingAttempts - 1,
	});
}

export async function clickBridgeViewerProjectionMenuOption(
	label: string,
	remainingAttempts = 20,
): Promise<void> {
	const menuTrigger = document.querySelector(
		'[data-testid="bridge-review-projection-menu-control"]',
	);
	if (!(menuTrigger instanceof HTMLButtonElement)) {
		throw new Error('expected Bridge viewer projection menu control');
	}
	menuTrigger.focus();
	menuTrigger.click();
	await clickBridgeViewerFilterMenuOptionWhenReady({
		label,
		scope: document,
		remainingAttempts,
	});
}

export function findBridgeViewerTreeItemButton(path: string): HTMLButtonElement | null {
	const fileTreeContainer = document.querySelector('file-tree-container');
	const shadowRoot = fileTreeContainer?.shadowRoot;
	if (shadowRoot === undefined || shadowRoot === null) {
		return null;
	}
	const buttons = [...shadowRoot.querySelectorAll('button[data-item-path]')];
	return (
		buttons.find(
			(button): button is HTMLButtonElement =>
				button instanceof HTMLButtonElement && button.dataset['itemPath'] === path,
		) ?? null
	);
}

function findBridgeViewerTreeItemButtonForPathCandidates(path: string): HTMLButtonElement | null {
	return findBridgeViewerTreeItemButton(path) ?? findBridgeViewerTreeItemButton(`${path}/`);
}

async function waitForBridgeViewerTreeItemButtonForPathCandidates(
	path: string,
	remainingAttempts = 180,
): Promise<HTMLButtonElement> {
	const button = findBridgeViewerTreeItemButtonForPathCandidates(path);
	if (button !== null) {
		return button;
	}
	if (remainingAttempts <= 0) {
		throw new Error(`expected Bridge viewer tree item for path ${path}`);
	}
	await Promise.resolve();
	await waitForBridgeViewerAnimationFrame();
	return await waitForBridgeViewerTreeItemButtonForPathCandidates(path, remainingAttempts - 1);
}

export function findBridgeViewerCodeScrollOwner(): HTMLElement | null {
	const codeViewScrollOwner = document.querySelector('.bridge-code-view-scroll-owner');
	if (
		codeViewScrollOwner instanceof HTMLElement &&
		codeViewScrollOwner.clientHeight > 0 &&
		codeViewScrollOwner.scrollHeight > codeViewScrollOwner.clientHeight + 32
	) {
		return codeViewScrollOwner;
	}
	const codeViewPanel = document.querySelector('[data-testid="bridge-code-view-panel"]');
	const candidates: Element[] =
		codeViewPanel === null ? [] : [...codeViewPanel.querySelectorAll('*')];
	for (const element of document.querySelectorAll('diffs-container')) {
		if (element.shadowRoot !== null) {
			candidates.push(...element.shadowRoot.querySelectorAll('*'));
		}
	}
	return (
		candidates.find(
			(candidate): candidate is HTMLElement =>
				candidate instanceof HTMLElement &&
				candidate.clientHeight > 0 &&
				candidate.scrollHeight > candidate.clientHeight + 32,
		) ?? null
	);
}

export async function waitForBridgeViewerCodeScrollOwner(
	remainingAttempts = 180,
): Promise<HTMLElement> {
	const scrollOwner = findBridgeViewerCodeScrollOwner();
	if (scrollOwner !== null) {
		return scrollOwner;
	}
	if (remainingAttempts <= 0) {
		throw new Error('expected Bridge CodeView scroll owner');
	}
	await Promise.resolve();
	await waitForBridgeViewerAnimationFrame();
	return await waitForBridgeViewerCodeScrollOwner(remainingAttempts - 1);
}

export function findBridgeViewerTreeScrollOwner(): HTMLElement | null {
	const fileTreeContainer = document.querySelector('file-tree-container');
	const scrollOwner = fileTreeContainer?.shadowRoot?.querySelector(
		'[data-file-tree-virtualized-scroll="true"]',
	);
	return scrollOwner instanceof HTMLElement ? scrollOwner : null;
}

export function findBridgeViewerHunkExpandButton(): HTMLElement | null {
	for (const element of document.querySelectorAll('diffs-container')) {
		const shadowRoot = element.shadowRoot;
		if (shadowRoot === null) {
			continue;
		}
		const expandButton = shadowRoot.querySelector('[data-expand-button]');
		if (expandButton instanceof HTMLElement) {
			return expandButton;
		}
		const unmodifiedLines = shadowRoot.querySelector('[data-unmodified-lines]');
		if (unmodifiedLines instanceof HTMLElement) {
			return unmodifiedLines;
		}
	}
	return null;
}

export function findBridgeViewerCodeHeaderCollapseButton(): HTMLButtonElement | null {
	const lightDomButton = document.querySelector(
		'[data-testid="bridge-code-view-header-collapse-button"]',
	);
	if (lightDomButton instanceof HTMLButtonElement) {
		return lightDomButton;
	}
	for (const element of document.querySelectorAll('diffs-container')) {
		const shadowRoot = element.shadowRoot;
		if (shadowRoot === null) {
			continue;
		}
		const collapseButton = shadowRoot.querySelector(
			'[data-testid="bridge-code-view-header-collapse-button"]',
		);
		if (collapseButton instanceof HTMLButtonElement) {
			return collapseButton;
		}
	}
	return null;
}

export async function waitForBridgeViewerCodeHeaderCollapseButton(
	remainingAttempts = 180,
): Promise<HTMLButtonElement> {
	const collapseButton = findBridgeViewerCodeHeaderCollapseButton();
	if (collapseButton !== null) {
		return collapseButton;
	}
	if (remainingAttempts <= 0) {
		throw new Error('expected Bridge CodeView header collapse button');
	}
	await Promise.resolve();
	await waitForBridgeViewerAnimationFrame();
	return await waitForBridgeViewerCodeHeaderCollapseButton(remainingAttempts - 1);
}

export async function waitForBridgeViewerHunkExpandButton(
	remainingAttempts = 180,
): Promise<HTMLElement> {
	const expandButton = findBridgeViewerHunkExpandButton();
	if (expandButton !== null) {
		return expandButton;
	}
	if (remainingAttempts <= 0) {
		throw new Error('expected Bridge CodeView hunk expansion control');
	}
	await Promise.resolve();
	await waitForBridgeViewerAnimationFrame();
	return await waitForBridgeViewerHunkExpandButton(remainingAttempts - 1);
}

export async function waitForBridgeViewerTreeScrollOwner(
	remainingAttempts = 180,
): Promise<HTMLElement> {
	const scrollOwner = findBridgeViewerTreeScrollOwner();
	if (scrollOwner !== null) {
		return scrollOwner;
	}
	if (remainingAttempts <= 0) {
		throw new Error('expected Bridge file tree scroll owner');
	}
	await Promise.resolve();
	await waitForBridgeViewerAnimationFrame();
	return await waitForBridgeViewerTreeScrollOwner(remainingAttempts - 1);
}

export async function waitForBridgeViewerTreeItemButton(
	path: string,
	remainingAttempts = 180,
): Promise<HTMLButtonElement> {
	const button = findBridgeViewerTreeItemButton(path);
	if (button !== null) {
		return button;
	}
	if (remainingAttempts <= 0) {
		throw new Error(`expected Bridge viewer tree item button for ${path}`);
	}
	await Promise.resolve();
	await waitForBridgeViewerAnimationFrame();
	return await waitForBridgeViewerTreeItemButton(path, remainingAttempts - 1);
}

function bridgeViewerTestElementScrollTo(
	this: HTMLElement,
	optionsOrX?: ScrollToOptions | number,
	y?: number,
): void {
	if (typeof optionsOrX === 'number') {
		this.scrollLeft = optionsOrX;
		this.scrollTop = y ?? 0;
		return;
	}
	if (optionsOrX !== undefined) {
		if (typeof optionsOrX.top === 'number') {
			this.scrollTop = optionsOrX.top;
		}
		if (typeof optionsOrX.left === 'number') {
			this.scrollLeft = optionsOrX.left;
		}
	}
}

function bridgeViewerTestElementScrollIntoView(): void {}

class BridgeViewerTestResizeObserver implements ResizeObserver {
	readonly #callback: ResizeObserverCallback;

	constructor(callback: ResizeObserverCallback) {
		this.#callback = callback;
	}

	observe(target: Element): void {
		const entry = {
			target,
			contentRect: {
				x: 0,
				y: 0,
				width: 1280,
				height: 720,
				top: 0,
				right: 1280,
				bottom: 720,
				left: 0,
				toJSON: (): Record<string, number> => ({}),
			},
			borderBoxSize: [{ blockSize: 720, inlineSize: 1280 }],
			contentBoxSize: [{ blockSize: 720, inlineSize: 1280 }],
			devicePixelContentBoxSize: [{ blockSize: 720, inlineSize: 1280 }],
		} satisfies ResizeObserverEntry;
		this.#callback([entry], this);
	}

	unobserve(): void {}

	disconnect(): void {}
}

export interface BridgePierreTreeDirectoryHandle {
	readonly isDirectory: () => boolean;
	readonly isExpanded: () => boolean;
	readonly expand: () => void;
}

export interface BridgePierreTreeItemHandleForExpansion {
	readonly isDirectory: () => boolean;
	readonly isExpanded?: () => boolean;
	readonly expand?: () => void;
}

export interface BridgePierreTreeModelForExpansion {
	readonly getItem: (path: string) => BridgePierreTreeItemHandleForExpansion | null;
	readonly resolveMountedDirectoryPathFromInput?: (path: string) => string | null;
}

export interface BridgePierreTreeContainerModel {
	readonly getFileTreeContainer: () => BridgePierreTreeRootContainer | null | undefined;
}

export interface BridgePierreTreeQueryContainer {
	readonly addEventListener?: (
		type: string,
		listener: EventListenerOrEventListenerObject,
		options?: AddEventListenerOptions | boolean,
	) => void;
	readonly querySelector: (selector: string) => BridgePierreTreeScrollOwner | null;
	readonly querySelectorAll: (selector: string) => Iterable<BridgePierreFileRowElement>;
	readonly removeEventListener?: (
		type: string,
		listener: EventListenerOrEventListenerObject,
		options?: EventListenerOptions | boolean,
	) => void;
}

export interface BridgePierreTreeRootContainer extends BridgePierreTreeQueryContainer {
	readonly shadowRoot?: BridgePierreTreeQueryContainer | null;
}

export interface BridgePierreTreeScrollOwner {
	readonly addEventListener: (
		type: string,
		listener: EventListenerOrEventListenerObject,
		options?: AddEventListenerOptions | boolean,
	) => void;
	readonly dispatchEvent: (event: Event) => boolean;
	readonly getBoundingClientRect: () => DOMRect;
	readonly querySelectorAll: (selector: string) => Iterable<BridgePierreFileRowElement>;
	readonly removeEventListener: (
		type: string,
		listener: EventListenerOrEventListenerObject,
		options?: EventListenerOptions | boolean,
	) => void;
	scrollTop: number;
}

export interface BridgePierreFileRowElement {
	readonly getAttribute: (name: string) => string | null;
}

interface BridgePierreMeasuredFileRowElement extends BridgePierreFileRowElement {
	readonly getBoundingClientRect: () => DOMRect;
}

export interface BridgePierreTreePathEvent {
	readonly target?: EventTarget | null;
	readonly composedPath?: () => readonly unknown[];
}

const pierreTreeScrollOwnerSelector = '[data-file-tree-virtualized-scroll="true"]';
const pierreTreeFileRowSelector =
	'button[data-item-type="file"][data-item-path],[data-type="item"][data-item-type="file"][data-item-path]';
const pierreTreeSelectableFileRowSelector =
	'button[data-item-type="file"][data-item-path],[data-type="item"][data-item-type="file"][data-item-path]';

export interface BridgePierreTreeRowScrollAnchor {
	readonly offsetFromScrollOwnerTop: number;
	readonly path: string;
	readonly scrollOwner: BridgePierreTreeScrollOwner;
}

export function appendedOnlyPierreTreePaths(props: {
	readonly nextPaths: readonly string[];
	readonly previousPaths: readonly string[];
}): readonly string[] | null {
	if (props.nextPaths.length < props.previousPaths.length) {
		return null;
	}
	for (let index = 0; index < props.previousPaths.length; index += 1) {
		if (props.nextPaths[index] !== props.previousPaths[index]) {
			return null;
		}
	}
	return props.nextPaths.slice(props.previousPaths.length);
}

export function expandAncestorDirectoriesForPierreTreePaths(props: {
	readonly ignoreExpandErrors?: boolean;
	readonly model: BridgePierreTreeModelForExpansion;
	readonly paths: readonly string[];
}): void {
	for (const path of props.paths) {
		for (const ancestorPath of ancestorDirectoryPaths(path)) {
			const item = directoryItemForInputPath({
				model: props.model,
				path: ancestorPath,
			});
			if (!isExpandableDirectoryHandle(item) || item.isExpanded()) {
				continue;
			}
			if (props.ignoreExpandErrors === true) {
				try {
					item.expand();
				} catch {
					continue;
				}
				continue;
			}
			item.expand();
		}
	}
}

export function pierreTreeRowContainerForModel(
	model: BridgePierreTreeContainerModel,
): BridgePierreTreeQueryContainer | null {
	const fileTreeContainer = model.getFileTreeContainer();
	return fileTreeContainer?.shadowRoot ?? fileTreeContainer ?? null;
}

export function pierreTreeScrollOwnerForModel(
	model: BridgePierreTreeContainerModel,
): BridgePierreTreeScrollOwner | null {
	return (
		pierreTreeRowContainerForModel(model)?.querySelector(pierreTreeScrollOwnerSelector) ?? null
	);
}

export function visiblePierreFileRowElementsForModel(
	model: BridgePierreTreeContainerModel,
): readonly BridgePierreFileRowElement[] {
	return Array.from(
		pierreTreeRowContainerForModel(model)?.querySelectorAll(pierreTreeFileRowSelector) ?? [],
	);
}

export function captureFirstVisiblePierreTreeRowAnchor(
	model: BridgePierreTreeContainerModel,
): BridgePierreTreeRowScrollAnchor | null {
	const scrollOwner = pierreTreeScrollOwnerForModel(model);
	if (scrollOwner === null) {
		return null;
	}
	const scrollOwnerRect = scrollOwner.getBoundingClientRect();
	const visibleRows = visiblePierreFileRowElementsForModel(model)
		.map(
			(
				rowElement,
			): {
				readonly path: string;
				readonly rowElement: BridgePierreMeasuredFileRowElement;
			} | null => {
				if (!hasGetBoundingClientRect(rowElement)) {
					return null;
				}
				const path = rowElement.getAttribute('data-item-path');
				if (path === null || path.length === 0) {
					return null;
				}
				const rowRect = rowElement.getBoundingClientRect();
				if (rowRect.bottom < scrollOwnerRect.top || rowRect.top > scrollOwnerRect.bottom) {
					return null;
				}
				return { path, rowElement };
			},
		)
		.filter(
			(
				row,
			): row is {
				readonly path: string;
				readonly rowElement: BridgePierreMeasuredFileRowElement;
			} => row !== null,
		)
		.toSorted(
			(firstRow, secondRow): number =>
				firstRow.rowElement.getBoundingClientRect().top -
				secondRow.rowElement.getBoundingClientRect().top,
		);
	const anchorRow = visibleRows[0];
	if (anchorRow === undefined) {
		return null;
	}
	return {
		offsetFromScrollOwnerTop:
			anchorRow.rowElement.getBoundingClientRect().top - scrollOwnerRect.top,
		path: anchorRow.path,
		scrollOwner,
	};
}

export function restorePierreTreeRowAnchor(anchor: BridgePierreTreeRowScrollAnchor | null): void {
	if (anchor === null) {
		return;
	}
	const currentAnchorRow = Array.from(
		anchor.scrollOwner.querySelectorAll(pierreTreeFileRowSelector),
	)
		.filter(hasGetAttribute)
		.filter(hasGetBoundingClientRect)
		.find((rowElement): boolean => rowElement.getAttribute('data-item-path') === anchor.path);
	if (currentAnchorRow === undefined) {
		return;
	}
	const currentOffset =
		currentAnchorRow.getBoundingClientRect().top - anchor.scrollOwner.getBoundingClientRect().top;
	const offsetDelta = currentOffset - anchor.offsetFromScrollOwnerTop;
	if (Math.abs(offsetDelta) < 1) {
		return;
	}
	anchor.scrollOwner.scrollTop += offsetDelta;
	anchor.scrollOwner.dispatchEvent(new Event('scroll', { bubbles: true }));
}

export function restorePierreTreeRowAnchorFromPathOrder(props: {
	readonly anchor: BridgePierreTreeRowScrollAnchor | null;
	readonly nextPaths: readonly string[];
	readonly previousPaths: readonly string[];
	readonly rowHeightPixels: number;
}): void {
	const anchor = props.anchor;
	if (anchor === null) {
		return;
	}
	const previousIndex = props.previousPaths.indexOf(anchor.path);
	const nextIndex = props.nextPaths.indexOf(anchor.path);
	if (previousIndex < 0 || nextIndex < 0 || previousIndex === nextIndex) {
		return;
	}
	anchor.scrollOwner.scrollTop += (nextIndex - previousIndex) * props.rowHeightPixels;
	anchor.scrollOwner.dispatchEvent(new Event('scroll', { bubbles: true }));
}

export function restorePierreTreeRowAnchorAcrossAnimationFrames(props: {
	readonly anchor: BridgePierreTreeRowScrollAnchor | null;
	readonly frameBudget: number;
}): void {
	restorePierreTreeRowAnchor(props.anchor);
	if (props.anchor === null || props.frameBudget <= 0) {
		return;
	}
	requestAnimationFrame((): void => {
		restorePierreTreeRowAnchorAcrossAnimationFrames({
			anchor: props.anchor,
			frameBudget: props.frameBudget - 1,
		});
	});
}

export function pierreFilePathFromTreeEvent(event: BridgePierreTreePathEvent): string | null {
	const composedPath = event.composedPath?.() ?? [];
	for (const target of composedPath) {
		const path = pierreFilePathFromRowCandidate(target);
		if (path !== null) {
			return path;
		}
	}
	return pierreFilePathFromEventTarget(event.target ?? null);
}

export function pierreFilePathFromEventTarget(target: unknown): string | null {
	const rowElement = pierreFileRowElementForEventTarget(target);
	return pierreFilePathFromRowCandidate(rowElement);
}

function pierreFileRowElementForEventTarget(target: unknown): BridgePierreFileRowElement | null {
	const directPath = pierreFilePathFromRowCandidate(target);
	if (directPath !== null) {
		return hasGetAttribute(target) ? target : null;
	}
	const closestFromTarget = closestPierreFileRowElement(target);
	if (closestFromTarget !== null) {
		return closestFromTarget;
	}
	const root = getRootNodeForTarget(target);
	const host = isShadowRootWithHost(root) ? root.host : null;
	return closestPierreFileRowElement(host);
}

function pierreFilePathFromRowCandidate(candidate: unknown): string | null {
	if (!hasGetAttribute(candidate)) {
		return null;
	}
	const itemType = candidate.getAttribute('data-item-type');
	const itemPath = candidate.getAttribute('data-item-path');
	return itemType === 'file' && itemPath !== null && itemPath.length > 0 ? itemPath : null;
}

function closestPierreFileRowElement(target: unknown): BridgePierreFileRowElement | null {
	if (!hasClosest(target)) {
		return null;
	}
	const matched = target.closest(pierreTreeSelectableFileRowSelector);
	return hasGetAttribute(matched) ? matched : null;
}

function directoryItemForInputPath(props: {
	readonly model: BridgePierreTreeModelForExpansion;
	readonly path: string;
}): BridgePierreTreeItemHandleForExpansion | null {
	const slashPath = `${props.path}/`;
	const mountedPath =
		props.model.resolveMountedDirectoryPathFromInput?.(props.path) ??
		props.model.resolveMountedDirectoryPathFromInput?.(slashPath) ??
		null;
	if (mountedPath !== null) {
		return props.model.getItem(mountedPath);
	}
	return props.model.getItem(props.path) ?? props.model.getItem(slashPath);
}

function isExpandableDirectoryHandle(
	item: BridgePierreTreeItemHandleForExpansion | null,
): item is BridgePierreTreeDirectoryHandle {
	return (
		item?.isDirectory() === true &&
		typeof item.isExpanded === 'function' &&
		typeof item.expand === 'function'
	);
}

function ancestorDirectoryPaths(path: string): readonly string[] {
	const segments = path.split('/').filter((segment: string): boolean => segment.length > 0);
	const ancestorPaths: string[] = [];
	let currentPath = '';
	for (const segment of segments.slice(0, -1)) {
		currentPath = currentPath.length === 0 ? segment : `${currentPath}/${segment}`;
		ancestorPaths.push(currentPath);
	}
	return ancestorPaths;
}

function hasGetAttribute(candidate: unknown): candidate is BridgePierreFileRowElement {
	return (
		typeof candidate === 'object' &&
		candidate !== null &&
		'getAttribute' in candidate &&
		typeof candidate.getAttribute === 'function'
	);
}

function hasGetBoundingClientRect(
	candidate: BridgePierreFileRowElement,
): candidate is BridgePierreMeasuredFileRowElement {
	return (
		'getBoundingClientRect' in candidate && typeof candidate.getBoundingClientRect === 'function'
	);
}

function hasClosest(
	candidate: unknown,
): candidate is { readonly closest: (selector: string) => unknown } {
	return (
		typeof candidate === 'object' &&
		candidate !== null &&
		'closest' in candidate &&
		typeof candidate.closest === 'function'
	);
}

function getRootNodeForTarget(target: unknown): Node | null {
	if (hasGetRootNode(target)) {
		return target.getRootNode();
	}
	return null;
}

function hasGetRootNode(candidate: unknown): candidate is { readonly getRootNode: () => Node } {
	return (
		typeof candidate === 'object' &&
		candidate !== null &&
		'getRootNode' in candidate &&
		typeof candidate.getRootNode === 'function'
	);
}

function isShadowRootWithHost(root: unknown): root is { readonly host: unknown } {
	return (
		typeof root === 'object' &&
		root !== null &&
		'host' in root &&
		typeof root.host === 'object' &&
		root.host !== null
	);
}

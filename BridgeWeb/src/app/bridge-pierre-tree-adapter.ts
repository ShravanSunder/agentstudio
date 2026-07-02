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
	readonly removeEventListener: (
		type: string,
		listener: EventListenerOrEventListenerObject,
		options?: EventListenerOptions | boolean,
	) => void;
}

export interface BridgePierreFileRowElement {
	readonly getAttribute: (name: string) => string | null;
}

export interface BridgePierreTreePathEvent {
	readonly target?: EventTarget | null;
	readonly composedPath?: () => readonly unknown[];
}

const pierreTreeScrollOwnerSelector = '[data-file-tree-virtualized-scroll="true"]';
const pierreTreeFileRowSelector = '[data-type="item"][data-item-type="file"][data-item-path]';
const pierreTreeSelectableFileRowSelector =
	'button[data-item-type="file"][data-item-path],[data-type="item"][data-item-type="file"][data-item-path]';

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

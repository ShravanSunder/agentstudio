import { useEffect, useLayoutEffect, useRef, type RefObject } from 'react';

type BridgeViewerSearchFocusIdentity =
	| { readonly kind: 'tree_path'; readonly path: string }
	| { readonly kind: 'test_id'; readonly testId: string }
	| { readonly kind: 'surface_root' };

export function useBridgeViewerSearchFocusRestoration(props: {
	readonly isActive: boolean;
	readonly isSearchOpen: boolean;
	readonly searchTriggerRef: RefObject<HTMLButtonElement | null>;
	readonly surfaceRootRef: RefObject<HTMLElement | null>;
}): void {
	const focusIdentityRef = useRef<BridgeViewerSearchFocusIdentity | null>(null);
	const wasSearchOpenRef = useRef(props.isSearchOpen);

	useEffect((): (() => void) => {
		if (!props.isActive) return (): void => {};
		const recordFocusIdentity = (event: FocusEvent): void => {
			const surfaceRoot = props.surfaceRootRef.current;
			if (surfaceRoot === null) return;
			const eventPath = event.composedPath();
			const searchTrigger = props.searchTriggerRef.current;
			if (
				!eventPath.includes(surfaceRoot) ||
				(searchTrigger !== null && eventPath.includes(searchTrigger))
			)
				return;
			if (
				eventPath.some(
					(candidate): boolean =>
						candidate instanceof HTMLElement &&
						candidate.dataset['bridgeViewerSearchField'] === 'true',
				)
			)
				return;

			const treeRow = eventPath.find(
				(candidate): candidate is HTMLElement =>
					candidate instanceof HTMLElement && candidate.hasAttribute('data-item-path'),
			);
			if (treeRow !== undefined) {
				focusIdentityRef.current = {
					kind: 'tree_path',
					path: normalizedTreePath(treeRow.getAttribute('data-item-path') ?? ''),
				};
				return;
			}

			const identifiedOwner = eventPath.find(
				(candidate): candidate is HTMLElement =>
					candidate instanceof HTMLElement &&
					candidate !== surfaceRoot &&
					(candidate.dataset['testid']?.length ?? 0) > 0,
			);
			focusIdentityRef.current =
				identifiedOwner === undefined
					? { kind: 'surface_root' }
					: { kind: 'test_id', testId: identifiedOwner.dataset['testid'] ?? '' };
		};
		document.addEventListener('focusin', recordFocusIdentity, true);
		return (): void => document.removeEventListener('focusin', recordFocusIdentity, true);
	}, [props.isActive, props.searchTriggerRef, props.surfaceRootRef]);

	useLayoutEffect((): void => {
		const didClose = wasSearchOpenRef.current && !props.isSearchOpen;
		wasSearchOpenRef.current = props.isSearchOpen;
		if (!didClose || !props.isActive) return;
		const surfaceRoot = props.surfaceRootRef.current;
		if (surfaceRoot === null || !surfaceRoot.isConnected) return;
		const semanticOwner =
			focusIdentityRef.current === null
				? null
				: resolveSearchFocusIdentity(surfaceRoot, focusIdentityRef.current);
		const searchTrigger = props.searchTriggerRef.current;
		const focusTarget =
			semanticOwner ??
			(searchTrigger?.isConnected === true && surfaceRoot.contains(searchTrigger)
				? searchTrigger
				: surfaceRoot);
		focusTarget.focus({ preventScroll: true });
	}, [props.isActive, props.isSearchOpen, props.searchTriggerRef, props.surfaceRootRef]);
}

function resolveSearchFocusIdentity(
	surfaceRoot: HTMLElement,
	identity: BridgeViewerSearchFocusIdentity,
): HTMLElement | null {
	switch (identity.kind) {
		case 'tree_path':
			return (
				allElementsIncludingOpenShadowRoots(surfaceRoot).find(
					(element): boolean =>
						normalizedTreePath(element.getAttribute('data-item-path') ?? '') === identity.path,
				) ?? null
			);
		case 'test_id':
			return (
				allElementsIncludingOpenShadowRoots(surfaceRoot).find(
					(element): boolean => element.dataset['testid'] === identity.testId,
				) ?? null
			);
		case 'surface_root':
			return surfaceRoot;
	}
	return assertNeverSearchFocusIdentity(identity);
}

function allElementsIncludingOpenShadowRoots(root: HTMLElement): readonly HTMLElement[] {
	const elements: HTMLElement[] = [root];
	collectElements(root, elements);
	return elements;
}

function collectElements(root: ParentNode, elements: HTMLElement[]): void {
	for (const element of root.querySelectorAll<HTMLElement>('*')) {
		elements.push(element);
		if (element.shadowRoot !== null) collectElements(element.shadowRoot, elements);
	}
}

function normalizedTreePath(path: string): string {
	return path.endsWith('/') ? path.slice(0, -1) : path;
}

function assertNeverSearchFocusIdentity(_identity: never): never {
	throw new Error('Unhandled Bridge Viewer Search focus identity.');
}

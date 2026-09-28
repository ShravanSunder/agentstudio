export function waitForBridgeFileViewerBrowserDomState<TState>(props: {
	readonly readState: () => TState;
	readonly isExpected: (state: TState) => boolean;
}): Promise<TState> {
	const initialState = props.readState();
	if (props.isExpected(initialState)) return Promise.resolve(initialState);

	return new Promise<TState>((resolve): void => {
		const observedRoots = new WeakSet<Node>();
		const observer = new MutationObserver((): void => {
			observeOpenShadowRoots(document.documentElement);
			publishWhenExpected();
		});
		const observeRoot = (root: Node): void => {
			if (observedRoots.has(root)) return;
			observedRoots.add(root);
			observer.observe(root, {
				attributes: true,
				characterData: true,
				childList: true,
				subtree: true,
			});
		};
		const observeOpenShadowRoots = (root: ParentNode): void => {
			for (const element of root.querySelectorAll('*')) {
				if (element.shadowRoot !== null) {
					observeRoot(element.shadowRoot);
					observeOpenShadowRoots(element.shadowRoot);
				}
			}
		};
		const removeFocusListeners = (): void => {
			document.removeEventListener('focusin', publishWhenExpected, true);
			document.removeEventListener('focusout', publishWhenExpected, true);
		};
		function publishWhenExpected(): void {
			const state = props.readState();
			if (!props.isExpected(state)) return;
			observer.disconnect();
			removeFocusListeners();
			resolve(state);
		}

		observeRoot(document.documentElement);
		observeOpenShadowRoots(document.documentElement);
		document.addEventListener('focusin', publishWhenExpected, true);
		document.addEventListener('focusout', publishWhenExpected, true);
		publishWhenExpected();
	});
}

export function installBridgeFileViewerNoopResizeObserver(): void {
	Object.assign(globalThis, { ResizeObserver: BridgeFileViewerNoopResizeObserver });
}

export function bridgeFileViewerNoopResizeObserverIsInstalled(): boolean {
	return globalThis.ResizeObserver === BridgeFileViewerNoopResizeObserver;
}

export function installBridgeFileViewerBrowserTestMotionOverride(): HTMLStyleElement {
	const style = document.createElement('style');
	style.setAttribute('data-bridge-file-viewer-test-motion', 'disabled');
	style.textContent = `
		*, *::before, *::after {
			animation: none !important;
			transition: none !important;
			scroll-behavior: auto !important;
		}
	`;
	document.head.append(style);
	return style;
}

class BridgeFileViewerNoopResizeObserver implements ResizeObserver {
	disconnect(): void {}

	observe(_target: Element): void {}

	unobserve(_target: Element): void {}
}

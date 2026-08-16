import {
	createBridgeMarkdownRenderRuntime,
	type BridgeMarkdownRenderRuntime,
} from './bridge-markdown-render-runtime.js';

export interface BridgeMarkdownRuntimeHost {
	readonly disposeWithComponent: boolean;
	readonly runtime: BridgeMarkdownRenderRuntime;
}

export function createBridgeMarkdownRuntimeHost(props: {
	readonly externallyOwnedRuntime: BridgeMarkdownRenderRuntime | null;
	readonly runtimeFactory?: () => BridgeMarkdownRenderRuntime;
}): BridgeMarkdownRuntimeHost {
	return {
		disposeWithComponent: props.externallyOwnedRuntime === null,
		runtime:
			props.externallyOwnedRuntime ?? (props.runtimeFactory ?? createBridgeMarkdownRenderRuntime)(),
	};
}

export function disposeBridgeMarkdownRuntimeHost(host: BridgeMarkdownRuntimeHost): void {
	if (host.disposeWithComponent) {
		host.runtime.dispose();
	}
}

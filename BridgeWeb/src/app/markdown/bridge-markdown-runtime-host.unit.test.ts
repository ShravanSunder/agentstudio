import { describe, expect, test, vi } from 'vitest';

import type { BridgeMarkdownRenderRuntime } from './bridge-markdown-render-runtime.js';
import {
	createBridgeMarkdownRuntimeHost,
	disposeBridgeMarkdownRuntimeHost,
} from './bridge-markdown-runtime-host.js';

describe('Bridge Markdown runtime host', () => {
	test('creates and disposes the component-owned default runtime', () => {
		const defaultRuntime = makeRuntime();
		const runtimeFactory = vi.fn<() => BridgeMarkdownRenderRuntime>(() => defaultRuntime);

		const host = createBridgeMarkdownRuntimeHost({
			externallyOwnedRuntime: null,
			runtimeFactory,
		});
		disposeBridgeMarkdownRuntimeHost(host);

		expect(runtimeFactory).toHaveBeenCalledOnce();
		expect(host.runtime).toBe(defaultRuntime);
		expect(defaultRuntime.dispose).toHaveBeenCalledOnce();
	});

	test('does not create or dispose an injected runtime', () => {
		const injectedRuntime = makeRuntime();
		const runtimeFactory = vi.fn<() => BridgeMarkdownRenderRuntime>();

		const host = createBridgeMarkdownRuntimeHost({
			externallyOwnedRuntime: injectedRuntime,
			runtimeFactory,
		});
		disposeBridgeMarkdownRuntimeHost(host);

		expect(runtimeFactory).not.toHaveBeenCalled();
		expect(host.runtime).toBe(injectedRuntime);
		expect(injectedRuntime.dispose).not.toHaveBeenCalled();
	});
});

function makeRuntime(): BridgeMarkdownRenderRuntime {
	return {
		workerClient: null,
		mermaidRenderer: { render: async (): Promise<string> => '<svg role="img"></svg>' },
		dispose: vi.fn<() => void>(),
	};
}

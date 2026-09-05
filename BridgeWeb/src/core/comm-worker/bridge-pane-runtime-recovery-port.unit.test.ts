import { afterEach, expect, test, vi } from 'vitest';

import type { BridgePaneSessionPort } from './bridge-pane-runtime.js';

afterEach((): void => {
	vi.unstubAllGlobals();
});

test('surface recovery prepares both consumers through one pane session and cannot revive disposal', async () => {
	// Arrange
	vi.stubGlobal('cancelAnimationFrame', vi.fn());
	vi.stubGlobal(
		'requestAnimationFrame',
		vi.fn((): number => 1),
	);
	const { createBridgePaneRuntime } = await import('./bridge-pane-runtime.js');
	const requestWorkerReplacement = vi.fn<() => void>();
	const session: BridgePaneSessionPort = {
		createDispatcher: () => ({ dispatch: (): void => {}, dispose: (): void => {} }),
		dispose: (): void => {},
		installNativeBootstrap: (): void => {},
		requestWorkerReplacement,
	};
	const runtime = createBridgePaneRuntime({
		recordDiagnosticSnapshot: (): void => {},
		sessionFactory: () => session,
	});
	try {
		const fileClient = runtime.surfaceClient('fileView');
		const reviewClient = runtime.surfaceClient('review');
		const prepareFile = vi.fn();
		const prepareReview = vi.fn();
		fileClient.subscribeWorkerReplacement?.(prepareFile);
		reviewClient.subscribeWorkerReplacement?.(prepareReview);

		// Act
		reviewClient.requestWorkerReplacement();

		// Assert
		expect(prepareFile).toHaveBeenCalledOnce();
		expect(prepareReview).toHaveBeenCalledOnce();
		expect(requestWorkerReplacement).toHaveBeenCalledOnce();
		runtime.dispose();
		fileClient.requestWorkerReplacement();
		expect(requestWorkerReplacement).toHaveBeenCalledOnce();
	} finally {
		runtime.dispose();
	}
});

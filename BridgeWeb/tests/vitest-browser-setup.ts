import { act } from 'react';
import { afterEach, beforeEach } from 'vitest';
import { cleanup } from 'vitest-browser-react';

import { installBridgeViewerBrowserDomAPIs } from '../src/review-viewer/test-support/bridge-viewer-browser-dom.js';

// `vitest-browser-react`'s own `render()`/`unmount()` helpers wrap React's
// root mutation in a private `act()` that sets `IS_REACT_ACT_ENVIRONMENT = true`
// and then resets it to `false` in a `finally` block once that single call
// completes (see `vitest-browser-react/dist/chunk-*.js`). Test files also call
// React's own `act(...)` (imported from `react`) around later updates such as
// `setVisibleItemIds` or fake-timer flushes; by the time those run, the flag
// has already been flipped back to `false`, so `react-dom`'s
// `isConcurrentActEnvironment()` check emits "not configured to support
// act(...)" even though every mutation is properly act-wrapped. Pin the flag
// to `true` for the life of the browser test run by intercepting writes,
// rather than relying on a one-time assignment that a later `render()` call
// silently undoes.
Object.defineProperty(globalThis, 'IS_REACT_ACT_ENVIRONMENT', {
	configurable: true,
	enumerable: true,
	get: (): boolean => true,
	set: (): void => {
		// Ignore writes: vitest-browser-react resets this to `false` after
		// each of its internal render/unmount calls, which must not disable
		// the act environment for the rest of the test.
	},
});

const allowedConsoleErrorSubstrings: readonly string[] = [
	'flushSync was called from inside a lifecycle method',
];

let browserFailureMessages: string[] = [];
let originalConsoleError: typeof console.error | null = null;
let windowErrorListener: ((event: ErrorEvent) => void) | null = null;
let unhandledRejectionListener: ((event: PromiseRejectionEvent) => void) | null = null;

beforeEach((): void => {
	browserFailureMessages = [];
	installBridgeViewerBrowserDomAPIs();
	installBridgeViewerFailureGuards();
});

afterEach(async (): Promise<void> => {
	uninstallBridgeViewerFailureGuards();
	await act(async (): Promise<void> => {
		cleanup();
		await Promise.resolve();
	});
	document.body.replaceChildren();
	document.documentElement.removeAttribute('data-bridge-nonce');
	if (browserFailureMessages.length > 0) {
		throw new Error(
			`Bridge viewer browser test failure guard tripped:\n${browserFailureMessages.join('\n')}`,
		);
	}
});

function installBridgeViewerFailureGuards(): void {
	originalConsoleError = console.error;
	console.error = (...args: readonly unknown[]): void => {
		const message = args.map((arg: unknown): string => stringifyGuardValue(arg)).join(' ');
		if (!isAllowedConsoleError(message)) {
			browserFailureMessages.push(`console.error: ${message}`);
		}
		originalConsoleError?.(...args);
	};
	windowErrorListener = (event: ErrorEvent): void => {
		browserFailureMessages.push(`window.error: ${event.message}`);
	};
	unhandledRejectionListener = (event: PromiseRejectionEvent): void => {
		browserFailureMessages.push(`unhandledrejection: ${stringifyGuardValue(event.reason)}`);
	};
	window.addEventListener('error', windowErrorListener);
	window.addEventListener('unhandledrejection', unhandledRejectionListener);
}

function uninstallBridgeViewerFailureGuards(): void {
	if (originalConsoleError !== null) {
		console.error = originalConsoleError;
		originalConsoleError = null;
	}
	if (windowErrorListener !== null) {
		window.removeEventListener('error', windowErrorListener);
		windowErrorListener = null;
	}
	if (unhandledRejectionListener !== null) {
		window.removeEventListener('unhandledrejection', unhandledRejectionListener);
		unhandledRejectionListener = null;
	}
}

function isAllowedConsoleError(message: string): boolean {
	return allowedConsoleErrorSubstrings.some((allowedSubstring: string): boolean =>
		message.includes(allowedSubstring),
	);
}

function stringifyGuardValue(value: unknown): string {
	if (value instanceof Error) {
		return `${value.name}: ${value.message}`;
	}
	if (typeof value === 'string') {
		return value;
	}
	const serializedValue = JSON.stringify(value);
	return serializedValue ?? String(value);
}

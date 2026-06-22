import { afterEach, beforeEach } from 'vitest';
import { cleanup } from 'vitest-browser-react';

import { installBridgeViewerBrowserDomAPIs } from '../src/review-viewer/test-support/bridge-viewer-browser-dom.js';

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

afterEach((): void => {
	uninstallBridgeViewerFailureGuards();
	cleanup();
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

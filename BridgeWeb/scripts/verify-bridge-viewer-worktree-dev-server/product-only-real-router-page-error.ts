import type { Page } from 'playwright';

import type { BridgeViewerConsoleDiagnostic } from './product-only-real-router-contract.ts';

interface InstallBridgeViewerBrowserErrorCaptureProps {
	readonly consoleDiagnostics: BridgeViewerConsoleDiagnostic[];
	readonly consoleErrors: string[];
	readonly maximumCapturedConsoleErrorCharacters: number;
	readonly maximumCapturedConsoleErrors: number;
	readonly page: Page;
}

export function installBridgeViewerBrowserErrorCapture(
	props: InstallBridgeViewerBrowserErrorCaptureProps,
): void {
	props.page.on('console', (message): void => {
		const messageType = message.type();
		if (
			(messageType === 'error' || messageType === 'warning') &&
			props.consoleErrors.length < props.maximumCapturedConsoleErrors
		) {
			const text = message.text().slice(0, props.maximumCapturedConsoleErrorCharacters);
			const location = message.location();
			props.consoleErrors.push(text);
			props.consoleDiagnostics.push({
				columnNumber: location.columnNumber ?? null,
				lineNumber: location.lineNumber ?? null,
				path: consoleDiagnosticPath({
					maximumCharacters: props.maximumCapturedConsoleErrorCharacters,
					url: location.url,
				}),
				text,
				type: messageType,
			});
		}
	});
	props.page.on('pageerror', (error): void => {
		if (props.consoleErrors.length >= props.maximumCapturedConsoleErrors) return;
		const text = (error.stack ?? `${error.name}: ${error.message}`).slice(
			0,
			props.maximumCapturedConsoleErrorCharacters,
		);
		props.consoleErrors.push(text);
		props.consoleDiagnostics.push({
			columnNumber: null,
			lineNumber: null,
			path: null,
			text,
			type: 'error',
		});
	});
}

function consoleDiagnosticPath(props: {
	readonly maximumCharacters: number;
	readonly url: string;
}): string | null {
	if (props.url.length === 0) return null;
	try {
		return new URL(props.url).pathname;
	} catch {
		return props.url.slice(0, props.maximumCharacters);
	}
}

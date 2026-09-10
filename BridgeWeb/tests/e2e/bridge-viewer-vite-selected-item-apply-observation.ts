import type { Page, Response } from 'playwright';

export function observeSelectedItemApplies(page: Page): {
	readonly install: (itemId: string) => Promise<void>;
} {
	let controllerModuleUrl: string | null = null;
	const observeResponse = (response: Response): void => {
		if (new URL(response.url()).pathname.endsWith('/bridge-code-view-controller.ts')) {
			controllerModuleUrl = response.url();
		}
	};
	page.on('response', observeResponse);
	return {
		install: async (itemId): Promise<void> => {
			page.off('response', observeResponse);
			if (controllerModuleUrl === null)
				throw new Error('Selected apply observer did not see the live controller module.');
			// A browser expression preserves native import; Vite SSR rewrites imports in serialized callbacks.
			// Both interpolated values are JSON-encoded and the module URL was observed on this page.
			await page.evaluate(`(async () => {
				const { BridgeCodeViewController } = await import(${JSON.stringify(controllerModuleUrl)});
				const prototype = BridgeCodeViewController.prototype;
				const originalApply = prototype.applyItemUpdate;
				const selectedItemId = ${JSON.stringify(itemId)};
				const observations = [];
				prototype.applyItemUpdate = function (...args) {
					const result = originalApply.apply(this, args);
					const item = args[0];
					if (item.id === selectedItemId) {
						observations.push({ atMilliseconds: Math.round(performance.now()), result,
							version: item.version, contentState: item.bridgeMetadata.contentState,
							annotationCount: item.annotations?.length ?? 0,
							annotationKinds: item.annotations?.map(annotation => annotation.metadata?.kind ?? null) ?? [] });
						if (observations.length > 24) observations.shift();
					}
					return result;
				};
				Object.defineProperty(globalThis, '__bridgeSelectedItemApplies', { value: observations });
			})()`);
		},
	};
}

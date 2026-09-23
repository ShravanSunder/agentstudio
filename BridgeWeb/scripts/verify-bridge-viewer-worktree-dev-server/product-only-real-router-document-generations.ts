import type { Page, Request as PlaywrightRequest } from 'playwright';

// Which page document issued a request or created a worker. A response waiter is
// bound to one generation and accepts only responses to that generation's
// requests, so a late response from an earlier document cannot satisfy it.
export interface BridgeViewerDocumentGenerations {
	// The newest page document's generation; 0 before the first document.
	readonly currentGeneration: () => number;
	// The generation of the document that issued `request`.
	readonly requestGeneration: (request: PlaywrightRequest) => number;
	// The generation of the document that created the worker at `workerUrl`, and
	// the script the worker runs.
	readonly observedWorker: (workerUrl: string) => BridgeViewerObservedWorkerOrigin;
}

export interface BridgeViewerObservedWorkerOrigin {
	readonly documentGeneration: number;
	readonly scriptUrl: string;
}

export async function installBridgeViewerDocumentGenerations(
	page: Page,
): Promise<BridgeViewerDocumentGenerations> {
	let mainFrameDocumentGeneration = 0;
	page.on('framenavigated', (frame): void => {
		if (frame === page.mainFrame()) mainFrameDocumentGeneration += 1;
	});
	return {
		currentGeneration: (): number => mainFrameDocumentGeneration,
		observedWorker: (workerUrl: string): BridgeViewerObservedWorkerOrigin => ({
			documentGeneration: mainFrameDocumentGeneration,
			scriptUrl: workerUrl,
		}),
		requestGeneration: (): number => mainFrameDocumentGeneration,
	};
}

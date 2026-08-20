import type { ConsoleMessage, Page, Request, Response } from 'playwright';
import { expect } from 'vitest';

export interface ReviewComparisonBrowserObservation {
	readonly packageId: string;
	readonly reviewGeneration: number;
	readonly revision: number;
	readonly symbolicTargetLabel: string;
	readonly targetOID: string;
}

export interface BrowserRuntimeDiagnostics {
	readonly describe: () => Promise<string>;
}

export function observeBrowserRuntimeDiagnostics(page: Page): BrowserRuntimeDiagnostics {
	const consoleErrors: string[] = [];
	const failedRequests: string[] = [];
	const pageErrors: string[] = [];
	const productResponses: string[] = [];
	const responseBodyReads: Promise<void>[] = [];
	page.on('console', (message: ConsoleMessage): void => {
		if (message.type() === 'error') consoleErrors.push(message.text());
	});
	page.on('pageerror', (error: Error): void => {
		pageErrors.push(error.stack ?? error.message);
	});
	page.on('requestfailed', (request: Request): void => {
		failedRequests.push(
			`${request.method()} ${request.url()}: ${request.failure()?.errorText ?? 'unknown'}`,
		);
	});
	page.on('response', (response: Response): void => {
		const path = new URL(response.url()).pathname;
		if (!path.startsWith('/__bridge-product/')) return;
		const requestBody = response.request().postData()?.slice(0, 1_000) ?? '';
		const responseIndex =
			productResponses.push(
				`${response.status()} ${response.request().method()} ${path} request=${requestBody}`,
			) - 1;
		if (path !== '/__bridge-product/command' && response.status() < 400) return;
		responseBodyReads.push(
			response
				.text()
				.then((body): void => {
					productResponses[responseIndex] += ` body=${body.slice(0, 2_000)}`;
				})
				.catch((error: unknown): void => {
					productResponses[responseIndex] += ` bodyError=${String(error)}`;
				}),
		);
	});
	return {
		describe: async (): Promise<string> => {
			await Promise.allSettled(responseBodyReads);
			return JSON.stringify({
				bodyText: (
					await page
						.locator('body')
						.textContent()
						.catch((): null => null)
				)?.slice(0, 2_000),
				consoleErrors,
				failedRequests,
				pageErrors,
				productResponses,
				url: page.url(),
			});
		},
	};
}

export async function waitForSettledReviewComparison(props: {
	readonly expectedTargetLabel: string;
	readonly expectedTargetOID: string;
	readonly page: Page;
	readonly timeoutMilliseconds: number;
}): Promise<ReviewComparisonBrowserObservation> {
	const comparisonTrigger = props.page.getByTestId('bridge-review-comparison-trigger');
	await expect
		.poll(async (): Promise<string | null> => await comparisonTrigger.textContent(), {
			timeout: props.timeoutMilliseconds,
		})
		.toBe(props.expectedTargetLabel);
	let settledTargetOID = '';
	try {
		await expect
			.poll(
				async (): Promise<string | null> => {
					const observedTargetOID = await props.page.evaluate(
						(): string | null =>
							document
								.querySelector('[data-testid="bridge-review-comparison-current-state"]')
								?.getAttribute('data-resolved-target-oid') ?? null,
					);
					if (observedTargetOID !== null) settledTargetOID = observedTargetOID;
					if (
						observedTargetOID === null &&
						(await props.page.getByTestId('bridge-review-comparison-content').count()) === 0
					) {
						await comparisonTrigger.click();
					}
					return observedTargetOID;
				},
				{ timeout: props.timeoutMilliseconds },
			)
			.toBe(props.expectedTargetOID);
	} catch (error: unknown) {
		const comparisonState = await props.page.evaluate(
			(): string | null =>
				document.querySelector('[data-testid="bridge-review-comparison-content"]')?.textContent ??
				null,
		);
		throw new Error(`Review comparison did not settle: ${comparisonState ?? '<missing>'}`, {
			cause: error,
		});
	}
	const reviewShell = props.page.getByTestId('review-viewer-shell');
	const packageId = await reviewShell.getAttribute('data-review-metadata-id');
	const reviewGeneration = Number(
		await reviewShell.getAttribute('data-review-metadata-generation'),
	);
	const revision = Number(await reviewShell.getAttribute('data-review-metadata-revision'));
	const symbolicTargetLabel = (await comparisonTrigger.textContent()) ?? '';
	if (packageId === null || packageId.length === 0) {
		throw new Error('Settled Review comparison is missing package identity.');
	}
	return {
		packageId,
		reviewGeneration,
		revision,
		symbolicTargetLabel,
		targetOID: settledTargetOID,
	};
}

export async function waitForSettledReviewComparisonWithDiagnostics(props: {
	readonly diagnostics: BrowserRuntimeDiagnostics;
	readonly expectedTargetLabel: string;
	readonly expectedTargetOID: string;
	readonly failureContext: () => string;
	readonly page: Page;
	readonly timeoutMilliseconds: number;
}): Promise<ReviewComparisonBrowserObservation> {
	try {
		return await waitForSettledReviewComparison(props);
	} catch (error: unknown) {
		throw new Error(
			`Restarted Review comparison did not load: ${await props.diagnostics.describe()} ${props.failureContext()}`,
			{ cause: error },
		);
	}
}

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
	const productRequestPaths: string[] = [];
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
	page.on('request', (request: Request): void => {
		const path = new URL(request.url()).pathname;
		if (path.startsWith('/__bridge-product/')) productRequestPaths.push(path);
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
			const productBootstrapResponses = productResponses
				.filter((response): boolean => response.includes(' /__bridge-product/bootstrap '))
				.slice(-4)
				.map((response): string => response.slice(0, 3_000));
			const productErrorResponses = productResponses
				.filter((response): boolean => /^[45]\d\d /u.test(response))
				.slice(-8)
				.map((response): string => response.slice(0, 3_000));
			const reviewComparison = await page.evaluate(() => {
				const reviewShell = document.querySelector('[data-testid="review-viewer-shell"]');
				return {
					comparisonStatus:
						document.querySelector('[data-testid="bridge-viewer-content-status"]')?.textContent ??
						null,
					comparisonTrigger:
						document.querySelector('[data-testid="bridge-review-comparison-trigger"]')
							?.textContent ?? null,
					packageId: reviewShell?.getAttribute('data-review-metadata-id') ?? null,
					resolvedTargetOID:
						document
							.querySelector('[data-testid="bridge-review-comparison-current-state"]')
							?.getAttribute('data-resolved-target-oid') ?? null,
					reviewGeneration: reviewShell?.getAttribute('data-review-metadata-generation') ?? null,
					revision: reviewShell?.getAttribute('data-review-metadata-revision') ?? null,
					updateReadyCount: [...document.querySelectorAll('*')].filter(
						(element): boolean => element.textContent?.trim() === 'Update ready',
					).length,
				};
			});
			return JSON.stringify({
				bodyText: (
					await page
						.locator('body')
						.textContent()
						.catch((): null => null)
				)?.slice(0, 2_000),
				consoleErrorCount: consoleErrors.length,
				consoleErrors: consoleErrors.slice(-8),
				failedRequestCount: failedRequests.length,
				failedRequests: failedRequests.slice(-8),
				pageErrorCount: pageErrors.length,
				pageErrors: pageErrors.slice(-8),
				productRequestCount: productRequestPaths.length,
				productRequestPaths: productRequestPaths.slice(-16),
				productBootstrapResponses,
				productErrorResponses,
				productResponseCount: productResponses.length,
				productResponses: productResponses
					.slice(-8)
					.map((response): string => response.slice(0, 500)),
				reviewComparison,
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

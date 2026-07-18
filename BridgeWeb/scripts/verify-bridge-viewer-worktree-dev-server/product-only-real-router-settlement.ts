import { errors, type Page } from 'playwright';

let nextFrameSettlementSequence = 1;

export async function waitForProductBrowserFrameSettlement(props: {
	readonly page: Page;
	readonly stage: string;
	readonly timeoutMilliseconds: number;
}): Promise<void> {
	const settlementToken = `${props.stage}:${nextFrameSettlementSequence++}`;
	await props.page.evaluate((token): void => {
		type ProductJourneyWindow = Window & {
			bridgeViewerProductFrameSettlementToken?: string;
		};
		requestAnimationFrame((): void => {
			requestAnimationFrame((): void => {
				(window as ProductJourneyWindow).bridgeViewerProductFrameSettlementToken = token;
			});
		});
	}, settlementToken);
	try {
		await props.page.waitForFunction(
			(token: string): boolean => {
				type ProductJourneyWindow = Window & {
					bridgeViewerProductFrameSettlementToken?: string;
				};
				return (window as ProductJourneyWindow).bridgeViewerProductFrameSettlementToken === token;
			},
			settlementToken,
			{ timeout: props.timeoutMilliseconds },
		);
	} catch (error: unknown) {
		if (!(error instanceof errors.TimeoutError)) throw error;
		throw new Error(`BRIDGE_PRODUCT_FRAME_SETTLEMENT_TIMEOUT:${props.stage}`, { cause: error });
	}
}

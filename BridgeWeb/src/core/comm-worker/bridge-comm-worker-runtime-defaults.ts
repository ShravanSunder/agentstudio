import type { BridgeProductControlCommand } from './bridge-product-control-contracts.js';

export function scheduleDefaultBridgeRenderFulfillmentWake(
	delayMilliseconds: number,
	wake: () => void,
): () => void {
	const timeoutId = globalThis.setTimeout(wake, delayMilliseconds);
	return (): void => globalThis.clearTimeout(timeoutId);
}

export async function rejectUninstalledBridgeProductControl(
	command: BridgeProductControlCommand,
): Promise<never> {
	throw new Error(`Bridge product-control sender is not installed for ${command.method}.`);
}

export async function rejectUninstalledReviewMetadataInterestUpdate(): Promise<never> {
	throw new Error('Bridge Review metadata product subscription is not installed.');
}

export function rejectUninstalledBridgeFileContentOpen(): never {
	throw new Error('Bridge File content transport is not installed.');
}

export function bridgeCommWorkerProductControlFailureMessage(props: {
	readonly command: BridgeProductControlCommand;
}): string {
	return `Bridge comm worker failed to forward ${props.command.method}.`;
}

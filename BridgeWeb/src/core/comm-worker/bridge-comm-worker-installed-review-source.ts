import type { BridgeCommWorkerProductController } from './bridge-comm-worker-product-controller.js';
import type { BridgeWorkerReviewPublicationInstalledCommand } from './bridge-worker-review-publication-contracts.js';

export interface BridgeCommWorkerInstalledReviewSource {
	readonly hasInstalledSource: boolean;
	handleMetadataFailure(error: unknown): void;
	recordInstallation(command: BridgeWorkerInstalledReviewIdentity): void;
}

export type BridgeWorkerInstalledReviewIdentity = Pick<
	BridgeWorkerReviewPublicationInstalledCommand,
	'packageId' | 'publicationId' | 'reviewGeneration' | 'revision' | 'sourceIdentity'
>;

export function createBridgeCommWorkerInstalledReviewSource(
	readProductController: () => Pick<
		BridgeCommWorkerProductController,
		'setAnnotationProjectionSourceUnavailable' | 'setReviewAnnotationProjectionIdentity'
	> | null,
): BridgeCommWorkerInstalledReviewSource {
	let installedIdentity: BridgeWorkerInstalledReviewIdentity | null = null;
	return {
		get hasInstalledSource(): boolean {
			return installedIdentity !== null;
		},
		handleMetadataFailure: (error): void => {
			if (installedIdentity === null) {
				readProductController()?.setAnnotationProjectionSourceUnavailable('review', error);
			}
		},
		recordInstallation: (command): void => {
			installedIdentity = command;
			readProductController()?.setReviewAnnotationProjectionIdentity(command);
		},
	};
}

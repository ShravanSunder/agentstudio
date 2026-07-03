import type { BridgeReviewPackage } from '../foundation/review-package/bridge-review-package.js';
import type { SupportedLanguages } from '../review-viewer/code-view/bridge-code-view-pierre-types.js';
import {
	prewarmBridgePierreWorkerPool,
	type BridgePierreWorkerPoolPrewarmRequest,
} from '../review-viewer/workers/pierre/bridge-pierre-worker-prewarm.js';

export type BridgeViewerActivationMode = 'file' | 'review';

export interface BridgeViewerActivationPrewarmState {
	readonly prewarmedModes: Set<BridgeViewerActivationMode>;
}

export interface BridgeViewerActivationPrewarmProps {
	readonly activeViewerMode: BridgeViewerActivationMode;
	readonly prewarm?: (request: BridgePierreWorkerPoolPrewarmRequest) => void;
	readonly reviewPackage?: BridgeReviewPackage | null;
	readonly state: BridgeViewerActivationPrewarmState;
}

const bridgePierreStaticPrewarmLanguages: readonly SupportedLanguages[] = [
	'typescript',
	'tsx',
	'swift',
	'markdown',
	'json',
	'yaml',
] as const;

const bridgePierreStaticPrewarmLanguageSet = new Set<string>(bridgePierreStaticPrewarmLanguages);

const bridgePierrePrewarmLanguageAliasByMetadataValue: Readonly<
	Record<string, SupportedLanguages>
> = {
	md: 'markdown',
	ts: 'typescript',
	yml: 'yaml',
};

export function bridgeViewerActivationPrewarm(props: BridgeViewerActivationPrewarmProps): void {
	if (props.state.prewarmedModes.has(props.activeViewerMode)) {
		return;
	}
	props.state.prewarmedModes.add(props.activeViewerMode);
	const prewarm =
		props.prewarm ??
		((request: BridgePierreWorkerPoolPrewarmRequest): void => {
			void prewarmBridgePierreWorkerPool(request);
		});
	prewarm({
		languages:
			props.reviewPackage === undefined || props.reviewPackage === null
				? bridgePierreStaticPrewarmLanguages
				: bridgePierrePrewarmLanguagesForReviewPackage(props.reviewPackage),
	});
}

export function bridgePierrePrewarmLanguagesForReviewPackage(
	reviewPackage: BridgeReviewPackage,
): readonly SupportedLanguages[] {
	const countsByLanguage = new Map<SupportedLanguages, number>();
	for (const itemId of reviewPackage.orderedItemIds) {
		const item = reviewPackage.itemsById[itemId];
		if (item === undefined || item.isHiddenByDefault || item.fileClass === 'binary') {
			continue;
		}
		const language = supportedPrewarmLanguage(item.language ?? item.extension);
		if (language === null) {
			continue;
		}
		countsByLanguage.set(language, (countsByLanguage.get(language) ?? 0) + 1);
	}
	const languages = [...countsByLanguage.entries()]
		.toSorted(
			([leftLanguage, leftCount], [rightLanguage, rightCount]): number =>
				rightCount - leftCount ||
				staticPrewarmLanguageRank(leftLanguage) - staticPrewarmLanguageRank(rightLanguage) ||
				leftLanguage.localeCompare(rightLanguage),
		)
		.map(([language]): SupportedLanguages => language)
		.slice(0, bridgePierreStaticPrewarmLanguages.length);
	return languages.length === 0 ? bridgePierreStaticPrewarmLanguages : languages;
}

function supportedPrewarmLanguage(language: string | null | undefined): SupportedLanguages | null {
	if (language === null || language === undefined || language.length === 0) {
		return null;
	}
	const normalizedLanguage = language.toLowerCase();
	return (
		bridgePierrePrewarmLanguageAliasByMetadataValue[normalizedLanguage] ??
		(bridgePierreStaticPrewarmLanguageSet.has(normalizedLanguage)
			? (normalizedLanguage as SupportedLanguages)
			: null)
	);
}

function staticPrewarmLanguageRank(language: SupportedLanguages): number {
	const rank = bridgePierreStaticPrewarmLanguages.indexOf(language);
	return rank < 0 ? bridgePierreStaticPrewarmLanguages.length : rank;
}

import type { BridgeReviewPackage } from '../foundation/review-package/bridge-review-package.js';
import type { SupportedLanguages } from '../review-viewer/code-view/bridge-code-view-pierre-types.js';
import { bridgePierreHighlightLanguageOrPlainText } from '../review-viewer/workers/pierre/bridge-pierre-language-normalization.js';
import {
	prewarmBridgePierreWorkerPool,
	type BridgePierreWorkerPoolPrewarmRequest,
	type PrewarmBridgePierreWorkerPoolProps,
} from '../review-viewer/workers/pierre/bridge-pierre-worker-prewarm.js';

export type BridgeViewerActivationMode = 'file' | 'review';

export interface BridgeViewerActivationPrewarmState {
	readonly prewarmedModes: Set<BridgeViewerActivationMode>;
}

type BridgeViewerActivationPrewarmRequest = BridgePierreWorkerPoolPrewarmRequest &
	Pick<PrewarmBridgePierreWorkerPoolProps, 'workerFactory'>;

export interface BridgeViewerActivationPrewarmProps {
	readonly activeViewerMode: BridgeViewerActivationMode;
	readonly prewarm?: (request: BridgeViewerActivationPrewarmRequest) => void;
	readonly reviewPackage?: BridgeReviewPackage | null;
	readonly state: BridgeViewerActivationPrewarmState;
	readonly workerFactory?: () => Worker;
}

const bridgePierreStaticPrewarmLanguages: readonly SupportedLanguages[] = [
	'typescript',
	'tsx',
	'swift',
	'markdown',
	'json',
	'yaml',
] as const;

export function bridgeViewerActivationPrewarm(props: BridgeViewerActivationPrewarmProps): void {
	if (props.state.prewarmedModes.has(props.activeViewerMode)) {
		return;
	}
	props.state.prewarmedModes.add(props.activeViewerMode);
	const prewarm =
		props.prewarm ??
		((request: BridgeViewerActivationPrewarmRequest): void => {
			void prewarmBridgePierreWorkerPool(request);
		});
	const request: BridgeViewerActivationPrewarmRequest = {
		languages:
			props.reviewPackage === undefined || props.reviewPackage === null
				? bridgePierreStaticPrewarmLanguages
				: bridgePierrePrewarmLanguagesForReviewPackage(props.reviewPackage),
		...(props.workerFactory === undefined ? {} : { workerFactory: props.workerFactory }),
	};
	prewarm(request);
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
	const normalizedLanguage = bridgePierreHighlightLanguageOrPlainText(language);
	return normalizedLanguage === 'text' || normalizedLanguage === 'ansi' ? null : normalizedLanguage;
}

function staticPrewarmLanguageRank(language: SupportedLanguages): number {
	const rank = bridgePierreStaticPrewarmLanguages.indexOf(language);
	return rank < 0 ? bridgePierreStaticPrewarmLanguages.length : rank;
}

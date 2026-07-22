import type { SupportedLanguages } from '@pierre/diffs';
import { bundledLanguages } from 'shiki';

const bridgePierrePlaintextLanguage = 'text' satisfies SupportedLanguages;

const bridgePierrePlaintextLanguageAliases = new Set(['gitignore', 'plain', 'plaintext', 'txt']);

export function bridgePierreHighlightLanguageOrPlainText(
	language: string | null | undefined,
): SupportedLanguages {
	if (language === null || language === undefined) {
		return bridgePierrePlaintextLanguage;
	}
	const normalizedLanguage = language.trim().toLowerCase();
	if (
		normalizedLanguage.length === 0 ||
		bridgePierrePlaintextLanguageAliases.has(normalizedLanguage)
	) {
		return bridgePierrePlaintextLanguage;
	}
	if (normalizedLanguage === bridgePierrePlaintextLanguage || normalizedLanguage === 'ansi') {
		return normalizedLanguage;
	}
	return Object.prototype.hasOwnProperty.call(bundledLanguages, normalizedLanguage)
		? (normalizedLanguage as SupportedLanguages)
		: bridgePierrePlaintextLanguage;
}

export function bridgePierreOptionalHighlightLanguage(
	language: string | null | undefined,
): SupportedLanguages | undefined {
	return language === null || language === undefined || language.trim().length === 0
		? undefined
		: bridgePierreHighlightLanguageOrPlainText(language);
}

import DOMPurify from 'dompurify';
import type { ReactElement } from 'react';

export interface BridgeMarkdownPreviewProps {
	readonly html: string;
	readonly sourcePath: string;
}

export interface BridgeMarkdownPreviewElementProps {
	readonly className: string;
	readonly 'data-testid': string;
	readonly dangerouslySetInnerHTML: { readonly __html: string };
}

export function BridgeMarkdownPreview(
	props: BridgeMarkdownPreviewProps,
): ReactElement<BridgeMarkdownPreviewElementProps> {
	const sanitizedHtml = sanitizeBridgeMarkdownHtml(props.html);

	return (
		<article
			aria-label={`Markdown preview ${props.sourcePath}`}
			className="bridge-markdown-preview mx-auto min-h-full w-full max-w-[920px] px-10 py-8 text-[14px] leading-6 text-[var(--bridge-text-primary)]"
			data-testid="bridge-markdown-preview"
			dangerouslySetInnerHTML={{ __html: sanitizedHtml }}
		/>
	);
}

export function sanitizeBridgeMarkdownHtml(html: string): string {
	const sanitizedHtml = DOMPurify.sanitize(html, {
		USE_PROFILES: { html: true },
		ALLOWED_ATTR: ['class', 'style'],
		FORBID_TAGS: [
			'script',
			'style',
			'iframe',
			'object',
			'embed',
			'img',
			'picture',
			'source',
			'video',
			'audio',
			'svg',
			'math',
			'form',
			'input',
			'button',
			'select',
			'textarea',
			'option',
			'optgroup',
			'fieldset',
			'label',
			'legend',
			'details',
			'summary',
			'dialog',
			'menu',
			'menuitem',
		],
	});
	return sanitizeBridgeMarkdownAttributes(sanitizedHtml);
}

function sanitizeBridgeMarkdownAttributes(html: string): string {
	const template = document.createElement('template');
	template.innerHTML = html;
	for (const element of template.content.querySelectorAll<HTMLElement>('*')) {
		stripUnsafeBridgeMarkdownAttributes(element);
		const sanitizedStyle = safeBridgeMarkdownStyle(element.getAttribute('style') ?? '');
		if (sanitizedStyle.length === 0) {
			element.removeAttribute('style');
		} else {
			element.setAttribute('style', sanitizedStyle);
		}
	}
	return template.innerHTML;
}

function stripUnsafeBridgeMarkdownAttributes(element: HTMLElement): void {
	for (let index = element.attributes.length - 1; index >= 0; index -= 1) {
		const attribute = element.attributes.item(index);
		if (attribute === null) {
			continue;
		}
		if (attribute.name === 'class' || attribute.name === 'style') {
			continue;
		}
		element.removeAttribute(attribute.name);
	}
}

function safeBridgeMarkdownStyle(style: string): string {
	const declarations: string[] = [];
	for (const rawDeclaration of style.split(';')) {
		const separatorIndex = rawDeclaration.indexOf(':');
		if (separatorIndex < 0) {
			continue;
		}
		const propertyName = rawDeclaration.slice(0, separatorIndex).trim().toLowerCase();
		const propertyValue = rawDeclaration.slice(separatorIndex + 1).trim();
		if (!isAllowedShikiStyleDeclaration(propertyName, propertyValue)) {
			continue;
		}
		declarations.push(`${propertyName}: ${propertyValue}`);
	}
	return declarations.join('; ');
}

function isAllowedShikiStyleDeclaration(propertyName: string, propertyValue: string): boolean {
	if (propertyName !== 'color' && propertyName !== 'background-color') {
		return false;
	}
	if (/url\s*\(|expression\s*\(|var\s*\(/iu.test(propertyValue)) {
		return false;
	}
	return /^#[\da-f]{3,8}$/iu.test(propertyValue) || /^rgba?\([\d\s.,/%]+\)$/iu.test(propertyValue);
}

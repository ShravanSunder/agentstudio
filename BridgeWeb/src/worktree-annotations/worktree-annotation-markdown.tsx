import DOMPurify from 'dompurify';
import type { ReactElement } from 'react';

import { isAbsoluteHTTPURL } from './worktree-annotation-markdown-policy.js';

export interface WorktreeAnnotationMarkdownProps {
	readonly html: string;
}

export function WorktreeAnnotationMarkdown(props: WorktreeAnnotationMarkdownProps): ReactElement {
	return (
		<div
			className="worktree-annotation-markdown text-xs/relaxed text-comment-foreground"
			data-testid="worktree-annotation-markdown"
			dangerouslySetInnerHTML={{ __html: sanitizeWorktreeAnnotationMarkdownHtml(props.html) }}
		/>
	);
}

export function sanitizeWorktreeAnnotationMarkdownHtml(html: string): string {
	const sanitizedHtml = DOMPurify.sanitize(html, {
		ALLOWED_ATTR: ['class', 'href', 'style'],
		FORBID_TAGS: [
			'h1',
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
		USE_PROFILES: { html: true },
	});
	const template = document.createElement('template');
	template.innerHTML = sanitizedHtml;
	for (const element of template.content.querySelectorAll<HTMLElement>('*')) {
		sanitizeAnnotationElementAttributes(element);
	}
	return template.innerHTML;
}

function sanitizeAnnotationElementAttributes(element: HTMLElement): void {
	const tagName = element.tagName.toLowerCase();
	if (tagName === 'a') {
		const href = element.getAttribute('href');
		removeAllAttributes(element);
		if (href !== null && isAbsoluteHTTPURL(href)) element.setAttribute('href', href);
		return;
	}
	if (tagName === 'pre' || tagName === 'code' || tagName === 'span') {
		const className = element.getAttribute('class');
		const safeStyle = safeAnnotationShikiStyle(element.getAttribute('style') ?? '');
		removeAllAttributes(element);
		if (className !== null && className.length > 0) element.setAttribute('class', className);
		if (safeStyle.length > 0) element.setAttribute('style', safeStyle);
		return;
	}
	removeAllAttributes(element);
}

function removeAllAttributes(element: HTMLElement): void {
	for (
		let attributeIndex = element.attributes.length - 1;
		attributeIndex >= 0;
		attributeIndex -= 1
	) {
		const attribute = element.attributes.item(attributeIndex);
		if (attribute !== null) element.removeAttribute(attribute.name);
	}
}

function safeAnnotationShikiStyle(style: string): string {
	const declarations: string[] = [];
	for (const rawDeclaration of style.split(';')) {
		const separatorIndex = rawDeclaration.indexOf(':');
		if (separatorIndex < 0) continue;
		const propertyName = rawDeclaration.slice(0, separatorIndex).trim().toLowerCase();
		const propertyValue = rawDeclaration.slice(separatorIndex + 1).trim();
		if (!isAllowedAnnotationShikiStyle(propertyName, propertyValue)) continue;
		declarations.push(`${propertyName}: ${propertyValue}`);
	}
	return declarations.join('; ');
}

function isAllowedAnnotationShikiStyle(propertyName: string, propertyValue: string): boolean {
	if (propertyName !== 'color' && propertyName !== 'background-color') return false;
	if (/url\s*\(|expression\s*\(|var\s*\(/iu.test(propertyValue)) return false;
	return /^#[\da-f]{3,8}$/iu.test(propertyValue) || /^rgba?\([\d\s.,/%]+\)$/iu.test(propertyValue);
}

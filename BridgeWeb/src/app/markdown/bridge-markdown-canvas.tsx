import DOMPurify from 'dompurify';
import {
	memo,
	useCallback,
	useEffect,
	useRef,
	useState,
	type ReactElement,
	type RefObject,
} from 'react';
import { createPortal } from 'react-dom';

import { Button } from '@/components/ui/button.js';

import {
	bridgeMermaidPolicy,
	bridgeMermaidSourceAdmission,
	sanitizeBridgeMermaidSvg,
	type BridgeMermaidRenderer,
} from './bridge-mermaid-renderer.js';
import type { BridgeMarkdownPresentationState } from './use-bridge-markdown-presentation.js';

export interface BridgeMarkdownCanvasProps {
	readonly isActive: boolean;
	readonly presentationState: BridgeMarkdownPresentationState;
	readonly retry: () => void;
	readonly mermaidRenderer?: BridgeMermaidRenderer;
}

export function BridgeMarkdownCanvas(props: BridgeMarkdownCanvasProps): ReactElement {
	if (props.presentationState.status === 'idle') {
		return <BridgeMarkdownStatus label="Select a Markdown file" />;
	}
	if (props.presentationState.status === 'loading') {
		return <BridgeMarkdownStatus label="Rendering Markdown" />;
	}
	if (props.presentationState.status === 'failed') {
		return (
			<div className="flex h-full items-center justify-center" role="alert">
				<div className="flex flex-col items-center gap-3 text-sm text-[var(--bridge-text-secondary)]">
					<span>Markdown could not be rendered.</span>
					<Button onClick={props.retry} type="button" variant="outline">
						Retry
					</Button>
				</div>
			</div>
		);
	}

	return (
		<BridgeMarkdownReadyDocument
			isActive={props.isActive}
			mermaidRenderer={props.mermaidRenderer}
			presentation={props.presentationState}
		/>
	);
}

const BridgeMarkdownReadyDocument = memo(function BridgeMarkdownReadyDocument(props: {
	readonly isActive: boolean;
	readonly mermaidRenderer: BridgeMermaidRenderer | undefined;
	readonly presentation: Extract<BridgeMarkdownPresentationState, { readonly status: 'ready' }>;
}): ReactElement {
	const articleRef = useRef<HTMLElement>(null);
	const [diagramRetryRevision, setDiagramRetryRevision] = useState(0);
	const [diagramFailureTargets, setDiagramFailureTargets] = useState<
		readonly BridgeMermaidFailureTarget[]
	>([]);
	const retryMermaidDiagrams = useCallback((): void => {
		setDiagramFailureTargets((currentTargets): readonly BridgeMermaidFailureTarget[] =>
			currentTargets.length === 0 ? currentTargets : [],
		);
		setDiagramRetryRevision((revision): number => revision + 1);
	}, []);
	useEffect((): (() => void) | void => {
		let acceptsDiagramResults = true;
		if (!props.isActive) {
			return;
		}
		const article = articleRef.current;
		if (article === null) {
			return;
		}
		setDiagramFailureTargets([]);
		void renderBridgeMarkdownMermaidDiagrams({
			acceptsResult: (): boolean => acceptsDiagramResults,
			article,
			mermaidRenderer: props.mermaidRenderer,
			onFailure: (failureTarget: BridgeMermaidFailureTarget): void =>
				setDiagramFailureTargets((currentTargets): readonly BridgeMermaidFailureTarget[] => [
					...currentTargets.filter(
						(currentTarget): boolean => currentTarget.diagramId !== failureTarget.diagramId,
					),
					failureTarget,
				]),
			renderResult: props.presentation.renderResult,
			sourcePath: props.presentation.sourcePath,
		});
		return (): void => {
			acceptsDiagramResults = false;
		};
	}, [diagramRetryRevision, props.isActive, props.mermaidRenderer, props.presentation]);

	return (
		<div className="bridge-scrollbar h-full min-h-0 overflow-auto bg-[var(--bridge-canvas-bg)]">
			<BridgeMarkdownArticle articleRef={articleRef} presentation={props.presentation} />
			{diagramFailureTargets
				.filter(
					(failureTarget): boolean =>
						failureTarget.placeholder.isConnected &&
						articleRef.current?.contains(failureTarget.placeholder) === true,
				)
				.map((failureTarget) =>
					createPortal(
						<BridgeMermaidFailure onRetry={retryMermaidDiagrams} />,
						failureTarget.placeholder,
						failureTarget.diagramId,
					),
				)}
		</div>
	);
});

const BridgeMarkdownArticle = memo(function BridgeMarkdownArticle(props: {
	readonly articleRef: RefObject<HTMLElement | null>;
	readonly presentation: Extract<BridgeMarkdownPresentationState, { readonly status: 'ready' }>;
}): ReactElement {
	return (
		<article
			ref={props.articleRef}
			aria-label={`Markdown document ${props.presentation.sourcePath}`}
			className="bridge-markdown-document mx-auto min-h-full w-full max-w-[920px] px-10 py-8 text-[14px] leading-6 text-[var(--bridge-text-primary)]"
			data-bridge-markdown-source-path={props.presentation.sourcePath}
			data-testid="bridge-markdown-canvas"
			dangerouslySetInnerHTML={{
				__html: sanitizeBridgeMarkdownDocumentHtml(props.presentation.renderResult.htmlCandidate),
			}}
		/>
	);
});

interface BridgeMermaidFailureTarget {
	readonly diagramId: string;
	readonly placeholder: HTMLElement;
}

function BridgeMermaidFailure(props: { readonly onRetry: () => void }): ReactElement {
	return (
		<>
			<span>Diagram could not be rendered.</span>
			<Button onClick={props.onRetry} size="sm" type="button" variant="outline">
				Retry diagram
			</Button>
		</>
	);
}

async function renderBridgeMarkdownMermaidDiagrams(props: {
	readonly acceptsResult: () => boolean;
	readonly article: HTMLElement;
	readonly mermaidRenderer: BridgeMermaidRenderer | undefined;
	readonly onFailure: (failureTarget: BridgeMermaidFailureTarget) => void;
	readonly renderResult: Extract<
		BridgeMarkdownPresentationState,
		{ readonly status: 'ready' }
	>['renderResult'];
	readonly sourcePath: string;
}): Promise<void> {
	const diagrams = props.renderResult.mermaidDiagrams;
	const totalSourceBytes = diagrams.reduce(
		(totalBytes, diagram): number =>
			totalBytes + new TextEncoder().encode(diagram.source).byteLength,
		0,
	);
	const documentWithinPolicy =
		diagrams.length <= bridgeMermaidPolicy.maxDiagramCount &&
		totalSourceBytes <= bridgeMermaidPolicy.maxDocumentDiagramSourceBytes;
	for (const [index, diagram] of diagrams.entries()) {
		if (!props.acceptsResult()) {
			return;
		}
		const placeholder = props.article.querySelector<HTMLElement>(
			`[data-bridge-mermaid-id="${CSS.escape(diagram.id)}"]`,
		);
		if (placeholder === null || !placeholder.isConnected) {
			continue;
		}
		const admission = bridgeMermaidSourceAdmission(diagram.source);
		if (!documentWithinPolicy || !admission.admitted || props.mermaidRenderer === undefined) {
			markMermaidPlaceholderFailed(placeholder);
			props.onFailure({ diagramId: diagram.id, placeholder });
			continue;
		}
		placeholder.removeAttribute('role');
		placeholder.dataset['bridgeMermaidState'] = 'rendering';
		try {
			// oxlint-disable-next-line eslint/no-await-in-loop -- Serial rendering bounds Mermaid browser work.
			const renderedSvgCandidate = await props.mermaidRenderer.render({
				diagramId: `bridge-mermaid-${props.renderResult.requestId}-${index.toString()}`,
				source: diagram.source,
				accessibleLabel: `Diagram ${index + 1} in ${props.sourcePath}`,
			});
			if (
				!props.acceptsResult() ||
				!placeholder.isConnected ||
				placeholder.dataset['bridgeMermaidId'] !== diagram.id
			) {
				continue;
			}
			placeholder.innerHTML = sanitizeBridgeMermaidSvg(renderedSvgCandidate);
			placeholder.dataset['bridgeMermaidState'] = 'ready';
		} catch {
			if (props.acceptsResult() && placeholder.isConnected) {
				markMermaidPlaceholderFailed(placeholder);
				props.onFailure({ diagramId: diagram.id, placeholder });
			}
		}
	}
}

function markMermaidPlaceholderFailed(placeholder: HTMLElement): void {
	placeholder.replaceChildren();
	placeholder.dataset['bridgeMermaidState'] = 'failed';
	placeholder.setAttribute('role', 'alert');
}

export function sanitizeBridgeMarkdownDocumentHtml(htmlCandidate: string): string {
	const sanitizedHtml = DOMPurify.sanitize(htmlCandidate, {
		USE_PROFILES: { html: true },
		ALLOWED_ATTR: ['class', 'style', 'data-bridge-mermaid-id'],
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
		],
	});
	const template = document.createElement('template');
	template.innerHTML = sanitizedHtml;
	for (const element of template.content.querySelectorAll<HTMLElement>('*')) {
		for (
			let attributeIndex = element.attributes.length - 1;
			attributeIndex >= 0;
			attributeIndex -= 1
		) {
			const attribute = element.attributes.item(attributeIndex);
			if (attribute === null) {
				continue;
			}
			if (
				attribute.name !== 'class' &&
				attribute.name !== 'style' &&
				attribute.name !== 'data-bridge-mermaid-id'
			) {
				element.removeAttribute(attribute.name);
			}
		}
		const safeStyle = safeBridgeMarkdownStyle(element.getAttribute('style') ?? '');
		if (safeStyle.length === 0) {
			element.removeAttribute('style');
		} else {
			element.setAttribute('style', safeStyle);
		}
		if (element.tagName === 'A') {
			element.removeAttribute('href');
			element.removeAttribute('role');
			element.setAttribute('class', `${element.className} bridge-markdown-inert-link`.trim());
		}
	}
	return template.innerHTML;
}

function BridgeMarkdownStatus(props: { readonly label: string }): ReactElement {
	return (
		<div
			className="flex h-full items-center justify-center text-sm text-[var(--bridge-text-secondary)]"
			data-testid="bridge-markdown-status"
			role="status"
		>
			{props.label}
		</div>
	);
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
		if (
			(propertyName === 'color' || propertyName === 'background-color') &&
			!/(?:url|expression|var)\s*\(/iu.test(propertyValue) &&
			(/^#[\da-f]{3,8}$/iu.test(propertyValue) || /^rgba?\([\d\s.,/%]+\)$/iu.test(propertyValue))
		) {
			declarations.push(`${propertyName}: ${propertyValue}`);
		}
	}
	return declarations.join('; ');
}

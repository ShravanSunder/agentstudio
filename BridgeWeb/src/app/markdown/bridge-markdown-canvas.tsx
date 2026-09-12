import DOMPurify from 'dompurify';
import {
	memo,
	useCallback,
	useEffect,
	useLayoutEffect,
	useRef,
	useState,
	type ReactElement,
	type RefObject,
} from 'react';
import { createPortal } from 'react-dom';

import { Button } from '@/components/ui/button.js';

import type {
	BridgeMainRenderFulfillmentCoordinator,
	BridgeMainRenderPublicationItem,
} from '../../core/comm-worker/bridge-main-render-fulfillment-coordinator.js';
import type { BridgeFileViewerSelectedCodeViewItem } from '../../file-viewer/bridge-file-viewer-code-view-items.js';
import {
	useWorktreeAnnotationActiveEditTokens,
	useWorktreeAnnotationPrepareActiveEditorsForInstallation,
	useWorktreeAnnotationProjection,
} from '../../worktree-annotations/worktree-annotation-surface-provider.js';
import { BridgeMarkdownAnnotationLayer } from './bridge-markdown-annotation-layer.js';
import {
	type BridgeMarkdownRenderBinding,
	type BridgeMarkdownRenderedArticle,
	createBridgeMarkdownRenderReadback,
	bridgeMarkdownBindingMatchesCurrentSource,
} from './bridge-markdown-render-readback.js';
import {
	bridgeMermaidPolicy,
	bridgeMermaidSourceAdmission,
	sanitizeBridgeMermaidSvg,
	type BridgeMermaidRenderer,
} from './bridge-mermaid-renderer.js';
import type {
	BridgeMarkdownPresentationState,
	BridgeMarkdownRenderIntent,
} from './use-bridge-markdown-presentation.js';

export interface BridgeMarkdownRenderFulfillment {
	readonly coordinator: Pick<
		BridgeMainRenderFulfillmentCoordinator,
		'observePostRender' | 'reconcilePublication'
	>;
	readonly intent: BridgeMarkdownRenderIntent;
	readonly selectedItem: BridgeMainRenderPublicationItem;
}

export interface BridgeMarkdownCanvasProps {
	readonly annotationSource?:
		| { readonly item: BridgeFileViewerSelectedCodeViewItem | null }
		| undefined;
	readonly isActive: boolean;
	readonly presentationState: BridgeMarkdownPresentationState;
	readonly renderFulfillment?: BridgeMarkdownRenderFulfillment;
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
				<div className="flex flex-col items-center gap-3 text-sm text-muted-foreground">
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
			retry={props.retry}
			annotationSource={props.annotationSource}
			isActive={props.isActive}
			mermaidRenderer={props.mermaidRenderer}
			presentation={props.presentationState}
			{...(props.renderFulfillment === undefined
				? {}
				: { renderFulfillment: props.renderFulfillment })}
		/>
	);
}

const BridgeMarkdownReadyDocument = memo(function BridgeMarkdownReadyDocument(props: {
	readonly retry: () => void;
	readonly annotationSource?:
		| { readonly item: BridgeFileViewerSelectedCodeViewItem | null }
		| undefined;
	readonly isActive: boolean;
	readonly mermaidRenderer: BridgeMermaidRenderer | undefined;
	readonly presentation: Extract<BridgeMarkdownPresentationState, { readonly status: 'ready' }>;
	readonly renderFulfillment?: BridgeMarkdownRenderFulfillment;
}): ReactElement {
	const [presentation, setPresentation] = useState(props.presentation);
	const [installationFailure, setInstallationFailure] = useState(false);
	const [installationAttempt, setInstallationAttempt] = useState(0);
	const editTokens = useWorktreeAnnotationActiveEditTokens();
	const editTokensRef = useRef(editTokens);
	editTokensRef.current = editTokens;
	const annotationProjection = useWorktreeAnnotationProjection();
	const prepareEditors = useWorktreeAnnotationPrepareActiveEditorsForInstallation();
	const displayedSourceRef = useRef<BridgeFileViewerSelectedCodeViewItem | null>(null);
	const candidateRef = useRef(props.presentation);
	candidateRef.current = props.presentation;
	const keepsConfirmedSource =
		displayedSourceRef.current !== null &&
		props.annotationSource?.item !== null &&
		props.annotationSource?.item?.bridgeMetadata.sourceDescriptorId !==
			displayedSourceRef.current.bridgeMetadata.sourceDescriptorId &&
		annotationProjection.commandConfirmedThreads.some(
			(thread): boolean =>
				thread.context.sourceIdentity ===
				displayedSourceRef.current?.bridgeMetadata.sourceDescriptorId,
		);
	useEffect((): (() => void) | undefined => {
		if (presentation.identity.requestId === props.presentation.identity.requestId) return undefined;
		if (presentation.sourcePath !== props.presentation.sourcePath) {
			setPresentation(props.presentation);
			return undefined;
		}
		let current = true;
		const candidate = props.presentation;
		void prepareEditors().then(
			(prepared): void => {
				if (!current || candidateRef.current !== candidate) return;
				if (!prepared) {
					setInstallationFailure(true);
					return;
				}
				if (editTokensRef.current.size > 0 || keepsConfirmedSource) return;
				setInstallationFailure(false);
				setPresentation(candidate);
			},
			(): void => {
				if (current) setInstallationFailure(true);
			},
		);
		return (): void => {
			current = false;
		};
	}, [
		editTokens,
		installationAttempt,
		keepsConfirmedSource,
		prepareEditors,
		presentation,
		props.presentation,
	]);
	const articleRef = useRef<BridgeMarkdownRenderedArticle>(null);
	const renderBindingRef = useRef<BridgeMarkdownRenderBinding | null>(null);
	renderBindingRef.current =
		props.renderFulfillment === undefined
			? null
			: {
					isActive: props.isActive,
					intent: props.renderFulfillment.intent,
					presentation,
					selectedItem: props.renderFulfillment.selectedItem,
				};
	const canAnnotate =
		props.presentation.refresh.kind === 'current' &&
		renderBindingRef.current !== null &&
		bridgeMarkdownBindingMatchesCurrentSource(renderBindingRef.current);
	if (canAnnotate && props.annotationSource !== undefined)
		displayedSourceRef.current = props.annotationSource.item;
	if (displayedSourceRef.current?.bridgeMetadata.displayPath !== presentation.sourcePath)
		displayedSourceRef.current = null;
	useLayoutEffect((): void => {
		const renderFulfillment = props.renderFulfillment;
		if (renderFulfillment === undefined) return;
		const expectedBinding = renderBindingRef.current;
		if (expectedBinding === null) return;
		renderFulfillment.coordinator.observePostRender({
			...createBridgeMarkdownRenderReadback({
				expectedBinding,
				readArticle: (): BridgeMarkdownRenderedArticle | null => articleRef.current,
				readBinding: (): BridgeMarkdownRenderBinding | null => renderBindingRef.current,
			}),
			contextItem: renderFulfillment.selectedItem,
			itemId: renderFulfillment.selectedItem.id,
			phase: 'update',
		});
	});
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
			renderResult: presentation.renderResult,
			sourcePath: presentation.sourcePath,
		});
		return (): void => {
			acceptsDiagramResults = false;
		};
	}, [diagramRetryRevision, props.isActive, props.mermaidRenderer, presentation]);

	return (
		<div className="bridge-scrollbar h-full min-h-0 overflow-auto bg-background">
			{props.presentation.refresh.kind === 'failed' ? (
				<div role="status" className="flex items-center gap-2 p-2 text-sm text-muted-foreground">
					Markdown refresh failed. Showing the previous document.
					<Button variant="outline" size="sm" onClick={props.retry}>
						Retry
					</Button>
				</div>
			) : null}
			{installationFailure ? (
				<div role="status" className="flex items-center gap-2 p-2 text-sm text-muted-foreground">
					Your editor is retained. Finish editing or retry the refresh.
					<Button
						variant="outline"
						size="sm"
						onClick={(): void => setInstallationAttempt((attempt): number => attempt + 1)}
					>
						Retry
					</Button>
				</div>
			) : null}
			<div className="bridge-markdown-document-frame">
				<BridgeMarkdownArticle
					articleRef={articleRef}
					presentation={presentation}
					annotated={props.annotationSource !== undefined}
				/>
				{props.annotationSource === undefined ? null : (
					<BridgeMarkdownAnnotationLayer
						key={`${presentation.identity.sourceIdentity.fileId}:${presentation.sourcePath}`}
						articleRef={articleRef}
						targets={presentation.renderResult.annotationTargets}
						displayedSource={displayedSourceRef.current}
						canAnnotate={canAnnotate}
					/>
				)}
			</div>
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
	readonly annotated: boolean;
	readonly articleRef: RefObject<HTMLElement | null>;
	readonly presentation: Extract<BridgeMarkdownPresentationState, { readonly status: 'ready' }>;
}): ReactElement {
	return (
		<article
			ref={props.articleRef}
			aria-label={`Markdown document ${props.presentation.sourcePath}`}
			className="bridge-markdown-document mx-auto min-h-full w-full px-10 py-8 text-sm leading-6 text-foreground"
			data-bridge-markdown-annotated={props.annotated}
			data-bridge-markdown-source-path={props.presentation.sourcePath}
			data-bridge-markdown-content-cache-key={props.presentation.identity.contentCacheKey}
			data-bridge-markdown-content-hash={props.presentation.identity.contentHash}
			data-bridge-markdown-file-id={props.presentation.identity.sourceIdentity.fileId}
			data-bridge-markdown-file-version={props.presentation.identity.sourceIdentity.fileVersion}
			data-bridge-markdown-request-id={props.presentation.identity.requestId}
			data-bridge-markdown-source-generation={
				props.presentation.identity.sourceIdentity.sourceGeneration
			}
			data-bridge-markdown-source-id={props.presentation.identity.sourceIdentity.sourceId}
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
		ALLOWED_ATTR: [
			'class',
			'style',
			'data-bridge-mermaid-id',
			'data-bridge-markdown-target',
			'data-bridge-markdown-task',
			'role',
			'aria-label',
		],
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
				attribute.name !== 'data-bridge-mermaid-id' &&
				attribute.name !== 'data-bridge-markdown-target' &&
				attribute.name !== 'data-bridge-markdown-task' &&
				!(
					element.classList.contains('bridge-markdown-task-check') &&
					(attribute.name === 'role' || attribute.name === 'aria-label')
				)
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
			className="flex h-full items-center justify-center text-sm text-muted-foreground"
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

import type { Page } from 'playwright';

export interface AnnotationRangeBounds {
	readonly height: number;
	readonly width: number;
	readonly x: number;
	readonly y: number;
}

export async function reviewAdditionRangeBounds(props: {
	readonly endLine: number;
	readonly page: Page;
	readonly startLine: number;
}): Promise<readonly [AnnotationRangeBounds, AnnotationRangeBounds]> {
	const additionRows = await props.page.evaluate((): AnnotationRangeBounds[] => {
		const panel = document.querySelector('[data-testid="bridge-code-view-panel"]');
		if (panel === null) return [];
		const pending: Array<Element | ShadowRoot> = [panel];
		const rows: AnnotationRangeBounds[] = [];
		while (pending.length > 0) {
			const current = pending.shift();
			if (current === undefined) break;
			for (const row of current.querySelectorAll('[data-column-number]')) {
				const bounds = row.getBoundingClientRect();
				if (row.closest('[data-additions]') !== null && bounds.width > 0 && bounds.height > 0) {
					rows.push({ height: bounds.height, width: bounds.width, x: bounds.x, y: bounds.y });
				}
			}
			for (const descendant of current.querySelectorAll('*')) {
				if (descendant.shadowRoot !== null) pending.push(descendant.shadowRoot);
			}
		}
		return rows;
	});
	const orderedAdditionRows = additionRows.toSorted((left, right): number => left.y - right.y);
	const startBounds = orderedAdditionRows[0];
	const endBounds = orderedAdditionRows[2];
	if (startBounds === undefined || endBounds === undefined) {
		throw new Error('Review annotation journey requires three visible additions-side rows.');
	}
	return [startBounds, endBounds];
}

export interface ReviewRangeSelectionDiagnostic {
	readonly endHitPath: readonly string[];
	readonly selectedLineCount: number;
	readonly startHitPath: readonly string[];
	readonly utilityButtonCount: number;
}

export async function reviewRangeSelectionDiagnostic(props: {
	readonly endBounds: AnnotationRangeBounds;
	readonly page: Page;
	readonly startBounds: AnnotationRangeBounds;
}): Promise<ReviewRangeSelectionDiagnostic> {
	return await props.page.evaluate(
		({ endBounds, startBounds }): ReviewRangeSelectionDiagnostic => {
			const queryComposedCount = (selector: string): number => {
				const pending: Array<Document | ShadowRoot> = [document];
				let count = 0;
				while (pending.length > 0) {
					const current = pending.shift();
					if (current === undefined) break;
					count += current.querySelectorAll(selector).length;
					for (const descendant of current.querySelectorAll('*')) {
						if (descendant.shadowRoot !== null) pending.push(descendant.shadowRoot);
					}
				}
				return count;
			};
			const hitPath = (bounds: AnnotationRangeBounds): readonly string[] => {
				const point = { x: bounds.x + 4, y: bounds.y + bounds.height / 2 };
				const path: string[] = [];
				let currentRoot: Document | ShadowRoot = document;
				while (true) {
					const hit: Element | undefined = currentRoot.elementsFromPoint(point.x, point.y)[0];
					if (hit === undefined) break;
					path.push(
						[
							hit.tagName.toLowerCase(),
							hit.getAttribute('data-column-number'),
							hit.getAttribute('data-selected-line'),
							hit.getAttribute('data-testid'),
						]
							.filter((part): part is string => part !== null)
							.join(':'),
					);
					if (hit.shadowRoot === null) break;
					currentRoot = hit.shadowRoot;
				}
				return path;
			};
			return {
				endHitPath: hitPath(endBounds),
				selectedLineCount: queryComposedCount('[data-selected-line]'),
				startHitPath: hitPath(startBounds),
				utilityButtonCount: queryComposedCount('[data-utility-button]'),
			};
		},
		{ endBounds: props.endBounds, startBounds: props.startBounds },
	);
}

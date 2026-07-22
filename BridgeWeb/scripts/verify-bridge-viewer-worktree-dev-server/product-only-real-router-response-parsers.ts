export class GenerationScopedResponseParsers {
	readonly #failureByDocumentGeneration = new Map<number, unknown>();
	readonly #promisesByDocumentGeneration = new Map<number, Set<Promise<void>>>();

	async flush(documentGeneration: number): Promise<void> {
		const activePromises = this.#promisesByDocumentGeneration.get(documentGeneration);
		if (activePromises !== undefined) await Promise.allSettled(activePromises);
		if (this.#failureByDocumentGeneration.has(documentGeneration)) {
			throw this.#failureByDocumentGeneration.get(documentGeneration);
		}
	}

	track(promise: Promise<void>, documentGeneration: number): void {
		const generationPromises =
			this.#promisesByDocumentGeneration.get(documentGeneration) ?? new Set<Promise<void>>();
		this.#promisesByDocumentGeneration.set(documentGeneration, generationPromises);
		generationPromises.add(promise);
		void promise.then(
			(): void => this.#removePromise(promise, documentGeneration, generationPromises),
			(error: unknown): void => {
				if (!this.#failureByDocumentGeneration.has(documentGeneration)) {
					this.#failureByDocumentGeneration.set(documentGeneration, error);
				}
				this.#removePromise(promise, documentGeneration, generationPromises);
			},
		);
	}

	#removePromise(
		promise: Promise<void>,
		documentGeneration: number,
		generationPromises: Set<Promise<void>>,
	): void {
		generationPromises.delete(promise);
		if (generationPromises.size === 0) {
			this.#promisesByDocumentGeneration.delete(documentGeneration);
		}
	}
}

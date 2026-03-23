# Contributing to Agent Studio

Thank you for contributing!

## Requirements Before Opening a PR

**Every pull request must:**

1. **Reference an open issue.** Open or find an existing issue first. PRs without a linked issue will not be merged. Issues should describe the user pain point, not just the implementation.
2. **Pass CI.** All tests and lints must pass.
3. **Include a test plan.** Describe how the change was verified.

## Workflow

1. Open or find an issue describing the problem or feature
2. Fork the repository and create a branch from `main`
3. Implement your changes following the conventions in [CLAUDE.md](CLAUDE.md)
4. Run `mise run test` and `mise run lint` — both must pass
5. Open a pull request using the PR template (do not delete any sections)

## Using AI Agents

Most contributors use Claude Code or another AI agent. That's expected and encouraged. Please fill in the "How This Was Built" section of the PR template with the prompt or approach you used — this helps reviewers understand the context and improves future contributions.

## Contributor License Agreement

Agent Studio requires a lightweight CLA so the project can be maintained and dual-licensed while you retain full copyright ownership.

**You agree to the CLA by submitting a pull request with the Contributor License Agreement section intact.** The PR template includes the agreement at the bottom — do not remove or modify it. Keeping it intact constitutes your agreement.

Full terms: [CLA.md](CLA.md). One agreement covers all future contributions.

## Code Style

- `mise run format` — auto-format Swift sources
- `mise run lint` — lint + boundary checks (must pass before commit)
- Follow the architecture described in [CLAUDE.md](CLAUDE.md)

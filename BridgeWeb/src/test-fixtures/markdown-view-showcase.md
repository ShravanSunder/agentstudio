# Markdown View Showcase

This permanent fixture makes the semantic Markdown presentation easy to verify in
the BridgeWeb File View.

## Document structure

- Headings retain visible hierarchy.
- Lists, links, tables, quotations, and code use document styling.
- Mermaid fences render as diagrams.

> File View is the readable document surface. Review remains the exact Pierre diff.

| Surface   | Presentation      |
| --------- | ----------------- |
| Review    | Exact Pierre diff |
| File View | Semantic Markdown |

The [Agent Studio repository](https://example.com/agent-studio) is intentionally
shown as inert link text in this read-only view.

## Swift highlighting

```swift
struct MarkdownViewProof {
    let renderer: String = "Shiki"
    let diagramsAreEnabled: Bool = true
}
```

## Mermaid diagram

```mermaid
flowchart LR
    Selection[Select Markdown file] --> Worker[Markdown worker]
    Worker --> Document[Semantic document]
```

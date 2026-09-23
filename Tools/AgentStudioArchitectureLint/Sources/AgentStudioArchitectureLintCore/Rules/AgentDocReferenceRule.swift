import Foundation

/// Agent instruction documents are followed literally, so a reference that
/// resolves to nothing is an instruction that describes nothing.
///
/// In every `AGENTS.md`, outside fenced code:
/// - each Markdown link target that is not a URL must exist, resolved against
///   the document's directory or the repository root, and its `#anchor` must
///   name a heading (GitHub slug rules) or an explicit `<a id>`/`<a name>` in
///   the target Markdown file;
/// - each inline-code token written in repository-path form — it starts with
///   `./` or with an entry at the repository root, and contains only path
///   characters, optionally ending in `:line` or `#anchor` — must resolve the
///   same way.
///
/// Tokens not in that form (type names, commands, globs, placeholders such as
/// `<owner>/State/`) are not references. There is no per-token allowlist: a
/// false match is fixed by tightening the form.
struct AgentDocReferenceRule: ArchitectureDocumentRule {
    let id = "agentstudio_agent_doc_reference_resolves"
    let severity = ArchitectureSeverity.error

    func validate(document: AgentDocumentContext) -> [ArchitectureDiagnostic] {
        let resolver = RepositoryReferenceResolver(
            workspaceRootPath: document.workspaceRootPath,
            documentDirectoryPath: document.directoryPath
        )
        let scan = MarkdownReferenceScan(
            contents: document.contents,
            repositoryRootEntries: Self.repositoryRootEntries(workspaceRootPath: document.workspaceRootPath)
        )
        var anchorsByTargetPath: [String: Set<String>] = [:]

        return scan.references.compactMap { reference in
            guard
                let problem = problem(
                    with: reference,
                    document: document,
                    scan: scan,
                    resolver: resolver,
                    anchorsByTargetPath: &anchorsByTargetPath
                )
            else {
                return nil
            }
            return ArchitectureDiagnostic(
                path: document.path,
                line: reference.line,
                column: reference.column,
                severity: severity,
                ruleID: id,
                message: problem
            )
        }
    }

    /// Names at the repository root that a path can start with. Git metadata
    /// and build output are never paths an agent document should name.
    private static func repositoryRootEntries(workspaceRootPath: String) -> Set<String> {
        let entries = (try? FileManager.default.contentsOfDirectory(atPath: workspaceRootPath)) ?? []
        return Set(entries.filter { $0 != ".git" && !$0.hasPrefix(".build") })
    }

    private func problem(
        with reference: MarkdownReference,
        document: AgentDocumentContext,
        scan: MarkdownReferenceScan,
        resolver: RepositoryReferenceResolver,
        anchorsByTargetPath: inout [String: Set<String>]
    ) -> String? {
        let anchors: Set<String>
        if reference.path.isEmpty {
            anchors = scan.anchors
        } else {
            guard let resolvedPath = resolver.resolve(reference.path) else {
                return
                    "\(reference.written) does not exist (resolved against \(document.workspaceRelativePath ?? document.path)'s folder and the repository root)"
            }
            guard reference.anchor != nil, resolvedPath.hasSuffix(".md") else {
                return nil
            }
            if let cached = anchorsByTargetPath[resolvedPath] {
                anchors = cached
            } else {
                let contents = (try? String(contentsOfFile: resolvedPath, encoding: .utf8)) ?? ""
                anchors = MarkdownReferenceScan(contents: contents).anchors
                anchorsByTargetPath[resolvedPath] = anchors
            }
        }
        guard let anchor = reference.anchor, !anchors.contains(anchor) else {
            return nil
        }
        return "\(reference.written) names #\(anchor), which is not a heading or explicit anchor in its target"
    }
}

private struct RepositoryReferenceResolver {
    let workspaceRootPath: String
    let documentDirectoryPath: String

    /// The existing absolute path the reference names, trying the document's
    /// folder first and then the repository root.
    func resolve(_ path: String) -> String? {
        let decoded = path.removingPercentEncoding ?? path
        for base in [documentDirectoryPath, workspaceRootPath] {
            let candidate = URL(fileURLWithPath: decoded, relativeTo: URL(fileURLWithPath: base, isDirectory: true))
                .standardizedFileURL.path
            if FileManager.default.fileExists(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }
}

struct MarkdownReference: Equatable {
    /// The reference as written, for the diagnostic.
    let written: String
    /// Empty for a same-document `#anchor` link.
    let path: String
    let anchor: String?
    let line: Int
    let column: Int
}

/// One pass over a Markdown document: its references (outside fenced code),
/// and the anchors it defines (GitHub heading slugs plus explicit ids).
struct MarkdownReferenceScan {
    private(set) var references: [MarkdownReference] = []
    private(set) var anchors: Set<String> = []

    /// Inline-code tokens count as references only when rooted at one of
    /// these. `nil` scans headings and links only (a link target's anchors).
    private let repositoryRootEntries: Set<String>?

    init(contents: String, repositoryRootEntries: Set<String>? = nil) {
        self.repositoryRootEntries = repositoryRootEntries
        var slugCounts: [String: Int] = [:]
        var fence: Substring?
        for (index, line) in contents.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let trimmed = line.drop { $0 == " " }
            if let openFence = fence {
                if trimmed.hasPrefix(openFence) {
                    fence = nil
                }
                continue
            }
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                fence = trimmed.prefix(3)
                continue
            }
            if let heading = Self.headingText(line: line) {
                let slug = Self.gitHubSlug(heading)
                let count = slugCounts[slug, default: 0]
                anchors.insert(count == 0 ? slug : "\(slug)-\(count)")
                slugCounts[slug] = count + 1
            }
            anchors.formUnion(Self.explicitAnchors(in: line))
            references.append(contentsOf: scanReferences(line: line, lineNumber: index + 1))
        }
    }

    // MARK: - Headings

    /// ATX headings (`#` to `######`). The docs use no setext headings.
    private static func headingText(line: Substring) -> String? {
        let indentation = line.prefix { $0 == " " }
        guard indentation.count <= 3 else {
            return nil
        }
        let rest = line.dropFirst(indentation.count)
        let hashes = rest.prefix { $0 == "#" }
        if (1...6).contains(hashes.count), rest.dropFirst(hashes.count).first.map({ $0 == " " || $0 == "\t" }) ?? true {
            var text = rest.dropFirst(hashes.count).trimmingCharacters(in: .whitespaces)
            while text.hasSuffix("#") {
                text.removeLast()
            }
            return text.trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    /// GitHub's heading anchor: rendered text lowercased, every character
    /// that is not a letter, number, `-`, `_` or space removed, each space
    /// turned into `-`. So `Foo — Bar` becomes `foo--bar` and `7. Key Files`
    /// becomes `7-key-files`.
    static func gitHubSlug(_ heading: String) -> String {
        let rendered = renderedHeadingText(heading)
        return String(
            rendered.lowercased().compactMap { character -> Character? in
                if character == " " {
                    return "-"
                }
                if character.isLetter || character.isNumber || character == "-" || character == "_" {
                    return character
                }
                return nil
            }
        )
    }

    /// Link syntax renders as its text: `[Text](target)` contributes `Text`.
    private static func renderedHeadingText(_ heading: String) -> String {
        var rendered = ""
        var remaining = Substring(heading)
        while let open = remaining.firstIndex(of: "[") {
            rendered += remaining[..<open]
            let afterOpen = remaining[remaining.index(after: open)...]
            guard let close = afterOpen.firstIndex(of: "]"),
                afterOpen[afterOpen.index(after: close)...].first == "(",
                let closeParen = afterOpen[close...].firstIndex(of: ")")
            else {
                rendered += "["
                remaining = afterOpen
                continue
            }
            rendered += afterOpen[..<close]
            remaining = afterOpen[afterOpen.index(after: closeParen)...]
        }
        return rendered + remaining
    }

    private static func explicitAnchors(in line: Substring) -> [String] {
        var anchors: [String] = []
        var remaining = line[...]
        while let tagStart = remaining.range(of: "<a ") {
            let tag = remaining[tagStart.lowerBound...].prefix { $0 != ">" }
            for attribute in ["id=", "name="] {
                guard let attributeRange = tag.range(of: attribute) else {
                    continue
                }
                let valueStart = tag[attributeRange.upperBound...]
                guard let quote = valueStart.first, quote == "\"" || quote == "'" else {
                    continue
                }
                anchors.append(String(valueStart.dropFirst().prefix { $0 != quote }))
            }
            remaining = remaining[tagStart.upperBound...]
        }
        return anchors
    }

    // MARK: - References

    private func scanReferences(line: Substring, lineNumber: Int) -> [MarkdownReference] {
        var references: [MarkdownReference] = []
        var proseCharacters: [Character] = []
        var proseColumns: [Int] = []
        let characters = Array(line)
        var index = 0
        while index < characters.count {
            if characters[index] == "`" {
                let tickCount = characters[index...].prefix { $0 == "`" }.count
                let contentStart = index + tickCount
                var search = contentStart
                var contentEnd: Int?
                while search < characters.count {
                    if characters[search] == "`" {
                        let run = characters[search...].prefix { $0 == "`" }.count
                        if run == tickCount {
                            contentEnd = search
                            break
                        }
                        search += run
                    } else {
                        search += 1
                    }
                }
                guard let end = contentEnd else {
                    proseCharacters.append(contentsOf: characters[index..<contentStart])
                    proseColumns.append(contentsOf: (index..<contentStart).map { $0 + 1 })
                    index = contentStart
                    continue
                }
                let token = String(characters[contentStart..<end]).trimmingCharacters(in: .whitespaces)
                if let reference = codeTokenReference(token, line: lineNumber, column: contentStart + 1) {
                    references.append(reference)
                }
                index = end + tickCount
                continue
            }
            proseCharacters.append(characters[index])
            proseColumns.append(index + 1)
            index += 1
        }
        references.append(contentsOf: Self.linkReferences(in: proseCharacters, columns: proseColumns, line: lineNumber))
        return references.sorted { $0.column < $1.column }
    }

    /// `[text](target)` and `[text](target "title")`, with nesting of the
    /// text brackets ignored; also reference definitions `[id]: target`.
    private static func linkReferences(in characters: [Character], columns: [Int], line: Int) -> [MarkdownReference] {
        var references: [MarkdownReference] = []
        var index = 0
        while index + 1 < characters.count {
            guard characters[index] == "]" else {
                index += 1
                continue
            }
            let targetStart: Int
            if characters[index + 1] == "(" {
                targetStart = index + 2
            } else if characters[index + 1] == ":", Self.isReferenceDefinitionLine(characters, closingBracket: index) {
                targetStart = (index + 2..<characters.count).first { characters[$0] != " " } ?? characters.count
            } else {
                index += 1
                continue
            }
            var targetEnd = targetStart
            while targetEnd < characters.count, characters[targetEnd] != ")", characters[targetEnd] != " " {
                targetEnd += 1
            }
            var target = String(characters[targetStart..<targetEnd])
            if target.hasPrefix("<"), target.hasSuffix(">") {
                target = String(target.dropFirst().dropLast())
            }
            if !target.isEmpty, !Self.isExternalTarget(target), targetStart < columns.count {
                references.append(Self.reference(written: target, line: line, column: columns[targetStart]))
            }
            index = max(targetEnd, index + 1)
        }
        return references
    }

    private static func isReferenceDefinitionLine(_ characters: [Character], closingBracket: Int) -> Bool {
        let leading = characters.prefix { $0 == " " }.count
        return leading <= 3 && characters.indices.contains(leading) && characters[leading] == "["
            && !characters[(leading + 1)..<closingBracket].contains("]")
    }

    private static func isExternalTarget(_ target: String) -> Bool {
        target.contains("://") || target.hasPrefix("mailto:") || target.hasPrefix("tel:")
    }

    /// A code token in repository-path form, or `nil` when the token is not a
    /// reference at all.
    private func codeTokenReference(_ token: String, line: Int, column: Int) -> MarkdownReference? {
        guard let rootEntries = repositoryRootEntries, Self.hasRepositoryPathForm(token) else {
            return nil
        }
        let pathPart = token.split(separator: "#", maxSplits: 1).first.map(String.init) ?? token
        let withoutLineSuffix = Self.droppingLineSuffix(pathPart)
        let firstComponent = withoutLineSuffix.split(separator: "/").first.map(String.init) ?? withoutLineSuffix
        guard withoutLineSuffix.hasPrefix("./") || rootEntries.contains(firstComponent) else {
            return nil
        }
        let reference = Self.reference(written: token, line: line, column: column)
        return MarkdownReference(
            written: token,
            path: withoutLineSuffix,
            anchor: reference.anchor,
            line: line,
            column: column
        )
    }

    /// Only path characters, optionally a `:12` or `:12-40` line suffix and
    /// a `#anchor`. Spaces, globs, placeholders and call syntax fail.
    private static func hasRepositoryPathForm(_ token: String) -> Bool {
        let pathCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._/-+@"))
        let parts = token.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
        let path = droppingLineSuffix(String(parts[0]))
        guard !path.isEmpty, path.unicodeScalars.allSatisfy(pathCharacters.contains) else {
            return false
        }
        if parts.count == 2 {
            let anchorCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
            return !parts[1].isEmpty && parts[1].unicodeScalars.allSatisfy(anchorCharacters.contains)
        }
        return true
    }

    private static func droppingLineSuffix(_ path: String) -> String {
        guard let colon = path.lastIndex(of: ":") else {
            return path
        }
        let suffix = path[path.index(after: colon)...]
        let isLineSuffix =
            !suffix.isEmpty && suffix.first?.isNumber == true
            && suffix.allSatisfy { $0.isNumber || $0 == "-" || $0 == "," }
        return isLineSuffix ? String(path[..<colon]) : path
    }

    private static func reference(written: String, line: Int, column: Int) -> MarkdownReference {
        let parts = written.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
        return MarkdownReference(
            written: written,
            path: String(parts[0]),
            anchor: parts.count == 2 ? String(parts[1]) : nil,
            line: line,
            column: column
        )
    }
}

struct ImportDirectionRule: ArchitectureRule {
    let id = "agentstudio_import_direction"
    let severity = ArchitectureSeverity.error
    let message = "AgentStudio modules must follow the documented product and test dependency graph"

    func validate(context: ArchitectureLintContext) -> [ArchitectureDiagnostic] {
        let classifier = AgentStudioPathClassifier(path: context.normalizedPath)
        guard let currentModule = classifier.sourceModuleOwner ?? classifier.testModuleOwner else {
            return []
        }

        let visitor = ImportCollectingVisitor()
        visitor.walk(context.sourceFile)

        return visitor.imports.compactMap { importRecord in
            guard let importedModule = AgentStudioPathClassifier.importedModuleOwner(importRecord.path),
                !isAllowed(
                    currentModule: currentModule,
                    importedModule: importedModule,
                    isProductSource: classifier.sourceModuleOwner != nil
                )
            else {
                return nil
            }
            return diagnostic(
                context: context,
                position: importRecord.position,
                message: violationMessage(
                    currentModule: currentModule,
                    importedModule: importedModule,
                    importedPath: importRecord.path.joined(separator: "."),
                    isProductSource: classifier.sourceModuleOwner != nil
                )
            )
        }
    }

    private func isAllowed(
        currentModule: AgentStudioModuleOwner,
        importedModule: AgentStudioModuleOwner,
        isProductSource: Bool
    ) -> Bool {
        if isProductSource, importedModule == .testSupport {
            return false
        }

        switch currentModule {
        case .app:
            return importedModule != .testSupport || !isProductSource
        case .infrastructure:
            return importedModule == .infrastructure
        case .sharedComponents:
            return [.infrastructure, .sharedComponents].contains(importedModule)
        case .core:
            return [.core, .infrastructure, .sharedComponents, .testSupport].contains(importedModule)
        case .feature(let currentFeature):
            return [.core, .infrastructure, .sharedComponents, .testSupport].contains(importedModule)
                || importedModule == .feature(currentFeature)
        case .testSupport:
            return importedModule == .core || importedModule == .testSupport
        }
    }

    private func violationMessage(
        currentModule: AgentStudioModuleOwner,
        importedModule: AgentStudioModuleOwner,
        importedPath: String,
        isProductSource: Bool
    ) -> String {
        if isProductSource, importedModule == .testSupport {
            return "Product targets must not import AgentStudioTestSupport"
        }
        if !isProductSource, importedModule == .testSupport {
            switch currentModule {
            case .infrastructure:
                return "Infrastructure tests must not import AgentStudioTestSupport"
            case .sharedComponents:
                return "SharedComponents tests must not import AgentStudioTestSupport"
            default:
                break
            }
        }

        let ownerDescription: String
        switch currentModule {
        case .feature(let featureName):
            ownerDescription = "Feature \(featureName)\(isProductSource ? "" : " tests")"
        case .testSupport:
            ownerDescription = "TestSupport"
        default:
            ownerDescription = "\(currentModule.layerName)\(isProductSource ? "" : " tests")"
        }
        return "\(ownerDescription) cannot import \(importedPath)"
    }
}

import Foundation
import SwiftSyntax
import SwiftParser
import ArchitectCore

// MARK: - SwiftSyntax-Based StateObject Transform

/// Adds @StateObject wrapper using actual AST manipulation.
/// This is the gold-standard deterministic transform.
public struct SyntaxStateObjectTransform: DeterministicTransform, Sendable {
    
    public var supportedIntents: [String] {
        ["addStateObject", "addObservedObject"]
    }
    
    public init() {}
    
    public func apply(
        to source: String,
        intent: TaskIntent,
        context: TransformContext
    ) throws -> TransformResult {
        
        guard case .addStateObject(let property, let type, _) = intent else {
            throw TransformError.unsupportedIntent(String(describing: intent))
        }
        
        // Parse the source
        let sourceFile = Parser.parse(source: source)
        
        // Find and rewrite the property
        let rewriter = StateObjectRewriter(
            targetProperty: property,
            targetType: type
        )
        
        let rewritten = rewriter.rewrite(sourceFile)
        
        guard rewriter.didRewrite else {
            if rewriter.alreadyHasWrapper {
                throw TransformError.alreadyHasWrapper(property)
            }
            throw TransformError.propertyNotFound(property)
        }
        
        if rewriter.matchCount > 1 {
            throw TransformError.multipleMatches(property, count: rewriter.matchCount)
        }
        
        let transformedSource = rewritten.description
        let diff = generateUnifiedDiff(
            original: source,
            modified: transformedSource,
            filePath: context.filePath
        )
        
        return TransformResult(
            originalSource: source,
            transformedSource: transformedSource,
            diff: diff,
            linesChanged: rewriter.didRewrite ? 1 : 0
        )
    }
    
    private func generateUnifiedDiff(original: String, modified: String, filePath: String) -> String {
        let originalLines = original.components(separatedBy: "\n")
        let modifiedLines = modified.components(separatedBy: "\n")
        
        var diff = "--- a/\(filePath)\n+++ b/\(filePath)\n"
        
        for (i, (orig, mod)) in zip(originalLines, modifiedLines).enumerated() {
            if orig != mod {
                diff += "@@ -\(i + 1),1 +\(i + 1),1 @@\n"
                diff += "-\(orig)\n"
                diff += "+\(mod)\n"
            }
        }
        
        return diff
    }
}

// MARK: - StateObject Rewriter

private final class StateObjectRewriter: SyntaxRewriter {
    let targetProperty: String
    let targetType: String
    
    var didRewrite = false
    var alreadyHasWrapper = false
    var matchCount = 0
    
    init(targetProperty: String, targetType: String) {
        self.targetProperty = targetProperty
        self.targetType = targetType
        super.init()
    }
    
    override func visit(_ node: VariableDeclSyntax) -> DeclSyntax {
        // Check if this is our target property
        guard let binding = node.bindings.first,
              let pattern = binding.pattern.as(IdentifierPatternSyntax.self),
              pattern.identifier.text == targetProperty else {
            return DeclSyntax(node)
        }
        
        // Check type matches
        if let typeAnnotation = binding.typeAnnotation {
            let typeText = typeAnnotation.type.trimmedDescription
            guard typeText == targetType else {
                return DeclSyntax(node)
            }
        }
        
        matchCount += 1
        
        // Check if already has a property wrapper
        let existingWrappers = ["StateObject", "ObservedObject", "State", "Binding", "Environment", "EnvironmentObject"]
        for attr in node.attributes {
            if case .attribute(let attribute) = attr {
                let attrName = attribute.attributeName.trimmedDescription
                if existingWrappers.contains(attrName) {
                    alreadyHasWrapper = true
                    return DeclSyntax(node)
                }
            }
        }
        
        // Determine wrapper type
        let wrapperName = targetType.hasSuffix("ViewModel") || targetType.hasSuffix("Store") 
            ? "StateObject" 
            : "ObservedObject"
        
        // Create the @StateObject attribute
        let attribute = AttributeSyntax(
            atSign: .atSignToken(),
            attributeName: IdentifierTypeSyntax(name: .identifier(wrapperName)),
            trailingTrivia: .space
        )
        
        // Build new attributes list
        var newAttributes = node.attributes
        newAttributes.append(.attribute(attribute))
        
        // Create new variable declaration with the attribute
        let newNode = node.with(\.attributes, newAttributes)
        
        didRewrite = true
        return DeclSyntax(newNode)
    }
}

// MARK: - SwiftSyntax-Based Binding Transform

/// Adds @Binding wrapper using actual AST manipulation.
public struct SyntaxBindingTransform: DeterministicTransform, Sendable {
    
    public var supportedIntents: [String] {
        ["addBinding"]
    }
    
    public init() {}
    
    public func apply(
        to source: String,
        intent: TaskIntent,
        context: TransformContext
    ) throws -> TransformResult {
        
        guard case .addBinding(let property, _) = intent else {
            throw TransformError.unsupportedIntent(String(describing: intent))
        }
        
        let sourceFile = Parser.parse(source: source)
        let rewriter = BindingRewriter(targetProperty: property)
        let rewritten = rewriter.rewrite(sourceFile)
        
        guard rewriter.didRewrite else {
            if rewriter.alreadyHasWrapper {
                throw TransformError.alreadyHasWrapper(property)
            }
            throw TransformError.propertyNotFound(property)
        }
        
        if rewriter.matchCount > 1 {
            throw TransformError.multipleMatches(property, count: rewriter.matchCount)
        }
        
        let transformedSource = rewritten.description
        let diff = generateUnifiedDiff(
            original: source,
            modified: transformedSource,
            filePath: context.filePath
        )
        
        return TransformResult(
            originalSource: source,
            transformedSource: transformedSource,
            diff: diff,
            linesChanged: rewriter.didRewrite ? 1 : 0
        )
    }
    
    private func generateUnifiedDiff(original: String, modified: String, filePath: String) -> String {
        let originalLines = original.components(separatedBy: "\n")
        let modifiedLines = modified.components(separatedBy: "\n")
        
        var diff = "--- a/\(filePath)\n+++ b/\(filePath)\n"
        
        for (i, (orig, mod)) in zip(originalLines, modifiedLines).enumerated() {
            if orig != mod {
                diff += "@@ -\(i + 1),1 +\(i + 1),1 @@\n"
                diff += "-\(orig)\n"
                diff += "+\(mod)\n"
            }
        }
        
        return diff
    }
}

// MARK: - Binding Rewriter

private final class BindingRewriter: SyntaxRewriter {
    let targetProperty: String
    
    var didRewrite = false
    var alreadyHasWrapper = false
    var matchCount = 0
    
    init(targetProperty: String) {
        self.targetProperty = targetProperty
        super.init()
    }
    
    override func visit(_ node: VariableDeclSyntax) -> DeclSyntax {
        guard let binding = node.bindings.first,
              let pattern = binding.pattern.as(IdentifierPatternSyntax.self),
              pattern.identifier.text == targetProperty else {
            return DeclSyntax(node)
        }
        
        matchCount += 1
        
        // Check existing wrappers
        let existingWrappers = ["StateObject", "ObservedObject", "State", "Binding", "Environment", "EnvironmentObject"]
        for attr in node.attributes {
            if case .attribute(let attribute) = attr {
                let attrName = attribute.attributeName.trimmedDescription
                if existingWrappers.contains(attrName) {
                    alreadyHasWrapper = true
                    return DeclSyntax(node)
                }
            }
        }
        
        // Create @Binding attribute
        let attribute = AttributeSyntax(
            atSign: .atSignToken(),
            attributeName: IdentifierTypeSyntax(name: .identifier("Binding")),
            trailingTrivia: .space
        )
        
        var newAttributes = node.attributes
        newAttributes.append(.attribute(attribute))
        
        // Ensure it's var, not let
        let newBindingSpecifier = TokenSyntax.keyword(.var, trailingTrivia: node.bindingSpecifier.trailingTrivia)
        
        let newNode = node
            .with(\.attributes, newAttributes)
            .with(\.bindingSpecifier, newBindingSpecifier)
        
        didRewrite = true
        return DeclSyntax(newNode)
    }
}

// MARK: - SwiftSyntax-Based Import Transform

/// Adds import statements using AST manipulation.
public struct SyntaxImportTransform: DeterministicTransform, Sendable {
    
    public var supportedIntents: [String] {
        ["addImport"]
    }
    
    public init() {}
    
    public func apply(
        to source: String,
        intent: TaskIntent,
        context: TransformContext
    ) throws -> TransformResult {
        
        guard let moduleName = context.typeName else {
            throw TransformError.unsupportedIntent("addImport requires module name in context")
        }
        
        let sourceFile = Parser.parse(source: source)
        
        // Check if already imported
        for statement in sourceFile.statements {
            if let importDecl = statement.item.as(ImportDeclSyntax.self) {
                let importedModule = importDecl.path.map { $0.name.text }.joined(separator: ".")
                if importedModule == moduleName {
                    return TransformResult(
                        originalSource: source,
                        transformedSource: source,
                        diff: "// Already imported: \(moduleName)",
                        linesChanged: 0,
                        warnings: ["Module '\(moduleName)' is already imported"]
                    )
                }
            }
        }
        
        // Find insertion point (after last import, or at top)
        var insertIndex = 0
        for (index, statement) in sourceFile.statements.enumerated() {
            if statement.item.is(ImportDeclSyntax.self) {
                insertIndex = index + 1
            }
        }
        
        // Create new import
        let importDecl = ImportDeclSyntax(
            importKeyword: .keyword(.import, trailingTrivia: .space),
            path: ImportPathComponentListSyntax([
                ImportPathComponentSyntax(name: .identifier(moduleName))
            ])
        )
        
        let newStatement = CodeBlockItemSyntax(
            item: .decl(DeclSyntax(importDecl)),
            trailingTrivia: .newline
        )
        
        var newStatements = Array(sourceFile.statements)
        newStatements.insert(newStatement, at: insertIndex)
        
        let newSourceFile = sourceFile.with(\.statements, CodeBlockItemListSyntax(newStatements))
        let transformedSource = newSourceFile.description
        
        let diff = """
        --- a/\(context.filePath)
        +++ b/\(context.filePath)
        @@ -\(insertIndex + 1),0 +\(insertIndex + 1),1 @@
        +import \(moduleName)
        """
        
        return TransformResult(
            originalSource: source,
            transformedSource: transformedSource,
            diff: diff,
            linesChanged: 1
        )
    }
}

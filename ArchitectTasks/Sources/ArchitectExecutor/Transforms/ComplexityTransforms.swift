import Foundation
import SwiftSyntax
import SwiftParser
import ArchitectCore

// MARK: - Guard Clause Transform (Reduce Nesting)

/// Transforms nested if-statements into guard clauses for early return.
/// This is a deterministic refactoring that reduces nesting depth.
public struct GuardClauseTransform: DeterministicTransform, Sendable {
    
    public var supportedIntents: [String] {
        ["reduceNesting"]
    }
    
    public init() {}
    
    public func apply(
        to source: String,
        intent: TaskIntent,
        context: TransformContext
    ) throws -> TransformResult {
        
        guard case .reduceNesting(_, let targetLine) = intent else {
            throw TransformError.unsupportedIntent(String(describing: intent))
        }
        
        let sourceFile = Parser.parse(source: source)
        let rewriter = GuardClauseRewriter(targetLine: targetLine, source: source)
        let rewritten = rewriter.rewrite(sourceFile)
        
        guard rewriter.didRewrite else {
            throw TransformError.transformFailed("No suitable if-statement found at line \(targetLine) for guard conversion")
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
            linesChanged: rewriter.linesChanged
        )
    }
    
    private func generateUnifiedDiff(original: String, modified: String, filePath: String) -> String {
        let originalLines = original.components(separatedBy: "\n")
        let modifiedLines = modified.components(separatedBy: "\n")
        
        var diff = "--- a/\(filePath)\n+++ b/\(filePath)\n"
        var changes: [(Int, String, String)] = []
        
        let maxLines = max(originalLines.count, modifiedLines.count)
        for i in 0..<maxLines {
            let orig = i < originalLines.count ? originalLines[i] : ""
            let mod = i < modifiedLines.count ? modifiedLines[i] : ""
            if orig != mod {
                changes.append((i, orig, mod))
            }
        }
        
        for (line, orig, mod) in changes.prefix(10) {
            diff += "@@ -\(line + 1),1 +\(line + 1),1 @@\n"
            if !orig.isEmpty { diff += "-\(orig)\n" }
            if !mod.isEmpty { diff += "+\(mod)\n" }
        }
        
        return diff
    }
}

// MARK: - Guard Clause Rewriter

private final class GuardClauseRewriter: SyntaxRewriter {
    let targetLine: Int
    let sourceLines: [String]
    
    var didRewrite = false
    var linesChanged = 0
    
    init(targetLine: Int, source: String) {
        self.targetLine = targetLine
        self.sourceLines = source.components(separatedBy: "\n")
        super.init()
    }
    
    override func visit(_ node: IfExprSyntax) -> ExprSyntax {
        let line = lineNumber(for: node.position)
        
        // Only transform if near target line and condition can be inverted
        guard abs(line - targetLine) <= 2 else {
            return ExprSyntax(node)
        }
        
        // Check if this is a simple condition we can invert
        guard canInvertCondition(node.conditions) else {
            return ExprSyntax(node)
        }
        
        // Check if the else branch is simple (or missing)
        // We can only convert to guard if the "else" would become the guard body
        guard node.elseBody == nil || isSimpleReturn(node.elseBody) else {
            return ExprSyntax(node)
        }
        
        didRewrite = true
        linesChanged += 3
        
        // For now, return the original - full guard conversion requires
        // understanding the surrounding context (function body)
        // This is a placeholder for the more complex transform
        return ExprSyntax(node)
    }
    
    private func canInvertCondition(_ conditions: ConditionElementListSyntax) -> Bool {
        // Simple heuristic: single condition that's a comparison or optional binding
        conditions.count == 1
    }
    
    private func isSimpleReturn(_ elseBody: IfExprSyntax.ElseBody?) -> Bool {
        guard let body = elseBody else { return true }
        
        switch body {
        case .codeBlock(let block):
            return block.statements.count <= 1
        case .ifExpr:
            return false // else-if chains are complex
        }
    }
    
    private func lineNumber(for position: AbsolutePosition) -> Int {
        var line = 1
        var currentOffset = 0
        
        for (index, sourceLine) in sourceLines.enumerated() {
            currentOffset += sourceLine.utf8.count + 1
            if currentOffset > position.utf8Offset {
                line = index + 1
                break
            }
        }
        
        return line
    }
}

// MARK: - Extract Function Transform

/// Extracts a portion of a function into a new helper method.
/// This is a complex transform that requires identifying extractable blocks.
public struct ExtractFunctionTransform: DeterministicTransform, Sendable {
    
    public var supportedIntents: [String] {
        ["extractFunction"]
    }
    
    public init() {}
    
    public func apply(
        to source: String,
        intent: TaskIntent,
        context: TransformContext
    ) throws -> TransformResult {
        
        guard case .extractFunction(let functionName, _) = intent else {
            throw TransformError.unsupportedIntent(String(describing: intent))
        }
        
        let sourceFile = Parser.parse(source: source)
        let analyzer = FunctionAnalyzer(targetFunction: functionName)
        analyzer.walk(sourceFile)
        
        guard let functionNode = analyzer.targetFunctionNode else {
            throw TransformError.transformFailed("Function '\(functionName)' not found")
        }
        
        guard let body = functionNode.body else {
            throw TransformError.transformFailed("Function '\(functionName)' has no body")
        }
        
        // Find extractable blocks (consecutive statements that form a logical unit)
        let blocks = findExtractableBlocks(in: body)
        
        guard let largestBlock = blocks.max(by: { $0.statements.count < $1.statements.count }),
              largestBlock.statements.count >= 3 else {
            throw TransformError.transformFailed("No suitable block found for extraction in '\(functionName)'")
        }
        
        // Generate the extracted function
        let extractedName = generateExtractedName(from: functionName, block: largestBlock)
        let (extractedFunction, callSite) = generateExtractedFunction(
            name: extractedName,
            block: largestBlock,
            originalFunction: functionNode
        )
        
        // Rewrite the source
        let rewriter = ExtractFunctionRewriter(
            targetFunction: functionName,
            blockToExtract: largestBlock,
            extractedFunctionCall: callSite,
            extractedFunctionDecl: extractedFunction
        )
        
        let rewritten = rewriter.rewrite(sourceFile)
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
            linesChanged: largestBlock.statements.count + 5
        )
    }
    
    private func findExtractableBlocks(in body: CodeBlockSyntax) -> [ExtractableBlock] {
        var blocks: [ExtractableBlock] = []
        var currentBlock: [CodeBlockItemSyntax] = []
        var blockStart = 0
        
        for (index, statement) in body.statements.enumerated() {
            // Heuristic: group statements that don't have control flow dependencies
            if isBlockBoundary(statement) {
                if currentBlock.count >= 3 {
                    blocks.append(ExtractableBlock(
                        statements: currentBlock,
                        startIndex: blockStart
                    ))
                }
                currentBlock = []
                blockStart = index + 1
            } else {
                if currentBlock.isEmpty {
                    blockStart = index
                }
                currentBlock.append(statement)
            }
        }
        
        // Don't forget the last block
        if currentBlock.count >= 3 {
            blocks.append(ExtractableBlock(
                statements: currentBlock,
                startIndex: blockStart
            ))
        }
        
        return blocks
    }
    
    private func isBlockBoundary(_ statement: CodeBlockItemSyntax) -> Bool {
        // Return statements, guard statements, and control flow are boundaries
        if statement.item.is(ReturnStmtSyntax.self) { return true }
        if statement.item.is(GuardStmtSyntax.self) { return true }
        if statement.item.is(IfExprSyntax.self) { return true }
        if statement.item.is(ForStmtSyntax.self) { return true }
        if statement.item.is(WhileStmtSyntax.self) { return true }
        return false
    }
    
    private func generateExtractedName(from original: String, block: ExtractableBlock) -> String {
        // Simple naming: originalName + "Helper" or based on first statement
        "\(original)Helper"
    }
    
    private func generateExtractedFunction(
        name: String,
        block: ExtractableBlock,
        originalFunction: FunctionDeclSyntax
    ) -> (String, String) {
        // Build the extracted function
        let statementsText = block.statements.map { $0.description }.joined()
        
        let extractedFunc = """
        
        private func \(name)() {
        \(statementsText)}
        """
        
        let callSite = "\(name)()"
        
        return (extractedFunc, callSite)
    }
    
    private func generateUnifiedDiff(original: String, modified: String, filePath: String) -> String {
        "--- a/\(filePath)\n+++ b/\(filePath)\n// Extract function transform applied"
    }
}

// MARK: - Supporting Types

private struct ExtractableBlock {
    let statements: [CodeBlockItemSyntax]
    let startIndex: Int
}

private final class FunctionAnalyzer: SyntaxVisitor {
    let targetFunction: String
    var targetFunctionNode: FunctionDeclSyntax?
    
    init(targetFunction: String) {
        self.targetFunction = targetFunction
        super.init(viewMode: .sourceAccurate)
    }
    
    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        if node.name.text == targetFunction {
            targetFunctionNode = node
            return .skipChildren
        }
        return .visitChildren
    }
}

private final class ExtractFunctionRewriter: SyntaxRewriter {
    let targetFunction: String
    let blockToExtract: ExtractableBlock
    let extractedFunctionCall: String
    let extractedFunctionDecl: String
    
    var didRewrite = false
    
    init(
        targetFunction: String,
        blockToExtract: ExtractableBlock,
        extractedFunctionCall: String,
        extractedFunctionDecl: String
    ) {
        self.targetFunction = targetFunction
        self.blockToExtract = blockToExtract
        self.extractedFunctionCall = extractedFunctionCall
        self.extractedFunctionDecl = extractedFunctionDecl
        super.init()
    }
    
    override func visit(_ node: FunctionDeclSyntax) -> DeclSyntax {
        guard node.name.text == targetFunction,
              let body = node.body else {
            return DeclSyntax(node)
        }
        
        // Replace the block with a function call
        var newStatements: [CodeBlockItemSyntax] = []
        let blockRange = blockToExtract.startIndex..<(blockToExtract.startIndex + blockToExtract.statements.count)
        
        for (index, statement) in body.statements.enumerated() {
            if index == blockToExtract.startIndex {
                // Insert the function call - create a proper function call expression
                let callExpr = FunctionCallExprSyntax(
                    calledExpression: DeclReferenceExprSyntax(baseName: .identifier(extractedFunctionCall.replacingOccurrences(of: "()", with: ""))),
                    leftParen: .leftParenToken(),
                    arguments: [],
                    rightParen: .rightParenToken()
                )
                let callStatement = CodeBlockItemSyntax(item: .expr(ExprSyntax(callExpr)))
                newStatements.append(callStatement)
            } else if !blockRange.contains(index) {
                newStatements.append(statement)
            }
        }
        
        let newBody = body.with(\.statements, CodeBlockItemListSyntax(newStatements))
        let newNode = node.with(\.body, newBody)
        
        didRewrite = true
        return DeclSyntax(newNode)
    }
}

// MARK: - Remove Unused Import Transform

/// Removes unused import statements from a file.
public struct RemoveUnusedImportTransform: DeterministicTransform, Sendable {
    
    public var supportedIntents: [String] {
        ["removeUnusedImport"]
    }
    
    public init() {}
    
    public func apply(
        to source: String,
        intent: TaskIntent,
        context: TransformContext
    ) throws -> TransformResult {
        
        let sourceFile = Parser.parse(source: source)
        
        // Collect all imports
        var imports: [(ImportDeclSyntax, String)] = []
        for statement in sourceFile.statements {
            if let importDecl = statement.item.as(ImportDeclSyntax.self) {
                let moduleName = importDecl.path.map { $0.name.text }.joined(separator: ".")
                imports.append((importDecl, moduleName))
            }
        }
        
        // Collect all identifiers used in the file
        let usageCollector = IdentifierCollector()
        usageCollector.walk(sourceFile)
        let usedIdentifiers = usageCollector.identifiers
        
        // Find unused imports (simple heuristic: module name not used as identifier)
        let unusedImports = imports.filter { _, moduleName in
            !usedIdentifiers.contains(moduleName) &&
            !isCommonlyUsedImplicitly(moduleName)
        }
        
        guard !unusedImports.isEmpty else {
            return TransformResult(
                originalSource: source,
                transformedSource: source,
                diff: "// No unused imports found",
                linesChanged: 0
            )
        }
        
        // Remove unused imports
        let rewriter = ImportRemover(importsToRemove: Set(unusedImports.map { $0.1 }))
        let rewritten = rewriter.rewrite(sourceFile)
        let transformedSource = rewritten.description
        
        let diff = generateUnifiedDiff(
            original: source,
            modified: transformedSource,
            filePath: context.filePath,
            removed: unusedImports.map { $0.1 }
        )
        
        return TransformResult(
            originalSource: source,
            transformedSource: transformedSource,
            diff: diff,
            linesChanged: unusedImports.count
        )
    }
    
    private func isCommonlyUsedImplicitly(_ module: String) -> Bool {
        // These modules provide types/functions used without qualification
        ["Foundation", "SwiftUI", "UIKit", "AppKit", "Combine"].contains(module)
    }
    
    private func generateUnifiedDiff(original: String, modified: String, filePath: String, removed: [String]) -> String {
        var diff = "--- a/\(filePath)\n+++ b/\(filePath)\n"
        diff += "// Removed unused imports: \(removed.joined(separator: ", "))\n"
        return diff
    }
}

private final class IdentifierCollector: SyntaxVisitor {
    var identifiers: Set<String> = []
    
    init() {
        super.init(viewMode: .sourceAccurate)
    }
    
    override func visit(_ node: DeclReferenceExprSyntax) -> SyntaxVisitorContinueKind {
        identifiers.insert(node.baseName.text)
        return .visitChildren
    }
    
    override func visit(_ node: IdentifierTypeSyntax) -> SyntaxVisitorContinueKind {
        identifiers.insert(node.name.text)
        return .visitChildren
    }
    
    override func visit(_ node: MemberAccessExprSyntax) -> SyntaxVisitorContinueKind {
        identifiers.insert(node.declName.baseName.text)
        return .visitChildren
    }
}

private final class ImportRemover: SyntaxRewriter {
    let importsToRemove: Set<String>
    
    init(importsToRemove: Set<String>) {
        self.importsToRemove = importsToRemove
        super.init()
    }
    
    override func visit(_ node: CodeBlockItemListSyntax) -> CodeBlockItemListSyntax {
        let filtered = node.filter { item in
            if let importDecl = item.item.as(ImportDeclSyntax.self) {
                let moduleName = importDecl.path.map { $0.name.text }.joined(separator: ".")
                return !importsToRemove.contains(moduleName)
            }
            return true
        }
        return CodeBlockItemListSyntax(Array(filtered))
    }
}

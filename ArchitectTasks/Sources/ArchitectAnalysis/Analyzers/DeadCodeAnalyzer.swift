import Foundation
import SwiftSyntax
import SwiftParser
import ArchitectCore

// MARK: - Dead Code Analyzer

/// Detects potentially dead code:
/// - Unreachable code after return/throw
/// - Unused private functions
/// - Unused private properties
/// - Empty functions/closures
public final class DeadCodeAnalyzer: Analyzer, Sendable {
    
    public var supportedFindingTypes: [Finding.FindingType] {
        [.deadCode]
    }
    
    public init() {}
    
    public func analyze(fileAt path: String, content: String) throws -> [Finding] {
        var findings: [Finding] = []
        
        let sourceFile = Parser.parse(source: content)
        let visitor = DeadCodeVisitor(filePath: path, source: content)
        visitor.walk(sourceFile)
        
        findings.append(contentsOf: visitor.findings)
        
        return findings
    }
}

// MARK: - Dead Code Visitor

private final class DeadCodeVisitor: SyntaxVisitor {
    let filePath: String
    let sourceLines: [String]
    
    var findings: [Finding] = []
    
    // Track declarations for unused detection
    private var privateFunctions: [String: (line: Int, used: Bool)] = [:]
    private var privateProperties: [String: (line: Int, used: Bool)] = [:]
    private var usedIdentifiers: Set<String> = []
    
    init(filePath: String, source: String) {
        self.filePath = filePath
        self.sourceLines = source.components(separatedBy: "\n")
        super.init(viewMode: .sourceAccurate)
    }
    
    // MARK: - Unreachable Code Detection
    
    override func visit(_ node: CodeBlockSyntax) -> SyntaxVisitorContinueKind {
        var foundTerminator = false
        var terminatorLine = 0
        
        for statement in node.statements {
            if foundTerminator {
                // Code after return/throw is unreachable
                let line = lineNumber(for: statement.position)
                findings.append(Finding(
                    type: .deadCode,
                    location: SourceLocation(file: filePath, line: line),
                    severity: .warning,
                    context: [
                        "reason": "unreachable",
                        "afterLine": String(terminatorLine)
                    ],
                    message: "Unreachable code after line \(terminatorLine)"
                ))
                break
            }
            
            if isTerminator(statement) {
                foundTerminator = true
                terminatorLine = lineNumber(for: statement.position)
            }
        }
        
        return .visitChildren
    }
    
    private func isTerminator(_ statement: CodeBlockItemSyntax) -> Bool {
        statement.item.is(ReturnStmtSyntax.self) ||
        statement.item.is(ThrowStmtSyntax.self) ||
        isGuardWithReturn(statement)
    }
    
    private func isGuardWithReturn(_ statement: CodeBlockItemSyntax) -> Bool {
        guard let guardStmt = statement.item.as(GuardStmtSyntax.self) else {
            return false
        }
        // Guard always has an else that exits
        return true
    }
    
    // MARK: - Empty Function Detection
    
    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        let name = node.name.text
        let line = lineNumber(for: node.position)
        
        // Track private functions
        if isPrivate(node.modifiers) {
            privateFunctions[name] = (line: line, used: false)
        }
        
        // Check for empty body
        if let body = node.body {
            let hasOnlyComments = body.statements.allSatisfy { statement in
                // Check if statement is effectively empty
                statement.item.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            
            if body.statements.isEmpty || hasOnlyComments {
                findings.append(Finding(
                    type: .deadCode,
                    location: SourceLocation(file: filePath, line: line),
                    severity: .info,
                    context: [
                        "reason": "emptyFunction",
                        "function": name
                    ],
                    message: "Function '\(name)' has an empty body"
                ))
            }
        }
        
        return .visitChildren
    }
    
    // MARK: - Unused Private Property Detection
    
    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        guard isPrivate(node.modifiers) else {
            return .visitChildren
        }
        
        for binding in node.bindings {
            if let pattern = binding.pattern.as(IdentifierPatternSyntax.self) {
                let name = pattern.identifier.text
                let line = lineNumber(for: node.position)
                privateProperties[name] = (line: line, used: false)
            }
        }
        
        return .visitChildren
    }
    
    // MARK: - Track Usage
    
    override func visit(_ node: DeclReferenceExprSyntax) -> SyntaxVisitorContinueKind {
        usedIdentifiers.insert(node.baseName.text)
        return .visitChildren
    }
    
    override func visit(_ node: MemberAccessExprSyntax) -> SyntaxVisitorContinueKind {
        usedIdentifiers.insert(node.declName.baseName.text)
        return .visitChildren
    }
    
    // MARK: - Finalize (check unused)
    
    override func visitPost(_ node: SourceFileSyntax) {
        // Check for unused private functions
        for (name, info) in privateFunctions {
            if !usedIdentifiers.contains(name) {
                findings.append(Finding(
                    type: .deadCode,
                    location: SourceLocation(file: filePath, line: info.line),
                    severity: .warning,
                    context: [
                        "reason": "unusedPrivateFunction",
                        "function": name
                    ],
                    message: "Private function '\(name)' appears to be unused"
                ))
            }
        }
        
        // Check for unused private properties
        for (name, info) in privateProperties {
            if !usedIdentifiers.contains(name) {
                findings.append(Finding(
                    type: .deadCode,
                    location: SourceLocation(file: filePath, line: info.line),
                    severity: .warning,
                    context: [
                        "reason": "unusedPrivateProperty",
                        "property": name
                    ],
                    message: "Private property '\(name)' appears to be unused"
                ))
            }
        }
    }
    
    // MARK: - Helpers
    
    private func isPrivate(_ modifiers: DeclModifierListSyntax) -> Bool {
        modifiers.contains { modifier in
            modifier.name.text == "private" || modifier.name.text == "fileprivate"
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

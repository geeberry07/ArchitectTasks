import Foundation
import SwiftSyntax
import SwiftParser
import ArchitectCore

// MARK: - Complexity Analyzer

/// Analyzes Swift code for complexity issues:
/// - Functions with too many lines
/// - Functions with too many parameters
/// - Deeply nested code
/// - Large files
public final class ComplexityAnalyzer: Analyzer, Sendable {
    
    public struct Thresholds: Sendable {
        public var maxFunctionLines: Int
        public var maxFunctionParameters: Int
        public var maxNestingDepth: Int
        public var maxFileLines: Int
        public var maxCyclomaticComplexity: Int
        
        public init(
            maxFunctionLines: Int = 50,
            maxFunctionParameters: Int = 5,
            maxNestingDepth: Int = 4,
            maxFileLines: Int = 500,
            maxCyclomaticComplexity: Int = 10
        ) {
            self.maxFunctionLines = maxFunctionLines
            self.maxFunctionParameters = maxFunctionParameters
            self.maxNestingDepth = maxNestingDepth
            self.maxFileLines = maxFileLines
            self.maxCyclomaticComplexity = maxCyclomaticComplexity
        }
        
        public static let `default` = Thresholds()
        public static let strict = Thresholds(
            maxFunctionLines: 30,
            maxFunctionParameters: 3,
            maxNestingDepth: 3,
            maxFileLines: 300,
            maxCyclomaticComplexity: 7
        )
    }
    
    private let thresholds: Thresholds
    
    public var supportedFindingTypes: [Finding.FindingType] {
        [.highComplexity]
    }
    
    public init(thresholds: Thresholds = .default) {
        self.thresholds = thresholds
    }
    
    public func analyze(fileAt path: String, content: String) throws -> [Finding] {
        var findings: [Finding] = []
        
        let lines = content.components(separatedBy: "\n")
        
        // Check file length
        if lines.count > thresholds.maxFileLines {
            findings.append(Finding(
                type: .highComplexity,
                location: SourceLocation(file: path, line: 1),
                severity: .warning,
                context: [
                    "metric": "fileLines",
                    "value": String(lines.count),
                    "threshold": String(thresholds.maxFileLines)
                ],
                message: "File has \(lines.count) lines (threshold: \(thresholds.maxFileLines))"
            ))
        }
        
        // Parse and analyze AST
        let sourceFile = Parser.parse(source: content)
        let visitor = ComplexityVisitor(
            filePath: path,
            thresholds: thresholds,
            source: content
        )
        visitor.walk(sourceFile)
        
        findings.append(contentsOf: visitor.findings)
        
        return findings
    }
}

// MARK: - Complexity Visitor

private final class ComplexityVisitor: SyntaxVisitor {
    let filePath: String
    let thresholds: ComplexityAnalyzer.Thresholds
    let sourceLines: [String]
    
    var findings: [Finding] = []
    private var currentNestingDepth = 0
    
    init(filePath: String, thresholds: ComplexityAnalyzer.Thresholds, source: String) {
        self.filePath = filePath
        self.thresholds = thresholds
        self.sourceLines = source.components(separatedBy: "\n")
        super.init(viewMode: .sourceAccurate)
    }
    
    // MARK: - Function Analysis
    
    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        let functionName = node.name.text
        let startLine = lineNumber(for: node.position)
        
        // Check parameter count
        let paramCount = node.signature.parameterClause.parameters.count
        if paramCount > thresholds.maxFunctionParameters {
            findings.append(Finding(
                type: .highComplexity,
                location: SourceLocation(file: filePath, line: startLine),
                severity: .warning,
                context: [
                    "metric": "parameterCount",
                    "function": functionName,
                    "value": String(paramCount),
                    "threshold": String(thresholds.maxFunctionParameters)
                ],
                message: "Function '\(functionName)' has \(paramCount) parameters (threshold: \(thresholds.maxFunctionParameters))"
            ))
        }
        
        // Check function length
        if let body = node.body {
            let endLine = lineNumber(for: body.endPosition)
            let functionLines = endLine - startLine + 1
            
            if functionLines > thresholds.maxFunctionLines {
                findings.append(Finding(
                    type: .highComplexity,
                    location: SourceLocation(file: filePath, line: startLine),
                    severity: .warning,
                    context: [
                        "metric": "functionLines",
                        "function": functionName,
                        "value": String(functionLines),
                        "threshold": String(thresholds.maxFunctionLines)
                    ],
                    message: "Function '\(functionName)' has \(functionLines) lines (threshold: \(thresholds.maxFunctionLines))"
                ))
            }
            
            // Calculate cyclomatic complexity
            let complexity = calculateCyclomaticComplexity(body)
            if complexity > thresholds.maxCyclomaticComplexity {
                findings.append(Finding(
                    type: .highComplexity,
                    location: SourceLocation(file: filePath, line: startLine),
                    severity: .warning,
                    context: [
                        "metric": "cyclomaticComplexity",
                        "function": functionName,
                        "value": String(complexity),
                        "threshold": String(thresholds.maxCyclomaticComplexity)
                    ],
                    message: "Function '\(functionName)' has cyclomatic complexity \(complexity) (threshold: \(thresholds.maxCyclomaticComplexity))"
                ))
            }
        }
        
        return .visitChildren
    }
    
    // MARK: - Nesting Depth
    
    override func visit(_ node: IfExprSyntax) -> SyntaxVisitorContinueKind {
        checkNestingDepth(at: node.position)
        currentNestingDepth += 1
        return .visitChildren
    }
    
    override func visitPost(_ node: IfExprSyntax) {
        currentNestingDepth -= 1
    }
    
    override func visit(_ node: ForStmtSyntax) -> SyntaxVisitorContinueKind {
        checkNestingDepth(at: node.position)
        currentNestingDepth += 1
        return .visitChildren
    }
    
    override func visitPost(_ node: ForStmtSyntax) {
        currentNestingDepth -= 1
    }
    
    override func visit(_ node: WhileStmtSyntax) -> SyntaxVisitorContinueKind {
        checkNestingDepth(at: node.position)
        currentNestingDepth += 1
        return .visitChildren
    }
    
    override func visitPost(_ node: WhileStmtSyntax) {
        currentNestingDepth -= 1
    }
    
    override func visit(_ node: SwitchExprSyntax) -> SyntaxVisitorContinueKind {
        checkNestingDepth(at: node.position)
        currentNestingDepth += 1
        return .visitChildren
    }
    
    override func visitPost(_ node: SwitchExprSyntax) {
        currentNestingDepth -= 1
    }
    
    override func visit(_ node: GuardStmtSyntax) -> SyntaxVisitorContinueKind {
        checkNestingDepth(at: node.position)
        currentNestingDepth += 1
        return .visitChildren
    }
    
    override func visitPost(_ node: GuardStmtSyntax) {
        currentNestingDepth -= 1
    }
    
    // MARK: - Helpers
    
    private func checkNestingDepth(at position: AbsolutePosition) {
        if currentNestingDepth >= thresholds.maxNestingDepth {
            let line = lineNumber(for: position)
            findings.append(Finding(
                type: .highComplexity,
                location: SourceLocation(file: filePath, line: line),
                severity: .warning,
                context: [
                    "metric": "nestingDepth",
                    "value": String(currentNestingDepth + 1),
                    "threshold": String(thresholds.maxNestingDepth)
                ],
                message: "Nesting depth \(currentNestingDepth + 1) exceeds threshold \(thresholds.maxNestingDepth)"
            ))
        }
    }
    
    private func lineNumber(for position: AbsolutePosition) -> Int {
        var line = 1
        var currentOffset = 0
        
        for (index, sourceLine) in sourceLines.enumerated() {
            currentOffset += sourceLine.utf8.count + 1 // +1 for newline
            if currentOffset > position.utf8Offset {
                line = index + 1
                break
            }
        }
        
        return line
    }
    
    private func calculateCyclomaticComplexity(_ body: CodeBlockSyntax) -> Int {
        let counter = ComplexityCounter()
        counter.walk(body)
        return counter.complexity + 1 // Base complexity is 1
    }
}

// MARK: - Cyclomatic Complexity Counter

private final class ComplexityCounter: SyntaxVisitor {
    var complexity = 0
    
    init() {
        super.init(viewMode: .sourceAccurate)
    }
    
    override func visit(_ node: IfExprSyntax) -> SyntaxVisitorContinueKind {
        complexity += 1
        // Count else-if branches
        if node.elseBody != nil {
            complexity += 1
        }
        return .visitChildren
    }
    
    override func visit(_ node: ForStmtSyntax) -> SyntaxVisitorContinueKind {
        complexity += 1
        return .visitChildren
    }
    
    override func visit(_ node: WhileStmtSyntax) -> SyntaxVisitorContinueKind {
        complexity += 1
        return .visitChildren
    }
    
    override func visit(_ node: RepeatStmtSyntax) -> SyntaxVisitorContinueKind {
        complexity += 1
        return .visitChildren
    }
    
    override func visit(_ node: SwitchCaseSyntax) -> SyntaxVisitorContinueKind {
        complexity += 1
        return .visitChildren
    }
    
    override func visit(_ node: GuardStmtSyntax) -> SyntaxVisitorContinueKind {
        complexity += 1
        return .visitChildren
    }
    
    override func visit(_ node: CatchClauseSyntax) -> SyntaxVisitorContinueKind {
        complexity += 1
        return .visitChildren
    }
    
    override func visit(_ node: TernaryExprSyntax) -> SyntaxVisitorContinueKind {
        complexity += 1
        return .visitChildren
    }
    
    override func visit(_ node: InfixOperatorExprSyntax) -> SyntaxVisitorContinueKind {
        // Count && and || operators
        if let op = node.operator.as(BinaryOperatorExprSyntax.self) {
            let opText = op.operator.text
            if opText == "&&" || opText == "||" {
                complexity += 1
            }
        }
        return .visitChildren
    }
}

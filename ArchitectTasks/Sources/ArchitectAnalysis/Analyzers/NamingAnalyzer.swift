import Foundation
import SwiftSyntax
import SwiftParser
import ArchitectCore

// MARK: - Naming Convention Analyzer

/// Analyzes Swift code for naming convention violations:
/// - Types should be UpperCamelCase
/// - Functions/variables should be lowerCamelCase
/// - Constants can be lowerCamelCase or SCREAMING_SNAKE_CASE
/// - Boolean properties should use is/has/should prefixes
/// - Protocols should be nouns or -able/-ible suffixes
public final class NamingAnalyzer: Analyzer, Sendable {
    
    public struct Config: Sendable {
        public var enforceTypeCase: Bool
        public var enforceFunctionCase: Bool
        public var enforceVariableCase: Bool
        public var enforceBooleanPrefix: Bool
        public var enforceProtocolNaming: Bool
        public var minNameLength: Int
        public var maxNameLength: Int
        
        public init(
            enforceTypeCase: Bool = true,
            enforceFunctionCase: Bool = true,
            enforceVariableCase: Bool = true,
            enforceBooleanPrefix: Bool = true,
            enforceProtocolNaming: Bool = false,
            minNameLength: Int = 2,
            maxNameLength: Int = 50
        ) {
            self.enforceTypeCase = enforceTypeCase
            self.enforceFunctionCase = enforceFunctionCase
            self.enforceVariableCase = enforceVariableCase
            self.enforceBooleanPrefix = enforceBooleanPrefix
            self.enforceProtocolNaming = enforceProtocolNaming
            self.minNameLength = minNameLength
            self.maxNameLength = maxNameLength
        }
        
        public static let `default` = Config()
        public static let strict = Config(
            enforceProtocolNaming: true,
            minNameLength: 3,
            maxNameLength: 40
        )
    }
    
    private let config: Config
    
    public var supportedFindingTypes: [Finding.FindingType] {
        [.namingViolation]
    }
    
    public init(config: Config = .default) {
        self.config = config
    }
    
    public func analyze(fileAt path: String, content: String) throws -> [Finding] {
        let sourceFile = Parser.parse(source: content)
        let visitor = NamingVisitor(filePath: path, source: content, config: config)
        visitor.walk(sourceFile)
        return visitor.findings
    }
}

// MARK: - Naming Visitor

private final class NamingVisitor: SyntaxVisitor {
    let filePath: String
    let sourceLines: [String]
    let config: NamingAnalyzer.Config
    
    var findings: [Finding] = []
    
    init(filePath: String, source: String, config: NamingAnalyzer.Config) {
        self.filePath = filePath
        self.sourceLines = source.components(separatedBy: "\n")
        self.config = config
        super.init(viewMode: .sourceAccurate)
    }
    
    // MARK: - Type Names (struct, class, enum)
    
    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        if config.enforceTypeCase {
            checkTypeName(node.name.text, at: node.position, kind: "Struct")
        }
        return .visitChildren
    }
    
    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        if config.enforceTypeCase {
            checkTypeName(node.name.text, at: node.position, kind: "Class")
        }
        return .visitChildren
    }
    
    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        if config.enforceTypeCase {
            checkTypeName(node.name.text, at: node.position, kind: "Enum")
        }
        return .visitChildren
    }
    
    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        let name = node.name.text
        
        if config.enforceTypeCase {
            checkTypeName(name, at: node.position, kind: "Protocol")
        }
        
        if config.enforceProtocolNaming {
            checkProtocolNaming(name, at: node.position)
        }
        
        return .visitChildren
    }
    
    // MARK: - Function Names
    
    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        if config.enforceFunctionCase {
            let name = node.name.text
            checkFunctionName(name, at: node.position)
        }
        return .visitChildren
    }
    
    // MARK: - Variable Names
    
    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        guard config.enforceVariableCase else {
            return .visitChildren
        }
        
        for binding in node.bindings {
            if let pattern = binding.pattern.as(IdentifierPatternSyntax.self) {
                let name = pattern.identifier.text
                checkVariableName(name, at: node.position, binding: binding)
            }
        }
        
        return .visitChildren
    }
    
    // MARK: - Enum Cases
    
    override func visit(_ node: EnumCaseDeclSyntax) -> SyntaxVisitorContinueKind {
        for element in node.elements {
            let name = element.name.text
            if !isLowerCamelCase(name) {
                let line = lineNumber(for: element.position)
                findings.append(Finding(
                    type: .namingViolation,
                    location: SourceLocation(file: filePath, line: line),
                    severity: .info,
                    context: [
                        "kind": "enumCase",
                        "name": name,
                        "expected": "lowerCamelCase"
                    ],
                    message: "Enum case '\(name)' should be lowerCamelCase"
                ))
            }
        }
        return .visitChildren
    }
    
    // MARK: - Validation Helpers
    
    private func checkTypeName(_ name: String, at position: AbsolutePosition, kind: String) {
        let line = lineNumber(for: position)
        
        // Check length
        if name.count < config.minNameLength {
            findings.append(Finding(
                type: .namingViolation,
                location: SourceLocation(file: filePath, line: line),
                severity: .info,
                context: [
                    "kind": kind.lowercased(),
                    "name": name,
                    "reason": "tooShort",
                    "minLength": String(config.minNameLength)
                ],
                message: "\(kind) name '\(name)' is too short (min: \(config.minNameLength))"
            ))
        }
        
        if name.count > config.maxNameLength {
            findings.append(Finding(
                type: .namingViolation,
                location: SourceLocation(file: filePath, line: line),
                severity: .info,
                context: [
                    "kind": kind.lowercased(),
                    "name": name,
                    "reason": "tooLong",
                    "maxLength": String(config.maxNameLength)
                ],
                message: "\(kind) name '\(name)' is too long (max: \(config.maxNameLength))"
            ))
        }
        
        // Check case
        if !isUpperCamelCase(name) {
            findings.append(Finding(
                type: .namingViolation,
                location: SourceLocation(file: filePath, line: line),
                severity: .warning,
                context: [
                    "kind": kind.lowercased(),
                    "name": name,
                    "expected": "UpperCamelCase"
                ],
                message: "\(kind) '\(name)' should be UpperCamelCase"
            ))
        }
    }
    
    private func checkFunctionName(_ name: String, at position: AbsolutePosition) {
        let line = lineNumber(for: position)
        
        // Skip operators
        guard name.first?.isLetter == true || name.first == "_" else {
            return
        }
        
        if !isLowerCamelCase(name) {
            findings.append(Finding(
                type: .namingViolation,
                location: SourceLocation(file: filePath, line: line),
                severity: .warning,
                context: [
                    "kind": "function",
                    "name": name,
                    "expected": "lowerCamelCase"
                ],
                message: "Function '\(name)' should be lowerCamelCase"
            ))
        }
    }
    
    private func checkVariableName(_ name: String, at position: AbsolutePosition, binding: PatternBindingSyntax) {
        let line = lineNumber(for: position)
        
        // Skip underscore (unused variable)
        guard name != "_" else { return }
        
        // Check case
        if !isLowerCamelCase(name) && !isScreamingSnakeCase(name) {
            findings.append(Finding(
                type: .namingViolation,
                location: SourceLocation(file: filePath, line: line),
                severity: .info,
                context: [
                    "kind": "variable",
                    "name": name,
                    "expected": "lowerCamelCase"
                ],
                message: "Variable '\(name)' should be lowerCamelCase"
            ))
        }
        
        // Check boolean prefix
        if config.enforceBooleanPrefix {
            if let typeAnnotation = binding.typeAnnotation,
               typeAnnotation.type.description.trimmingCharacters(in: .whitespaces) == "Bool" {
                checkBooleanName(name, at: position)
            }
        }
    }
    
    private func checkBooleanName(_ name: String, at position: AbsolutePosition) {
        let validPrefixes = ["is", "has", "should", "can", "will", "did", "was", "were", "allows", "needs", "requires"]
        let hasValidPrefix = validPrefixes.contains { prefix in
            name.hasPrefix(prefix) && name.count > prefix.count && name[name.index(name.startIndex, offsetBy: prefix.count)].isUppercase
        }
        
        if !hasValidPrefix {
            let line = lineNumber(for: position)
            findings.append(Finding(
                type: .namingViolation,
                location: SourceLocation(file: filePath, line: line),
                severity: .info,
                context: [
                    "kind": "boolean",
                    "name": name,
                    "suggestion": "is\(name.prefix(1).uppercased())\(name.dropFirst())"
                ],
                message: "Boolean '\(name)' should use is/has/should/can prefix"
            ))
        }
    }
    
    private func checkProtocolNaming(_ name: String, at position: AbsolutePosition) {
        let validSuffixes = ["able", "ible", "ing", "Protocol", "Type", "Delegate", "DataSource"]
        let hasValidSuffix = validSuffixes.contains { name.hasSuffix($0) }
        
        // Also allow noun-like names (heuristic: doesn't look like an adjective)
        let looksLikeNoun = !name.hasSuffix("ed") && !name.hasSuffix("ly")
        
        if !hasValidSuffix && !looksLikeNoun {
            let line = lineNumber(for: position)
            findings.append(Finding(
                type: .namingViolation,
                location: SourceLocation(file: filePath, line: line),
                severity: .info,
                context: [
                    "kind": "protocol",
                    "name": name,
                    "suggestion": "\(name)able or \(name)Protocol"
                ],
                message: "Protocol '\(name)' should describe a capability (-able/-ible) or be a noun"
            ))
        }
    }
    
    // MARK: - Case Detection
    
    private func isUpperCamelCase(_ name: String) -> Bool {
        guard let first = name.first else { return false }
        guard first.isUppercase || first == "_" else { return false }
        // No underscores except leading
        return !name.dropFirst().contains("_")
    }
    
    private func isLowerCamelCase(_ name: String) -> Bool {
        guard let first = name.first else { return false }
        guard first.isLowercase || first == "_" else { return false }
        // No underscores except leading
        return !name.dropFirst().contains("_") || name.hasPrefix("_")
    }
    
    private func isScreamingSnakeCase(_ name: String) -> Bool {
        // All uppercase with underscores
        name.allSatisfy { $0.isUppercase || $0 == "_" || $0.isNumber }
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

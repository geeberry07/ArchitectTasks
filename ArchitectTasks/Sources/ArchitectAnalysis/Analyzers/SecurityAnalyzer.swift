import Foundation
import SwiftSyntax
import SwiftParser
import ArchitectCore

// MARK: - Security Analyzer

/// Detects potential security issues and unsafe patterns:
/// - Force unwrapping (!)
/// - Force try (try!)
/// - Implicitly unwrapped optionals
/// - Unsafe API usage
/// - Hardcoded secrets/credentials
public final class SecurityAnalyzer: Analyzer, Sendable {
    
    public struct Config: Sendable {
        public var detectForceUnwrap: Bool
        public var detectForceTry: Bool
        public var detectImplicitUnwrap: Bool
        public var detectHardcodedSecrets: Bool
        public var detectUnsafeAPIs: Bool
        public var secretPatterns: [String]
        
        public init(
            detectForceUnwrap: Bool = true,
            detectForceTry: Bool = true,
            detectImplicitUnwrap: Bool = true,
            detectHardcodedSecrets: Bool = true,
            detectUnsafeAPIs: Bool = true,
            secretPatterns: [String] = [
                "password", "secret", "api_key", "apikey", "token",
                "credential", "private_key", "privatekey", "auth"
            ]
        ) {
            self.detectForceUnwrap = detectForceUnwrap
            self.detectForceTry = detectForceTry
            self.detectImplicitUnwrap = detectImplicitUnwrap
            self.detectHardcodedSecrets = detectHardcodedSecrets
            self.detectUnsafeAPIs = detectUnsafeAPIs
            self.secretPatterns = secretPatterns
        }
        
        public static let `default` = Config()
        public static let strict = Config(
            detectForceUnwrap: true,
            detectForceTry: true,
            detectImplicitUnwrap: true,
            detectHardcodedSecrets: true,
            detectUnsafeAPIs: true
        )
    }
    
    private let config: Config
    
    public var supportedFindingTypes: [Finding.FindingType] {
        [.securityIssue]
    }
    
    public init(config: Config = .default) {
        self.config = config
    }
    
    public func analyze(fileAt path: String, content: String) throws -> [Finding] {
        let sourceFile = Parser.parse(source: content)
        let visitor = SecurityVisitor(filePath: path, source: content, config: config)
        visitor.walk(sourceFile)
        return visitor.findings
    }
}

// MARK: - Security Visitor

private final class SecurityVisitor: SyntaxVisitor {
    let filePath: String
    let sourceLines: [String]
    let config: SecurityAnalyzer.Config
    
    var findings: [Finding] = []
    
    init(filePath: String, source: String, config: SecurityAnalyzer.Config) {
        self.filePath = filePath
        self.sourceLines = source.components(separatedBy: "\n")
        self.config = config
        super.init(viewMode: .sourceAccurate)
    }
    
    // MARK: - Force Unwrap Detection
    
    override func visit(_ node: ForceUnwrapExprSyntax) -> SyntaxVisitorContinueKind {
        guard config.detectForceUnwrap else { return .visitChildren }
        
        let line = lineNumber(for: node.position)
        findings.append(Finding(
            type: .securityIssue,
            location: SourceLocation(file: filePath, line: line),
            severity: .warning,
            context: [
                "issue": "forceUnwrap",
                "expression": node.expression.trimmedDescription
            ],
            message: "Force unwrap (!) can cause runtime crashes. Consider using optional binding or nil coalescing."
        ))
        
        return .visitChildren
    }
    
    // MARK: - Force Try Detection
    
    override func visit(_ node: TryExprSyntax) -> SyntaxVisitorContinueKind {
        guard config.detectForceTry else { return .visitChildren }
        
        // Check if it's try! (force try)
        if node.questionOrExclamationMark?.tokenKind == .exclamationMark {
            let line = lineNumber(for: node.position)
            findings.append(Finding(
                type: .securityIssue,
                location: SourceLocation(file: filePath, line: line),
                severity: .warning,
                context: [
                    "issue": "forceTry",
                    "expression": node.expression.trimmedDescription
                ],
                message: "Force try (try!) can cause runtime crashes. Consider using do-catch or try?."
            ))
        }
        
        return .visitChildren
    }
    
    // MARK: - Implicitly Unwrapped Optional Detection
    
    override func visit(_ node: ImplicitlyUnwrappedOptionalTypeSyntax) -> SyntaxVisitorContinueKind {
        guard config.detectImplicitUnwrap else { return .visitChildren }
        
        let line = lineNumber(for: node.position)
        findings.append(Finding(
            type: .securityIssue,
            location: SourceLocation(file: filePath, line: line),
            severity: .info,
            context: [
                "issue": "implicitUnwrap",
                "type": node.wrappedType.trimmedDescription
            ],
            message: "Implicitly unwrapped optional (\(node.wrappedType.trimmedDescription)!) can cause runtime crashes. Consider using regular optional."
        ))
        
        return .visitChildren
    }
    
    // MARK: - Hardcoded Secrets Detection
    
    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        guard config.detectHardcodedSecrets else { return .visitChildren }
        
        for binding in node.bindings {
            guard let pattern = binding.pattern.as(IdentifierPatternSyntax.self) else { continue }
            let name = pattern.identifier.text.lowercased()
            
            // Check if variable name suggests a secret
            let isSecretName = config.secretPatterns.contains { name.contains($0) }
            
            if isSecretName {
                // Check if it has a string literal initializer
                if let initializer = binding.initializer,
                   initializer.value.is(StringLiteralExprSyntax.self) {
                    let line = lineNumber(for: node.position)
                    findings.append(Finding(
                        type: .securityIssue,
                        location: SourceLocation(file: filePath, line: line),
                        severity: .error,
                        context: [
                            "issue": "hardcodedSecret",
                            "variable": pattern.identifier.text
                        ],
                        message: "Potential hardcoded secret in '\(pattern.identifier.text)'. Use environment variables or secure storage."
                    ))
                }
            }
        }
        
        return .visitChildren
    }
    
    // MARK: - Unsafe API Detection
    
    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        guard config.detectUnsafeAPIs else { return .visitChildren }
        
        let functionName = extractFunctionName(node)
        
        // Check for unsafe APIs
        let unsafeAPIs: [(name: String, reason: String)] = [
            ("unsafeBitCast", "Can cause undefined behavior if types don't match"),
            ("unsafeDowncast", "Can crash if cast fails"),
            ("withUnsafePointer", "Manual memory management is error-prone"),
            ("withUnsafeMutablePointer", "Manual memory management is error-prone"),
            ("withUnsafeBytes", "Can cause memory corruption if misused"),
            ("assumingMemoryBound", "Assumes memory layout, can cause undefined behavior"),
            ("bindMemory", "Manual memory binding is dangerous"),
            ("deallocate", "Manual deallocation can cause use-after-free"),
        ]
        
        for (api, reason) in unsafeAPIs {
            if functionName.contains(api) {
                let line = lineNumber(for: node.position)
                findings.append(Finding(
                    type: .securityIssue,
                    location: SourceLocation(file: filePath, line: line),
                    severity: .warning,
                    context: [
                        "issue": "unsafeAPI",
                        "api": api,
                        "reason": reason
                    ],
                    message: "Unsafe API '\(api)' detected. \(reason)"
                ))
            }
        }
        
        return .visitChildren
    }
    
    // MARK: - Helpers
    
    private func extractFunctionName(_ call: FunctionCallExprSyntax) -> String {
        if let member = call.calledExpression.as(MemberAccessExprSyntax.self) {
            return member.declName.baseName.text
        } else if let identifier = call.calledExpression.as(DeclReferenceExprSyntax.self) {
            return identifier.baseName.text
        }
        return call.calledExpression.trimmedDescription
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

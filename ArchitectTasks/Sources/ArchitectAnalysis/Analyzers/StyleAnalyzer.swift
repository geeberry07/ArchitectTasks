import Foundation
import SwiftSyntax
import SwiftParser
import ArchitectCore

// MARK: - Style Analyzer

/// Detects style and formatting issues:
/// - Line length violations
/// - Trailing whitespace
/// - Missing/extra blank lines
/// - Import organization
/// - File structure (imports, types, extensions order)
public final class StyleAnalyzer: Analyzer, Sendable {
    
    public struct Config: Sendable {
        public var maxLineLength: Int
        public var detectTrailingWhitespace: Bool
        public var detectMultipleBlankLines: Bool
        public var detectImportOrder: Bool
        public var detectFileStructure: Bool
        public var detectTrailingNewline: Bool
        
        public init(
            maxLineLength: Int = 120,
            detectTrailingWhitespace: Bool = true,
            detectMultipleBlankLines: Bool = true,
            detectImportOrder: Bool = true,
            detectFileStructure: Bool = true,
            detectTrailingNewline: Bool = true
        ) {
            self.maxLineLength = maxLineLength
            self.detectTrailingWhitespace = detectTrailingWhitespace
            self.detectMultipleBlankLines = detectMultipleBlankLines
            self.detectImportOrder = detectImportOrder
            self.detectFileStructure = detectFileStructure
            self.detectTrailingNewline = detectTrailingNewline
        }
        
        public static let `default` = Config()
        
        public static let strict = Config(
            maxLineLength: 100,
            detectTrailingWhitespace: true,
            detectMultipleBlankLines: true,
            detectImportOrder: true,
            detectFileStructure: true,
            detectTrailingNewline: true
        )
        
        public static let lenient = Config(
            maxLineLength: 150,
            detectTrailingWhitespace: false,
            detectMultipleBlankLines: false,
            detectImportOrder: false,
            detectFileStructure: false,
            detectTrailingNewline: false
        )
    }
    
    private let config: Config
    
    public var supportedFindingTypes: [Finding.FindingType] {
        [.namingViolation]  // Reusing for style issues
    }
    
    public init(config: Config = .default) {
        self.config = config
    }
    
    public func analyze(fileAt path: String, content: String) throws -> [Finding] {
        var findings: [Finding] = []
        let lines = content.components(separatedBy: "\n")
        
        // Line-based checks
        findings.append(contentsOf: checkLineLength(lines: lines, path: path))
        
        if config.detectTrailingWhitespace {
            findings.append(contentsOf: checkTrailingWhitespace(lines: lines, path: path))
        }
        
        if config.detectMultipleBlankLines {
            findings.append(contentsOf: checkMultipleBlankLines(lines: lines, path: path))
        }
        
        if config.detectTrailingNewline {
            findings.append(contentsOf: checkTrailingNewline(content: content, path: path))
        }
        
        // AST-based checks
        let sourceFile = Parser.parse(source: content)
        
        if config.detectImportOrder {
            findings.append(contentsOf: checkImportOrder(sourceFile: sourceFile, path: path, content: content))
        }
        
        if config.detectFileStructure {
            findings.append(contentsOf: checkFileStructure(sourceFile: sourceFile, path: path, content: content))
        }
        
        return findings
    }
    
    // MARK: - Line Length
    
    private func checkLineLength(lines: [String], path: String) -> [Finding] {
        var findings: [Finding] = []
        
        for (index, line) in lines.enumerated() {
            let length = line.count
            if length > config.maxLineLength {
                findings.append(Finding(
                    type: .namingViolation,
                    location: SourceLocation(file: path, line: index + 1),
                    severity: .info,
                    context: [
                        "issue": "lineLength",
                        "length": String(length),
                        "maxLength": String(config.maxLineLength)
                    ],
                    message: "Line exceeds \(config.maxLineLength) characters (\(length) chars)"
                ))
            }
        }
        
        return findings
    }
    
    // MARK: - Trailing Whitespace
    
    private func checkTrailingWhitespace(lines: [String], path: String) -> [Finding] {
        var findings: [Finding] = []
        
        for (index, line) in lines.enumerated() {
            if line.hasSuffix(" ") || line.hasSuffix("\t") {
                findings.append(Finding(
                    type: .namingViolation,
                    location: SourceLocation(file: path, line: index + 1),
                    severity: .info,
                    context: ["issue": "trailingWhitespace"],
                    message: "Line has trailing whitespace"
                ))
            }
        }
        
        return findings
    }
    
    // MARK: - Multiple Blank Lines
    
    private func checkMultipleBlankLines(lines: [String], path: String) -> [Finding] {
        var findings: [Finding] = []
        var consecutiveBlankLines = 0
        
        for (index, line) in lines.enumerated() {
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                consecutiveBlankLines += 1
                if consecutiveBlankLines > 1 {
                    findings.append(Finding(
                        type: .namingViolation,
                        location: SourceLocation(file: path, line: index + 1),
                        severity: .info,
                        context: [
                            "issue": "multipleBlankLines",
                            "count": String(consecutiveBlankLines)
                        ],
                        message: "Multiple consecutive blank lines (\(consecutiveBlankLines))"
                    ))
                }
            } else {
                consecutiveBlankLines = 0
            }
        }
        
        return findings
    }
    
    // MARK: - Trailing Newline
    
    private func checkTrailingNewline(content: String, path: String) -> [Finding] {
        var findings: [Finding] = []
        
        if !content.isEmpty && !content.hasSuffix("\n") {
            let lineCount = content.components(separatedBy: "\n").count
            findings.append(Finding(
                type: .namingViolation,
                location: SourceLocation(file: path, line: lineCount),
                severity: .info,
                context: ["issue": "missingTrailingNewline"],
                message: "File should end with a newline"
            ))
        }
        
        return findings
    }
    
    // MARK: - Import Order
    
    private func checkImportOrder(sourceFile: SourceFileSyntax, path: String, content: String) -> [Finding] {
        var findings: [Finding] = []
        let lines = content.components(separatedBy: "\n")
        
        var imports: [(name: String, line: Int)] = []
        
        for item in sourceFile.statements {
            if let importDecl = item.item.as(ImportDeclSyntax.self) {
                let importName = importDecl.path.description.trimmingCharacters(in: .whitespaces)
                let line = lineNumber(for: importDecl.position, in: lines)
                imports.append((name: importName, line: line))
            }
        }
        
        // Check if imports are sorted
        let sortedImports = imports.sorted { $0.name.lowercased() < $1.name.lowercased() }
        
        for (index, import_) in imports.enumerated() {
            if index < sortedImports.count && import_.name != sortedImports[index].name {
                findings.append(Finding(
                    type: .namingViolation,
                    location: SourceLocation(file: path, line: import_.line),
                    severity: .info,
                    context: [
                        "issue": "importOrder",
                        "import": import_.name,
                        "expected": sortedImports[index].name
                    ],
                    message: "Import '\(import_.name)' is not in alphabetical order (expected '\(sortedImports[index].name)')"
                ))
                break  // Only report first out-of-order import
            }
        }
        
        // Check for blank line after imports
        if let lastImport = imports.last {
            let nextLineIndex = lastImport.line
            if nextLineIndex < lines.count {
                let nextLine = lines[nextLineIndex]
                if !nextLine.trimmingCharacters(in: .whitespaces).isEmpty {
                    findings.append(Finding(
                        type: .namingViolation,
                        location: SourceLocation(file: path, line: lastImport.line),
                        severity: .info,
                        context: ["issue": "missingBlankLineAfterImports"],
                        message: "Missing blank line after imports"
                    ))
                }
            }
        }
        
        return findings
    }
    
    // MARK: - File Structure
    
    private func checkFileStructure(sourceFile: SourceFileSyntax, path: String, content: String) -> [Finding] {
        var findings: [Finding] = []
        let lines = content.components(separatedBy: "\n")
        
        var lastDeclarationType: DeclarationType = .import_
        var lastDeclarationLine = 0
        
        for item in sourceFile.statements {
            let currentType = declarationType(for: Syntax(item.item))
            let currentLine = lineNumber(for: item.position, in: lines)
            
            // Check order: imports -> types -> extensions
            if currentType.order < lastDeclarationType.order {
                findings.append(Finding(
                    type: .namingViolation,
                    location: SourceLocation(file: path, line: currentLine),
                    severity: .info,
                    context: [
                        "issue": "fileStructure",
                        "found": currentType.rawValue,
                        "after": lastDeclarationType.rawValue
                    ],
                    message: "\(currentType.rawValue.capitalized) should come before \(lastDeclarationType.rawValue)"
                ))
            }
            
            lastDeclarationType = currentType
            lastDeclarationLine = currentLine
        }
        
        return findings
    }
    
    // MARK: - Helpers
    
    private enum DeclarationType: String {
        case import_ = "import"
        case typeAlias = "typealias"
        case type = "type"
        case extension_ = "extension"
        case function = "function"
        case variable = "variable"
        case other = "other"
        
        var order: Int {
            switch self {
            case .import_: return 0
            case .typeAlias: return 1
            case .type: return 2
            case .extension_: return 3
            case .function: return 4
            case .variable: return 5
            case .other: return 6
            }
        }
    }
    
    private func declarationType(for syntax: Syntax) -> DeclarationType {
        if syntax.is(ImportDeclSyntax.self) { return .import_ }
        if syntax.is(TypeAliasDeclSyntax.self) { return .typeAlias }
        if syntax.is(ClassDeclSyntax.self) { return .type }
        if syntax.is(StructDeclSyntax.self) { return .type }
        if syntax.is(EnumDeclSyntax.self) { return .type }
        if syntax.is(ProtocolDeclSyntax.self) { return .type }
        if syntax.is(ActorDeclSyntax.self) { return .type }
        if syntax.is(ExtensionDeclSyntax.self) { return .extension_ }
        if syntax.is(FunctionDeclSyntax.self) { return .function }
        if syntax.is(VariableDeclSyntax.self) { return .variable }
        return .other
    }
    
    private func lineNumber(for position: AbsolutePosition, in lines: [String]) -> Int {
        var line = 1
        var currentOffset = 0
        
        for (index, sourceLine) in lines.enumerated() {
            currentOffset += sourceLine.utf8.count + 1
            if currentOffset > position.utf8Offset {
                line = index + 1
                break
            }
        }
        
        return line
    }
}

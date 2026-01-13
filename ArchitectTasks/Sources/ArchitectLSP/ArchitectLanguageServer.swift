import Foundation
import ArchitectHost

// MARK: - Language Server Protocol Implementation
//
// This module provides LSP integration for ArchitectTasks.
// It can be used with any LSP-compatible editor (VS Code, Neovim, etc.)
//
// To use:
// 1. Build: swift build --product architect-lsp
// 2. Configure your editor to use the binary as a language server
//
// Capabilities:
// - textDocument/publishDiagnostics - Shows findings as diagnostics
// - textDocument/codeAction - Suggests fixes based on tasks
// - workspace/executeCommand - Executes approved transforms

/// LSP message types
public enum LSPMessage: Codable {
    case request(LSPRequest)
    case response(LSPResponse)
    case notification(LSPNotification)
}

public struct LSPRequest: Codable {
    public let jsonrpc: String
    public let id: Int
    public let method: String
    public let params: [String: AnyCodable]?
}

public struct LSPResponse: Codable {
    public let jsonrpc: String
    public let id: Int
    public let result: AnyCodable?
    public let error: LSPError?
}

public struct LSPNotification: Codable {
    public let jsonrpc: String
    public let method: String
    public let params: [String: AnyCodable]?
}

public struct LSPError: Codable {
    public let code: Int
    public let message: String
}

/// Type-erased Codable wrapper
public struct AnyCodable: Codable {
    public let value: Any
    
    public init(_ value: Any) {
        self.value = value
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else {
            value = NSNull()
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        
        switch value {
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let bool as Bool:
            try container.encode(bool)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        default:
            try container.encodeNil()
        }
    }
}

/// Main language server class
public final class ArchitectLanguageServer {
    private let host: LocalHost
    private var documentCache: [String: String] = [:]
    private var findingsCache: [String: [Finding]] = [:]
    private var tasksCache: [String: [AgentTask]] = [:]
    
    public init(projectRoot: URL) {
        self.host = LocalHost(
            projectRoot: projectRoot,
            config: .default,
            approvalHandler: { task in
                TaskApprovalResult(task: task, decision: .deferred)
            }
        )
    }
    
    /// Handle incoming LSP request
    public func handle(request: LSPRequest) async -> LSPResponse {
        switch request.method {
        case "initialize":
            return initializeResponse(id: request.id)
            
        case "textDocument/didOpen":
            if let params = request.params,
               let textDocument = params["textDocument"]?.value as? [String: Any],
               let uri = textDocument["uri"] as? String,
               let text = textDocument["text"] as? String {
                documentCache[uri] = text
                await publishDiagnostics(uri: uri, text: text)
            }
            return LSPResponse(jsonrpc: "2.0", id: request.id, result: nil, error: nil)
            
        case "textDocument/didChange":
            if let params = request.params,
               let textDocument = params["textDocument"]?.value as? [String: Any],
               let uri = textDocument["uri"] as? String,
               let changes = params["contentChanges"]?.value as? [[String: Any]],
               let text = changes.first?["text"] as? String {
                documentCache[uri] = text
                await publishDiagnostics(uri: uri, text: text)
            }
            return LSPResponse(jsonrpc: "2.0", id: request.id, result: nil, error: nil)
            
        case "textDocument/codeAction":
            return await codeActionResponse(id: request.id, params: request.params)
            
        case "workspace/executeCommand":
            return await executeCommandResponse(id: request.id, params: request.params)
            
        case "shutdown":
            return LSPResponse(jsonrpc: "2.0", id: request.id, result: nil, error: nil)
            
        default:
            return LSPResponse(
                jsonrpc: "2.0",
                id: request.id,
                result: nil,
                error: LSPError(code: -32601, message: "Method not found: \(request.method)")
            )
        }
    }
    
    private func initializeResponse(id: Int) -> LSPResponse {
        let capabilities: [String: Any] = [
            "textDocumentSync": [
                "openClose": true,
                "change": 1  // Full sync
            ],
            "codeActionProvider": [
                "codeActionKinds": [
                    "quickfix",
                    "refactor",
                    "refactor.extract",
                    "refactor.inline",
                    "source.fixAll"
                ]
            ],
            "executeCommandProvider": [
                "commands": [
                    "architect.applyFix",
                    "architect.addStateObject",
                    "architect.addBinding",
                    "architect.extractFunction",
                    "architect.reduceNesting",
                    "architect.fixAll"
                ]
            ]
        ]
        
        let result: [String: Any] = [
            "capabilities": capabilities,
            "serverInfo": [
                "name": "architect-lsp",
                "version": "0.1.0"
            ]
        ]
        
        return LSPResponse(jsonrpc: "2.0", id: id, result: AnyCodable(result), error: nil)
    }
    
    private func publishDiagnostics(uri: String, text: String) async {
        let path = uri.replacingOccurrences(of: "file://", with: "")
        
        do {
            let findings = try await analyzeFile(path: path, content: text)
            findingsCache[uri] = findings
            
            // Generate tasks from findings
            let tasks = host.proposeTasks(from: findings)
            tasksCache[uri] = tasks
            
            let diagnostics = findings.map { finding -> [String: Any] in
                [
                    "range": [
                        "start": ["line": finding.location.line - 1, "character": 0],
                        "end": ["line": finding.location.line - 1, "character": 1000]
                    ],
                    "severity": severityToLSP(finding.severity),
                    "source": "architect",
                    "message": finding.message,
                    "code": finding.type.rawValue,
                    "data": ["findingId": finding.id.uuidString]
                ]
            }
            
            let notification: [String: Any] = [
                "jsonrpc": "2.0",
                "method": "textDocument/publishDiagnostics",
                "params": [
                    "uri": uri,
                    "diagnostics": diagnostics
                ]
            ]
            
            if let data = try? JSONSerialization.data(withJSONObject: notification),
               let json = String(data: data, encoding: .utf8) {
                print("Content-Length: \(data.count)\r\n\r\n\(json)", terminator: "")
                fflush(stdout)
            }
        } catch {
            // Log error
        }
    }
    
    private func analyzeFile(path: String, content: String) async throws -> [Finding] {
        var allFindings: [Finding] = []
        
        let swiftUIAnalyzer = SwiftUIBindingAnalyzer()
        let complexityAnalyzer = ComplexityAnalyzer()
        let securityAnalyzer = SecurityAnalyzer()
        let namingAnalyzer = NamingAnalyzer()
        let deadCodeAnalyzer = DeadCodeAnalyzer()
        
        allFindings.append(contentsOf: try swiftUIAnalyzer.analyze(fileAt: path, content: content))
        allFindings.append(contentsOf: try complexityAnalyzer.analyze(fileAt: path, content: content))
        allFindings.append(contentsOf: try securityAnalyzer.analyze(fileAt: path, content: content))
        allFindings.append(contentsOf: try namingAnalyzer.analyze(fileAt: path, content: content))
        allFindings.append(contentsOf: try deadCodeAnalyzer.analyze(fileAt: path, content: content))
        
        return allFindings
    }
    
    private func codeActionResponse(id: Int, params: [String: AnyCodable]?) async -> LSPResponse {
        guard let params = params,
              let textDocument = params["textDocument"]?.value as? [String: Any],
              let uri = textDocument["uri"] as? String,
              let range = params["range"]?.value as? [String: Any],
              let start = range["start"] as? [String: Any],
              let line = start["line"] as? Int else {
            return LSPResponse(jsonrpc: "2.0", id: id, result: AnyCodable([]), error: nil)
        }
        
        var actions: [[String: Any]] = []
        
        // Get findings and tasks for this file
        let findings = findingsCache[uri] ?? []
        let tasks = tasksCache[uri] ?? []
        
        // Find findings on or near the current line
        let relevantFindings = findings.filter { abs($0.location.line - 1 - line) <= 1 }
        let relevantTasks = tasks.filter { task in
            task.sourceFindings.contains { findingId in
                relevantFindings.contains { $0.id == findingId }
            }
        }
        
        // Generate code actions for each relevant task
        for task in relevantTasks {
            let action = createCodeAction(for: task, uri: uri)
            actions.append(action)
        }
        
        // Add "Fix All" action if there are multiple issues
        if tasks.count > 1 {
            actions.append([
                "title": "Fix all issues in file (\(tasks.count))",
                "kind": "source.fixAll",
                "command": [
                    "title": "Fix All",
                    "command": "architect.fixAll",
                    "arguments": [uri]
                ]
            ])
        }
        
        return LSPResponse(jsonrpc: "2.0", id: id, result: AnyCodable(actions), error: nil)
    }
    
    private func createCodeAction(for task: AgentTask, uri: String) -> [String: Any] {
        let kind: String
        let command: String
        
        switch task.intent {
        case .addStateObject:
            kind = "quickfix"
            command = "architect.addStateObject"
        case .addBinding:
            kind = "quickfix"
            command = "architect.addBinding"
        case .extractFunction:
            kind = "refactor.extract"
            command = "architect.extractFunction"
        case .reduceNesting:
            kind = "refactor"
            command = "architect.reduceNesting"
        default:
            kind = "quickfix"
            command = "architect.applyFix"
        }
        
        return [
            "title": task.title,
            "kind": kind,
            "diagnostics": [],
            "command": [
                "title": task.title,
                "command": command,
                "arguments": [uri, task.id.uuidString]
            ]
        ]
    }
    
    private func executeCommandResponse(id: Int, params: [String: AnyCodable]?) async -> LSPResponse {
        guard let params = params,
              let command = params["command"]?.value as? String,
              let arguments = params["arguments"]?.value as? [Any],
              let uri = arguments.first as? String else {
            return LSPResponse(jsonrpc: "2.0", id: id, result: nil, error: LSPError(code: -32602, message: "Invalid params"))
        }
        
        let path = uri.replacingOccurrences(of: "file://", with: "")
        
        switch command {
        case "architect.fixAll":
            return await executeFixAll(id: id, uri: uri, path: path)
            
        case "architect.addStateObject", "architect.addBinding", "architect.extractFunction", "architect.reduceNesting", "architect.applyFix":
            guard arguments.count > 1, let taskId = arguments[1] as? String else {
                return LSPResponse(jsonrpc: "2.0", id: id, result: nil, error: LSPError(code: -32602, message: "Missing task ID"))
            }
            return await executeSingleFix(id: id, uri: uri, path: path, taskId: taskId)
            
        default:
            return LSPResponse(jsonrpc: "2.0", id: id, result: nil, error: LSPError(code: -32601, message: "Unknown command"))
        }
    }
    
    private func executeSingleFix(id: Int, uri: String, path: String, taskId: String) async -> LSPResponse {
        guard let source = documentCache[uri],
              let tasks = tasksCache[uri],
              let task = tasks.first(where: { $0.id.uuidString == taskId }) else {
            return LSPResponse(jsonrpc: "2.0", id: id, result: nil, error: LSPError(code: -32602, message: "Task not found"))
        }
        
        // Execute the transform
        let pipeline = TransformPipeline.standard()
        
        do {
            let result = try pipeline.execute(
                intents: [task.intent],
                source: source,
                context: TransformContext(filePath: path)
            )
            
            if result.success {
                // Send workspace edit
                let edit = createWorkspaceEdit(uri: uri, newText: result.transformedSource)
                sendWorkspaceEdit(edit)
                
                return LSPResponse(jsonrpc: "2.0", id: id, result: AnyCodable(["applied": true]), error: nil)
            }
        } catch {
            return LSPResponse(jsonrpc: "2.0", id: id, result: nil, error: LSPError(code: -32603, message: error.localizedDescription))
        }
        
        return LSPResponse(jsonrpc: "2.0", id: id, result: AnyCodable(["applied": false]), error: nil)
    }
    
    private func executeFixAll(id: Int, uri: String, path: String) async -> LSPResponse {
        guard let source = documentCache[uri],
              let tasks = tasksCache[uri] else {
            return LSPResponse(jsonrpc: "2.0", id: id, result: nil, error: LSPError(code: -32602, message: "No tasks found"))
        }
        
        let pipeline = TransformPipeline.standard()
        let intents = tasks.map { $0.intent }
        
        do {
            let result = try pipeline.execute(
                intents: intents,
                source: source,
                context: TransformContext(filePath: path)
            )
            
            if result.success {
                let edit = createWorkspaceEdit(uri: uri, newText: result.transformedSource)
                sendWorkspaceEdit(edit)
                
                return LSPResponse(jsonrpc: "2.0", id: id, result: AnyCodable([
                    "applied": true,
                    "transformsApplied": result.appliedTransforms.count
                ]), error: nil)
            }
        } catch {
            return LSPResponse(jsonrpc: "2.0", id: id, result: nil, error: LSPError(code: -32603, message: error.localizedDescription))
        }
        
        return LSPResponse(jsonrpc: "2.0", id: id, result: AnyCodable(["applied": false]), error: nil)
    }
    
    private func createWorkspaceEdit(uri: String, newText: String) -> [String: Any] {
        [
            "changes": [
                uri: [[
                    "range": [
                        "start": ["line": 0, "character": 0],
                        "end": ["line": 999999, "character": 0]
                    ],
                    "newText": newText
                ]]
            ]
        ]
    }
    
    private func sendWorkspaceEdit(_ edit: [String: Any]) {
        let request: [String: Any] = [
            "jsonrpc": "2.0",
            "id": Int.random(in: 1000...9999),
            "method": "workspace/applyEdit",
            "params": ["edit": edit]
        ]
        
        if let data = try? JSONSerialization.data(withJSONObject: request),
           let json = String(data: data, encoding: .utf8) {
            print("Content-Length: \(data.count)\r\n\r\n\(json)", terminator: "")
            fflush(stdout)
        }
    }
    
    private func severityToLSP(_ severity: Finding.Severity) -> Int {
        switch severity {
        case .critical, .error: return 1
        case .warning: return 2
        case .info: return 3
        }
    }
}

// MARK: - LSP Entry Point

/// Run the language server (reads from stdin, writes to stdout)
func runLanguageServer(projectRoot: URL) async {
    let server = ArchitectLanguageServer(projectRoot: projectRoot)
    
    // Read LSP messages from stdin
    while let line = readLine() {
        // Parse Content-Length header
        if line.hasPrefix("Content-Length:") {
            let length = Int(line.dropFirst(15).trimmingCharacters(in: .whitespaces)) ?? 0
            _ = readLine() // Empty line
            
            // Read content
            var content = ""
            var remaining = length
            while remaining > 0 {
                if let chunk = readLine() {
                    content += chunk
                    remaining -= chunk.utf8.count + 1
                }
            }
            
            // Parse and handle request
            if let data = content.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let id = json["id"] as? Int,
               let method = json["method"] as? String {
                
                let params = json["params"] as? [String: Any]
                let request = LSPRequest(
                    jsonrpc: "2.0",
                    id: id,
                    method: method,
                    params: params?.mapValues { AnyCodable($0) }
                )
                
                let response = await server.handle(request: request)
                
                // Send response
                if let responseData = try? JSONEncoder().encode(response),
                   let responseJson = String(data: responseData, encoding: .utf8) {
                    print("Content-Length: \(responseData.count)\r\n\r\n\(responseJson)", terminator: "")
                    fflush(stdout)
                }
            }
        }
    }
}

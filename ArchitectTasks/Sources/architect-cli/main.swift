import Foundation
import ArchitectHost

// MARK: - CLI Entry Point

@main
struct ArchitectCLI {
    static func main() async {
        let cli = CLI()
        let exitCode = await cli.run()
        exit(exitCode)
    }
}

// MARK: - CLI Implementation

final class CLI: @unchecked Sendable {
    private let args: [String]
    private let output: OutputWriter
    
    init(args: [String] = CommandLine.arguments, output: OutputWriter = ConsoleOutput()) {
        self.args = args
        self.output = output
    }
    
    func run() async -> Int32 {
        output.write("""
        ┌─────────────────────────────────────┐
        │  ArchitectTasks CLI v0.1.0          │
        │  Task-driven code intelligence      │
        └─────────────────────────────────────┘
        
        """)
        
        let command = parseCommand()
        
        switch command {
        case .analyze(let path):
            return await runAnalysis(at: path)
            
        case .run(let options):
            return await runPipeline(options: options)
            
        case .ci(let options):
            return await runCI(options: options)
            
        case .exportPolicy(let name, let outputPath):
            return exportPolicy(name: name, to: outputPath)
            
        case .selfAnalyze:
            return await runSelfAnalysis()
            
        case .help:
            printHelp()
            return 0
            
        case .version:
            output.write("architect-cli 0.1.0\n")
            return 0
        }
    }
    
    // MARK: - Commands
    
    private func runAnalysis(at path: String) async -> Int32 {
        let url = URL(fileURLWithPath: path)
        output.write("Analyzing: \(url.path)\n")
        
        let host = LocalHost(
            projectRoot: url,
            config: .default,
            approvalHandler: { task in
                TaskApprovalResult(task: task, decision: .deferred)
            }
        )
        host.addObserver(CLIObserver(output: output))
        
        do {
            let findings = try await host.analyze()
            let tasks = host.proposeTasks(from: findings)
            
            output.write("\n── Summary ──────────────────────────\n")
            output.write("  Findings: \(findings.count)\n")
            output.write("  Tasks proposed: \(tasks.count)\n")
            
            if !tasks.isEmpty {
                output.write("\n── Proposed Tasks ───────────────────\n")
                for (i, task) in tasks.enumerated() {
                    output.write("  \(i + 1). \(task.title)\n")
                    output.write("     Intent: \(task.intent.category.rawValue)\n")
                    output.write("     Scope: \(task.scope.description)\n")
                    output.write("     Confidence: \(String(format: "%.0f%%", task.confidence * 100))\n")
                    output.write("     Steps: \(task.steps.count)\n\n")
                }
            }
            return 0
        } catch {
            output.write("Error: \(error.localizedDescription)\n")
            return 1
        }
    }
    
    private func runPipeline(options: RunOptions) async -> Int32 {
        let url = URL(fileURLWithPath: options.path)
        output.write("Running pipeline at: \(url.path)\n")
        output.write("Policy: \(options.policyName)\n")
        output.write("Apply changes: \(options.applyChanges ? "yes" : "no (dry run)")\n\n")
        
        let policy = resolvePolicy(options.policyName)
        
        let config = HostConfig(
            autoApproveThreshold: options.autoApprove ? .medium : .none,
            applyChanges: options.applyChanges
        )
        
        let host = LocalHost(
            projectRoot: url,
            config: config,
            policy: policy,
            approvalHandler: { [output] task in
                await self.interactiveApproval(task: task, output: output)
            }
        )
        host.addObserver(CLIObserver(output: output))
        
        do {
            let result = try await host.run()
            
            output.write("\n── Run Complete ─────────────────────\n")
            output.write(result.summary)
            output.write("\n")
            
            if !result.results.isEmpty {
                output.write("\n── Diffs Generated ──────────────────\n")
                for (_, taskResult) in result.results {
                    if !taskResult.combinedDiff.isEmpty {
                        output.write(taskResult.combinedDiff)
                        output.write("\n")
                    }
                }
            }
            
            return 0
        } catch {
            output.write("Error: \(error.localizedDescription)\n")
            return 1
        }
    }
    
    /// CI mode: analyze + plan only, no execution
    /// Exit 0 if clean, 1 if tasks would be generated
    private func runCI(options: CIOptions) async -> Int32 {
        let url = URL(fileURLWithPath: options.path)
        output.write("CI Mode: \(url.path)\n")
        output.write("Policy: \(options.policyName)\n\n")
        
        let policy = resolvePolicy(options.policyName)
        
        let host = LocalHost(
            projectRoot: url,
            config: .ci,
            policy: policy,
            approvalHandler: { task in
                // CI never approves
                TaskApprovalResult(task: task, decision: .deferred)
            }
        )
        host.addObserver(CLIObserver(output: output))
        
        do {
            let findings = try await host.analyze()
            let tasks = host.proposeTasks(from: findings)
            
            // Apply policy to filter tasks
            var actionableTasks: [AgentTask] = []
            for task in tasks {
                if let policy = policy {
                    let decision = policy.evaluate(task)
                    if decision != .deny {
                        actionableTasks.append(task)
                    }
                } else {
                    actionableTasks.append(task)
                }
            }
            
            output.write("\n── CI Report ────────────────────────\n")
            output.write("  Findings: \(findings.count)\n")
            output.write("  Tasks proposed: \(tasks.count)\n")
            output.write("  Actionable tasks: \(actionableTasks.count)\n")
            
            if !actionableTasks.isEmpty {
                output.write("\n── Issues Found ─────────────────────\n")
                for (i, task) in actionableTasks.enumerated() {
                    output.write("  \(i + 1). \(task.title)\n")
                    output.write("     Category: \(task.intent.category.rawValue)\n")
                    output.write("     File: \(scopeFile(task.scope))\n")
                }
                
                output.write("\n✗ CI failed: \(actionableTasks.count) issue(s) found\n")
                output.write("  Run 'architect-cli run \(options.path)' to fix\n")
                return 1
            }
            
            output.write("\n✓ CI passed: no issues found\n")
            return 0
            
        } catch {
            output.write("Error: \(error.localizedDescription)\n")
            return 1
        }
    }
    
    private func runSelfAnalysis() async -> Int32 {
        output.write("🔄 Self-analysis mode\n\n")
        let currentPath = FileManager.default.currentDirectoryPath
        return await runAnalysis(at: currentPath)
    }
    
    private func exportPolicy(name: String, to outputPath: String?) -> Int32 {
        do {
            let policy = try ApprovalPolicy.resolve(name)
            let json = try policy.toJSON()
            
            if let path = outputPath {
                try json.write(to: URL(fileURLWithPath: path))
                output.write("Policy '\(name)' exported to: \(path)\n")
            } else {
                output.write(String(data: json, encoding: .utf8) ?? "")
                output.write("\n")
            }
            return 0
        } catch {
            output.write("Error: \(error.localizedDescription)\n")
            return 1
        }
    }
    
    private func interactiveApproval(task: AgentTask, output: OutputWriter) async -> TaskApprovalResult {
        output.write("\n── Task Approval Required ───────────\n")
        output.write("  Title: \(task.title)\n")
        output.write("  Intent: \(task.intent.description)\n")
        output.write("  Scope: \(task.scope.description)\n")
        output.write("  Confidence: \(String(format: "%.0f%%", task.confidence * 100))\n")
        output.write("  Steps:\n")
        for (i, step) in task.steps.enumerated() {
            output.write("    \(i + 1). \(step.description)\n")
        }
        output.write("\n  [A]pprove / [R]eject / [S]kip? ")
        
        guard let input = readLine()?.lowercased() else {
            return TaskApprovalResult(task: task, decision: .deferred)
        }
        
        var mutableTask = task
        
        switch input {
        case "a", "approve", "y", "yes":
            mutableTask.approve()
            return TaskApprovalResult(task: mutableTask, decision: .approved)
        case "r", "reject", "n", "no":
            output.write("  Reason (optional): ")
            let reason = readLine()
            mutableTask.reject(reason: reason ?? "User rejected")
            return TaskApprovalResult(task: mutableTask, decision: .rejected, reason: reason)
        default:
            return TaskApprovalResult(task: task, decision: .deferred)
        }
    }
    
    private func printHelp() {
        output.write("""
        Usage: architect-cli <command> [options]
        
        Commands:
          analyze <path>          Analyze a project and show findings/tasks
          run <path>              Run full pipeline (analyze → approve → execute)
          ci <path>               CI mode: analyze only, exit 1 if issues found
          export-policy <name>    Export a policy to JSON
          self                    Analyze this package itself
          help                    Show this help message
          version                 Show version
        
        Run Options:
          --policy <name|path>    Use policy: conservative, moderate, permissive, ci, strict
                                  Or path to custom policy JSON file
          --auto-approve          Auto-approve based on policy (default: interactive)
          --apply                 Apply changes (default: dry run)
        
        CI Options:
          --policy <name|path>    Use policy for filtering (default: moderate)
        
        Policies:
          conservative    Only auto-approve documentation tasks
          moderate        Auto-approve high-confidence, single-file changes
          permissive      Auto-approve most changes, deny architecture
          ci              Report only, never auto-approve
          strict          Require human approval for everything
        
        Examples:
          # Analyze a project
          architect-cli analyze .
          
          # Run with interactive approval
          architect-cli run .
          
          # Run with policy-based auto-approval
          architect-cli run . --policy moderate --auto-approve
          
          # Run with custom policy
          architect-cli run . --policy ./team-policy.json
          
          # CI integration (fails if issues found)
          architect-cli ci .
          architect-cli ci . --policy strict
          
          # Export policy to customize
          architect-cli export-policy moderate > my-policy.json
          
          # Self-analysis
          architect-cli self
        
        Exit Codes:
          0    Success (or no issues in CI mode)
          1    Error or issues found (CI mode)
        
        """)
    }
    
    // MARK: - Helpers
    
    private func resolvePolicy(_ nameOrPath: String) -> ApprovalPolicy? {
        guard nameOrPath != "none" else { return nil }
        return try? ApprovalPolicy.resolve(nameOrPath)
    }
    
    private func scopeFile(_ scope: TaskScope) -> String {
        switch scope {
        case .file(let path): return path
        case .module(let name): return "module: \(name)"
        case .feature(let name): return "feature: \(name)"
        case .project: return "project-wide"
        }
    }
    
    // MARK: - Argument Parsing
    
    private enum Command {
        case analyze(path: String)
        case run(RunOptions)
        case ci(CIOptions)
        case exportPolicy(name: String, output: String?)
        case selfAnalyze
        case help
        case version
    }
    
    private struct RunOptions {
        var path: String
        var policyName: String
        var autoApprove: Bool
        var applyChanges: Bool
    }
    
    private struct CIOptions {
        var path: String
        var policyName: String
    }
    
    private func parseCommand() -> Command {
        guard args.count > 1 else {
            return .help
        }
        
        let command = args[1].lowercased()
        
        switch command {
        case "analyze":
            let path = args.count > 2 ? args[2] : "."
            return .analyze(path: path)
            
        case "run":
            let path = args.count > 2 && !args[2].hasPrefix("-") ? args[2] : "."
            let policyName = parseOption("--policy") ?? "none"
            let autoApprove = args.contains("--auto-approve")
            let applyChanges = args.contains("--apply")
            return .run(RunOptions(
                path: path,
                policyName: policyName,
                autoApprove: autoApprove,
                applyChanges: applyChanges
            ))
            
        case "ci":
            let path = args.count > 2 && !args[2].hasPrefix("-") ? args[2] : "."
            let policyName = parseOption("--policy") ?? "moderate"
            return .ci(CIOptions(path: path, policyName: policyName))
            
        case "export-policy":
            let name = args.count > 2 ? args[2] : "moderate"
            let output = parseOption("-o") ?? parseOption("--output")
            return .exportPolicy(name: name, output: output)
            
        case "self":
            return .selfAnalyze
            
        case "help", "-h", "--help":
            return .help
            
        case "version", "-v", "--version":
            return .version
            
        default:
            return .help
        }
    }
    
    private func parseOption(_ flag: String) -> String? {
        guard let idx = args.firstIndex(of: flag), idx + 1 < args.count else {
            return nil
        }
        return args[idx + 1]
    }
}

// MARK: - Output Protocol

protocol OutputWriter: Sendable {
    func write(_ text: String)
}

final class ConsoleOutput: OutputWriter, @unchecked Sendable {
    func write(_ text: String) {
        print(text, terminator: "")
    }
}

// MARK: - CLI Event Observer

final class CLIObserver: HostEventObserver, @unchecked Sendable {
    private let output: OutputWriter
    
    init(output: OutputWriter) {
        self.output = output
    }
    
    func handle(event: HostEvent) async {
        switch event {
        case .analysisStarted(let path):
            output.write("📂 Scanning: \(path)\n")
            
        case .analysisCompleted(let count):
            output.write("✓ Found \(count) finding(s)\n")
            
        case .taskProposed(let task):
            output.write("📋 Task: \(task.title)\n")
            
        case .taskApproved(let task):
            output.write("✓ Approved: \(task.title)\n")
            
        case .taskRejected(let task, let reason):
            output.write("✗ Rejected: \(task.title)")
            if let reason = reason {
                output.write(" (\(reason))")
            }
            output.write("\n")
            
        case .taskExecutionStarted(let task):
            output.write("⚙ Executing: \(task.title)\n")
            
        case .taskExecutionCompleted(let task, let result):
            let status = result.success ? "✓" : "✗"
            output.write("\(status) Completed: \(task.title)\n")
            
        case .taskExecutionFailed(let task, let error):
            output.write("✗ Failed: \(task.title) - \(error.localizedDescription)\n")
            
        case .runCompleted(let processed, let succeeded):
            output.write("── Done: \(succeeded)/\(processed) tasks succeeded ──\n")
        }
    }
}

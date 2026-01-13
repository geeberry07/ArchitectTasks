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
        case .analyze(let path, let json):
            return await runAnalysis(at: path, jsonOutput: json)
            
        case .run(let options):
            return await runPipeline(options: options)
            
        case .ci(let options):
            return await runCI(options: options)
            
        case .watch(let options):
            return await runWatch(options: options)
            
        case .batch(let options):
            return await runBatch(options: options)
            
        case .exportPolicy(let name, let outputPath):
            return exportPolicy(name: name, to: outputPath)
            
        case .exportRuleset(let name, let outputPath):
            return exportRuleset(name: name, to: outputPath)
            
        case .interactive(let path):
            return await runInteractive(at: path)
            
        case .report(let options):
            return await generateReport(options: options)
            
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
    
    private func runAnalysis(at path: String, jsonOutput: Bool = false) async -> Int32 {
        let url = URL(fileURLWithPath: path)
        
        if !jsonOutput {
            output.write("Analyzing: \(url.path)\n")
        }
        
        let host = LocalHost(
            projectRoot: url,
            config: .default,
            approvalHandler: { task in
                TaskApprovalResult(task: task, decision: .deferred)
            }
        )
        
        if !jsonOutput {
            host.addObserver(CLIObserver(output: output))
        }
        
        do {
            let findings = try await host.analyze()
            let tasks = host.proposeTasks(from: findings)
            
            if jsonOutput {
                // Output JSON report
                let report = AnalysisReport(
                    timestamp: Date(),
                    projectPath: url.path,
                    findings: findings,
                    tasks: tasks,
                    summary: AnalysisReport.ReportSummary(
                        totalFindings: findings.count,
                        totalTasks: tasks.count,
                        findingsByType: Dictionary(grouping: findings, by: { $0.type.rawValue })
                            .mapValues { $0.count },
                        tasksByCategory: Dictionary(grouping: tasks, by: { $0.intent.category.rawValue })
                            .mapValues { $0.count }
                    )
                )
                
                let json = try JSONExporter.exportReport(report)
                output.write(String(data: json, encoding: .utf8) ?? "{}")
                output.write("\n")
            } else {
                output.write("\n── Summary ──────────────────────────\n")
                output.write("  Findings: \(String(findings.count).colored(.cyan, bold: true))\n")
                output.write("  Tasks proposed: \(String(tasks.count).colored(.cyan, bold: true))\n")
                
                if !tasks.isEmpty {
                    output.write("\n── Proposed Tasks ───────────────────\n")
                    for (i, task) in tasks.enumerated() {
                        let categoryColor: ANSIColor = {
                            switch task.intent.category {
                            case .quality: return .green
                            case .dataFlow: return .blue
                            case .structural: return .magenta
                            case .architecture: return .red
                            case .documentation: return .cyan
                            }
                        }()
                        
                        output.write("  \(i + 1). \(task.title.colored(.white, bold: true))\n")
                        output.write("     Intent: \(task.intent.category.rawValue.colored(categoryColor))\n")
                        output.write("     Scope: \(task.scope.description)\n")
                        output.write("     Confidence: \(String(format: "%.0f%%", task.confidence * 100))\n")
                        output.write("     Steps: \(task.steps.count)\n\n")
                    }
                }
            }
            return 0
        } catch {
            if jsonOutput {
                output.write("{\"error\": \"\(error.localizedDescription)\"}\n")
            } else {
                output.write("Error: \(error.localizedDescription.colored(.red))\n")
            }
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
    
    private func runWatch(options: WatchOptions) async -> Int32 {
        let url = URL(fileURLWithPath: options.path)
        output.write("👁 Watch mode: \(url.path)\n".colored(.cyan, bold: true))
        output.write("   Policy: \(options.policyName)\n")
        output.write("   Debounce: \(options.debounceSeconds)s\n")
        output.write("   Press Ctrl+C to stop\n\n")
        
        _ = resolvePolicy(options.policyName)  // Validate policy exists
        
        // Initial analysis
        output.write("── Initial Analysis ─────────────────\n")
        _ = await runAnalysis(at: options.path)
        
        // Setup file watcher
        let watcher = DirectoryWatcher(
            directory: url,
            extensions: ["swift"],
            debounceSeconds: options.debounceSeconds
        ) { [weak self] changedFiles in
            guard let self = self else { return }
            
            Task {
                self.output.write("\n── File Changed ─────────────────────\n")
                for file in changedFiles.prefix(5) {
                    self.output.write("   \(file.lastPathComponent)\n")
                }
                if changedFiles.count > 5 {
                    self.output.write("   ... and \(changedFiles.count - 5) more\n")
                }
                self.output.write("\n")
                
                _ = await self.runAnalysis(at: options.path)
            }
        }
        
        watcher.start()
        
        // Keep running until interrupted
        let semaphore = DispatchSemaphore(value: 0)
        
        signal(SIGINT) { _ in
            print("\n\n👋 Watch mode stopped")
            exit(0)
        }
        
        semaphore.wait()
        return 0
    }
    
    private func runBatch(options: BatchOptions) async -> Int32 {
        output.write("📦 Batch mode: \(options.paths.count) project(s)\n".colored(.cyan, bold: true))
        output.write("   Policy: \(options.policyName)\n")
        output.write("   Parallel: \(options.parallel ? "yes" : "no")\n\n")
        
        var allFindings: [String: [Finding]] = [:]
        var allTasks: [String: [AgentTask]] = [:]
        var totalFindings = 0
        var totalTasks = 0
        var failedProjects: [String] = []
        
        if options.parallel {
            // Parallel execution
            await withTaskGroup(of: (String, [Finding], [AgentTask], Error?).self) { group in
                for path in options.paths {
                    group.addTask {
                        await self.analyzeProject(at: path, policy: options.policyName)
                    }
                }
                
                for await (path, findings, tasks, error) in group {
                    if error != nil {
                        failedProjects.append(path)
                    } else {
                        allFindings[path] = findings
                        allTasks[path] = tasks
                        totalFindings += findings.count
                        totalTasks += tasks.count
                    }
                }
            }
        } else {
            // Sequential execution
            for path in options.paths {
                output.write("\n── Analyzing: \(path) ──\n")
                let (_, findings, tasks, error) = await analyzeProject(at: path, policy: options.policyName)
                
                if error != nil {
                    failedProjects.append(path)
                    output.write("   \("✗".colored(.red)) Failed\n")
                } else {
                    allFindings[path] = findings
                    allTasks[path] = tasks
                    totalFindings += findings.count
                    totalTasks += tasks.count
                    output.write("   \("✓".colored(.green)) \(findings.count) findings, \(tasks.count) tasks\n")
                }
            }
        }
        
        // Output results
        if options.jsonOutput {
            let report = BatchReport(
                timestamp: Date(),
                projects: options.paths.map { path in
                    BatchReport.ProjectReport(
                        path: path,
                        findings: allFindings[path] ?? [],
                        tasks: allTasks[path] ?? [],
                        failed: failedProjects.contains(path)
                    )
                },
                summary: BatchReport.Summary(
                    totalProjects: options.paths.count,
                    successfulProjects: options.paths.count - failedProjects.count,
                    totalFindings: totalFindings,
                    totalTasks: totalTasks
                )
            )
            
            if let data = try? JSONEncoder().encode(report),
               let json = String(data: data, encoding: .utf8) {
                output.write(json)
                output.write("\n")
            }
        } else {
            output.write("\n── Batch Summary ────────────────────\n")
            output.write("  Projects: \(String(options.paths.count).colored(.cyan, bold: true))\n")
            output.write("  Successful: \(String(options.paths.count - failedProjects.count).colored(.green, bold: true))\n")
            output.write("  Failed: \(String(failedProjects.count).colored(failedProjects.isEmpty ? .green : .red, bold: true))\n")
            output.write("  Total findings: \(String(totalFindings).colored(.cyan, bold: true))\n")
            output.write("  Total tasks: \(String(totalTasks).colored(.cyan, bold: true))\n")
            
            if !failedProjects.isEmpty {
                output.write("\n  Failed projects:\n")
                for path in failedProjects {
                    output.write("    - \(path)\n")
                }
            }
            
            // Show top issues across all projects
            let allFindingsList = allFindings.values.flatMap { $0 }
            let findingsByType = Dictionary(grouping: allFindingsList, by: { $0.type.rawValue })
            let sortedTypes = findingsByType.sorted { $0.value.count > $1.value.count }
            
            if !sortedTypes.isEmpty {
                output.write("\n  Top issues:\n")
                for (type, findings) in sortedTypes.prefix(5) {
                    output.write("    \(type): \(findings.count)\n")
                }
            }
        }
        
        return failedProjects.isEmpty ? 0 : 1
    }
    
    private func analyzeProject(at path: String, policy: String) async -> (String, [Finding], [AgentTask], Error?) {
        let url = URL(fileURLWithPath: path)
        
        let host = LocalHost(
            projectRoot: url,
            config: .default,
            approvalHandler: { task in
                TaskApprovalResult(task: task, decision: .deferred)
            }
        )
        
        do {
            let findings = try await host.analyze()
            let tasks = host.proposeTasks(from: findings)
            return (path, findings, tasks, nil)
        } catch {
            return (path, [], [], error)
        }
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
    
    private func exportRuleset(name: String, to outputPath: String?) -> Int32 {
        do {
            let config = try RuleConfiguration.resolve(name)
            let json = try config.toJSON()
            
            if let path = outputPath {
                try json.write(to: URL(fileURLWithPath: path))
                output.write("Ruleset '\(name)' exported to: \(path)\n")
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
    
    private func runInteractive(at path: String) async -> Int32 {
        let url = URL(fileURLWithPath: path)
        let session = InteractiveSession(projectRoot: url, output: output)
        return await session.run()
    }
    
    private func generateReport(options: ReportOptions) async -> Int32 {
        let url = URL(fileURLWithPath: options.path)
        output.write("Generating \(options.format.rawValue.uppercased()) report for: \(url.path)\n")
        
        let host = LocalHost(
            projectRoot: url,
            config: .default,
            approvalHandler: { task in
                TaskApprovalResult(task: task, decision: .deferred)
            }
        )
        
        do {
            let findings = try await host.analyze()
            let tasks = host.proposeTasks(from: findings)
            
            let content: String
            let defaultExtension: String
            
            switch options.format {
            case .html:
                content = ReportExporter.generateHTML(
                    projectPath: url.path,
                    findings: findings,
                    tasks: tasks
                )
                defaultExtension = "html"
                
            case .markdown:
                content = ReportExporter.generateMarkdown(
                    projectPath: url.path,
                    findings: findings,
                    tasks: tasks
                )
                defaultExtension = "md"
                
            case .json:
                let report = AnalysisReport(
                    timestamp: Date(),
                    projectPath: url.path,
                    findings: findings,
                    tasks: tasks,
                    summary: AnalysisReport.ReportSummary(
                        totalFindings: findings.count,
                        totalTasks: tasks.count,
                        findingsByType: Dictionary(grouping: findings, by: { $0.type.rawValue })
                            .mapValues { $0.count },
                        tasksByCategory: Dictionary(grouping: tasks, by: { $0.intent.category.rawValue })
                            .mapValues { $0.count }
                    )
                )
                let data = try JSONExporter.exportReport(report)
                content = String(data: data, encoding: .utf8) ?? "{}"
                defaultExtension = "json"
            }
            
            if let outputPath = options.outputPath {
                let outputURL = URL(fileURLWithPath: outputPath)
                try content.write(to: outputURL, atomically: true, encoding: .utf8)
                output.write("\("✓".colored(.green)) Report saved to: \(outputPath)\n")
            } else {
                // Default output path
                let defaultPath = "architect-report.\(defaultExtension)"
                try content.write(toFile: defaultPath, atomically: true, encoding: .utf8)
                output.write("\("✓".colored(.green)) Report saved to: \(defaultPath)\n")
            }
            
            output.write("  Findings: \(findings.count)\n")
            output.write("  Tasks: \(tasks.count)\n")
            
            return 0
        } catch {
            output.write("\("✗".colored(.red)) Error: \(error.localizedDescription)\n")
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
          watch <path>            Watch mode: re-analyze on file changes
          batch <paths...>        Analyze multiple projects at once
          interactive <path>      Interactive mode: review/apply transforms one-by-one
          report <path>           Generate HTML/Markdown/JSON report
          export-policy <name>    Export a policy to JSON
          export-ruleset <name>   Export a ruleset configuration to JSON
          self                    Analyze this package itself
          help                    Show this help message
          version                 Show version
        
        Global Options:
          --json                  Output results as JSON
        
        Run Options:
          --policy <name|path>    Use policy: conservative, moderate, permissive, ci, strict
                                  Or path to custom policy JSON file
          --auto-approve          Auto-approve based on policy (default: interactive)
          --apply                 Apply changes (default: dry run)
        
        CI Options:
          --policy <name|path>    Use policy for filtering (default: moderate)
        
        Watch Options:
          --policy <name|path>    Use policy for filtering (default: moderate)
          --debounce <seconds>    Wait time before re-analyzing (default: 1.0)
        
        Batch Options:
          --policy <name|path>    Use policy for filtering (default: moderate)
          --parallel              Analyze projects in parallel
          --json                  Output aggregated JSON report
        
        Report Options:
          --format <type>         Output format: html (default), markdown, json
          -o, --output <path>     Output file path (default: architect-report.<ext>)
        
        Policies:
          conservative    Only auto-approve documentation tasks
          moderate        Auto-approve high-confidence, single-file changes
          permissive      Auto-approve most changes, deny architecture
          ci              Report only, never auto-approve
          strict          Require human approval for everything
        
        Rulesets:
          default         Balanced settings for most projects
          strict          All rules at higher severity
          lenient         Relaxed settings for rapid development
          security        Security-focused rules only
          swiftui         Optimized for SwiftUI projects
          ci              Configuration for CI/CD pipelines
        
        Examples:
          # Analyze a project
          architect-cli analyze .
          
          # Analyze with JSON output
          architect-cli analyze . --json
          
          # Run with interactive approval
          architect-cli run .
          
          # Run with policy-based auto-approval
          architect-cli run . --policy moderate --auto-approve
          
          # Interactive mode (review transforms one-by-one)
          architect-cli interactive .
          architect-cli i .
          
          # Generate reports
          architect-cli report . --format html
          architect-cli report . --format markdown -o report.md
          architect-cli report . --format json -o analysis.json
          # CI integration (fails if issues found)
          architect-cli ci .
          architect-cli ci . --policy strict
          
          # Watch mode (re-analyze on save)
          architect-cli watch .
          architect-cli watch . --debounce 2.0
          
          # Batch mode (multiple projects)
          architect-cli batch ./ProjectA ./ProjectB ./ProjectC
          architect-cli batch ~/Code/* --parallel --json
          
          # Export policy to customize
          architect-cli export-policy moderate > my-policy.json
          
          # Self-analysis
          architect-cli self
        
        Exit Codes:
          0    Success (or no issues in CI/batch mode)
          1    Error or issues found
        
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
        case analyze(path: String, json: Bool)
        case run(RunOptions)
        case ci(CIOptions)
        case watch(WatchOptions)
        case batch(BatchOptions)
        case interactive(path: String)
        case report(ReportOptions)
        case exportPolicy(name: String, output: String?)
        case exportRuleset(name: String, output: String?)
        case selfAnalyze
        case help
        case version
    }
    
    private struct ReportOptions {
        var path: String
        var format: ReportFormat
        var outputPath: String?
    }
    
    private enum ReportFormat: String {
        case html
        case markdown
        case json
    }
    
    private struct RunOptions {
        var path: String
        var policyName: String
        var autoApprove: Bool
        var applyChanges: Bool
        var jsonOutput: Bool
    }
    
    private struct CIOptions {
        var path: String
        var policyName: String
        var jsonOutput: Bool
    }
    
    private struct WatchOptions {
        var path: String
        var policyName: String
        var debounceSeconds: Double
    }
    
    private struct BatchOptions {
        var paths: [String]
        var policyName: String
        var jsonOutput: Bool
        var parallel: Bool
    }
    
    private func parseCommand() -> Command {
        guard args.count > 1 else {
            return .help
        }
        
        let command = args[1].lowercased()
        let jsonOutput = args.contains("--json")
        
        switch command {
        case "analyze":
            let path = args.count > 2 && !args[2].hasPrefix("-") ? args[2] : "."
            return .analyze(path: path, json: jsonOutput)
            
        case "run":
            let path = args.count > 2 && !args[2].hasPrefix("-") ? args[2] : "."
            let policyName = parseOption("--policy") ?? "none"
            let autoApprove = args.contains("--auto-approve")
            let applyChanges = args.contains("--apply")
            return .run(RunOptions(
                path: path,
                policyName: policyName,
                autoApprove: autoApprove,
                applyChanges: applyChanges,
                jsonOutput: jsonOutput
            ))
            
        case "ci":
            let path = args.count > 2 && !args[2].hasPrefix("-") ? args[2] : "."
            let policyName = parseOption("--policy") ?? "moderate"
            return .ci(CIOptions(path: path, policyName: policyName, jsonOutput: jsonOutput))
            
        case "watch":
            let path = args.count > 2 && !args[2].hasPrefix("-") ? args[2] : "."
            let policyName = parseOption("--policy") ?? "moderate"
            let debounce = Double(parseOption("--debounce") ?? "1.0") ?? 1.0
            return .watch(WatchOptions(path: path, policyName: policyName, debounceSeconds: debounce))
            
        case "batch":
            // Collect all non-flag arguments as paths
            var paths: [String] = []
            for i in 2..<args.count {
                if !args[i].hasPrefix("-") {
                    paths.append(args[i])
                }
            }
            if paths.isEmpty { paths = ["."] }
            let policyName = parseOption("--policy") ?? "moderate"
            let parallel = args.contains("--parallel")
            return .batch(BatchOptions(
                paths: paths,
                policyName: policyName,
                jsonOutput: jsonOutput,
                parallel: parallel
            ))
            
        case "export-policy":
            let name = args.count > 2 ? args[2] : "moderate"
            let output = parseOption("-o") ?? parseOption("--output")
            return .exportPolicy(name: name, output: output)
            
        case "export-ruleset":
            let name = args.count > 2 ? args[2] : "default"
            let output = parseOption("-o") ?? parseOption("--output")
            return .exportRuleset(name: name, output: output)
            
        case "interactive", "i":
            let path = args.count > 2 && !args[2].hasPrefix("-") ? args[2] : "."
            return .interactive(path: path)
            
        case "report":
            let path = args.count > 2 && !args[2].hasPrefix("-") ? args[2] : "."
            let formatStr = parseOption("--format") ?? "html"
            let format: ReportFormat
            switch formatStr.lowercased() {
            case "html": format = .html
            case "markdown", "md": format = .markdown
            case "json": format = .json
            default: format = .html
            }
            let outputPath = parseOption("-o") ?? parseOption("--output")
            return .report(ReportOptions(path: path, format: format, outputPath: outputPath))
            
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
    private let useColors: Bool
    
    init(useColors: Bool = true) {
        // Check if stdout is a terminal
        self.useColors = useColors && isatty(STDOUT_FILENO) != 0
    }
    
    func write(_ text: String) {
        print(text, terminator: "")
    }
}

// MARK: - ANSI Colors

enum ANSIColor: String {
    case reset = "\u{001B}[0m"
    case bold = "\u{001B}[1m"
    case dim = "\u{001B}[2m"
    
    case red = "\u{001B}[31m"
    case green = "\u{001B}[32m"
    case yellow = "\u{001B}[33m"
    case blue = "\u{001B}[34m"
    case magenta = "\u{001B}[35m"
    case cyan = "\u{001B}[36m"
    case white = "\u{001B}[37m"
    
    case bgRed = "\u{001B}[41m"
    case bgGreen = "\u{001B}[42m"
    case bgYellow = "\u{001B}[43m"
    case bgBlue = "\u{001B}[44m"
}

extension String {
    func colored(_ color: ANSIColor, bold: Bool = false) -> String {
        let boldCode = bold ? ANSIColor.bold.rawValue : ""
        return "\(boldCode)\(color.rawValue)\(self)\(ANSIColor.reset.rawValue)"
    }
}

// MARK: - JSON Export

struct JSONExporter {
    static func exportFindings(_ findings: [Finding]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(findings)
    }
    
    static func exportTasks(_ tasks: [AgentTask]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(tasks)
    }
    
    static func exportReport(_ report: AnalysisReport) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(report)
    }
}

struct AnalysisReport: Codable {
    let timestamp: Date
    let projectPath: String
    let findings: [Finding]
    let tasks: [AgentTask]
    let summary: ReportSummary
    
    struct ReportSummary: Codable {
        let totalFindings: Int
        let totalTasks: Int
        let findingsByType: [String: Int]
        let tasksByCategory: [String: Int]
    }
}

struct BatchReport: Codable {
    let timestamp: Date
    let projects: [ProjectReport]
    let summary: Summary
    
    struct ProjectReport: Codable {
        let path: String
        let findings: [Finding]
        let tasks: [AgentTask]
        let failed: Bool
    }
    
    struct Summary: Codable {
        let totalProjects: Int
        let successfulProjects: Int
        let totalFindings: Int
        let totalTasks: Int
    }
}

// MARK: - CLI Event Observer

final class CLIObserver: HostEventObserver, @unchecked Sendable {
    private let output: OutputWriter
    private let useColors: Bool
    
    init(output: OutputWriter, useColors: Bool = true) {
        self.output = output
        self.useColors = useColors && isatty(STDOUT_FILENO) != 0
    }
    
    func handle(event: HostEvent) async {
        switch event {
        case .analysisStarted(let path):
            output.write("\("📂".colored(.blue)) Scanning: \(path)\n")
            
        case .analysisCompleted(let count):
            output.write("\("✓".colored(.green)) Found \(count) finding(s)\n")
            
        case .taskProposed(let task):
            output.write("\("📋".colored(.cyan)) Task: \(task.title)\n")
            
        case .taskApproved(let task):
            output.write("\("✓".colored(.green, bold: true)) Approved: \(task.title)\n")
            
        case .taskRejected(let task, let reason):
            output.write("\("✗".colored(.red)) Rejected: \(task.title)")
            if let reason = reason {
                output.write(" (\(reason.colored(.dim)))")
            }
            output.write("\n")
            
        case .taskExecutionStarted(let task):
            output.write("\("⚙".colored(.yellow)) Executing: \(task.title)\n")
            
        case .taskExecutionCompleted(let task, let result):
            let status = result.success ? "✓".colored(.green, bold: true) : "✗".colored(.red, bold: true)
            output.write("\(status) Completed: \(task.title)\n")
            
        case .taskExecutionFailed(let task, let error):
            output.write("\("✗".colored(.red, bold: true)) Failed: \(task.title) - \(error.localizedDescription.colored(.red))\n")
            
        case .runCompleted(let processed, let succeeded):
            let color: ANSIColor = succeeded == processed ? .green : .yellow
            output.write("── Done: \(String(succeeded).colored(color, bold: true))/\(processed) tasks succeeded ──\n")
        }
    }
}

// MARK: - Directory Watcher

final class DirectoryWatcher {
    private let directory: URL
    private let extensions: Set<String>
    private let debounceSeconds: Double
    private let onChange: ([URL]) -> Void
    
    private var source: DispatchSourceFileSystemObject?
    private var lastEventTime: Date = .distantPast
    private var pendingFiles: Set<URL> = []
    private let queue = DispatchQueue(label: "architect.watcher")
    
    init(
        directory: URL,
        extensions: [String],
        debounceSeconds: Double,
        onChange: @escaping ([URL]) -> Void
    ) {
        self.directory = directory
        self.extensions = Set(extensions)
        self.debounceSeconds = debounceSeconds
        self.onChange = onChange
    }
    
    func start() {
        // Use FSEvents for directory monitoring
        let fd = open(directory.path, O_EVTONLY)
        guard fd >= 0 else {
            print("Failed to open directory for watching: \(directory.path)")
            return
        }
        
        source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .rename, .delete],
            queue: queue
        )
        
        source?.setEventHandler { [weak self] in
            self?.handleEvent()
        }
        
        source?.setCancelHandler {
            close(fd)
        }
        
        source?.resume()
    }
    
    func stop() {
        source?.cancel()
        source = nil
    }
    
    private func handleEvent() {
        // Debounce: wait for activity to settle
        queue.asyncAfter(deadline: .now() + debounceSeconds) { [weak self] in
            guard let self = self else { return }
            
            // Find changed Swift files
            let changedFiles = self.findSwiftFiles(in: self.directory)
            
            if !changedFiles.isEmpty {
                DispatchQueue.main.async {
                    self.onChange(changedFiles)
                }
            }
        }
    }
    
    private func findSwiftFiles(in directory: URL) -> [URL] {
        let fm = FileManager.default
        var files: [URL] = []
        
        guard let enumerator = fm.enumerator(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }
        
        for case let fileURL as URL in enumerator {
            guard extensions.contains(fileURL.pathExtension) else { continue }
            
            // Skip build directories
            if fileURL.path.contains(".build") || fileURL.path.contains("DerivedData") {
                continue
            }
            
            files.append(fileURL)
        }
        
        return files
    }
    
    deinit {
        stop()
    }
}

import Foundation
import ArchitectHost

// MARK: - Interactive Mode

/// Interactive CLI mode for reviewing and applying transforms one-by-one
/// with undo/redo capability and live preview.
final class InteractiveSession: @unchecked Sendable {
    
    private let projectRoot: URL
    private let output: OutputWriter
    private let host: LocalHost
    private let pipeline: TransformPipeline
    
    private var findings: [Finding] = []
    private var tasks: [AgentTask] = []
    private var fileContents: [String: String] = [:]  // Original contents
    private var modifiedContents: [String: String] = [:]  // Modified contents
    private var appliedTransforms: [(task: AgentTask, file: String, original: String)] = []
    private var currentTaskIndex: Int = 0
    
    init(projectRoot: URL, output: OutputWriter) {
        self.projectRoot = projectRoot
        self.output = output
        self.host = LocalHost(
            projectRoot: projectRoot,
            config: .default,
            approvalHandler: { task in
                TaskApprovalResult(task: task, decision: .deferred)
            }
        )
        self.pipeline = TransformPipeline.standard()
    }
    
    // MARK: - Main Loop
    
    func run() async -> Int32 {
        printWelcome()
        
        // Initial analysis
        output.write("\n\("🔍".colored(.cyan)) Analyzing project...\n")
        
        do {
            findings = try await host.analyze()
            tasks = host.proposeTasks(from: findings)
        } catch {
            output.write("\("✗".colored(.red)) Analysis failed: \(error.localizedDescription)\n")
            return 1
        }
        
        if tasks.isEmpty {
            output.write("\n\("✓".colored(.green, bold: true)) No issues found! Your code looks great.\n")
            return 0
        }
        
        output.write("\("✓".colored(.green)) Found \(findings.count) findings, \(tasks.count) tasks\n\n")
        
        // Load file contents for tasks
        loadFileContents()
        
        // Enter interactive loop
        await interactiveLoop()
        
        return 0
    }
    
    private func printWelcome() {
        output.write("""
        
        \("╔═══════════════════════════════════════════════════════════╗".colored(.cyan))
        \("║".colored(.cyan))  \("Interactive Mode".colored(.white, bold: true))                                      \("║".colored(.cyan))
        \("║".colored(.cyan))  Review and apply transforms one-by-one               \("║".colored(.cyan))
        \("╚═══════════════════════════════════════════════════════════╝".colored(.cyan))
        
        """)
    }
    
    private func loadFileContents() {
        let files = Set(tasks.compactMap { scopeFile($0.scope) })
        
        for file in files {
            let url = projectRoot.appendingPathComponent(file)
            if let content = try? String(contentsOf: url, encoding: .utf8) {
                fileContents[file] = content
                modifiedContents[file] = content
            }
        }
    }
    
    // MARK: - Interactive Loop
    
    private func interactiveLoop() async {
        var running = true
        
        while running {
            printStatus()
            printCurrentTask()
            printMenu()
            
            guard let input = readLine()?.trimmingCharacters(in: .whitespaces).lowercased() else {
                continue
            }
            
            switch input {
            case "a", "apply":
                await applyCurrentTask()
                
            case "s", "skip":
                skipCurrentTask()
                
            case "p", "preview":
                previewCurrentTask()
                
            case "d", "diff":
                showDiff()
                
            case "u", "undo":
                undoLastTransform()
                
            case "l", "list":
                listAllTasks()
                
            case "g", "goto":
                output.write("  Enter task number: ")
                if let numStr = readLine(), let num = Int(numStr), num > 0, num <= tasks.count {
                    currentTaskIndex = num - 1
                }
                
            case "w", "write":
                await writeChanges()
                
            case "r", "refresh":
                await refreshAnalysis()
                
            case "h", "help", "?":
                printHelp()
                
            case "q", "quit", "exit":
                running = false
                await promptSaveChanges()
                
            case "":
                // Enter = apply
                await applyCurrentTask()
                
            default:
                output.write("  Unknown command. Type 'h' for help.\n")
            }
        }
        
        output.write("\n\("👋".colored(.cyan)) Goodbye!\n")
    }
    
    // MARK: - Display
    
    private func printStatus() {
        let applied = appliedTransforms.count
        let remaining = tasks.count - currentTaskIndex
        let modified = modifiedContents.filter { fileContents[$0.key] != $0.value }.count
        
        output.write("\n\("─".colored(.dim))─── Status ───────────────────────────────────────────────\n")
        output.write("  Tasks: \(String(currentTaskIndex + 1).colored(.cyan))/\(tasks.count)")
        output.write("  │  Applied: \(String(applied).colored(.green))")
        output.write("  │  Remaining: \(String(remaining).colored(.yellow))")
        output.write("  │  Files modified: \(String(modified).colored(.magenta))\n")
    }
    
    private func printCurrentTask() {
        guard currentTaskIndex < tasks.count else {
            output.write("\n\("✓".colored(.green, bold: true)) All tasks reviewed!\n")
            return
        }
        
        let task = tasks[currentTaskIndex]
        let categoryColor = colorForCategory(task.intent.category)
        
        output.write("\n\("─".colored(.dim))─── Current Task ─────────────────────────────────────────\n")
        output.write("  \(task.title.colored(.white, bold: true))\n")
        output.write("  Category: \(task.intent.category.rawValue.colored(categoryColor))\n")
        output.write("  Scope: \((scopeFile(task.scope) ?? "unknown").colored(.dim))\n")
        output.write("  Confidence: \(String(format: "%.0f%%", task.confidence * 100).colored(confidenceColor(task.confidence)))\n")
        
        if !task.steps.isEmpty {
            output.write("  Steps:\n")
            for (i, step) in task.steps.prefix(3).enumerated() {
                output.write("    \(i + 1). \(step.description.colored(.dim))\n")
            }
            if task.steps.count > 3 {
                output.write("    ... and \(task.steps.count - 3) more\n")
            }
        }
    }
    
    private func printMenu() {
        output.write("\n\("─".colored(.dim))─── Commands ─────────────────────────────────────────────\n")
        output.write("  [\("a".colored(.green))]pply  [\("s".colored(.yellow))]kip  [\("p".colored(.cyan))]review  [\("d".colored(.blue))]iff  [\("u".colored(.magenta))]ndo  [\("l".colored(.white))]ist  [\("w".colored(.green, bold: true))]rite  [\("q".colored(.red))]uit\n")
        output.write("  > ")
    }
    
    private func printHelp() {
        output.write("""
        
        \("─".colored(.dim))─── Help ─────────────────────────────────────────────────────
          \("a".colored(.green))pply     Apply the current transform
          \("s".colored(.yellow))kip      Skip to the next task
          \("p".colored(.cyan))review   Show what the transform will change
          \("d".colored(.blue))iff      Show unified diff of current changes
          \("u".colored(.magenta))ndo      Undo the last applied transform
          \("l".colored(.white))ist      List all tasks
          \("g".colored(.white))oto      Jump to a specific task number
          \("w".colored(.green, bold: true))rite     Write all changes to disk
          \("r".colored(.cyan))efresh   Re-analyze the project
          \("h".colored(.dim))elp      Show this help
          \("q".colored(.red))uit      Exit interactive mode
          
          Press Enter to apply the current task.
        
        """)
    }
    
    // MARK: - Actions
    
    private func applyCurrentTask() async {
        guard currentTaskIndex < tasks.count else {
            output.write("  No more tasks to apply.\n")
            return
        }
        
        let task = tasks[currentTaskIndex]
        guard let file = scopeFile(task.scope) as String?,
              let source = modifiedContents[file] else {
            output.write("  \("✗".colored(.red)) Cannot find source file for task.\n")
            currentTaskIndex += 1
            return
        }
        
        do {
            let result = try pipeline.execute(
                intents: [task.intent],
                source: source,
                context: TransformContext(filePath: file)
            )
            
            if result.success {
                // Save for undo
                appliedTransforms.append((task: task, file: file, original: source))
                modifiedContents[file] = result.transformedSource
                
                output.write("  \("✓".colored(.green, bold: true)) Applied: \(task.title)\n")
                
                // Show brief diff summary
                let linesChanged = result.totalLinesChanged
                output.write("    \(linesChanged) line(s) changed\n")
            } else {
                output.write("  \("⚠".colored(.yellow)) Transform had no effect.\n")
            }
        } catch {
            output.write("  \("✗".colored(.red)) Transform failed: \(error.localizedDescription)\n")
        }
        
        currentTaskIndex += 1
    }
    
    private func skipCurrentTask() {
        guard currentTaskIndex < tasks.count else {
            output.write("  No more tasks to skip.\n")
            return
        }
        
        let task = tasks[currentTaskIndex]
        output.write("  \("→".colored(.yellow)) Skipped: \(task.title)\n")
        currentTaskIndex += 1
    }
    
    private func previewCurrentTask() {
        guard currentTaskIndex < tasks.count else {
            output.write("  No task to preview.\n")
            return
        }
        
        let task = tasks[currentTaskIndex]
        guard let file = scopeFile(task.scope) as String?,
              let source = modifiedContents[file] else {
            output.write("  \("✗".colored(.red)) Cannot find source file.\n")
            return
        }
        
        do {
            let result = try pipeline.execute(
                intents: [task.intent],
                source: source,
                context: TransformContext(filePath: file)
            )
            
            if result.success {
                output.write("\n\("─".colored(.dim))─── Preview ──────────────────────────────────────────────\n")
                
                // Show colored diff
                let diffLines = result.combinedDiff.components(separatedBy: "\n")
                for line in diffLines.prefix(30) {
                    if line.hasPrefix("+") && !line.hasPrefix("+++") {
                        output.write("\(line.colored(.green))\n")
                    } else if line.hasPrefix("-") && !line.hasPrefix("---") {
                        output.write("\(line.colored(.red))\n")
                    } else if line.hasPrefix("@@") {
                        output.write("\(line.colored(.cyan))\n")
                    } else {
                        output.write("\(line)\n")
                    }
                }
                
                if diffLines.count > 30 {
                    output.write("  ... \(diffLines.count - 30) more lines\n")
                }
            } else {
                output.write("  Transform would have no effect.\n")
            }
        } catch {
            output.write("  \("✗".colored(.red)) Preview failed: \(error.localizedDescription)\n")
        }
    }
    
    private func showDiff() {
        output.write("\n\("─".colored(.dim))─── Current Changes ──────────────────────────────────────\n")
        
        var hasChanges = false
        
        for (file, modified) in modifiedContents {
            guard let original = fileContents[file], original != modified else { continue }
            hasChanges = true
            
            output.write("\n  \("File:".colored(.dim)) \(file.colored(.cyan))\n")
            
            // Generate simple diff
            let originalLines = original.components(separatedBy: "\n")
            let modifiedLines = modified.components(separatedBy: "\n")
            
            // Simple line-by-line comparison
            let maxLines = max(originalLines.count, modifiedLines.count)
            var diffCount = 0
            
            for i in 0..<min(maxLines, 50) {
                let origLine = i < originalLines.count ? originalLines[i] : ""
                let modLine = i < modifiedLines.count ? modifiedLines[i] : ""
                
                if origLine != modLine {
                    diffCount += 1
                    if diffCount <= 20 {
                        if !origLine.isEmpty {
                            output.write("  \("-".colored(.red)) \(origLine.colored(.red))\n")
                        }
                        if !modLine.isEmpty {
                            output.write("  \("+".colored(.green)) \(modLine.colored(.green))\n")
                        }
                    }
                }
            }
            
            if diffCount > 20 {
                output.write("  ... and \(diffCount - 20) more changes\n")
            }
        }
        
        if !hasChanges {
            output.write("  No changes yet.\n")
        }
    }
    
    private func undoLastTransform() {
        guard let last = appliedTransforms.popLast() else {
            output.write("  \("⚠".colored(.yellow)) Nothing to undo.\n")
            return
        }
        
        // Restore original content
        modifiedContents[last.file] = last.original
        
        // Move back to that task
        if let idx = tasks.firstIndex(where: { $0.id == last.task.id }) {
            currentTaskIndex = idx
        }
        
        output.write("  \("↩".colored(.magenta)) Undone: \(last.task.title)\n")
    }
    
    private func listAllTasks() {
        output.write("\n\("─".colored(.dim))─── All Tasks ────────────────────────────────────────────\n")
        
        for (i, task) in tasks.enumerated() {
            let marker: String
            if i < currentTaskIndex {
                if appliedTransforms.contains(where: { $0.task.id == task.id }) {
                    marker = "✓".colored(.green)
                } else {
                    marker = "→".colored(.yellow)
                }
            } else if i == currentTaskIndex {
                marker = "▶".colored(.cyan, bold: true)
            } else {
                marker = "○".colored(.dim)
            }
            
            let categoryColor = colorForCategory(task.intent.category)
            output.write("  \(marker) \(String(i + 1).colored(.dim)). \(task.title)\n")
            output.write("       \(task.intent.category.rawValue.colored(categoryColor)) │ \((scopeFile(task.scope) ?? "unknown").colored(.dim))\n")
        }
    }
    
    private func writeChanges() async {
        let modifiedFiles = modifiedContents.filter { fileContents[$0.key] != $0.value }
        
        if modifiedFiles.isEmpty {
            output.write("  \("⚠".colored(.yellow)) No changes to write.\n")
            return
        }
        
        output.write("\n  Writing \(modifiedFiles.count) file(s)...\n")
        
        for (file, content) in modifiedFiles {
            let url = projectRoot.appendingPathComponent(file)
            do {
                try content.write(to: url, atomically: true, encoding: .utf8)
                output.write("  \("✓".colored(.green)) \(file)\n")
                
                // Update original to match (so we don't re-write)
                fileContents[file] = content
            } catch {
                output.write("  \("✗".colored(.red)) \(file): \(error.localizedDescription)\n")
            }
        }
        
        output.write("\n  \("✓".colored(.green, bold: true)) Changes written to disk.\n")
    }
    
    private func refreshAnalysis() async {
        output.write("\n  \("🔄".colored(.cyan)) Re-analyzing...\n")
        
        do {
            findings = try await host.analyze()
            tasks = host.proposeTasks(from: findings)
            currentTaskIndex = 0
            appliedTransforms.removeAll()
            loadFileContents()
            
            output.write("  \("✓".colored(.green)) Found \(findings.count) findings, \(tasks.count) tasks\n")
        } catch {
            output.write("  \("✗".colored(.red)) Analysis failed: \(error.localizedDescription)\n")
        }
    }
    
    private func promptSaveChanges() async {
        let modifiedFiles = modifiedContents.filter { fileContents[$0.key] != $0.value }
        
        guard !modifiedFiles.isEmpty else { return }
        
        output.write("\n  \("⚠".colored(.yellow)) You have \(modifiedFiles.count) unsaved file(s).\n")
        output.write("  Save changes before exiting? [y/N] ")
        
        if let input = readLine()?.lowercased(), input == "y" || input == "yes" {
            await writeChanges()
        } else {
            output.write("  Changes discarded.\n")
        }
    }
    
    // MARK: - Helpers
    
    private func scopeFile(_ scope: TaskScope) -> String? {
        switch scope {
        case .file(let path): return path
        default: return nil
        }
    }
    
    private func colorForCategory(_ category: IntentCategory) -> ANSIColor {
        switch category {
        case .quality: return .green
        case .dataFlow: return .blue
        case .structural: return .magenta
        case .architecture: return .red
        case .documentation: return .cyan
        }
    }
    
    private func confidenceColor(_ confidence: Double) -> ANSIColor {
        if confidence >= 0.8 { return .green }
        if confidence >= 0.6 { return .yellow }
        return .red
    }
}

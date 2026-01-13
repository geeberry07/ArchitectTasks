import Foundation
import ArchitectHost

// MARK: - Report Exporter

/// Exports analysis reports in various formats (HTML, JSON, Markdown)
public struct ReportExporter {
    
    // MARK: - HTML Export
    
    /// Generate an HTML report from analysis results
    public static func generateHTML(
        projectPath: String,
        findings: [Finding],
        tasks: [AgentTask],
        timestamp: Date = Date()
    ) -> String {
        let findingsByType = Dictionary(grouping: findings, by: { $0.type.rawValue })
        let findingsBySeverity = Dictionary(grouping: findings, by: { $0.severity })
        let tasksByCategory = Dictionary(grouping: tasks, by: { $0.intent.category })
        
        let criticalCount = findingsBySeverity[.critical]?.count ?? 0
        let errorCount = findingsBySeverity[.error]?.count ?? 0
        let warningCount = findingsBySeverity[.warning]?.count ?? 0
        let infoCount = findingsBySeverity[.info]?.count ?? 0
        
        let healthScore = calculateHealthScore(findings: findings)
        let healthColor = healthScore >= 80 ? "#22c55e" : healthScore >= 60 ? "#eab308" : "#ef4444"
        
        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>ArchitectTasks Report - \(projectPath)</title>
            <style>
                :root {
                    --bg-primary: #0f172a;
                    --bg-secondary: #1e293b;
                    --bg-tertiary: #334155;
                    --text-primary: #f8fafc;
                    --text-secondary: #94a3b8;
                    --accent: #3b82f6;
                    --critical: #ef4444;
                    --error: #f97316;
                    --warning: #eab308;
                    --info: #3b82f6;
                    --success: #22c55e;
                }
                
                * { box-sizing: border-box; margin: 0; padding: 0; }
                
                body {
                    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
                    background: var(--bg-primary);
                    color: var(--text-primary);
                    line-height: 1.6;
                    padding: 2rem;
                }
                
                .container { max-width: 1200px; margin: 0 auto; }
                
                header {
                    display: flex;
                    justify-content: space-between;
                    align-items: center;
                    margin-bottom: 2rem;
                    padding-bottom: 1rem;
                    border-bottom: 1px solid var(--bg-tertiary);
                }
                
                h1 { font-size: 1.5rem; font-weight: 600; }
                h2 { font-size: 1.25rem; font-weight: 600; margin-bottom: 1rem; }
                h3 { font-size: 1rem; font-weight: 500; margin-bottom: 0.5rem; }
                
                .timestamp { color: var(--text-secondary); font-size: 0.875rem; }
                
                .grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 1rem; margin-bottom: 2rem; }
                
                .card {
                    background: var(--bg-secondary);
                    border-radius: 0.5rem;
                    padding: 1.5rem;
                }
                
                .stat-card {
                    text-align: center;
                }
                
                .stat-value {
                    font-size: 2.5rem;
                    font-weight: 700;
                    line-height: 1;
                }
                
                .stat-label {
                    color: var(--text-secondary);
                    font-size: 0.875rem;
                    margin-top: 0.5rem;
                }
                
                .health-score {
                    width: 120px;
                    height: 120px;
                    border-radius: 50%;
                    display: flex;
                    flex-direction: column;
                    align-items: center;
                    justify-content: center;
                    margin: 0 auto;
                    border: 4px solid \(healthColor);
                }
                
                .health-value { font-size: 2rem; font-weight: 700; color: \(healthColor); }
                .health-label { font-size: 0.75rem; color: var(--text-secondary); }
                
                .severity-critical { color: var(--critical); }
                .severity-error { color: var(--error); }
                .severity-warning { color: var(--warning); }
                .severity-info { color: var(--info); }
                
                .badge {
                    display: inline-block;
                    padding: 0.25rem 0.5rem;
                    border-radius: 0.25rem;
                    font-size: 0.75rem;
                    font-weight: 500;
                }
                
                .badge-critical { background: rgba(239, 68, 68, 0.2); color: var(--critical); }
                .badge-error { background: rgba(249, 115, 22, 0.2); color: var(--error); }
                .badge-warning { background: rgba(234, 179, 8, 0.2); color: var(--warning); }
                .badge-info { background: rgba(59, 130, 246, 0.2); color: var(--info); }
                
                table {
                    width: 100%;
                    border-collapse: collapse;
                    margin-top: 1rem;
                }
                
                th, td {
                    text-align: left;
                    padding: 0.75rem;
                    border-bottom: 1px solid var(--bg-tertiary);
                }
                
                th {
                    color: var(--text-secondary);
                    font-weight: 500;
                    font-size: 0.875rem;
                }
                
                tr:hover { background: var(--bg-tertiary); }
                
                .file-path {
                    font-family: 'SF Mono', Monaco, monospace;
                    font-size: 0.875rem;
                    color: var(--accent);
                }
                
                .message { color: var(--text-secondary); }
                
                .chart-bar {
                    height: 8px;
                    background: var(--bg-tertiary);
                    border-radius: 4px;
                    overflow: hidden;
                    margin-top: 0.5rem;
                }
                
                .chart-fill {
                    height: 100%;
                    border-radius: 4px;
                }
                
                .section { margin-bottom: 2rem; }
                
                .empty-state {
                    text-align: center;
                    padding: 3rem;
                    color: var(--text-secondary);
                }
                
                .task-card {
                    background: var(--bg-secondary);
                    border-radius: 0.5rem;
                    padding: 1rem;
                    margin-bottom: 0.5rem;
                }
                
                .task-title { font-weight: 500; margin-bottom: 0.5rem; }
                .task-meta { font-size: 0.875rem; color: var(--text-secondary); }
                
                .category-quality { color: var(--success); }
                .category-dataFlow { color: var(--accent); }
                .category-structural { color: #a855f7; }
                .category-architecture { color: var(--critical); }
                .category-documentation { color: #06b6d4; }
                
                footer {
                    margin-top: 3rem;
                    padding-top: 1rem;
                    border-top: 1px solid var(--bg-tertiary);
                    text-align: center;
                    color: var(--text-secondary);
                    font-size: 0.875rem;
                }
                
                @media print {
                    body { background: white; color: black; }
                    .card { border: 1px solid #e5e7eb; }
                }
            </style>
        </head>
        <body>
            <div class="container">
                <header>
                    <div>
                        <h1>🏗️ ArchitectTasks Report</h1>
                        <div class="timestamp">\(projectPath)</div>
                    </div>
                    <div class="timestamp">\(formatDate(timestamp))</div>
                </header>
                
                <div class="grid">
                    <div class="card stat-card">
                        <div class="health-score">
                            <div class="health-value">\(healthScore)</div>
                            <div class="health-label">Health Score</div>
                        </div>
                    </div>
                    <div class="card stat-card">
                        <div class="stat-value">\(findings.count)</div>
                        <div class="stat-label">Total Findings</div>
                    </div>
                    <div class="card stat-card">
                        <div class="stat-value">\(tasks.count)</div>
                        <div class="stat-label">Suggested Tasks</div>
                    </div>
                    <div class="card stat-card">
                        <div class="stat-value severity-critical">\(criticalCount)</div>
                        <div class="stat-label">Critical</div>
                    </div>
                    <div class="card stat-card">
                        <div class="stat-value severity-error">\(errorCount)</div>
                        <div class="stat-label">Errors</div>
                    </div>
                    <div class="card stat-card">
                        <div class="stat-value severity-warning">\(warningCount)</div>
                        <div class="stat-label">Warnings</div>
                    </div>
                </div>
                
                <div class="section">
                    <div class="card">
                        <h2>📊 Findings by Type</h2>
                        \(generateFindingsByTypeHTML(findingsByType, total: findings.count))
                    </div>
                </div>
                
                <div class="section">
                    <div class="card">
                        <h2>🔍 All Findings</h2>
                        \(generateFindingsTableHTML(findings))
                    </div>
                </div>
                
                <div class="section">
                    <div class="card">
                        <h2>📋 Suggested Tasks</h2>
                        \(generateTasksHTML(tasks))
                    </div>
                </div>
                
                <footer>
                    Generated by ArchitectTasks • \(formatDate(timestamp))
                </footer>
            </div>
        </body>
        </html>
        """
    }
    
    // MARK: - Markdown Export
    
    /// Generate a Markdown report from analysis results
    public static func generateMarkdown(
        projectPath: String,
        findings: [Finding],
        tasks: [AgentTask],
        timestamp: Date = Date()
    ) -> String {
        let findingsByType = Dictionary(grouping: findings, by: { $0.type.rawValue })
        let findingsBySeverity = Dictionary(grouping: findings, by: { $0.severity })
        
        let criticalCount = findingsBySeverity[.critical]?.count ?? 0
        let errorCount = findingsBySeverity[.error]?.count ?? 0
        let warningCount = findingsBySeverity[.warning]?.count ?? 0
        let infoCount = findingsBySeverity[.info]?.count ?? 0
        
        let healthScore = calculateHealthScore(findings: findings)
        
        var md = """
        # 🏗️ ArchitectTasks Report
        
        **Project:** `\(projectPath)`  
        **Generated:** \(formatDate(timestamp))
        
        ---
        
        ## Summary
        
        | Metric | Value |
        |--------|-------|
        | Health Score | \(healthScore)/100 |
        | Total Findings | \(findings.count) |
        | Suggested Tasks | \(tasks.count) |
        | Critical | \(criticalCount) |
        | Errors | \(errorCount) |
        | Warnings | \(warningCount) |
        | Info | \(infoCount) |
        
        ---
        
        ## Findings by Type
        
        | Type | Count |
        |------|-------|
        """
        
        for (type, typeFindings) in findingsByType.sorted(by: { $0.value.count > $1.value.count }) {
            md += "| \(type) | \(typeFindings.count) |\n"
        }
        
        md += """
        
        ---
        
        ## All Findings
        
        | Severity | File | Line | Message |
        |----------|------|------|---------|
        """
        
        for finding in findings.sorted(by: { $0.severity.rawValue > $1.severity.rawValue }) {
            let severity = severityEmoji(finding.severity)
            let file = finding.location.file.components(separatedBy: "/").last ?? finding.location.file
            md += "| \(severity) | `\(file)` | \(finding.location.line) | \(finding.message) |\n"
        }
        
        md += """
        
        ---
        
        ## Suggested Tasks
        
        """
        
        for (i, task) in tasks.enumerated() {
            let categoryEmoji = categoryToEmoji(task.intent.category)
            md += """
            ### \(i + 1). \(task.title)
            
            - **Category:** \(categoryEmoji) \(task.intent.category.rawValue)
            - **Confidence:** \(Int(task.confidence * 100))%
            - **Steps:** \(task.steps.count)
            
            """
        }
        
        md += """
        
        ---
        
        *Generated by [ArchitectTasks](https://github.com/yourorg/ArchitectTasks)*
        """
        
        return md
    }
    
    // MARK: - Helpers
    
    private static func calculateHealthScore(findings: [Finding]) -> Int {
        guard !findings.isEmpty else { return 100 }
        
        var score = 100.0
        
        for finding in findings {
            switch finding.severity {
            case .critical: score -= 10
            case .error: score -= 5
            case .warning: score -= 2
            case .info: score -= 0.5
            }
        }
        
        return max(0, min(100, Int(score)))
    }
    
    private static func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    private static func severityEmoji(_ severity: Finding.Severity) -> String {
        switch severity {
        case .critical: return "🔴"
        case .error: return "🟠"
        case .warning: return "🟡"
        case .info: return "🔵"
        }
    }
    
    private static func categoryToEmoji(_ category: IntentCategory) -> String {
        switch category {
        case .quality: return "✨"
        case .dataFlow: return "🔄"
        case .structural: return "🏗️"
        case .architecture: return "🏛️"
        case .documentation: return "📝"
        }
    }
    
    private static func generateFindingsByTypeHTML(_ findingsByType: [String: [Finding]], total: Int) -> String {
        guard !findingsByType.isEmpty else {
            return "<div class=\"empty-state\">No findings</div>"
        }
        
        var html = ""
        let sorted = findingsByType.sorted { $0.value.count > $1.value.count }
        
        for (type, findings) in sorted {
            let percentage = total > 0 ? (Double(findings.count) / Double(total)) * 100 : 0
            let color = typeToColor(type)
            
            html += """
            <div style="margin-bottom: 1rem;">
                <div style="display: flex; justify-content: space-between;">
                    <span>\(type)</span>
                    <span>\(findings.count)</span>
                </div>
                <div class="chart-bar">
                    <div class="chart-fill" style="width: \(percentage)%; background: \(color);"></div>
                </div>
            </div>
            """
        }
        
        return html
    }
    
    private static func generateFindingsTableHTML(_ findings: [Finding]) -> String {
        guard !findings.isEmpty else {
            return "<div class=\"empty-state\">✅ No findings - your code looks great!</div>"
        }
        
        var html = """
        <table>
            <thead>
                <tr>
                    <th>Severity</th>
                    <th>File</th>
                    <th>Line</th>
                    <th>Type</th>
                    <th>Message</th>
                </tr>
            </thead>
            <tbody>
        """
        
        let sorted = findings.sorted { $0.severity.rawValue > $1.severity.rawValue }
        
        for finding in sorted {
            let severityName = severityName(finding.severity)
            let severityClass = "badge-\(severityName)"
            let fileName = finding.location.file.components(separatedBy: "/").last ?? finding.location.file
            
            html += """
                <tr>
                    <td><span class="badge \(severityClass)">\(severityName.uppercased())</span></td>
                    <td class="file-path">\(fileName)</td>
                    <td>\(finding.location.line)</td>
                    <td>\(finding.type.rawValue)</td>
                    <td class="message">\(escapeHTML(finding.message))</td>
                </tr>
            """
        }
        
        html += """
            </tbody>
        </table>
        """
        
        return html
    }
    
    private static func severityName(_ severity: Finding.Severity) -> String {
        switch severity {
        case .critical: return "critical"
        case .error: return "error"
        case .warning: return "warning"
        case .info: return "info"
        }
    }
    
    private static func generateTasksHTML(_ tasks: [AgentTask]) -> String {
        guard !tasks.isEmpty else {
            return "<div class=\"empty-state\">No tasks suggested</div>"
        }
        
        var html = ""
        
        for task in tasks {
            let categoryClass = "category-\(task.intent.category.rawValue)"
            
            html += """
            <div class="task-card">
                <div class="task-title">\(escapeHTML(task.title))</div>
                <div class="task-meta">
                    <span class="\(categoryClass)">\(task.intent.category.rawValue)</span> •
                    Confidence: \(Int(task.confidence * 100))% •
                    \(task.steps.count) step(s)
                </div>
            </div>
            """
        }
        
        return html
    }
    
    private static func typeToColor(_ type: String) -> String {
        if type.contains("security") || type.contains("Security") { return "#ef4444" }
        if type.contains("complexity") || type.contains("Complexity") { return "#f97316" }
        if type.contains("naming") || type.contains("Naming") { return "#eab308" }
        if type.contains("dead") || type.contains("Dead") { return "#a855f7" }
        if type.contains("swiftui") || type.contains("SwiftUI") { return "#3b82f6" }
        return "#64748b"
    }
    
    private static func escapeHTML(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

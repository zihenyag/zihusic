import Foundation

struct ProcessResult {
    var stdout: String
    var stderr: String
}

enum ProcessRunnerError: LocalizedError {
    case executableMissing(String)
    case failed(executable: String, status: Int32, stderr: String)

    var errorDescription: String? {
        switch self {
        case .executableMissing(let name):
            return "找不到命令行工具：\(name)"
        case .failed(let executable, let status, let stderr):
            let detail = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return "\(URL(fileURLWithPath: executable).lastPathComponent) 退出码 \(status)。\(detail)"
        }
    }
}

enum ProcessRunner {
    static func findExecutable(named name: String) -> String? {
        let candidates = [
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)",
            "/usr/bin/\(name)",
            "/bin/\(name)"
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    @discardableResult
    static func run(_ executable: String, arguments: [String]) throws -> ProcessResult {
        guard FileManager.default.isExecutableFile(atPath: executable) else {
            throw ProcessRunnerError.executableMissing(executable)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = utf8Environment()

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        let stdoutData = stdout.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderr.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: stdoutData, encoding: .utf8) ?? ""
        let error = String(data: stderrData, encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            throw ProcessRunnerError.failed(executable: executable, status: process.terminationStatus, stderr: error)
        }

        return ProcessResult(stdout: output, stderr: error)
    }

    private static func utf8Environment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["LANG"] = "en_US.UTF-8"
        environment["LC_ALL"] = "en_US.UTF-8"
        environment["LC_CTYPE"] = "en_US.UTF-8"
        return environment
    }
}

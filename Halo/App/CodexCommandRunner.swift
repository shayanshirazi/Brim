import Foundation

enum CodexCommandRunner {
    static func loginStatus(profilePath: String, subcommand: String) async -> CommandResult {
        await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["codex"] + subcommand.split(separator: " ").map(String.init)

            var environment = ProcessInfo.processInfo.environment
            environment["CODEX_HOME"] = profilePath
            process.environment = environment

            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            do {
                try process.run()
                process.waitUntilExit()
                return CommandResult(
                    exitCode: process.terminationStatus,
                    standardOutput: String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "",
                    standardError: String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                )
            } catch {
                return CommandResult(exitCode: -1, standardOutput: "", standardError: error.localizedDescription)
            }
        }.value
    }
}

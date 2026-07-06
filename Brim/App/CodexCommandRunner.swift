import Foundation

enum CodexCommandRunner {
    static func run(profilePath: String, subcommand: String) async -> CommandResult {
        await Task.detached {
            do {
                try FileManager.default.createDirectory(
                    at: URL(fileURLWithPath: profilePath, isDirectory: true),
                    withIntermediateDirectories: true
                )
            } catch {
                return CommandResult(
                    exitCode: -1,
                    standardOutput: "",
                    standardError: "Brim could not create the Codex profile folder."
                )
            }

            let process = Process()
            let executableURL = codexExecutableURL()
            let arguments = subcommand.split(separator: " ").map(String.init)
            process.executableURL = executableURL
            process.arguments = executableURL.path == "/usr/bin/env" ? ["codex"] + arguments : arguments

            var environment = ProcessInfo.processInfo.environment
            environment["CODEX_HOME"] = profilePath
            environment["PATH"] = codexSearchPath(environment: environment)
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

    static func loginStatus(profilePath: String, subcommand: String) async -> CommandResult {
        await run(profilePath: profilePath, subcommand: subcommand)
    }

    private static func codexExecutableURL() -> URL {
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser.path
        let candidates = [
            "\(home)/.local/bin/codex",
            "\(home)/.codex/packages/standalone/current/bin/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex"
        ]

        if let executablePath = candidates.first(where: { fileManager.isExecutableFile(atPath: $0) }) {
            return URL(fileURLWithPath: executablePath)
        }

        return URL(fileURLWithPath: "/usr/bin/env")
    }

    private static func codexSearchPath(environment: [String: String]) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let additions = [
            "\(home)/.local/bin",
            "\(home)/.codex/packages/standalone/current/bin",
            "/opt/homebrew/bin",
            "/opt/homebrew/sbin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin"
        ]

        let existingPaths = environment["PATH"]?
            .split(separator: ":")
            .map(String.init) ?? []
        var seen = Set<String>()

        return (additions + existingPaths)
            .filter { seen.insert($0).inserted }
            .joined(separator: ":")
    }
}

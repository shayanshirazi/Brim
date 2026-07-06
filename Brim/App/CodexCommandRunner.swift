import Foundation

private final class ProcessTerminationState: @unchecked Sendable {
    private let lock = NSLock()
    private var storedExitCode: Int32?

    var exitCode: Int32? {
        lock.lock()
        defer { lock.unlock() }
        return storedExitCode
    }

    func complete(exitCode: Int32) {
        lock.lock()
        storedExitCode = exitCode
        lock.unlock()
    }
}

enum CodexCommandRunner {
    static func run(profilePath: String, subcommand: String, timeout: TimeInterval? = nil) async -> CommandResult {
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
            guard let executableURL = codexExecutableURL() else {
                return CommandResult(
                    exitCode: -127,
                    standardOutput: "",
                    standardError: "Brim could not find Codex. Install the Codex app or make the codex command available in your login shell."
                )
            }

            let arguments = subcommand.split(separator: " ").map(String.init)
            process.executableURL = executableURL
            process.arguments = arguments

            var environment = ProcessInfo.processInfo.environment
            environment["CODEX_HOME"] = profilePath
            environment["PATH"] = codexSearchPath(environment: environment)
            process.environment = environment

            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            let terminationSemaphore = DispatchSemaphore(value: 0)
            let terminationState = ProcessTerminationState()
            process.terminationHandler = { terminatedProcess in
                terminationState.complete(exitCode: terminatedProcess.terminationStatus)
                terminationSemaphore.signal()
            }

            do {
                try process.run()
                let outputTask = Task.detached {
                    outputPipe.fileHandleForReading.readDataToEndOfFile()
                }
                let errorTask = Task.detached {
                    errorPipe.fileHandleForReading.readDataToEndOfFile()
                }

                if let timeout, !waitForProcess(process, timeout: timeout, terminationSemaphore: terminationSemaphore) {
                    return CommandResult(
                        exitCode: -124,
                        standardOutput: String(data: await outputTask.value, encoding: .utf8) ?? "",
                        standardError: "\(displayName(for: subcommand)) timed out after \(timeoutLabel(timeout)). Start again when you're ready."
                    )
                }

                if timeout == nil {
                    waitForTermination(terminationSemaphore)
                }

                return CommandResult(
                    exitCode: terminationState.exitCode ?? -1,
                    standardOutput: String(data: await outputTask.value, encoding: .utf8) ?? "",
                    standardError: String(data: await errorTask.value, encoding: .utf8) ?? ""
                )
            } catch {
                return CommandResult(exitCode: -1, standardOutput: "", standardError: error.localizedDescription)
            }
        }.value
    }

    static func loginStatus(profilePath: String, subcommand: String) async -> CommandResult {
        await run(profilePath: profilePath, subcommand: subcommand)
    }

    private static func waitForProcess(
        _ process: Process,
        timeout: TimeInterval,
        terminationSemaphore: DispatchSemaphore
    ) -> Bool {
        if terminationSemaphore.wait(timeout: .now() + timeout) == .success {
            return true
        }

        process.terminate()
        if terminationSemaphore.wait(timeout: .now() + 2) == .success {
            return false
        }

        if process.isRunning {
            kill(process.processIdentifier, SIGKILL)
        }

        _ = terminationSemaphore.wait(timeout: .now() + 1)
        return false
    }

    private static func waitForTermination(_ terminationSemaphore: DispatchSemaphore) {
        terminationSemaphore.wait()
    }

    private static func displayName(for subcommand: String) -> String {
        subcommand == "login" ? "Sign-in" : "Codex command"
    }

    private static func timeoutLabel(_ timeout: TimeInterval) -> String {
        let minutes = max(1, Int(round(timeout / 60)))
        return minutes == 1 ? "1 minute" : "\(minutes) minutes"
    }

    private static func codexExecutableURL() -> URL? {
        let fileManager = FileManager.default
        let home = QuotaFormatting.userHomeDirectoryPath
        let candidates = [
            "\(home)/.local/bin/codex",
            "\(home)/.codex/packages/standalone/current/bin/codex",
            "/Applications/Codex.app/Contents/Resources/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex"
        ]

        if let executablePath = candidates.first(where: { fileManager.isExecutableFile(atPath: $0) }) {
            return URL(fileURLWithPath: executablePath)
        }

        if
            let shellPath = codexPathFromLoginShell(),
            fileManager.isExecutableFile(atPath: shellPath)
        {
            return URL(fileURLWithPath: shellPath)
        }

        return nil
    }

    private static func codexPathFromLoginShell() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", "command -v codex"]

        var environment = ProcessInfo.processInfo.environment
        environment["HOME"] = QuotaFormatting.userHomeDirectoryPath
        environment["PATH"] = codexSearchPath(environment: environment)
        process.environment = environment

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        do {
            try process.run()
            guard waitForShellDiscovery(process) else {
                return nil
            }
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else {
            return nil
        }

        let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let path = output
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { $0.hasPrefix("/") }

        return path
    }

    private static func waitForShellDiscovery(_ process: Process) -> Bool {
        let semaphore = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .utility).async {
            process.waitUntilExit()
            semaphore.signal()
        }

        if semaphore.wait(timeout: .now() + 2) == .success {
            return true
        }

        process.terminate()
        if semaphore.wait(timeout: .now() + 1) == .success {
            return false
        }

        if process.isRunning {
            kill(process.processIdentifier, SIGKILL)
        }

        _ = semaphore.wait(timeout: .now() + 1)
        return false
    }

    private static func codexSearchPath(environment: [String: String]) -> String {
        let home = QuotaFormatting.userHomeDirectoryPath
        let additions = [
            "\(home)/.local/bin",
            "\(home)/.codex/packages/standalone/current/bin",
            "/Applications/Codex.app/Contents/Resources",
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

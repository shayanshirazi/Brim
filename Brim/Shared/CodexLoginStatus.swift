import Foundation

enum CodexLoginStatus: Equatable {
    case loggedIn(accountEmail: String?)
    case notLoggedIn
    case failed(message: String)
}

enum CodexLoginStatusClassifier {
    static func status(
        from commandResult: CommandResult,
        fallbackFailureMessage: String,
        ignoredFailureMessageFragments: [String] = []
    ) -> CodexLoginStatus {
        let combinedOutput = combinedCommandOutput(from: commandResult)
        let normalizedOutput = combinedOutput.lowercased()

        if normalizedOutput.contains("not logged in") {
            return .notLoggedIn
        }

        if commandResult.exitCode == 0, normalizedOutput.contains("logged in") {
            return .loggedIn(accountEmail: QuotaFormatting.emailAddress(in: combinedOutput))
        }

        return .failed(
            message: commandMessage(
                from: commandResult,
                fallbackMessage: fallbackFailureMessage,
                ignoredFragments: ignoredFailureMessageFragments
            )
        )
    }

    static func combinedCommandOutput(from commandResult: CommandResult) -> String {
        commandResult.standardOutput + "\n" + commandResult.standardError
    }

    static func commandMessage(
        from commandResult: CommandResult,
        fallbackMessage: String,
        ignoredFragments: [String] = []
    ) -> String {
        let trimmed = combinedCommandOutput(from: commandResult)
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { line in
                !line.isEmpty && ignoredFragments.allSatisfy { fragment in
                    !line.localizedCaseInsensitiveContains(fragment)
                }
            }
            .joined(separator: " ")

        return trimmed.isEmpty ? fallbackMessage : trimmed
    }
}

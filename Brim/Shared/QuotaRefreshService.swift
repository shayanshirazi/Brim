import Foundation

public struct QuotaRefreshService {
    public var apiTokenIsAvailable: (String) -> Bool
    public var commandRunner: (String, String) async -> CommandResult
    public var usageFetcher: (QuotaAccount) async -> CodexUsageFetchOutcome

    public init(
        apiTokenIsAvailable: @escaping (String) -> Bool = { _ in false },
        commandRunner: @escaping (String, String) async -> CommandResult = { _, _ in
            CommandResult(
                exitCode: -1,
                standardOutput: "",
                standardError: "Codex status runner is not configured."
            )
        },
        usageFetcher: @escaping (QuotaAccount) async -> CodexUsageFetchOutcome = { account in
            await CodexUsageClient().fetchUsage(for: account)
        }
    ) {
        self.apiTokenIsAvailable = apiTokenIsAvailable
        self.commandRunner = commandRunner
        self.usageFetcher = usageFetcher
    }

    public func refresh(_ account: QuotaAccount) async -> QuotaRefreshResult {
        switch account.connectionKind {
        case .manual:
            return QuotaRefreshResult(status: .manual, message: "Manual values are used.", quota: nil)
        case .apiToken:
            guard let credentialID = account.credentialID, apiTokenIsAvailable(credentialID) else {
                return QuotaRefreshResult(
                    status: .notConnected,
                    message: "Add an API token before automatic quota refresh can run.",
                    quota: nil
                )
            }

            let quota = readLocalQuotaSnapshot(for: account)
            return QuotaRefreshResult(
                status: .ready,
                message: quota == nil
                    ? "\(account.provider.displayName) token is saved. Exact usage opens in \(account.provider.displayName)."
                    : "Loaded quota snapshot from local profile.",
                quota: quota
            )
        case .login:
            switch account.provider {
            case .codex:
                return await refreshCodexLogin(account)
            }
        }
    }

    private func refreshCodexLogin(_ account: QuotaAccount) async -> QuotaRefreshResult {
        let profilePath = QuotaFormatting.expandedHomePath(account.providerProfilePathForThisDevice)
        do {
            try FileManager.default.createDirectory(
                at: URL(fileURLWithPath: profilePath, isDirectory: true),
                withIntermediateDirectories: true
            )
        } catch {
            return QuotaRefreshResult(
                status: .refreshFailed,
                message: "Brim could not create the Codex profile folder.",
                quota: nil
            )
        }

        let loginStatusResult = await commandRunner(profilePath, "login status")
        let loginStatus = CodexLoginStatusClassifier.status(
            from: loginStatusResult,
            fallbackFailureMessage: "Brim could not check the Codex session."
        )

        switch loginStatus {
        case .loggedIn(let statusAccountEmail):
            let usageFetchOutcome = await usageFetcher(account)
            let liveUsageResult = usageFetchOutcome.successfulUsageResult
            // A valid Codex login is still useful when the live usage endpoint is
            // down or reshaped. Keep the account connected and fall back to the
            // last local snapshot so the UI does not look disconnected.
            let quotaSnapshot = liveUsageResult?.quota ?? readLocalQuotaSnapshot(for: account)
            return QuotaRefreshResult(
                status: .ready,
                message: quotaSnapshot == nil
                    ? usageFetchOutcome.message
                    : (liveUsageResult == nil ? "Loaded quota snapshot from local profile." : "Loaded live Codex usage."),
                quota: quotaSnapshot,
                accountEmail: usageFetchOutcome.accountEmail ?? statusAccountEmail
            )
        case .notLoggedIn:
            return QuotaRefreshResult(
                status: .notConnected,
                message: "Sign in with Codex to connect this account.",
                quota: nil
            )
        case .failed(let message):
            return QuotaRefreshResult(
                status: .refreshFailed,
                message: message,
                quota: nil
            )
        }
    }

    private func readLocalQuotaSnapshot(for account: QuotaAccount) -> QuotaUsageSnapshot? {
        let profilePath = QuotaFormatting.expandedHomePath(account.providerProfilePathForThisDevice)
        let previousQuotaFilename = "\(BrimStorage.previousKey("").dropLast())-quota.json"
        // Probe current and legacy filenames because older local builds wrote
        // snapshots beside the Codex profile before the Brim-prefixed name.
        let candidates = [
            URL(fileURLWithPath: profilePath).appendingPathComponent("brim-quota.json"),
            URL(fileURLWithPath: profilePath).appendingPathComponent(previousQuotaFilename),
            URL(fileURLWithPath: profilePath).appendingPathComponent("quota.json")
        ]

        for url in candidates {
            guard
                let data = try? Data(contentsOf: url),
                let quota = try? JSONDecoder().decode(QuotaUsageSnapshot.self, from: data)
            else {
                continue
            }

            return quota
        }

        return nil
    }
}

public struct QuotaRefreshResult {
    public var status: QuotaRefreshStatus
    public var message: String?
    public var quota: QuotaUsageSnapshot?
    public var accountEmail: String?

    public init(status: QuotaRefreshStatus, message: String?, quota: QuotaUsageSnapshot?, accountEmail: String? = nil) {
        self.status = status
        self.message = message
        self.quota = quota
        self.accountEmail = accountEmail
    }
}

public struct CommandResult: Hashable {
    public var exitCode: Int32
    public var standardOutput: String
    public var standardError: String

    public init(exitCode: Int32, standardOutput: String, standardError: String) {
        self.exitCode = exitCode
        self.standardOutput = standardOutput
        self.standardError = standardError
    }
}

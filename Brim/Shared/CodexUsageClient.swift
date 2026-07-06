import Foundation

public struct CodexUsageClient {
    private let session: URLSession
    private let usageURL: URL
    private let fileManager: FileManager
    private let calendar: Calendar

    public init(
        session: URLSession = .shared,
        usageURL: URL = URL(string: "https://chatgpt.com/backend-api/wham/usage")!,
        fileManager: FileManager = .default,
        calendar: Calendar = .current
    ) {
        self.session = session
        self.usageURL = usageURL
        self.fileManager = fileManager
        self.calendar = calendar
    }

    public func fetchUsage(for account: QuotaAccount) async -> CodexUsageFetchOutcome {
        guard let token = accessToken(for: account) else {
            return .unavailable("Codex is connected, but Brim could not find this profile's auth token.", accountEmail: nil)
        }

        var request = URLRequest(url: usageURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (usageResponseData, urlResponse) = try await session.data(for: request)
            guard
                let httpResponse = urlResponse as? HTTPURLResponse,
                200..<300 ~= httpResponse.statusCode
            else {
                let statusCode = (urlResponse as? HTTPURLResponse)?.statusCode ?? -1
                return .unavailable("Codex usage request failed with HTTP \(statusCode).", accountEmail: nil)
            }

            let codexUsageResponse = try JSONDecoder().decode(CodexUsageResponse.self, from: usageResponseData)
            guard let quotaSnapshot = quotaSnapshot(from: codexUsageResponse) else {
                return .unavailable(
                    "Codex usage response did not include rate-limit data Brim understands.",
                    accountEmail: codexUsageResponse.email
                )
            }

            return .success(CodexUsageFetchResult(quota: quotaSnapshot, email: codexUsageResponse.email))
        } catch {
            return .unavailable("Codex usage request failed: \(error.localizedDescription)", accountEmail: nil)
        }
    }

    private func accessToken(for account: QuotaAccount) -> String? {
        let profilePath = QuotaFormatting.expandedHomePath(account.providerProfilePathForThisDevice)
        let authURL = URL(fileURLWithPath: profilePath, isDirectory: true).appendingPathComponent("auth.json")
        guard
            fileManager.fileExists(atPath: authURL.path),
            let authFileData = try? Data(contentsOf: authURL),
            let auth = try? JSONDecoder().decode(CodexAuthFile.self, from: authFileData),
            let token = auth.tokens?.accessToken,
            !token.isEmpty
        else {
            return nil
        }

        return token
    }

    private func quotaSnapshot(from usage: CodexUsageResponse) -> QuotaUsageSnapshot? {
        guard
            let rateLimit = usage.rateLimit,
            let primary = rateLimit.primaryWindow,
            let secondary = rateLimit.secondaryWindow,
            primary.normalizedUsedPercent != nil,
            secondary.normalizedUsedPercent != nil
        else {
            return nil
        }

        let sessionLimitMinutes = primary.limitMinutes
        let weeklyLimitMinutes = secondary.limitMinutes

        guard sessionLimitMinutes > 0, weeklyLimitMinutes > 0 else {
            return nil
        }

        let resetComponents = resetComponents(from: secondary.resetAt)

        return QuotaUsageSnapshot(
            weeklyLimitMinutes: weeklyLimitMinutes,
            usedMinutes: secondary.usedMinutes(limitMinutes: weeklyLimitMinutes),
            sessionLimitMinutes: sessionLimitMinutes,
            sessionUsedMinutes: primary.usedMinutes(limitMinutes: sessionLimitMinutes),
            weeklyUsedPercent: secondary.normalizedUsedPercent,
            sessionUsedPercent: primary.normalizedUsedPercent,
            sessionResetAt: primary.resetDate,
            weeklyResetAt: secondary.resetDate,
            resetWeekday: resetComponents.weekday,
            resetHour: resetComponents.hour,
            resetMinute: resetComponents.minute
        )
    }

    private func resetComponents(from timestamp: TimeInterval?) -> DateComponents {
        guard let timestamp else {
            return DateComponents()
        }

        let date = Date(timeIntervalSince1970: timestamp)
        return calendar.dateComponents([.weekday, .hour, .minute], from: date)
    }
}

private struct CodexAuthFile: Decodable {
    var tokens: CodexAuthTokens?
}

private struct CodexAuthTokens: Decodable {
    var accessToken: String?

    private enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
    }
}

private struct CodexUsageResponse: Decodable {
    var email: String?
    var rateLimit: CodexRateLimit?

    private enum CodingKeys: String, CodingKey {
        case email
        case accountEmail = "account_email"
        case rateLimit = "rate_limit"
        case rateLimitCamel = "rateLimit"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        email = try container.decodeFirstPresent(String.self, forKeys: [.email, .accountEmail])
        rateLimit = try container.decodeFirstPresent(CodexRateLimit.self, forKeys: [.rateLimit, .rateLimitCamel])
    }
}

private struct CodexRateLimit: Decodable {
    var primaryWindow: CodexRateLimitWindow?
    var secondaryWindow: CodexRateLimitWindow?

    // The Codex usage payload has appeared with product names, window names,
    // and snake/camel spellings. Normalize all aliases at this boundary so the
    // rest of Brim can reason only about primary and secondary windows.
    private enum CodingKeys: String, CodingKey {
        case primaryWindow = "primary_window"
        case primaryWindowCamel = "primaryWindow"
        case session
        case sessionWindow = "session_window"
        case fiveHourWindow = "five_hour_window"
        case secondaryWindow = "secondary_window"
        case secondaryWindowCamel = "secondaryWindow"
        case weekly
        case weeklyWindow = "weekly_window"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        primaryWindow = try container.decodeFirstPresent(
            CodexUsageWindow.self,
            forKeys: [.primaryWindow, .primaryWindowCamel, .session, .sessionWindow, .fiveHourWindow]
        )?.rateLimitWindow
        secondaryWindow = try container.decodeFirstPresent(
            CodexUsageWindow.self,
            forKeys: [.secondaryWindow, .secondaryWindowCamel, .weekly, .weeklyWindow]
        )?.rateLimitWindow
    }
}

private extension KeyedDecodingContainer {
    func decodeFirstPresent<Value: Decodable>(_ type: Value.Type, forKeys keys: [Key]) throws -> Value? {
        for key in keys {
            if let value = try decodeIfPresent(type, forKey: key) {
                return value
            }
        }

        return nil
    }
}

private struct CodexRateLimitWindow: Decodable {
    var usedPercent: Double?
    var limitWindowSeconds: Double?
    var resetAt: TimeInterval?

    private enum CodingKeys: String, CodingKey {
        case usedPercent = "used_percent"
        case limitWindowSeconds = "limit_window_seconds"
        case resetAt = "reset_at"
    }

    init(usedPercent: Double?, limitWindowSeconds: Double?, resetAt: TimeInterval?) {
        self.usedPercent = usedPercent
        self.limitWindowSeconds = limitWindowSeconds
        self.resetAt = resetAt
    }

    init(from decoder: Decoder) throws {
        self = try CodexUsageWindow(from: decoder).rateLimitWindow
    }

    var limitMinutes: Int {
        guard let limitWindowSeconds else {
            return 0
        }

        return max(1, Int(round(limitWindowSeconds / 60)))
    }

    func usedMinutes(limitMinutes: Int) -> Int {
        let usedFraction = (normalizedUsedPercent ?? 0) / 100
        return min(limitMinutes, max(0, Int(round(Double(limitMinutes) * usedFraction))))
    }

    var normalizedUsedPercent: Double? {
        usedPercent.map { max(0, min(100, $0)) }
    }

    var resetDate: Date? {
        resetAt.map { Date(timeIntervalSince1970: $0) }
    }
}

private struct CodexUsageWindow: Decodable {
    var rateLimitWindow: CodexRateLimitWindow

    // Accept both used and remaining percentages because backend variants have
    // reported either side of the same quota window. Values may arrive as 0...1,
    // 0...100, numeric strings, or millisecond timestamps.
    private enum CodingKeys: String, CodingKey {
        case usedPercent = "used_percent"
        case usedPercentCamel = "usedPercent"
        case remainingPercent = "remaining_percent"
        case remainingPercentCamel = "remainingPercent"
        case limitWindowSeconds = "limit_window_seconds"
        case limitWindowSecondsCamel = "limitWindowSeconds"
        case windowSeconds = "window_seconds"
        case windowSecondsCamel = "windowSeconds"
        case limitSeconds = "limit_seconds"
        case limitSecondsCamel = "limitSeconds"
        case resetAt = "reset_at"
        case resetAtCamel = "resetAt"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedUsedPercent = try Self.decodeDouble(
            from: container,
            keys: [.usedPercent, .usedPercentCamel]
        ).map(Self.percentValue)
        let decodedRemainingPercent = try Self.decodeDouble(
            from: container,
            keys: [.remainingPercent, .remainingPercentCamel]
        ).map(Self.percentValue)
        let limitWindowSeconds = try Self.decodeDouble(
            from: container,
            keys: [.limitWindowSeconds, .limitWindowSecondsCamel, .windowSeconds, .windowSecondsCamel, .limitSeconds, .limitSecondsCamel]
        )
        let resetAt = try Self.decodeDouble(
            from: container,
            keys: [.resetAt, .resetAtCamel]
        ).map(Self.timestampSeconds)

        rateLimitWindow = CodexRateLimitWindow(
            usedPercent: decodedUsedPercent ?? decodedRemainingPercent.map { 100 - $0 },
            limitWindowSeconds: limitWindowSeconds,
            resetAt: resetAt
        )
    }

    private static func decodeDouble(
        from container: KeyedDecodingContainer<CodingKeys>,
        keys: [CodingKeys]
    ) throws -> Double? {
        for key in keys {
            if let decodedDouble = try? container.decodeIfPresent(Double.self, forKey: key) {
                return decodedDouble
            }
            if let decodedInteger = try? container.decodeIfPresent(Int.self, forKey: key) {
                return Double(decodedInteger)
            }
            if let decodedString = try? container.decodeIfPresent(String.self, forKey: key),
               let decodedDouble = Double(decodedString) {
                return decodedDouble
            }
        }
        return nil
    }

    private static func percentValue(_ rawPercentValue: Double) -> Double {
        let percent = rawPercentValue <= 1 ? rawPercentValue * 100 : rawPercentValue
        return max(0, min(100, percent))
    }

    private static func timestampSeconds(_ rawTimestampValue: Double) -> TimeInterval {
        rawTimestampValue > 100_000_000_000 ? rawTimestampValue / 1_000 : rawTimestampValue
    }
}

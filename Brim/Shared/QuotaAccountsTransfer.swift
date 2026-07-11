import Foundation

public struct QuotaAccountsTransferPayload: Codable {
    public static let supportedVersion = 1

    public var version: Int
    public var exportedAt: Date
    public var accounts: [QuotaAccount]
    public var selectedAccountID: QuotaAccount.ID?

    public init(
        version: Int = Self.supportedVersion,
        exportedAt: Date = Date(),
        accounts: [QuotaAccount],
        selectedAccountID: QuotaAccount.ID?
    ) {
        self.version = version
        self.exportedAt = exportedAt
        self.accounts = accounts.map(Self.accountForExport)
        self.selectedAccountID = selectedAccountID
    }

    public init(state: QuotaState) {
        self.init(
            accounts: state.accounts,
            selectedAccountID: state.selectedAccountID
        )
    }

    public func stateForImport() throws -> QuotaState {
        try Self.stateForImport(
            accounts: accounts,
            selectedAccountID: selectedAccountID
        )
    }

    public static func importPreview(from data: Data) throws -> QuotaAccountsImportPreview {
        let state = try importedState(from: data)
        return QuotaAccountsImportPreview(accountCount: state.accounts.count)
    }

    public static func importedState(from data: Data) throws -> QuotaState {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            let payload = try decoder.decode(QuotaAccountsTransferPayload.self, from: data)
            guard payload.version == supportedVersion else {
                throw QuotaAccountsTransferError.unsupportedVersion(payload.version)
            }
            return try payload.stateForImport()
        } catch {
            if error is QuotaAccountsTransferError {
                throw error
            }
            let accounts = try decoder.decode([QuotaAccount].self, from: data)
            return try stateForImport(
                accounts: accounts,
                selectedAccountID: accounts.first?.id
            )
        }
    }

    public static func stateForImport(
        accounts: [QuotaAccount],
        selectedAccountID: QuotaAccount.ID?
    ) throws -> QuotaState {
        var seenAccountIDs = Set<QuotaAccount.ID>()
        for account in accounts where !seenAccountIDs.insert(account.id).inserted {
            throw QuotaAccountsTransferError.duplicateAccountID(account.id)
        }

        return QuotaState(
            accounts: accounts.map(accountForImport),
            selectedAccountID: selectedAccountID
        )
    }

    private static func accountForExport(_ account: QuotaAccount) -> QuotaAccount {
        account.portableExportAccount()
    }

    private static func accountForImport(_ account: QuotaAccount) -> QuotaAccount {
        account.portableImportAccount()
    }
}

public enum QuotaAccountsTransferError: LocalizedError, Equatable {
    case unsupportedVersion(Int)
    case duplicateAccountID(QuotaAccount.ID)

    public var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version):
            return "This Brim export uses version \(version), which this app cannot import."
        case .duplicateAccountID(let accountID):
            return "This Brim export contains the account ID \(accountID.uuidString) more than once."
        }
    }
}

public struct QuotaAccountsImportPreview: Hashable {
    public var accountCount: Int

    public init(accountCount: Int) {
        self.accountCount = accountCount
    }
}

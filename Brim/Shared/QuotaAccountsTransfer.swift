import Foundation

public struct QuotaAccountsTransferPayload: Codable {
    public static let supportedVersion = 1

    public var version: Int
    public var exportedAt: Date
    public var accounts: [QuotaAccount]
    public var selectedAccountID: QuotaAccount.ID?
    public var isAccountTextHidden: Bool
    public var widgetPageIndex: Int

    public init(
        version: Int = Self.supportedVersion,
        exportedAt: Date = Date(),
        accounts: [QuotaAccount],
        selectedAccountID: QuotaAccount.ID?,
        isAccountTextHidden: Bool,
        widgetPageIndex: Int
    ) {
        self.version = version
        self.exportedAt = exportedAt
        self.accounts = accounts.map(Self.accountForExport)
        self.selectedAccountID = selectedAccountID
        self.isAccountTextHidden = isAccountTextHidden
        self.widgetPageIndex = widgetPageIndex
    }

    public init(state: QuotaState) {
        self.init(
            accounts: state.accounts,
            selectedAccountID: state.selectedAccountID,
            isAccountTextHidden: state.isAccountTextHidden,
            widgetPageIndex: state.widgetPageIndex
        )
    }

    public func stateForImport() -> QuotaState {
        Self.stateForImport(
            accounts: accounts,
            selectedAccountID: selectedAccountID,
            isAccountTextHidden: isAccountTextHidden,
            widgetPageIndex: widgetPageIndex
        )
    }

    public static func importPreview(from accountsTransferData: Data) throws -> QuotaAccountsImportPreview {
        let importedAccountsState = try importedState(from: accountsTransferData)
        return QuotaAccountsImportPreview(accountCount: importedAccountsState.accounts.count)
    }

    public static func importedState(from accountsTransferData: Data) throws -> QuotaState {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        // Check the version header before the legacy-array fallback so future
        // export formats fail explicitly instead of being mistaken for old data.
        if let transferHeader = try? JSONDecoder().decode(QuotaAccountsTransferHeader.self, from: accountsTransferData) {
            guard transferHeader.version == supportedVersion else {
                throw QuotaAccountsTransferError.unsupportedVersion(transferHeader.version)
            }
        }

        do {
            let transferPayload = try decoder.decode(QuotaAccountsTransferPayload.self, from: accountsTransferData)
            return transferPayload.stateForImport()
        } catch {
            if error is QuotaAccountsTransferError {
                throw error
            }
            let legacyAccounts = try decoder.decode([QuotaAccount].self, from: accountsTransferData)
            return stateForImport(
                accounts: legacyAccounts,
                selectedAccountID: legacyAccounts.first?.id,
                isAccountTextHidden: false,
                widgetPageIndex: 0
            )
        }
    }

    public static func stateForImport(
        accounts: [QuotaAccount],
        selectedAccountID: QuotaAccount.ID?,
        isAccountTextHidden: Bool,
        widgetPageIndex: Int
    ) -> QuotaState {
        QuotaState(
            accounts: accounts.map(accountForImport),
            selectedAccountID: selectedAccountID,
            isAccountTextHidden: isAccountTextHidden,
            widgetPageIndex: widgetPageIndex
        )
    }

    private static func accountForExport(_ account: QuotaAccount) -> QuotaAccount {
        account.portableExportAccount()
    }

    private static func accountForImport(_ account: QuotaAccount) -> QuotaAccount {
        account.portableImportAccount()
    }
}

private struct QuotaAccountsTransferHeader: Decodable {
    var version: Int
}

public enum QuotaAccountsTransferError: LocalizedError, Equatable {
    case unsupportedVersion(Int)

    public var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version):
            return "This Brim export uses version \(version), which this app cannot import."
        }
    }
}

public struct QuotaAccountsImportPreview: Hashable {
    public var accountCount: Int

    public init(accountCount: Int) {
        self.accountCount = accountCount
    }
}

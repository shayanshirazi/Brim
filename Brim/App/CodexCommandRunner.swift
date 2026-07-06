import AppKit
import CryptoKit
import Foundation
import Network

enum CodexCommandRunner {
    static func startBrowserLogin(profilePath: String) async -> CommandResult {
        do {
            try FileManager.default.createDirectory(
                at: URL(fileURLWithPath: profilePath, isDirectory: true),
                withIntermediateDirectories: true
            )

            let tokens = try await CodexBrowserOAuthClient().login()
            try CodexProfileAuthStore.save(tokens: tokens, profilePath: profilePath)
            return CommandResult(exitCode: 0, standardOutput: "Logged in", standardError: "")
        } catch {
            return CommandResult(
                exitCode: -1,
                standardOutput: "",
                standardError: (error as? CodexOAuthError)?.message ?? error.localizedDescription
            )
        }
    }
}

private struct CodexBrowserOAuthClient {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func login() async throws -> CodexAuthTokens {
        let verifier = try PKCE.urlSafeRandomString(byteCount: 32)
        let challenge = PKCE.challenge(for: verifier)
        let state = try PKCE.urlSafeRandomString(byteCount: 32)
        let callbackServer = OAuthCallbackServer(expectedState: state)

        do {
            let port = try await callbackServer.start()
            let redirectURI = "http://localhost:\(port)/auth/callback"
            let authURL = try authorizationURL(
                redirectURI: redirectURI,
                codeChallenge: challenge,
                state: state
            )

            guard NSWorkspace.shared.open(authURL) else {
                throw CodexOAuthError.couldNotOpenBrowser
            }

            let callback = try await withTaskCancellationHandler {
                try await callbackServer.waitForCallback(timeout: 600)
            } onCancel: {
                callbackServer.stop()
            }

            return try await exchangeCode(
                callback.code,
                redirectURI: redirectURI,
                verifier: verifier
            )
        } catch {
            callbackServer.stop()
            throw error
        }
    }

    private func authorizationURL(
        redirectURI: String,
        codeChallenge: String,
        state: String
    ) throws -> URL {
        guard let url = CodexOAuthContract.authorizationURL(
            redirectURI: redirectURI,
            codeChallenge: codeChallenge,
            state: state
        ) else {
            throw CodexOAuthError.invalidAuthorizationURL
        }

        return url
    }

    private func exchangeCode(
        _ code: String,
        redirectURI: String,
        verifier: String
    ) async throws -> CodexAuthTokens {
        var request = URLRequest(url: CodexOAuthContract.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formBody([
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirectURI,
            "client_id": CodexOAuthContract.clientID,
            "code_verifier": verifier
        ])

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CodexOAuthError.networkFailed
        }

        guard 200..<300 ~= httpResponse.statusCode else {
            if let error = try? JSONDecoder().decode(CodexOAuthErrorResponse.self, from: data) {
                throw CodexOAuthError.serverMessage(error.displayMessage)
            }

            throw CodexOAuthError.serverMessage("Codex sign-in failed with HTTP \(httpResponse.statusCode).")
        }

        let tokenResponse = try JSONDecoder().decode(CodexTokenResponse.self, from: data)
        guard let tokens = tokenResponse.codexTokens, tokens.hasAccessToken else {
            throw CodexOAuthError.invalidTokenResponse
        }

        return tokens
    }

    private func formBody(_ fields: [String: String]) -> Data {
        CodexOAuthContract.formBody(fields)
    }
}

private final class OAuthCallbackServer: @unchecked Sendable {
    private let expectedState: String
    private let queue = DispatchQueue(label: "ai.hamming.brim.codex-oauth-callback")
    private let lock = NSLock()
    private var listener: NWListener?
    private var startContinuation: CheckedContinuation<UInt16, Error>?
    private var callbackContinuation: CheckedContinuation<CodexOAuthCallback, Error>?
    private var callbackResult: Result<CodexOAuthCallback, Error>?

    init(expectedState: String) {
        self.expectedState = expectedState
    }

    func start() async throws -> UInt16 {
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
        let listener = try NWListener(using: parameters, on: .any)
        self.listener = listener

        listener.stateUpdateHandler = { [weak self] state in
            self?.handleListenerState(state)
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.handleConnection(connection)
        }

        return try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            startContinuation = continuation
            lock.unlock()
            listener.start(queue: queue)
        }
    }

    func waitForCallback(timeout: TimeInterval) async throws -> CodexOAuthCallback {
        try await withThrowingTaskGroup(of: CodexOAuthCallback.self) { group in
            group.addTask { [self] in
                try await self.waitForCallback()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw CodexOAuthError.timedOut
            }

            guard let result = try await group.next() else {
                throw CodexOAuthError.timedOut
            }

            group.cancelAll()
            return result
        }
    }

    func stop() {
        lock.lock()
        let listener = listener
        self.listener = nil
        let startContinuation = startContinuation
        self.startContinuation = nil
        let callbackContinuation = callbackContinuation
        self.callbackContinuation = nil
        lock.unlock()

        listener?.cancel()
        startContinuation?.resume(throwing: CodexOAuthError.cancelled)
        callbackContinuation?.resume(throwing: CodexOAuthError.cancelled)
    }

    private func waitForCallback() async throws -> CodexOAuthCallback {
        lock.lock()
        if let callbackResult {
            lock.unlock()
            return try callbackResult.get()
        }
        lock.unlock()

        return try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            if let callbackResult {
                lock.unlock()
                continuation.resume(with: callbackResult)
                return
            }

            callbackContinuation = continuation
            lock.unlock()
        }
    }

    private func handleListenerState(_ state: NWListener.State) {
        switch state {
        case .ready:
            guard let port = listener?.port?.rawValue else {
                resumeStart(throwing: CodexOAuthError.localServerFailed)
                return
            }
            resumeStart(returning: port)
        case .failed(let error):
            resumeStart(throwing: CodexOAuthError.serverMessage(error.localizedDescription))
            completeCallback(.failure(CodexOAuthError.localServerFailed))
        case .cancelled:
            break
        case .setup, .waiting:
            break
        @unknown default:
            break
        }
    }

    private func handleConnection(_ connection: NWConnection) {
        guard Self.isLoopbackEndpoint(connection.endpoint) else {
            connection.cancel()
            return
        }

        connection.stateUpdateHandler = { state in
            if case .ready = state {
                self.receiveRequest(on: connection)
            }
        }
        connection.start(queue: queue)
    }

    private static func isLoopbackEndpoint(_ endpoint: NWEndpoint) -> Bool {
        guard case .hostPort(let host, _) = endpoint else {
            return false
        }

        switch host {
        case .ipv4(let address):
            return address == .loopback
        case .ipv6(let address):
            return address == .loopback
        case .name(let name, _):
            return name == "localhost"
        @unknown default:
            return false
        }
    }

    private func receiveRequest(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { data, _, _, error in
            let result = Result {
                if let error {
                    throw CodexOAuthError.serverMessage(error.localizedDescription)
                }

                guard let data, let request = String(data: data, encoding: .utf8) else {
                    throw CodexOAuthError.invalidCallback
                }

                return try self.parseCallback(from: request)
            }

            self.sendResponse(for: result, on: connection)
            self.completeCallback(result)
        }
    }

    private func parseCallback(from request: String) throws -> CodexOAuthCallback {
        guard
            let requestLine = request.components(separatedBy: "\r\n").first,
            let path = requestLine.split(separator: " ").dropFirst().first
        else {
            throw CodexOAuthError.invalidCallback
        }

        guard let components = URLComponents(string: "http://localhost\(path)") else {
            throw CodexOAuthError.invalidCallback
        }

        let items = (components.queryItems ?? []).reduce(into: [String: String]()) { values, item in
            values[item.name] = item.value ?? ""
        }
        if let error = items["error"] {
            throw CodexOAuthError.serverMessage(items["error_description"] ?? error)
        }

        guard components.path == "/auth/callback" else {
            throw CodexOAuthError.invalidCallback
        }

        guard items["state"] == expectedState else {
            throw CodexOAuthError.invalidState
        }

        guard let code = items["code"], !code.isEmpty else {
            throw CodexOAuthError.invalidCallback
        }

        return CodexOAuthCallback(code: code)
    }

    private func sendResponse(for result: Result<CodexOAuthCallback, Error>, on connection: NWConnection) {
        let isSuccess = (try? result.get()) != nil
        let title = isSuccess ? "Codex sign-in complete" : "Codex sign-in did not complete"
        let body = """
        <!doctype html><html><head><meta charset="utf-8"><title>\(title)</title></head>
        <body style="font-family:-apple-system,BlinkMacSystemFont,sans-serif;margin:48px;color:#202123">
        <h1 style="font-size:24px">\(title)</h1>
        <p style="font-size:15px;color:#5f6368">You can close this window and return to Brim.</p>
        </body></html>
        """
        let status = isSuccess ? "200 OK" : "400 Bad Request"
        let response = """
        HTTP/1.1 \(status)\r
        Content-Type: text/html; charset=utf-8\r
        Content-Length: \(Data(body.utf8).count)\r
        Connection: close\r
        \r
        \(body)
        """

        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
            connection.cancel()
            self.stop()
        })
    }

    private func resumeStart(returning port: UInt16) {
        lock.lock()
        let continuation = startContinuation
        startContinuation = nil
        lock.unlock()
        continuation?.resume(returning: port)
    }

    private func resumeStart(throwing error: Error) {
        lock.lock()
        let continuation = startContinuation
        startContinuation = nil
        lock.unlock()
        continuation?.resume(throwing: error)
    }

    private func completeCallback(_ result: Result<CodexOAuthCallback, Error>) {
        lock.lock()
        guard callbackResult == nil else {
            lock.unlock()
            return
        }

        callbackResult = result
        let continuation = callbackContinuation
        callbackContinuation = nil
        lock.unlock()

        continuation?.resume(with: result)
    }
}

private struct CodexOAuthCallback {
    var code: String
}

private enum PKCE {
    static func urlSafeRandomString(byteCount: Int) throws -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            throw CodexOAuthError.randomFailed
        }

        return base64URL(Data(bytes))
    }

    static func challenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return base64URL(Data(digest))
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

private struct CodexOAuthErrorResponse: Decodable {
    var error: String?
    var errorDescription: String?
    var message: String?

    var displayMessage: String {
        message ?? errorDescription ?? error ?? "Codex sign-in failed."
    }

    private enum CodingKeys: String, CodingKey {
        case error
        case errorDescription = "error_description"
        case message
    }
}

private enum CodexOAuthError: Error {
    case cancelled
    case couldNotOpenBrowser
    case invalidAuthorizationURL
    case invalidCallback
    case invalidState
    case invalidTokenResponse
    case localServerFailed
    case networkFailed
    case randomFailed
    case serverMessage(String)
    case timedOut

    var message: String {
        switch self {
        case .cancelled:
            return "Codex sign-in was cancelled."
        case .couldNotOpenBrowser:
            return "Brim could not open the browser for Codex sign-in."
        case .invalidAuthorizationURL:
            return "Brim could not prepare Codex sign-in."
        case .invalidCallback:
            return "Codex returned a sign-in callback Brim could not understand."
        case .invalidState:
            return "Codex sign-in returned an unexpected state."
        case .invalidTokenResponse:
            return "Codex returned a token response Brim could not understand."
        case .localServerFailed:
            return "Brim could not start the local Codex sign-in listener."
        case .networkFailed:
            return "Brim could not reach Codex sign-in."
        case .randomFailed:
            return "Brim could not prepare a secure Codex sign-in challenge."
        case .serverMessage(let message):
            return message
        case .timedOut:
            return "Codex sign-in timed out. Start again when you're ready."
        }
    }
}

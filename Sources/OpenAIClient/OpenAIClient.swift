import Foundation
public actor OpenAIClient {
    
    public struct Configuration: Sendable {
        public var baseURL: URL
        public var timeout: TimeInterval
        public var maxRetries: Int
        public var userAgent: String?
        
        public init(
            baseURL: URL = URL(string: "https://api.openai.com/v1")!,
            timeout: TimeInterval = 30,
            maxRetries: Int = 2,
            userAgent: String? = "OpenAIClient-Swift/1.0"
        ) {
            self.baseURL = baseURL
            self.timeout = timeout
            self.maxRetries = maxRetries
            self.userAgent = userAgent
        }
    }
    
    private let apiKeyProvider: @Sendable () throws -> String
    private let model: String
    private let config: Configuration
    private let session: URLSession
    
    /// Важно: URLSession — thread-safe, его можно шарить.
    /// Actor гарантирует безопасность наших собственных mutable state (у нас его почти нет).
    public init(
        apiKeyProvider: @escaping @Sendable () throws -> String,
        model: String,
        configuration: Configuration = .init(),
        session: URLSession = .shared
    ) {
        self.apiKeyProvider = apiKeyProvider
        self.model = model
        self.config = configuration
        self.session = session
    }
    
    public init(
        apiKey: String,
        model: String,
        configuration: Configuration = .init(),
        session: URLSession = .shared
    ) {
        self.init(apiKeyProvider: { apiKey }, model: model, configuration: configuration, session: session)
    }
    
    // MARK: Public API
    
    /// Обычный чат: вернёт текст.
    public func request(
        system: String,
        user: String,
        temperature: Double = 0.0
    ) async throws -> (String, RequestStatus) {
        try await requestCore(system: system, user: user, temperature: temperature, jsonMode: false)
    }
    
//    /// JSON-режим: просим вернуть строго JSON object (удобно для извлечения реквизитов).
//    public func chatJSON(
//        system: String,
//        user: String,
//        temperature: Double = 0.0
//    ) async throws -> (String, RequestStatus) {
//        try await chatCore(system: system, user: user, temperature: temperature, jsonMode: true)
//    }
    
    public func request<T: Decodable>(
        system: String,
        user: String,
        temperature: Double = 0.0,
        as type: T.Type = T.self
    ) async throws -> (T, RequestStatus) {
        let (raw, status) = try await requestCore(
            system: system,
            user: user,
            temperature: temperature,
            jsonMode: true
        )
        
        // Декодим контент в T
        let decoder = JSONDecoder()
        guard let data = raw.data(using: .utf8) else {
            throw OpenAIClientError.decoding("Response is not valid UTF-8 string")
        }
        
        do {
            let value = try decoder.decode(T.self, from: data)
            return (value, status)
        } catch {
            throw OpenAIClientError.decoding("Failed to decode \(T.self): \(error). Body: \(raw)")
        }
    }
    
    // MARK: Core
    
    private func requestCore(
        system: String,
        user: String,
        temperature: Double,
        jsonMode: Bool
    ) async throws -> (String, RequestStatus) {
        
        let start = DispatchTime.now()
        let url = config.baseURL.appendingPathComponent("chat/completions")
        
        // request строим каждый раз заново, чтобы не было shared mutable состояния
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = config.timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        if let ua = config.userAgent {
            request.setValue(ua, forHTTPHeaderField: "User-Agent")
        }
        
        let apiKey = try apiKeyProvider()
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        let body = ChatCompletionsRequest(
            model: model,
            messages: [
                .init(role: "system", content: system),
                .init(role: "user", content: user)
            ],
            temperature: temperature,
            response_format: jsonMode ? .init(type: "json_object") : nil
        )
        
        // Encoder/Decoder — локальные. Это убирает любые вопросы thread-safety.
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        
        do {
            request.httpBody = try encoder.encode(body)
        } catch {
            throw OpenAIClientError.decoding("Failed to encode request: \(error)")
        }
        
        var attempt = 0
        
        while true {
            do {
                try Task.checkCancellation()
                attempt += 1
                
                let (data, response) = try await session.data(for: request)
                
                guard let http = response as? HTTPURLResponse else {
                    throw OpenAIClientError.network("Non-HTTP response")
                }
                
                let requestId = http.value(forHTTPHeaderField: "x-request-id")
                let durationMs = Int((DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000)
                
                if (200...299).contains(http.statusCode) {
                    let decoded: ChatCompletionsResponse
                    do {
                        decoded = try decoder.decode(ChatCompletionsResponse.self, from: data)
                    } catch {
                        throw OpenAIClientError.decoding("Bad response JSON: \(error). Body: \(data.utf8Snippet())")
                    }
                    
                    let text = decoded.choices.first?.message.content ?? ""
                    let status = RequestStatus(
                        httpStatus: http.statusCode,
                        requestId: requestId,
                        retries: attempt - 1,
                        durationMs: durationMs
                    )
                    return (text, status)
                }
                
                // Попробуем распарсить стандартный error envelope
                if let apiErr = try? decoder.decode(APIErrorEnvelope.self, from: data) {
                    // Ретраим 429 и 5xx
                    if shouldRetry(status: http.statusCode, attempt: attempt) {
                        try await backoff(attempt: attempt, retryAfter: http.retryAfterSeconds())
                        continue
                    }
                    throw OpenAIClientError.api(apiErr.error.message)
                }
                
                // Если это 429/5xx, но envelope не распарсился — всё равно ретраим
                if shouldRetry(status: http.statusCode, attempt: attempt) {
                    try await backoff(attempt: attempt, retryAfter: http.retryAfterSeconds())
                    continue
                }
                
                // Иначе — отдаём как HTTP ошибку с кусочком тела
                throw OpenAIClientError.http(http.statusCode, data.utf8Snippet())
                
            } catch is CancellationError {
                throw OpenAIClientError.cancelled
            } catch let e as URLError where e.code == .timedOut {
                if attempt <= config.maxRetries {
                    try await backoff(attempt: attempt, retryAfter: nil)
                    continue
                }
                throw OpenAIClientError.timeout
            } catch let e as OpenAIClientError {
                // наши ошибки не ретраим повторно, кроме тех, что выше
                throw e
            } catch {
                // сетевые/прочие — можно ретраить ограниченно
                if attempt <= config.maxRetries {
                    try await backoff(attempt: attempt, retryAfter: nil)
                    continue
                }
                throw OpenAIClientError.network("\(error)")
            }
        }
    }
    
    private func shouldRetry(status: Int, attempt: Int) -> Bool {
        guard attempt <= config.maxRetries else { return false }
        return status == 429 || (500...599).contains(status)
    }
    
    private func backoff(attempt: Int, retryAfter: TimeInterval?) async throws {
        // Если сервер подсказал Retry-After — уважим.
        // Иначе expo backoff + jitter.
        let delay: TimeInterval
        if let retryAfter {
            delay = retryAfter
        } else {
            let base = 0.5 * pow(2.0, Double(max(0, attempt - 1)))
            let jitter = Double.random(in: 0...(base * 0.25))
            delay = base + jitter
        }
        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
    }
}

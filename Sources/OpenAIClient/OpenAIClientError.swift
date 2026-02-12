//
//  OpenAIClientError.swift
//  OpenAIClient
//
//  Created by Артем Денисов on 12.02.2026.
//


public enum OpenAIClientError: Error, Sendable, CustomStringConvertible {
    case badURL
    case http(Int, String)          // status + response snippet
    case api(String)                // API error message
    case decoding(String)           // decode/encode issue
    case timeout
    case cancelled
    case network(String)

    public var description: String {
        switch self {
        case .badURL: return "Bad URL"
        case .http(let code, let body): return "HTTP \(code): \(body)"
        case .api(let msg): return "OpenAI API error: \(msg)"
        case .decoding(let msg): return "Decoding error: \(msg)"
        case .timeout: return "Timeout"
        case .cancelled: return "Cancelled"
        case .network(let msg): return "Network error: \(msg)"
        }
    }
}
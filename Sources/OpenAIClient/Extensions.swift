//
//  Extensions.swift
//  OpenAIClient
//
//  Created by Артем Денисов on 12.02.2026.
//

import Foundation


extension Data {
    func utf8Snippet(limit: Int = 8_000) -> String {
        let s = String(data: self, encoding: .utf8) ?? "<non-utf8 data \(count) bytes>"
        return s.count > limit ? String(s.prefix(limit)) + "…" : s
    }
}

extension HTTPURLResponse {
    func retryAfterSeconds() -> TimeInterval? {
        guard let value = value(forHTTPHeaderField: "Retry-After") else { return nil }
        return TimeInterval(value)
    }
}

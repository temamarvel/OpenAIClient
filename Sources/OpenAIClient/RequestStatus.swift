//
//  RequestStatus.swift
//  OpenAIClient
//
//  Created by Артем Денисов on 12.02.2026.
//


public struct RequestStatus: Sendable, CustomStringConvertible {
    public let httpStatus: Int
    public let requestId: String?
    public let retries: Int
    public let durationMs: Int

    public var description: String {
        "HTTP \(httpStatus), retries=\(retries), duration=\(durationMs)ms, requestId=\(requestId ?? "nil")"
    }

    public init(httpStatus: Int, requestId: String?, retries: Int, durationMs: Int) {
        self.httpStatus = httpStatus
        self.requestId = requestId
        self.retries = retries
        self.durationMs = durationMs
    }
}

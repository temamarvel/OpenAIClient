//
//  ChatCompletionsRequest.swift
//  OpenAIClient
//
//  Created by Артем Денисов on 12.02.2026.
//


struct ChatCompletionsRequest: Encodable {
    let model: String
    let messages: [Message]
    let temperature: Double?
    let response_format: ResponseFormat?

    struct Message: Encodable {
        let role: String
        let content: String
    }

    struct ResponseFormat: Encodable {
        let type: String // "json_object"
    }
}

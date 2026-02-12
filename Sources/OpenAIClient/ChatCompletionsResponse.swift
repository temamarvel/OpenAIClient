//
//  ChatCompletionsResponse.swift
//  OpenAIClient
//
//  Created by Артем Денисов on 12.02.2026.
//


struct ChatCompletionsResponse: Decodable {
    let choices: [Choice]
    struct Choice: Decodable {
        let message: Message
    }
    struct Message: Decodable {
        let content: String
    }
}

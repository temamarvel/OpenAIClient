//
//  APIErrorEnvelope.swift
//  OpenAIClient
//
//  Created by Артем Денисов on 12.02.2026.
//


struct APIErrorEnvelope: Decodable {
    struct APIError: Decodable { let message: String }
    let error: APIError
}

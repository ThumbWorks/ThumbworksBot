//
//  SlackService.swift
//  App
//
//  Created by Roderic Campbell on 5/8/20.
//

import Vapor

enum Emoji: String {
    case uber = "Uber Technologies, Inc"
    case lohi = "Lohi Labs"
    case apple

    var symbol: String {
        get {
            switch self {
            case .uber:
                return ":uber:"
            case .lohi:
                return ":walmart:"
            case .apple:
                return ":apple:"
            }
        }
    }
}
/// @mockable
protocol SlackWebServicing {
    func sendSlackPayload(text: String, with emoji: Emoji?, on req: Request) throws -> EventLoopFuture<Response>
    var req: Request? { get set }
}

final class SlackWebService: SlackWebServicing {
    let slackURL: URL
    var req: Request?

    init(slackURL: URL) {
        self.slackURL = slackURL
    }

    func sendSlackPayload(text: String, with emoji: Emoji?, on req: Request) throws -> EventLoopFuture<Response> {
        return try SlackWebhookRequestPayload(text: text, iconEmoji: emoji?.symbol).encode(for: req).flatMap { slackRequestPayload in
            try req.client()
                .post(self.slackURL) { slackMessagePost in
                    slackMessagePost.http.body = slackRequestPayload.http.body
            }
        }
    }
}
